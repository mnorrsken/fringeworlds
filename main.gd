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
@onready var _minimap_root: Control = $MinimapLayer/Root
@onready var _minimap: Minimap = $MinimapLayer/Root/Center/Panel/Margin/VBox/Minimap
@onready var _gameover_root: Control = $GameOverLayer/Root
@onready var _gameover_title: Label = $GameOverLayer/Root/Center/Panel/Margin/VBox/Title
@onready var _gameover_subtitle: Label = $GameOverLayer/Root/Center/Panel/Margin/VBox/Subtitle
@onready var _sysmenu_root: Control = $SystemMenuLayer/Root
@onready var _sysmenu_status: Label = $SystemMenuLayer/Root/Center/Panel/Margin/VBox/Status
@onready var _debug: CanvasLayer = $Debug
@onready var _label: Label = $Debug/Label

var _map: ColonyMap
var _hover := Vector2i(-1, -1)
var _mode := Mode.NONE
var _place_type := ""
var _over_ui := false
var _selected_id := -1  # building inspected in the sidebar, -1 == none
var _sysmenu_was_paused := false  # pause state to restore when the menu closes

const MENU_SCENE := "res://menu.tscn"

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
	_sidebar.demolish_requested.connect(func() -> void: _set_mode(Mode.DEMOLISH))
	_sidebar.populate(Defs.buildings)
	_resource_bar.populate(Defs.resources)
	_minimap.setup(_map, _camera)
	Events.game_over.connect(_on_game_over)
	# New buildings can unlock others, so refresh the build menu's locks on place.
	Events.building_placed.connect(func(_i): _refresh_locks())
	_refresh_locks()
	_wire_system_menu()
	_set_mode(Mode.NONE)

func _wire_system_menu() -> void:
	var vbox := $SystemMenuLayer/Root/Center/Panel/Margin/VBox
	vbox.get_node("ResumeBtn").pressed.connect(_close_system_menu)
	vbox.get_node("SaveBtn").pressed.connect(_on_save_pressed)
	vbox.get_node("MenuBtn").pressed.connect(_on_return_to_menu)
	vbox.get_node("QuitBtn").pressed.connect(func() -> void: get_tree().quit())

func _refresh_locks() -> void:
	var locks := {}
	for id in Defs.buildings:
		var missing := Sim.colony.missing_prereqs(id)
		if missing.is_empty():
			locks[id] = ""
		else:
			var names := []
			for r in missing:
				names.append(str(Defs.buildings[r].name))
			locks[id] = "Requires: " + ", ".join(names)
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
		match event.keycode:
			KEY_F1:
				_debug.visible = not _debug.visible
			KEY_M:
				_minimap_root.visible = not _minimap_root.visible
			KEY_P:
				_toggle_prospect()
			KEY_O:
				_status.toggle()
			KEY_ESCAPE:
				if _minimap_root.visible:
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
			Sim.place_building(_place_type, _hover)
		Mode.DEMOLISH:
			Sim.demolish_at(_hover)
		Mode.NONE:
			# Click a building to inspect it; click empty ground to deselect.
			var b := Sim.building_at(_hover)
			_selected_id = int(b.id) if not b.is_empty() else -1

func _on_right_click() -> void:
	if _mode != Mode.NONE:
		_set_mode(Mode.NONE)
	else:
		Sim.demolish_at(_hover)

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

# Refreshes the sidebar inspector for the selected building; clears the
# selection if that building no longer exists (e.g. it was demolished).
func _update_inspector() -> void:
	if _selected_id == -1:
		_sidebar.set_inspector({})
		return
	var rep := Sim.building_report(_selected_id)
	if rep.is_empty():
		_selected_id = -1
	_sidebar.set_inspector(rep)

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
	var occupant := ""
	var reading := ""
	if _map.in_bounds(_hover):
		terrain = ColonyMap.TERRAIN_NAMES[_map.get_terrain(_hover)]
		reading = _map.reading_text(_hover)
		var b := Sim.building_at(_hover)
		if not b.is_empty():
			occupant = str(Defs.buildings[b.type].name)
	_sidebar.set_tile_info(_hover, terrain, occupant, reading)
	var col := Sim.colony
	# rates() is per-tick; the HUD shows per-second.
	var per_tick := col.rates()
	var per_sec := {}
	for r in per_tick:
		per_sec[r] = per_tick[r] * Sim.TICKS_PER_SECOND
	_resource_bar.set_resources(col.stockpile, per_sec)
	_sidebar.set_economy(col.power_produced, col.power_consumed, Sim.speed)
	_sidebar.set_colony(col.population, col.capacity(), col.workers_used())
	_update_inspector()
	if _debug.visible:
		_label.text = "cell (%d, %d)  %s\nzoom %dx  seed %d  FPS %d  [F1]" % [
			_hover.x, _hover.y, terrain,
			int(_camera.zoom.x), _map.seed, Engine.get_frames_per_second(),
		]
