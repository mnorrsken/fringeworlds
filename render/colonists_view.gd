class_name ColonistsView
extends Node2D
## Drives the colonist crowd and keeps one ColonistSprite per walker on screen.
##
## The sprites are *not* children of this node: they are parented into the
## y-sorted buildings layer, so a colonist walking behind a habitat is hidden by
## it and one crossing in front is drawn over it. Sorting only interleaves
## siblings, so sharing that parent is the whole trick.
##
## This node holds no game state — it steps the (cosmetic) crowd in real time,
## frozen while the sim is paused and sped up with it, and reads sim state only
## through Events and Sim.colony.

var crowd: ColonistCrowd = null

var _sort_parent: Node2D = null
var _sprites: Dictionary = {}   # walker id -> ColonistSprite
var _texture: Texture2D = null
var _cfg: Dictionary = {}
var _fps := 8.0
var _clock := 0.0

## `sort_parent` is the y-sorted node the walker sprites live in (the buildings
## layer). Call after BuildingsView.bind(), so the colony already has its sprites.
func bind(sort_parent: Node2D) -> void:
	_sort_parent = sort_parent
	_cfg = Defs.colonists
	_fps = maxf(1.0, float(_cfg.get("fps", 8.0)))
	var path := str(_cfg.get("sprite", ""))
	if path != "" and ResourceLoader.exists(path):
		_texture = load(path)
	crowd = ColonistCrowd.new(Sim.colony, _cfg)
	Events.building_placed.connect(func(_i: Dictionary) -> void: crowd.refresh())
	Events.building_removed.connect(func(_i: Dictionary) -> void: crowd.refresh())
	# Population, staffing and shut-downs all move on the tick, and the crowd is
	# what makes them visible: a building that just lost power empties out.
	Events.ticked.connect(func(_t: int) -> void: crowd.refresh())

func _process(delta: float) -> void:
	if crowd == null or _sort_parent == null:
		return
	if Sim.is_paused():
		return
	var scaled := delta * Sim.speed
	_clock += scaled
	crowd.step(scaled)
	_sync_sprites()

func _sync_sprites() -> void:
	var live := {}
	for w in crowd.walkers:
		var id := int(w.id)
		live[id] = true
		if int(w.state) == ColonistCrowd.State.INSIDE:
			if _sprites.has(id):
				_sprites[id].visible = false
			continue
		var spr: ColonistSprite = _sprites.get(id)
		if spr == null:
			spr = ColonistSprite.new()
			spr.configure(_texture, _cfg)
			_sort_parent.add_child(spr)
			_sprites[id] = spr
		spr.visible = true
		spr.position = IsoGrid.grid_to_screen_f(w.pos + w.offset)
		# Standing colonists hold frame 0; walkers cycle, offset by id so a group
		# crossing the yard isn't in lockstep.
		var frame := 0
		if int(w.state) == ColonistCrowd.State.WALKING:
			frame = int(_clock * _fps + id * 1.7)
		spr.set_pose(int(w.facing), frame)
	for id in _sprites.keys():
		if not live.has(id):
			_sprites[id].queue_free()
			_sprites.erase(id)
