extends Node
## Sim — authoritative game state and the fixed-tick loop.
##
## Simulation is pure data + logic, fully separate from rendering. State lives in
## plain arrays/dictionaries so it is headlessly testable and trivially
## serializable. Rendering reads this state; it never writes game rules back.
##
## Milestone 2: owns the Colony (map + stockpile + buildings) and wraps its
## placement API with Events signals. The producer/consumer economy arrives in
## Milestone 3.

## Simulation ticks per real second at 1x speed.
const TICKS_PER_SECOND := 4.0

## Save files live here as `<name>.json`. Autosave overwrites `autosave`.
const SAVE_DIR := "user://saves/"
const SAVE_EXT := ".json"
const SAVE_VERSION := 1
const AUTOSAVE_NAME := "autosave"
const AUTOSAVE_SECONDS := 180.0  # ~3 minutes of real time

## Resources the colony starts a new game with (a life-support buffer to get
## the first oxygen/water/food buildings up before the colonists run out).
const STARTING_STOCKPILE := {"metal": 200, "oxygen": 100, "water": 100, "food": 100}

## Speed multiplier: 0.0 = paused, 1.0 = normal, 3.0 = fast.
var speed: float = 1.0

## Monotonic simulation tick counter.
var tick: int = 0

## The live game state. Null until new_game() / load_game() is called.
var colony: Colony = null

## True only while the game scene is running the sim. The menu scene sets this
## false so the tick loop and autosave don't run in the background at the menu.
var active := false

var _accumulator: float = 0.0
var _autosave_accum: float = 0.0
var _ended := false

# Edge-triggered alert detector; reset each new_game(). Emits via Events.alert.
var _alerts := AlertMonitor.new()

## Starts a fresh game: generates a map and resets colony state.
func new_game(seed: int, size: int) -> void:
	var map := ColonyMap.new(size, size)
	map.generate(seed)
	colony = Colony.new(map, Defs.buildings, STARTING_STOCKPILE)
	tick = 0
	_accumulator = 0.0
	_autosave_accum = 0.0
	_ended = false
	_alerts = AlertMonitor.new()
	speed = 1.0
	_last_run_speed = 1.0
	active = true

# --- Save / load -------------------------------------------------------------

## Writes the full sim state to `SAVE_DIR/<name>.json`. Returns success.
func save_game(name: String) -> bool:
	if colony == null:
		return false
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var data := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"tick": tick,
		"speed": speed,
		"last_run_speed": _last_run_speed,
		"map": colony.map.to_dict(),
		"colony": colony.to_dict(),
	}
	var f := FileAccess.open(SAVE_DIR + name + SAVE_EXT, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true

## Reconstructs the sim from `SAVE_DIR/<name>.json`. Returns success. On success
## `colony` is the loaded state; the caller then shows the game scene.
func load_game(name: String) -> bool:
	var path := SAVE_DIR + name + SAVE_EXT
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or not data.has("map") or not data.has("colony"):
		return false
	var map := ColonyMap.from_dict(data.map)
	colony = Colony.from_dict(map, Defs.buildings, data.colony)
	tick = int(data.get("tick", 0))
	speed = float(data.get("speed", 1.0))
	_last_run_speed = float(data.get("last_run_speed", 1.0))
	if _last_run_speed <= 0.0:
		_last_run_speed = 1.0
	_accumulator = 0.0
	_autosave_accum = 0.0
	_ended = colony.status != Colony.Status.PLAYING
	_alerts = AlertMonitor.new()
	active = true
	return true

## Save names present on disk (without the extension), newest first.
func list_saves() -> Array:
	var out := []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for fn in dir.get_files():
		if fn.ends_with(SAVE_EXT):
			var name := fn.trim_suffix(SAVE_EXT)
			out.append({"name": name, "mtime": FileAccess.get_modified_time(SAVE_DIR + fn)})
	out.sort_custom(func(a, b): return int(a.mtime) > int(b.mtime))
	var names := []
	for e in out:
		names.append(str(e.name))
	return names

## The most recently modified save name, or "" if there are none.
func latest_save() -> String:
	var saves := list_saves()
	return str(saves[0]) if not saves.is_empty() else ""

func has_saves() -> bool:
	return not list_saves().is_empty()

func delete_save(name: String) -> void:
	var path := SAVE_DIR + name + SAVE_EXT
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

# --- Placement API (thin wrappers that emit Events after mutating state) ---

func can_place(type_id: String, origin: Vector2i) -> Dictionary:
	return colony.can_place(type_id, origin)

func place_building(type_id: String, origin: Vector2i) -> bool:
	var inst = colony.place(type_id, origin)
	if inst == null:
		return false
	Events.building_placed.emit(inst)
	Events.stockpile_changed.emit(colony.stockpile)
	return true

func demolish_at(cell: Vector2i) -> bool:
	var inst = colony.demolish_at(cell)
	if inst == null:
		return false
	Events.building_removed.emit(inst)
	return true

func building_at(cell: Vector2i) -> Dictionary:
	return colony.building_at(cell)

## Inspector display data for a placed building id ({} if it no longer exists).
func building_report(id: int) -> Dictionary:
	return colony.building_report(id)

func _process(delta: float) -> void:
	if not active or colony == null:
		return
	# Autosave runs on real time, regardless of pause, while the game is live.
	if colony.status == Colony.Status.PLAYING:
		_autosave_accum += delta
		if _autosave_accum >= AUTOSAVE_SECONDS:
			_autosave_accum = 0.0
			save_game(AUTOSAVE_NAME)
	if speed <= 0.0 or colony.status != Colony.Status.PLAYING:
		return
	_accumulator += delta * speed
	var step := 1.0 / TICKS_PER_SECOND
	while _accumulator >= step and colony.status == Colony.Status.PLAYING:
		_accumulator -= step
		_advance_tick()
	if colony.status != Colony.Status.PLAYING:
		_end_game()

func _advance_tick() -> void:
	tick += 1
	colony.tick()
	if not colony.scan_changes.is_empty():
		Events.scan_changed.emit(colony.scan_changes)
	for a in _alerts.check(colony):
		Events.alert.emit(a.text, a.level)
	Events.stockpile_changed.emit(colony.stockpile)
	Events.ticked.emit(tick)

# Emitted once when the game reaches a win/lose state; the sim then stays frozen.
func _end_game() -> void:
	if _ended:
		return
	_ended = true
	Events.game_over.emit(colony.status == Colony.Status.WON)

# --- Speed control (pause / 1x / 3x) ---

# Remembers the last running speed so unpausing restores it.
var _last_run_speed := 1.0

func set_speed(mult: float) -> void:
	speed = mult
	if mult > 0.0:
		_last_run_speed = mult

func toggle_pause() -> void:
	speed = 0.0 if speed > 0.0 else _last_run_speed

func is_paused() -> bool:
	return speed <= 0.0

func set_paused(paused: bool) -> void:
	set_speed(0.0 if paused else _last_run_speed)
