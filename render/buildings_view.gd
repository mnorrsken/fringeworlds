class_name BuildingsView
extends Node2D
## Spawns/frees BuildingSprites in response to Events. Each building spawns ONE
## sprite per footprint cell, so the y-sorted parent depth-sorts each tile
## individually. This is only a view — it holds no game state.

var _sprites: Dictionary = {}   # building instance id -> Array[BuildingSprite]
var _textures: Dictionary = {}  # sprite path -> Texture2D (cached)

## Connect to sim events and spawn sprites for any buildings already placed.
func bind() -> void:
	Events.building_placed.connect(_on_placed)
	Events.building_removed.connect(_on_removed)
	Events.ticked.connect(_on_ticked)
	for id in Sim.colony.buildings:
		_on_placed(Sim.colony.buildings[id])

# Each tick, reflect the shut-down (unpowered / understaffed) state as dimming.
func _on_ticked(_tick: int) -> void:
	for id in _sprites:
		var inst: Dictionary = Sim.colony.buildings.get(id, {})
		if inst.is_empty():
			continue
		for spr in _sprites[id]:
			spr.set_dimmed(not inst.active)

func _on_placed(inst: Dictionary) -> void:
	var def: Dictionary = Defs.buildings[inst.type]
	var color: Color = def.get("color_value", Color.WHITE)
	var tex := _load_texture(str(def.get("sprite", "")))
	var sprites := []
	if tex != null:
		# Art-backed building: one sprite for the whole footprint, anchored at the
		# front cell; the y-sorted parent occludes buildings behind it.
		var spr := BuildingSprite.new()
		add_child(spr)
		spr.configure(color, inst.cells, false, false, tex)
		_attach_fx(spr, def, int(inst.id))
		sprites.append(spr)
	else:
		# Procedural fallback: one block per footprint cell (per-tile depth sort);
		# smoke only from the front cell so a multi-tile building has one plume.
		var smoke: bool = def.get("smoke", false)
		var front := _front_cell(inst.cells)
		for cell in inst.cells:
			var spr := BuildingSprite.new()
			add_child(spr)
			spr.configure(color, [cell], false, smoke and cell == front)
			sprites.append(spr)
	_sprites[inst.id] = sprites

# Hangs the def's decorative fx (plumes, dust, blinking lamps) on the sprite.
# Offsets in the def are relative to the sprite's anchor, so this only applies to
# art-backed buildings — the procedural block has its own built-in lamps/smoke.
# The building id seeds the cycle phase so a row of the same building blinks and
# puffs out of step.
func _attach_fx(spr: BuildingSprite, def: Dictionary, id: int) -> void:
	var specs: Array = def.get("fx", [])
	if specs.is_empty():
		return
	var fx := BuildingFX.new()
	spr.attach_fx(fx)
	fx.configure(specs, float(id) * 0.37)

# Loads (and caches) a building's art texture, or null if it has none / is missing.
func _load_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]

func _front_cell(cells: Array) -> Vector2i:
	var front: Vector2i = cells[0]
	for c in cells:
		if c.x + c.y > front.x + front.y:
			front = c
	return front

func _on_removed(inst: Dictionary) -> void:
	for spr in _sprites.get(inst.id, []):
		spr.queue_free()
	_sprites.erase(inst.id)
