class_name ColonyMap
extends RefCounted
## The terrain grid — pure sim data. The TileMapLayer is only a view of this;
## game rules read terrain from here, never from sprite nodes.

enum Terrain { REGOLITH, HIGHLANDS, ICE, CRYSTAL, VOID }

## Hidden subsurface deposits, found via prospecting.
enum Deposit { NONE, IRON, COPPER, XENITE }

## Per-tile prospecting knowledge.
enum Scan { UNSCANNED, COARSE, CONFIRMED }

const TERRAIN_NAMES := {
	Terrain.REGOLITH: "Flat Regolith",
	Terrain.HIGHLANDS: "Rocky Highlands",
	Terrain.ICE: "Ice Field",
	Terrain.CRYSTAL: "Crystal Formation",
	Terrain.VOID: "Canyon / Void",
}

const DEPOSIT_NAMES := {
	Deposit.NONE: "—",
	Deposit.IRON: "Iron Ore",
	Deposit.COPPER: "Copper Ore",
	Deposit.XENITE: "Xenite",
}

## Deposit type -> the stockpile resource a matching extractor yields.
const DEPOSIT_RESOURCE := {
	Deposit.IRON: "iron_ore",
	Deposit.COPPER: "copper_ore",
	Deposit.XENITE: "xenite",
}

## Coarse readings only reveal a rough category, not the exact ore.
const DEPOSIT_CATEGORY := {
	Deposit.IRON: "metal",
	Deposit.COPPER: "metal",
	Deposit.XENITE: "crystal",
}

# Coarse readings jitter the true richness by up to this fraction.
const READING_JITTER := 0.25

var width: int
var height: int
var seed: int = 0

# Row-major layers, index = y * width + x.
var _cells: PackedByteArray = PackedByteArray()       # terrain
var _deposit: PackedByteArray = PackedByteArray()     # Deposit id (hidden)
var _richness: PackedFloat32Array = PackedFloat32Array()  # 0..1 (hidden)
var _scan: PackedByteArray = PackedByteArray()        # Scan state (revealed by play)
var _reading_noise: PackedFloat32Array = PackedFloat32Array()  # -1..1 per cell, for coarse jitter

func _init(w: int = 64, h: int = 64) -> void:
	width = w
	height = h
	var n := w * h
	_cells.resize(n)
	_deposit.resize(n)
	_richness.resize(n)
	_scan.resize(n)
	_reading_noise.resize(n)

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height

func get_terrain(cell: Vector2i) -> int:
	return _cells[cell.y * width + cell.x]

func set_terrain(cell: Vector2i, t: int) -> void:
	_cells[cell.y * width + cell.x] = t

func get_deposit(cell: Vector2i) -> int:
	return _deposit[cell.y * width + cell.x]

func get_richness(cell: Vector2i) -> float:
	return _richness[cell.y * width + cell.x]

func get_scan(cell: Vector2i) -> int:
	return _scan[cell.y * width + cell.x]

func set_scan(cell: Vector2i, s: int) -> void:
	_scan[cell.y * width + cell.x] = s

## The richness a coarse scan reports (true value + deterministic jitter).
func coarse_richness(cell: Vector2i) -> float:
	var noise := _reading_noise[cell.y * width + cell.x]
	return clampf(get_richness(cell) + noise * READING_JITTER, 0.05, 1.0)

## Human-readable prospecting reading for the sidebar; "" if unscanned.
func reading_text(cell: Vector2i) -> String:
	var dep := get_deposit(cell)
	match get_scan(cell):
		Scan.COARSE:
			if dep == Deposit.NONE:
				return "coarse scan: barren"
			return "coarse: %s traces (~%d%%)" % [
				DEPOSIT_CATEGORY[dep], int(round(coarse_richness(cell) * 100))]
		Scan.CONFIRMED:
			if dep == Deposit.NONE:
				return "confirmed: barren"
			return "%s · richness %d%%" % [
				DEPOSIT_NAMES[dep], int(round(get_richness(cell) * 100))]
	return ""

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

	_generate_deposits(p_seed)

# Blob-shaped subsurface deposits, one low-frequency noise field per type, only
# under buildable ground. The winning type per cell is the one furthest above
# its threshold; richness scales with that margin. Deterministic per seed.
func _generate_deposits(p_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed * 7919 + 13
	for i in width * height:
		_reading_noise[i] = rng.randf_range(-1.0, 1.0)

	var fields := {}
	var thresholds := {
		Deposit.IRON: 0.42, Deposit.COPPER: 0.45, Deposit.XENITE: 0.58,
	}
	for dep in thresholds:
		var n := FastNoiseLite.new()
		n.seed = p_seed + dep * 101
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n.frequency = 0.09
		fields[dep] = n

	for y in height:
		for x in width:
			var t := get_terrain(Vector2i(x, y))
			if t != Terrain.REGOLITH and t != Terrain.HIGHLANDS:
				continue
			var best_dep := Deposit.NONE
			var best_margin := 0.0
			for dep in fields:
				var v: float = fields[dep].get_noise_2d(x, y)
				var margin: float = v - thresholds[dep]
				if margin > 0.0 and margin > best_margin:
					best_margin = margin
					best_dep = dep
			if best_dep != Deposit.NONE:
				var i := y * width + x
				_deposit[i] = best_dep
				# Margin maps to richness; even a thin deposit reads > 0.
				_richness[i] = clampf(0.2 + best_margin * 1.6, 0.1, 1.0)
