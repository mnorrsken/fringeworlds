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

## Resources the colony starts a new game with (a life-support buffer to get
## the first oxygen/water/food buildings up before the colonists run out).
const STARTING_STOCKPILE := {"metal": 100, "oxygen": 60, "water": 60, "food": 60}

## Speed multiplier: 0.0 = paused, 1.0 = normal, 3.0 = fast.
var speed: float = 1.0

## Monotonic simulation tick counter.
var tick: int = 0

## The live game state. Null until new_game() is called.
var colony: Colony = null

var _accumulator: float = 0.0
var _ended := false

## Starts a fresh game: generates a map and resets colony state.
func new_game(seed: int, size: int) -> void:
	var map := ColonyMap.new(size, size)
	map.generate(seed)
	colony = Colony.new(map, Defs.buildings, STARTING_STOCKPILE)
	tick = 0
	_accumulator = 0.0
	_ended = false
	speed = 1.0
	_last_run_speed = 1.0

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

func _process(delta: float) -> void:
	if colony == null or speed <= 0.0 or colony.status != Colony.Status.PLAYING:
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
