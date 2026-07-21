class_name BuildingsView
extends Node2D
## Spawns/frees BuildingSprites in response to Events. Each building spawns ONE
## sprite per footprint cell, so the y-sorted parent depth-sorts each tile
## individually. This is only a view — it holds no game state.

var _sprites: Dictionary = {}  # building instance id -> Array[BuildingSprite]

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
	var color: Color = Defs.buildings[inst.type].get("color_value", Color.WHITE)
	var sprites := []
	for cell in inst.cells:
		var spr := BuildingSprite.new()
		add_child(spr)
		spr.configure(color, [cell], false)
		sprites.append(spr)
	_sprites[inst.id] = sprites

func _on_removed(inst: Dictionary) -> void:
	for spr in _sprites.get(inst.id, []):
		spr.queue_free()
	_sprites.erase(inst.id)
