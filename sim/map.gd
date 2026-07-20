class_name ColonyMap
extends RefCounted
## The terrain grid — pure sim data. The TileMapLayer is only a view of this;
## game rules read terrain from here, never from sprite nodes.

enum Terrain { REGOLITH, HIGHLANDS, ICE, CRYSTAL, VOID }

const TERRAIN_NAMES := {
	Terrain.REGOLITH: "Flat Regolith",
	Terrain.HIGHLANDS: "Rocky Highlands",
	Terrain.ICE: "Ice Field",
	Terrain.CRYSTAL: "Crystal Formation",
	Terrain.VOID: "Canyon / Void",
}

var width: int
var height: int
var seed: int = 0

# Row-major terrain ids, index = y * width + x.
var _cells: PackedByteArray = PackedByteArray()

func _init(w: int = 64, h: int = 64) -> void:
	width = w
	height = h
	_cells.resize(w * h)

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height

func get_terrain(cell: Vector2i) -> int:
	return _cells[cell.y * width + cell.x]

func set_terrain(cell: Vector2i, t: int) -> void:
	_cells[cell.y * width + cell.x] = t

## Generates terrain from noise. Deterministic for a given seed. Two noise
## fields: base elevation carves void/highlands, a feature field scatters ice
## across the flats and rare crystal across the highlands.
func generate(p_seed: int) -> void:
	seed = p_seed
	var base := FastNoiseLite.new()
	base.seed = p_seed
	base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base.frequency = 0.05
	var feat := FastNoiseLite.new()
	feat.seed = p_seed + 1
	feat.noise_type = FastNoiseLite.TYPE_SIMPLEX
	feat.frequency = 0.11

	for y in height:
		for x in width:
			var e := base.get_noise_2d(x, y)
			var f := feat.get_noise_2d(x, y)
			var t := Terrain.REGOLITH
			if e < -0.45:
				t = Terrain.VOID
			elif e > 0.40:
				t = Terrain.HIGHLANDS
			if t == Terrain.REGOLITH and f > 0.55:
				t = Terrain.ICE
			elif t == Terrain.HIGHLANDS and f < -0.60:
				t = Terrain.CRYSTAL
			set_terrain(Vector2i(x, y), t)
