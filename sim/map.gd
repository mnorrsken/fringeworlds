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

## Coarse readings jitter the true richness by up to this fraction. Set from
## data/balance.json by Sim; the default matches the shipped balance so a map
## built bare (in tests) reads the same as in game.
var reading_jitter := Balance.new().reading_jitter
## Units a deposit holds at full richness, by deposit name (see Balance).
var deposit_units := Balance.new().deposit_units

var width: int
var height: int
var seed: int = 0

# Row-major layers, index = y * width + x.
var _cells: PackedByteArray = PackedByteArray()       # terrain
var _deposit: PackedByteArray = PackedByteArray()     # Deposit id (hidden)
var _richness: PackedFloat32Array = PackedFloat32Array()  # 0..1 (hidden)
var _amount: PackedFloat32Array = PackedFloat32Array()    # extractable units left
var _scan: PackedByteArray = PackedByteArray()        # Scan state (revealed by play)
var _reading_noise: PackedFloat32Array = PackedFloat32Array()  # -1..1 per cell, for coarse jitter

# Loose objects sitting on the ground — a landed asteroid, and whatever else
# later falls out of the sky. Sparse (a Dictionary, not a layer): there are a
# handful of these on a 64x64 map, not four thousand. Vector2i -> { kind, ... }.
var _objects: Dictionary = {}

func _init(w: int = 64, h: int = 64) -> void:
	width = w
	height = h
	var n := w * h
	_cells.resize(n)
	_deposit.resize(n)
	_richness.resize(n)
	_amount.resize(n)
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

## Units of ore still in the ground here. Extractors draw this down and stop
## when it hits zero — a tile is a finite reserve, not a faucet.
func get_amount(cell: Vector2i) -> float:
	return _amount[cell.y * width + cell.x]

func set_amount(cell: Vector2i, v: float) -> void:
	_amount[cell.y * width + cell.x] = maxf(v, 0.0)

## Sets a cell's hidden deposit type and richness, sizing its reserve from that
## richness. Used at generation and by the hub's "guarantee reachable iron"
## rule; extractors read the type once, at placement, but draw the reserve live.
func set_deposit(cell: Vector2i, dep: int, richness: float) -> void:
	var i := cell.y * width + cell.x
	_deposit[i] = dep
	_richness[i] = richness
	_amount[i] = richness * float(deposit_units.get(Deposit.keys()[dep], 100.0))

## What's left in the ground here as a fraction of what a full-richness deposit
## of this type holds (0..1). Deposit sizes differ by an order of magnitude — 600
## units of iron against 30 of xenite — so the raw unit count says nothing on its
## own: 20 units left is a nearly-untouched crystal and an exhausted iron seam.
## This is the per-type scale that makes "how much is left" comparable, and it is
## what the prospecting overlay shades by.
func remaining_fraction(cell: Vector2i) -> float:
	var dep := get_deposit(cell)
	if dep == Deposit.NONE:
		return 0.0
	var full := float(deposit_units.get(Deposit.keys()[dep], 100.0))
	if full <= 0.0:
		return 0.0
	return clampf(get_amount(cell) / full, 0.0, 1.0)

func get_scan(cell: Vector2i) -> int:
	return _scan[cell.y * width + cell.x]

func set_scan(cell: Vector2i, s: int) -> void:
	_scan[cell.y * width + cell.x] = s

## The richness a coarse scan reports (true value + deterministic jitter).
func coarse_richness(cell: Vector2i) -> float:
	var noise := _reading_noise[cell.y * width + cell.x]
	return clampf(get_richness(cell) + noise * reading_jitter, 0.05, 1.0)

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
			var left := get_amount(cell)
			if left <= 0.0:
				return "%s · worked out" % DEPOSIT_NAMES[dep]
			return "%s · %d units left" % [DEPOSIT_NAMES[dep], int(round(left))]
	return ""

## --- Loose objects on the ground ---------------------------------------------

## The object lying on `cell`, or {} if the tile is clear.
func get_object(cell: Vector2i) -> Dictionary:
	return _objects.get(cell, {})

func has_object(cell: Vector2i) -> bool:
	return _objects.has(cell)

## Drops an object on a tile. `obj` is a plain dict; `kind` names its entry in
## data/objects.json, and the sim only ever reads that id — what an ice asteroid
## is worth is content, not engine code.
func set_object(cell: Vector2i, obj: Dictionary) -> void:
	_objects[cell] = obj

## Picks an object up, returning it ({} if there was nothing there). This is what
## a colonist collecting one will call.
func take_object(cell: Vector2i) -> Dictionary:
	var obj: Dictionary = _objects.get(cell, {})
	_objects.erase(cell)
	return obj

## Every object on the map, cell -> object. The view iterates this to place its
## sprites; treat it as read-only.
func objects() -> Dictionary:
	return _objects

## --- Serialization ---------------------------------------------------------
## A JSON-safe snapshot of the whole map. The four byte layers and two float
## layers are base64-encoded (compact and exact) rather than expanded to int
## arrays. ColonyMap.from_dict() is the inverse.
func to_dict() -> Dictionary:
	# Objects are sparse, so they serialize as a list of [x, y, obj] rather than
	# a layer the size of the map.
	var objs := []
	for cell in _objects:
		objs.append({"x": cell.x, "y": cell.y, "obj": _objects[cell]})
	return {
		"width": width,
		"height": height,
		"seed": seed,
		"objects": objs,
		"cells": Marshalls.raw_to_base64(_cells),
		"deposit": Marshalls.raw_to_base64(_deposit),
		"scan": Marshalls.raw_to_base64(_scan),
		"richness": Marshalls.raw_to_base64(_richness.to_byte_array()),
		"amount": Marshalls.raw_to_base64(_amount.to_byte_array()),
		"reading_noise": Marshalls.raw_to_base64(_reading_noise.to_byte_array()),
	}

## Rebuilds a ColonyMap from a to_dict() snapshot.
static func from_dict(d: Dictionary) -> ColonyMap:
	var m := ColonyMap.new(int(d.width), int(d.height))
	m.seed = int(d.seed)
	m._cells = Marshalls.base64_to_raw(str(d.cells))
	m._deposit = Marshalls.base64_to_raw(str(d.deposit))
	m._scan = Marshalls.base64_to_raw(str(d.scan))
	m._richness = Marshalls.base64_to_raw(str(d.richness)).to_float32_array()
	m._reading_noise = Marshalls.base64_to_raw(str(d.reading_noise)).to_float32_array()
	for e in d.get("objects", []):
		m._objects[Vector2i(int(e.x), int(e.y))] = e.get("obj", {})
	# Saves from before deposits were finite carry no reserves; refill them from
	# richness so an old save loads as an untouched map rather than a dead one.
	if d.has("amount"):
		m._amount = Marshalls.base64_to_raw(str(d.amount)).to_float32_array()
	else:
		for i in m.width * m.height:
			var dep := m._deposit[i]
			if dep != Deposit.NONE:
				m._amount[i] = m._richness[i] \
					* float(m.deposit_units.get(Deposit.keys()[dep], 100.0))
	return m

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
			elif t == Terrain.HIGHLANDS and f < -0.40:
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
		Deposit.IRON: 0.42, Deposit.COPPER: 0.45,
	}
	for dep in thresholds:
		var n := FastNoiseLite.new()
		n.seed = p_seed + dep * 101
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n.frequency = 0.09
		fields[dep] = n

	# Xenite is the exception: it sits in the crystal formations, which are
	# visible terrain. You can see where the crystal is from orbit — what you
	# can't see is how much is in it, so a formation still has to be prospected
	# before an extractor can be sited on it.
	var xen := FastNoiseLite.new()
	xen.seed = p_seed + Deposit.XENITE * 101
	xen.noise_type = FastNoiseLite.TYPE_SIMPLEX
	xen.frequency = 0.14

	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			var t := get_terrain(cell)
			if t == Terrain.CRYSTAL:
				var v := xen.get_noise_2d(x, y) * 0.5 + 0.5   # 0..1
				set_deposit(cell, Deposit.XENITE, clampf(0.25 + v * 0.75, 0.2, 1.0))
				continue
			if t != Terrain.REGOLITH and t != Terrain.HIGHLANDS:
				continue
			var best_dep := Deposit.NONE
			var best_margin := 0.0
			for dep in fields:
				var v2: float = fields[dep].get_noise_2d(x, y)
				var margin: float = v2 - thresholds[dep]
				if margin > 0.0 and margin > best_margin:
					best_margin = margin
					best_dep = dep
			if best_dep != Deposit.NONE:
				# Margin maps to richness; even a thin deposit reads > 0.
				set_deposit(cell, best_dep, clampf(0.2 + best_margin * 1.6, 0.1, 1.0))
