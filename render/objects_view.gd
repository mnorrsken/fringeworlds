class_name ObjectsView
extends Node2D
## Draws skyfall: rocks on their way down, the impact, and what's left lying on
## the ground afterwards.
##
## Two homes for the sprites, because the two halves live in different places:
##
##   * a falling rock is in the *air*, so it hangs off this node, which sits at a
##     high z_index and paints over the whole base;
##   * a crashing or resting one is on the *ground*, so its sprite is parented
##     into the y-sorted buildings layer — the same trick ColonistsView uses —
##     and a chunk of ice behind a habitat is properly hidden by it.
##
## The descent itself is screen-space: the sim only ever says which tile a rock
## is aimed at and how far through its fall it is, and the angle it comes in at
## is content (data/objects.json), not geometry. Nothing here writes sim state.

var _sort_parent: Node2D = null
var _air: Dictionary = {}      # asteroid id -> { sprite, phase }
var _ground: Dictionary = {}   # cell -> ObjectSprite
var _textures: Dictionary = {} # path -> Texture2D
var _clock := 0.0

func bind(sort_parent: Node2D) -> void:
	_sort_parent = sort_parent
	z_index = 20
	Events.ticked.connect(func(_t: int) -> void: _sync_ground())
	Events.object_landed.connect(func(_c: Vector2i, _k: String) -> void: _sync_ground())
	_sync_ground()

func _process(delta: float) -> void:
	if Sim.colony == null:
		return
	if not Sim.is_paused():
		_clock += delta * Sim.speed
	_sync_air()

# --- rocks in the air --------------------------------------------------------

func _sync_air() -> void:
	var live := {}
	for a in Sim.colony.asteroids.falling:
		var id := int(a.id)
		live[id] = true
		var def: Dictionary = Defs.objects.get(str(a.kind), {})
		if def.is_empty():
			continue
		var phase := int(a.phase)
		var entry: Dictionary = _air.get(id, {})
		# A rock that has just hit the ground changes both its animation and the
		# node it belongs to, so it is simplest to start it again.
		if entry.is_empty() or int(entry.phase) != phase:
			if not entry.is_empty():
				entry.sprite.queue_free()
			entry = {"sprite": _spawn(def, phase), "phase": phase}
			_air[id] = entry
		_pose(entry.sprite, def, a, phase)
	for id in _air.keys():
		if not live.has(id):
			_air[id].sprite.queue_free()
			_air.erase(id)

func _spawn(def: Dictionary, phase: int) -> ObjectSprite:
	var spr := ObjectSprite.new()
	spr.configure(def)
	var state: String = "falling" if phase == Asteroids.Phase.FALLING else "crashing"
	var anim: Dictionary = def.get(state, {})
	spr.set_animation(_texture(str(anim.get("sprite", ""))), int(anim.get("frames", 1)))
	# In the air it paints over everything; on the ground it sorts with the base.
	if phase == Asteroids.Phase.FALLING or _sort_parent == null:
		add_child(spr)
	else:
		_sort_parent.add_child(spr)
	return spr

func _pose(spr: ObjectSprite, def: Dictionary, a: Dictionary, phase: int) -> void:
	var impact := IsoGrid.grid_to_screen(a.cell)
	var p := _progress(a, phase)
	if phase == Asteroids.Phase.FALLING:
		# Straight line in screen space, down and to the left, arriving exactly on
		# the tile. `fall_px` is how far back up that line it starts.
		var ang := deg_to_rad(float(def.get("fall_angle_deg", 70.0)))
		var dir := Vector2(-cos(ang), sin(ang))
		spr.position = impact - dir * float(def.get("fall_px", 640.0)) * (1.0 - p)
		var anim: Dictionary = def.get("falling", {})
		var fps := float(anim.get("fps", 12.0))
		spr.set_frame(int(_clock * fps) % maxi(1, int(anim.get("frames", 1))))
	else:
		# Down. The crash plays once, stretched over the impact, so its last frame
		# lands as the rock comes to rest.
		spr.position = impact
		var frames := int(def.get("crashing", {}).get("frames", 1))
		spr.set_frame(int(p * float(frames)))

# How far through its phase a rock is, with the fraction of the current tick
# folded in — the sim ticks four times a second and the eye follows this.
func _progress(a: Dictionary, phase: int) -> float:
	var total: int = Defs.balance.asteroid_fall_ticks \
		if phase == Asteroids.Phase.FALLING else Defs.balance.asteroid_crash_ticks
	var p := Sim.colony.asteroids.progress(a)
	if total > 0:
		p += Sim.tick_fraction() / float(total)
	return clampf(p, 0.0, 1.0)

# --- what's lying on the ground ----------------------------------------------

func _sync_ground() -> void:
	if Sim.colony == null:
		return
	var objs := Sim.colony.map.objects()
	for cell in objs:
		if _ground.has(cell):
			continue
		var def: Dictionary = Defs.objects.get(str(objs[cell].get("kind", "")), {})
		if def.is_empty():
			continue
		var spr := ObjectSprite.new()
		spr.configure(def)
		spr.set_animation(_texture(str(def.get("resting", {}).get("sprite", ""))), 1)
		spr.position = IsoGrid.grid_to_screen(cell)
		if _sort_parent != null:
			_sort_parent.add_child(spr)
		else:
			add_child(spr)
		_ground[cell] = spr
	# Collected (or otherwise removed) objects lose their sprite. Nothing picks
	# these up yet, but the view shouldn't be the reason that can't change.
	for cell in _ground.keys():
		if not objs.has(cell):
			_ground[cell].queue_free()
			_ground.erase(cell)

func _texture(path: String) -> Texture2D:
	if path == "":
		return null
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]
