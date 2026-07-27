extends Node2D
## Game controller: wires input, camera, hover, the build/demolish interaction
## modes, and the sidebar to the Sim. Game rules live in Sim/Colony; this node
## only translates intent.

const MAP_SIZE := 64
const DEFAULT_SEED := 1337

enum Mode { NONE, PLACE, DEMOLISH }

@onready var _terrain: TerrainView = $TerrainView
@onready var _prospect: ProspectOverlay = $ProspectOverlay
@onready var _status: Node2D = $StatusOverlay
@onready var _buildings: BuildingsView = $Buildings
@onready var _camera: IsoCamera = $Camera
@onready var _cursor: TileCursor = $TileCursor
@onready var _ghost: BuildingSprite = $Ghost
@onready var _sidebar := $UI/Sidebar
@onready var _resource_bar := $UI/ResourceBar
@onready var _hover_panel := $UI/HoverPanel
@onready var _help_root: Control = $HelpLayer/Root
@onready var _help_body: Label = $HelpLayer/Root/Center/Panel/Margin/VBox/Body
@onready var _minimap_root: Control = $MinimapLayer/Root
@onready var _minimap: Minimap = $MinimapLayer/Root/Center/Panel/Margin/VBox/Minimap
@onready var _gameover_root: Control = $GameOverLayer/Root
@onready var _gameover_title: Label = $GameOverLayer/Root/Center/Panel/Margin/VBox/Title
@onready var _gameover_subtitle: Label = $GameOverLayer/Root/Center/Panel/Margin/VBox/Subtitle
@onready var _sysmenu_root: Control = $SystemMenuLayer/Root
@onready var _sysmenu_status: Label = $SystemMenuLayer/Root/Center/Panel/Margin/VBox/Status
@onready var _sound_btn: Button = $SystemMenuLayer/Root/Center/Panel/Margin/VBox/SoundBtn
@onready var _debug: CanvasLayer = $Debug
@onready var _label: Label = $Debug/Label

var _map: ColonyMap
var _hover := Vector2i(-1, -1)
var _mode := Mode.NONE
var _place_type := ""
var _over_ui := false
var _sysmenu_was_paused := false  # pause state to restore when the menu closes

const MENU_SCENE := "res://menu.tscn"

## Shown by the ? button in the top bar and the H key. The sidebar used to carry
## this as a permanently-wrapped paragraph, which cost a third of its height to
## something you read once.
const HELP_TEXT := """MOUSE
  Left click — place the selected building
  Right click — demolish, or cancel placement
  Hover — read a tile's terrain, survey reading and building

CAMERA
  WASD, arrows or middle-drag — pan
  Z — zoom

OVERLAYS
  P — prospecting: survey state and readings
  O — building status: what is running or idle
  M — overhead map      F1 — debug coordinates

TIME
  Space — pause      1 / 3 — normal / fast

  H — this screen      Esc — menu (save, sound, quit)

Prospect before you build: deposits stay hidden until surveyed, and a
building placed on an unsurveyed tile can bury the ore underneath it."""

func _ready() -> void:
	# The menu normally sets up the colony (new_game / load_game) before switching
	# here; only fall back to a fresh game if the scene was launched directly.
	if Sim.colony == null:
		Sim.new_game(DEFAULT_SEED, MAP_SIZE)
	Sim.active = true
	_map = Sim.colony.map
	_terrain.render_map(_map)
	_prospect.setup(_map)
	_buildings.bind()
	_camera.position = IsoGrid.grid_to_screen(Vector2i(_map.width / 2, _map.height / 2))
	_ghost.visible = false
	_sidebar.build_requested.connect(_on_build_requested)
	_resource_bar.help_requested.connect(_toggle_help)
	_help_root.get_node("Center/Panel/Margin/VBox/CloseBtn").pressed.connect(func() -> void:
		Audio.ui_click()
		_help_root.visible = false)
	_help_body.text = HELP_TEXT
	_help_body.add_theme_font_size_override("font_size", 14)
	_sidebar.demolish_requested.connect(func() -> void: _set_mode(Mode.DEMOLISH))
	_sidebar.populate(Defs.buildings)
	_resource_bar.populate(Defs.resources)
	_minimap.setup(_map, _camera)
	Events.game_over.connect(_on_game_over)
	# New buildings can unlock others, so refresh the build menu's locks on place.
	# Demolishing matters as much as building now: tearing down the hub (or a
	# one-per-colony building) puts it back in the menu.
	Events.building_placed.connect(func(_i): _refresh_locks())
	Events.building_removed.connect(func(_i): _refresh_locks())
	_refresh_locks()
	_wire_system_menu()
	_set_mode(Mode.NONE)

func _wire_system_menu() -> void:
	var vbox := $SystemMenuLayer/Root/Center/Panel/Margin/VBox
	for btn in vbox.get_children():
		if btn is Button:
			btn.pressed.connect(Audio.ui_click)
	vbox.get_node("ResumeBtn").pressed.connect(_close_system_menu)
	vbox.get_node("SaveBtn").pressed.connect(_on_save_pressed)
	vbox.get_node("SoundBtn").pressed.connect(_on_sound_pressed)
	vbox.get_node("MenuBtn").pressed.connect(_on_return_to_menu)
	vbox.get_node("QuitBtn").pressed.connect(func() -> void:
		Audio.shutdown()
		get_tree().quit())
	_refresh_sound_label()

func _on_sound_pressed() -> void:
	Audio.toggle_mute()
	_refresh_sound_label()

func _refresh_sound_label() -> void:
	_sound_btn.text = "Sound: Off" if Audio.is_muted() else "Sound: On"

func _refresh_locks() -> void:
	var locks := {}
	for id in Defs.buildings:
		locks[id] = Sim.colony.lock_reason(id)
	_sidebar.set_locks(locks)

func _process(_delta: float) -> void:
	_over_ui = get_viewport().gui_get_hovered_control() != null
	var cell := IsoGrid.screen_to_grid(get_global_mouse_position())
	if cell != _hover:
		_hover = cell
		_cursor.cell = cell
	_cursor.visible = not _over_ui and _map.in_bounds(_hover)
	_update_ghost()
	_update_info()

func _update_ghost() -> void:
	if _mode != Mode.PLACE or _over_ui or not _map.in_bounds(_hover):
		_ghost.visible = false
		return
	_ghost.visible = true
	_ghost.set_cells(Sim.colony.footprint(_place_type, _hover))
	_ghost.set_valid(Sim.can_place(_place_type, _hover).ok)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _gameover_root.visible:
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				# Fresh colony on the same map, then reload (which reuses it).
				Sim.new_game(_map.seed, _map.width)
				get_tree().reload_current_scene()
			return
		if _sysmenu_root.visible:
			if event.keycode == KEY_ESCAPE:
				_close_system_menu()
			return
		if _help_root.visible:
			if event.keycode == KEY_ESCAPE or event.keycode == KEY_H:
				_help_root.visible = false
			return
		match event.keycode:
			KEY_F1:
				_debug.visible = not _debug.visible
			KEY_H:
				_toggle_help()
			KEY_M:
				_minimap_root.visible = not _minimap_root.visible
			KEY_P:
				_toggle_prospect()
			KEY_O:
				_status.toggle()
			KEY_ESCAPE:
				if _help_root.visible:
					_help_root.visible = false
				elif _minimap_root.visible:
					_minimap_root.visible = false
				elif _mode != Mode.NONE:
					_set_mode(Mode.NONE)
				else:
					_open_system_menu()
			KEY_SPACE:
				Sim.toggle_pause()
			KEY_1:
				Sim.set_speed(1.0)
			KEY_3:
				Sim.set_speed(3.0)
		return
	if event is InputEventMouseButton and event.pressed and not _over_ui \
			and not _sysmenu_root.visible:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_on_right_click()

func _on_left_click() -> void:
	if not _map.in_bounds(_hover):
		return
	match _mode:
		Mode.PLACE:
			# Success plays via Events.building_placed; only the refusal is ours.
			if not Sim.place_building(_place_type, _hover):
				Audio.play(AudioCues.DENIED)
		Mode.DEMOLISH:
			if not Sim.demolish_at(_hover):
				Audio.play(AudioCues.DENIED)
		Mode.NONE:
			pass  # nothing to select: hovering a tile already shows its readout

func _on_right_click() -> void:
	if _mode != Mode.NONE:
		_set_mode(Mode.NONE)
	elif not Sim.demolish_at(_hover):
		Audio.play(AudioCues.DENIED)

func _on_build_requested(type_id: String) -> void:
	_place_type = type_id
	_set_mode(Mode.PLACE)
	_ghost.configure(Defs.buildings[type_id].get("color_value", Color.WHITE),
		Sim.colony.footprint(type_id, _hover), true)

func _set_mode(mode: Mode) -> void:
	_mode = mode
	_cursor.demolish = (mode == Mode.DEMOLISH)
	if mode != Mode.PLACE:
		_ghost.visible = false
	_sidebar.set_mode_label(_mode_name())

func _on_game_over(won: bool) -> void:
	_gameover_title.text = "BEACON LAUNCHED" if won else "COLONY LOST"
	_gameover_subtitle.text = ("The colony endures — victory!\n" if won
		else "The last colonist is gone.\n") + "Press Enter to start a new colony."
	_gameover_root.visible = true

# The readout for whatever is under the cursor. Hidden while the cursor is over
# the sidebar or off the map, and while a full-screen overlay is up — a panel
# chasing the mouse across a modal would just be noise.
func _update_hover_panel(terrain: String, reading: String) -> void:
	if _over_ui or not _map.in_bounds(_hover) or _minimap_root.visible \
			or _sysmenu_root.visible or _help_root.visible or _gameover_root.visible:
		_hover_panel.hide_info()
		return
	var b := Sim.building_at(_hover)
	var report := Sim.building_report(int(b.id)) if not b.is_empty() else {}
	_hover_panel.show_tile(terrain, reading, report)
	_hover_panel.place_at(get_viewport().get_mouse_position())

func _toggle_help() -> void:
	_help_root.visible = not _help_root.visible

# --- System / pause menu (Save, Main Menu, Quit) ---

func _open_system_menu() -> void:
	_sysmenu_was_paused = Sim.is_paused()
	Sim.set_paused(true)  # freeze the sim behind the menu
	_sysmenu_status.text = ""
	_sysmenu_root.visible = true

func _close_system_menu() -> void:
	_sysmenu_root.visible = false
	Sim.set_paused(_sysmenu_was_paused)

func _on_save_pressed() -> void:
	_sysmenu_status.text = "Game saved." if Sim.save_game("quicksave") else "Save failed."

func _on_return_to_menu() -> void:
	Sim.active = false  # stop the sim; the menu freezes it too
	get_tree().change_scene_to_file(MENU_SCENE)

func _toggle_prospect() -> void:
	_prospect.visible = not _prospect.visible
	if _prospect.visible:
		_prospect.rebuild()

func _mode_name() -> String:
	match _mode:
		Mode.PLACE:
			return "PLACE  " + str(Defs.buildings[_place_type].name)
		Mode.DEMOLISH:
			return "DEMOLISH"
		_:
			return "SELECT"

func _update_info() -> void:
	var terrain := "—"
	var reading := ""
	if _map.in_bounds(_hover):
		terrain = ColonyMap.TERRAIN_NAMES[_map.get_terrain(_hover)]
		reading = _map.reading_text(_hover)
	_update_hover_panel(terrain, reading)
	var col := Sim.colony
	# rates() is per-tick; the HUD shows per-second.
	var per_tick := col.rates()
	var per_sec := {}
	for r in per_tick:
		per_sec[r] = per_tick[r] * Sim.ticks_per_second
	var caps := {}
	for r in Defs.resources:
		caps[r] = col.storage_for(r)
	_resource_bar.set_resources(col.stockpile, per_sec, caps)
	_resource_bar.set_stats(col.power_produced, col.power_consumed,
		col.population, col.capacity(), col.workers_used())
	_sidebar.set_speed(Sim.speed)
	if _debug.visible:
		_label.text = "cell (%d, %d)  %s\nzoom %dx  seed %d  FPS %d  [F1]" % [
			_hover.x, _hover.y, terrain,
			int(_camera.zoom.x), _map.seed, Engine.get_frames_per_second(),
		]
