class_name BuildingsView
extends Node2D
## Spawns/frees BuildingSprites in response to Events, keyed by instance id.
## Enable y_sort on this node (in the scene) so overlapping buildings order by
## their front tile. This is only a view — it holds no game state.

var _sprites: Dictionary = {}  # building instance id -> BuildingSprite

## Connect to sim events and spawn sprites for any buildings already placed.
func bind() -> void:
	Events.building_placed.connect(_on_placed)
	Events.building_removed.connect(_on_removed)
	for id in Sim.colony.buildings:
		_on_placed(Sim.colony.buildings[id])

func _on_placed(inst: Dictionary) -> void:
	var spr := BuildingSprite.new()
	add_child(spr)
	spr.configure(Defs.buildings[inst.type], inst.origin, false)
	_sprites[inst.id] = spr

func _on_removed(inst: Dictionary) -> void:
	var spr: BuildingSprite = _sprites.get(inst.id)
	if spr != null:
		spr.queue_free()
	_sprites.erase(inst.id)
