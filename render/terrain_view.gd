class_name TerrainView
extends TileMapLayer
## A view of ColonyMap. Builds a procedural isometric tileset: each terrain gets
## several dithered variants for a textured SC2000-ish ground, and the special
## terrains (ice, crystal) get a few animation frames so they shimmer. All
## colours come from Palette.
##
## The ground is meant to read as continuous terrain, not a stack of plates: the
## tiles carry no bevel and only a faint seam where they meet, so the grid is a
## hint rather than an outline. Legibility of *which* tile you're on comes from
## the hover cursor and the overlays instead.
##
## A share of tiles use "clutter" variants — stones on regolith, craters and
## rubble on highlands, cracks in ice — so the ground has incident without every
## tile looking hand-placed.

# 4x4 ordered (Bayer) dither matrix — the classic pixel-art gradient technique.
const BAYER := [
	[0, 8, 2, 10],
	[12, 4, 14, 6],
	[3, 11, 1, 9],
	[15, 7, 13, 5],
]

# Per terrain: plain variants, animation frames, how many cluttered variants to
# also generate, and the percentage of tiles that should use one. Clutter is
# kept sparse — every tile having a rock reads as wallpaper, not ground.
const SPEC := {
	ColonyMap.Terrain.REGOLITH: {"variants": 5, "frames": 1, "clutter": 3, "clutter_pct": 28},
	ColonyMap.Terrain.HIGHLANDS: {"variants": 5, "frames": 1, "clutter": 3, "clutter_pct": 34},
	ColonyMap.Terrain.ICE: {"variants": 2, "frames": 3, "clutter": 2, "clutter_pct": 22},
	ColonyMap.Terrain.CRYSTAL: {"variants": 2, "frames": 3, "clutter": 0, "clutter_pct": 0},
}

# Canyons are autotiled instead of picked at random: which walls a void tile
# draws depends on which of its neighbours are solid ground. Only the two
# *far* edges can be seen from this camera angle — you look over the near rim
# and down at the opposite wall — so a two-bit mask covers it.
const VOID_NW := 1   # solid ground up-left  (cell.x - 1)
const VOID_NE := 2   # solid ground up-right (cell.y - 1)
const VOID_VARIANTS := 2
## How far the lit wall reaches down before everything is black, in the tile's
## normalised space. Past this there is no bottom — that's the whole point.
const WALL_DEPTH := 0.85

# How far out the faint seam between tiles starts (1.0 == the diamond edge).
const SEAM_START := 0.955
# The mask is relaxed slightly past the true diamond so neighbouring tiles
# overlap by a pixel at the corners. Without the old black rim to hide them,
# the geometric gaps where four tiles meet would otherwise show through.
const MASK_LIMIT := 1.03

# Representative base tone per terrain, used by the minimap.
const TERRAIN_COLORS := {
	ColonyMap.Terrain.REGOLITH: Palette.REGOLITH,
	ColonyMap.Terrain.HIGHLANDS: Palette.HIGHLANDS,
	ColonyMap.Terrain.ICE: Palette.ICE,
	ColonyMap.Terrain.CRYSTAL: Palette.CRYSTAL,
	ColonyMap.Terrain.VOID: Palette.VOID,
}

var _variant_coords: Dictionary = {}  # terrain -> Array[Vector2i] (plain variants)
var _clutter_coords: Dictionary = {}  # terrain -> Array[Vector2i] (cluttered variants)
var _void_coords: Dictionary = {}     # wall mask (0-3) -> Array[Vector2i]

func _ready() -> void:
	tile_set = _build_tileset()

func render_map(map: ColonyMap) -> void:
	clear()
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var terrain := map.get_terrain(cell)
			if terrain == ColonyMap.Terrain.VOID:
				var walls: Array = _void_coords[_void_mask(map, cell)]
				set_cell(cell, 0, walls[_cell_variant(cell, walls.size())])
				continue
			var coords: Array = _variant_coords[terrain]
			var clutter: Array = _clutter_coords.get(terrain, [])
			# A second, independent hash decides clutter, so a tile's texture and
			# whether it has a rock on it don't correlate into visible banding.
			if not clutter.is_empty() \
					and _cell_hash(cell, 26699) % 100 < int(SPEC[terrain].clutter_pct):
				coords = clutter
			set_cell(cell, 0, coords[_cell_variant(cell, coords.size())])

# Which walls a canyon tile shows: one per neighbouring tile of solid ground on
# the two edges facing the camera. Off-map counts as open, so the canyon runs off
# the edge of the world rather than ending in a wall.
func _void_mask(map: ColonyMap, cell: Vector2i) -> int:
	var mask := 0
	if _is_solid(map, cell + Vector2i(-1, 0)):
		mask |= VOID_NW
	if _is_solid(map, cell + Vector2i(0, -1)):
		mask |= VOID_NE
	return mask

func _is_solid(map: ColonyMap, cell: Vector2i) -> bool:
	return map.in_bounds(cell) and map.get_terrain(cell) != ColonyMap.Terrain.VOID

# Deterministic per-cell variant pick, so the ground looks varied but stable.
func _cell_variant(cell: Vector2i, n: int) -> int:
	return _cell_hash(cell, 0) % n

func _cell_hash(cell: Vector2i, salt: int) -> int:
	return abs((cell.x * 73856093) ^ (cell.y * 19349663) ^ (salt * 83492791))

func _build_tileset() -> TileSet:
	var w := IsoGrid.TILE_W
	var h := IsoGrid.TILE_H
	var total := 4 * VOID_VARIANTS
	for t in SPEC:
		total += (int(SPEC[t].variants) + int(SPEC[t].clutter)) * int(SPEC[t].frames)
	var img := Image.create(total * w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Draw every variant (and its animation frames) into successive atlas columns.
	# Cluttered variants follow the plain ones for each terrain.
	_variant_coords.clear()
	_clutter_coords.clear()
	var col := 0
	for t in SPEC:
		var frames := int(SPEC[t].frames)
		var plain := []
		var cluttered := []
		var n_plain := int(SPEC[t].variants)
		for vi in n_plain + int(SPEC[t].clutter):
			var has_clutter := vi >= n_plain
			if has_clutter:
				cluttered.append(Vector2i(col, 0))
			else:
				plain.append(Vector2i(col, 0))
			for fi in frames:
				_draw_terrain(img, col, t, vi, fi, has_clutter)
				col += 1
		_variant_coords[t] = plain
		if not cluttered.is_empty():
			_clutter_coords[t] = cluttered

	_void_coords.clear()
	for mask in 4:
		var walls := []
		for vi in VOID_VARIANTS:
			walls.append(Vector2i(col, 0))
			_draw_void(img, col, mask, vi)
			col += 1
		_void_coords[mask] = walls

	var src := TileSetAtlasSource.new()
	src.texture_region_size = Vector2i(w, h)
	src.texture = ImageTexture.create_from_image(img)
	for t in _variant_coords:
		var frames := int(SPEC[t].frames)
		for base in _variant_coords[t] + _clutter_coords.get(t, []):
			src.create_tile(base)
			if frames > 1:
				src.set_tile_animation_frames_count(base, frames)
				for fi in frames:
					src.set_tile_animation_frame_duration(base, fi, 0.4)
	for mask in _void_coords:
		for base in _void_coords[mask]:
			src.create_tile(base)

	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(w, h)
	ts.add_source(src, 0)
	return ts

# Draws one terrain diamond into the atlas column `col`: a Bayer-dithered fill
# with sparse flecks, a faint seam at the tile boundary, optional clutter, and
# (for ice/crystal) sparkle that shifts per animation frame.
#
# The fill is deliberately flat. The old version had a strong top-lit gradient
# plus a bevel, which made each tile read as a raised plate; a near-flat fill
# lets neighbouring tiles of the same terrain flow into one another.
func _draw_terrain(img: Image, col: int, terrain: int, variant: int, frame: int,
		has_clutter: bool) -> void:
	var w := IsoGrid.TILE_W
	var h := IsoGrid.TILE_H
	var ox := col * w
	var cx := (w - 1) / 2.0
	var cy := (h - 1) / 2.0
	var pal: Dictionary = _palette(terrain)

	for ly in h:
		for lx in w:
			var dx := (lx - cx) / (w / 2.0)
			var dy := (ly - cy) / (h / 2.0)
			var d := absf(dx) + absf(dy)
			if d > MASK_LIMIT:
				continue
			# Just enough vertical shading to keep the ground from looking like
			# flat paper, plus per-variant mottling dithered between the tones.
			var shade := 0.66 - 0.10 * dy
			shade += 0.09 * sin(lx * 0.5 + variant * 2.1) + 0.09 * sin(ly * 0.8 + variant * 1.3)
			var c: Color = pal.hi if clampf(shade, 0.0, 1.0) > BAYER[ly % 4][lx % 4] / 16.0 else pal.lo
			# A hint of the grid: the boundary darkens slightly rather than
			# carrying an outline.
			if d > SEAM_START:
				c = c.lerp(pal.seam, 0.5)
			img.set_pixel(ox + lx, ly, c)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash([terrain, variant])
	for i in int(pal.fleck_n):
		var fx := rng.randi_range(8, w - 9)
		var fy := rng.randi_range(4, h - 5)
		if _in_diamond(fx, fy, cx, cy, w, h):
			img.set_pixel(ox + fx, fy, pal.fleck if rng.randf() > 0.5 else pal.fleck_dk)

	if has_clutter:
		_draw_clutter(img, ox, terrain, variant, pal, cx, cy, w, h)

	if pal.has("sparkle"):
		var srng := RandomNumberGenerator.new()
		srng.seed = hash([terrain, variant, frame, 977])
		for i in 3:
			var sx := srng.randi_range(10, w - 11)
			var sy := srng.randi_range(6, h - 7)
			if _in_diamond(sx, sy, cx, cy, w, h):
				img.set_pixel(ox + sx, sy, pal.sparkle)

# --- canyons ----------------------------------------------------------------

# Draws one canyon tile: the sunlit tops of whichever walls face the camera,
# falling away through a dithered ramp into black. Nothing draws a floor,
# because there isn't one — the unbroken darkness is what sells the depth.
#
# Only the two far walls are drawn. From this camera you look over a rift's near
# rim and see the *opposite* wall; the near one faces away and is never visible.
func _draw_void(img: Image, col: int, mask: int, variant: int) -> void:
	var w := IsoGrid.TILE_W
	var h := IsoGrid.TILE_H
	var ox := col * w
	var cx := (w - 1) / 2.0
	var cy := (h - 1) / 2.0
	var ramp := _wall_ramp()

	# Per-column depth jitter, so the walls bottom out in a ragged line of strata
	# instead of a clean bevel.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([mask, variant, 8123])
	var strata := PackedFloat32Array()
	var grain := PackedFloat32Array()
	for i in w:
		strata.append(rng.randf_range(0.74, 1.26))
		grain.append(rng.randf_range(0.82, 1.06))

	for ly in h:
		for lx in w:
			var dx := (lx - cx) / (w / 2.0)
			var dy := (ly - cy) / (h / 2.0)
			if absf(dx) + absf(dy) > MASK_LIMIT:
				continue
			# Distance below each lit rim, 0 at the edge and growing inward.
			var depth := 99.0
			if mask & VOID_NW:
				depth = minf(depth, 1.0 + dx + dy)
			if mask & VOID_NE:
				depth = minf(depth, 1.0 - dx + dy)
			var c: Color = Palette.VOID_ABYSS
			var wall := WALL_DEPTH * strata[lx]
			if depth < wall:
				# Falls off faster than linear, so the lit band hugs the lip and
				# the eye reads a long drop rather than a shallow bevel. The
				# per-column grain breaks the face into rough vertical strata.
				var b := pow(1.0 - depth / wall, 1.35) * grain[lx]
				c = _ramp_color(ramp, b, lx, ly)
			img.set_pixel(ox + lx, ly, c)

# Canyon rock from the abyss up to the sunlit lip. The lip is lighter than any
# ground tone, so the rim reads as a hard edge against the dark.
func _wall_ramp() -> Array:
	var lip := Palette.VOID_RIM
	return [
		Palette.VOID_ABYSS,
		lip.darkened(0.84),
		lip.darkened(0.62),
		lip.darkened(0.38),
		lip.darkened(0.16),
		lip,
	]

# Picks from a dark-to-light ramp, dithering between neighbouring steps so the
# gradient stays pixel-art rather than a smooth blend.
func _ramp_color(ramp: Array, b: float, lx: int, ly: int) -> Color:
	var f := clampf(b, 0.0, 1.0) * (ramp.size() - 1)
	var i := int(floor(f))
	if f - i > BAYER[ly % 4][lx % 4] / 16.0:
		i += 1
	return ramp[clampi(i, 0, ramp.size() - 1)]

func _in_diamond(px: float, py: float, cx: float, cy: float, w: int, h: int) -> bool:
	return absf((px - cx) / (w / 2.0)) + absf((py - cy) / (h / 2.0)) <= 0.85

# --- ground clutter ----------------------------------------------------------

# The small stuff that makes ground read as a place rather than a texture:
# scattered stones on regolith, impact craters and rubble on the highlands,
# pressure cracks in ice. Deterministic per variant, so a tile never changes
# under the player.
func _draw_clutter(img: Image, ox: int, terrain: int, variant: int,
		pal: Dictionary, cx: float, cy: float, w: int, h: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([terrain, variant, 5501])
	match terrain:
		ColonyMap.Terrain.REGOLITH:
			for i in rng.randi_range(2, 3):
				_draw_stone(img, ox, rng.randi_range(14, w - 15), rng.randi_range(7, h - 8),
					rng.randi_range(2, 3), pal, cx, cy, w, h)
		ColonyMap.Terrain.HIGHLANDS:
			for i in rng.randi_range(1, 2):
				_draw_crater(img, ox, rng.randi_range(18, w - 19), rng.randi_range(9, h - 10),
					rng.randi_range(4, 6), rng.randi_range(2, 3), pal, cx, cy, w, h)
			for i in rng.randi_range(1, 2):
				_draw_stone(img, ox, rng.randi_range(14, w - 15), rng.randi_range(7, h - 8),
					rng.randi_range(2, 3), pal, cx, cy, w, h)
		ColonyMap.Terrain.ICE:
			_draw_crack(img, ox, rng.randi_range(20, w - 21), rng.randi_range(10, h - 11),
				rng, pal, cx, cy, w, h)

# A rock: a squat ellipse (wider than tall, to sit in the isometric plane), lit
# on its upper left and shadowed on the lower right, with a cast shadow beneath.
# It uses its own stone tones rather than the terrain's flecks, so it reads as a
# different material lying on the ground instead of a bright speck of it.
func _draw_stone(img: Image, ox: int, x: int, y: int, r: int, pal: Dictionary,
		cx: float, cy: float, w: int, h: int) -> void:
	var wide := r + 1.4
	var tall := maxf(r * 0.85, 1.0)
	for dy in range(-r - 1, r + 2):
		for dx in range(-r - 2, r + 3):
			var nx := dx / wide
			var ny := dy / tall
			if nx * nx + ny * ny > 1.0:
				continue
			var px := x + dx
			var py := y + dy
			if not _in_diamond(px, py, cx, cy, w, h):
				continue
			img.set_pixel(ox + px, py, pal.stone if dx + dy * 2 <= 0 else pal.stone_dk)
	# Cast shadow: one row under the stone, offset down-right from the light.
	for dx in range(0, r + 2):
		var px := x + dx
		var py := y + int(tall) + 1
		if _in_diamond(px, py, cx, cy, w, h):
			img.set_pixel(ox + px, py, pal.seam)

# An impact crater: a dished floor, its near wall in shadow and the far rim
# catching the light — the same top-lit convention the buildings use.
func _draw_crater(img: Image, ox: int, x: int, y: int, rx: int, ry: int,
		pal: Dictionary, cx: float, cy: float, w: int, h: int) -> void:
	var floor_col: Color = pal.lo.darkened(0.12)
	var shadow: Color = pal.lo.darkened(0.24)
	for dy in range(-ry - 1, ry + 2):
		for dx in range(-rx - 1, rx + 2):
			var px := x + dx
			var py := y + dy
			if not _in_diamond(px, py, cx, cy, w, h):
				continue
			var nx := float(dx) / float(rx)
			var ny := float(dy) / float(ry)
			var e := nx * nx + ny * ny
			if e > 1.35:
				continue
			if e > 0.62:
				img.set_pixel(ox + px, py, shadow if dy < 0 else pal.fleck)
			else:
				img.set_pixel(ox + px, py, floor_col)

# A pressure crack: a short jagged dark line, drifting one pixel at a time.
func _draw_crack(img: Image, ox: int, x: int, y: int, rng: RandomNumberGenerator,
		pal: Dictionary, cx: float, cy: float, w: int, h: int) -> void:
	var col: Color = pal.lo.darkened(0.3)
	var px := x
	var py := y
	for i in rng.randi_range(8, 14):
		if _in_diamond(px, py, cx, cy, w, h):
			img.set_pixel(ox + px, py, col)
		px += rng.randi_range(1, 2)
		py += rng.randi_range(-1, 1)

# Colour set per terrain: light/dark dither tones, the seam tone that hints at
# the tile boundary, flecks, and an optional sparkle for animated terrains.
# `seam` is a darker relative of the terrain itself rather than the shared black
# outline — that's what keeps the grid a hint instead of a lattice.
func _palette(terrain: int) -> Dictionary:
	match terrain:
		ColonyMap.Terrain.REGOLITH:
			return {
				"hi": Palette.REGOLITH_HI, "lo": Palette.REGOLITH_LO,
				"seam": Palette.REGOLITH_LO.darkened(0.3),
				"stone": Palette.HIGHLANDS_HI, "stone_dk": Palette.HIGHLANDS_LO,
				"fleck": Palette.REGOLITH_FLECK, "fleck_dk": Palette.REGOLITH_FLECK_DK, "fleck_n": 12,
			}
		ColonyMap.Terrain.HIGHLANDS:
			return {
				"hi": Palette.HIGHLANDS_HI, "lo": Palette.HIGHLANDS_LO,
				"seam": Palette.HIGHLANDS_LO.darkened(0.3),
				"stone": Palette.HIGHLANDS_FLECK, "stone_dk": Palette.HIGHLANDS_LO.darkened(0.15),
				"fleck": Palette.HIGHLANDS_FLECK, "fleck_dk": Palette.HIGHLANDS_FLECK_DK, "fleck_n": 16,
			}
		ColonyMap.Terrain.ICE:
			return {
				"hi": Palette.ICE_HI, "lo": Palette.ICE_LO,
				"seam": Palette.ICE_LO.darkened(0.22),
				"fleck": Palette.ICE_HI, "fleck_dk": Palette.ICE_LO, "fleck_n": 6,
				"sparkle": Palette.ICE_SPARKLE,
			}
		ColonyMap.Terrain.CRYSTAL:
			return {
				"hi": Palette.CRYSTAL_HI, "lo": Palette.CRYSTAL_LO,
				"seam": Palette.CRYSTAL_LO.darkened(0.3),
				"fleck": Palette.CRYSTAL_HI, "fleck_dk": Palette.CRYSTAL_LO, "fleck_n": 8,
				"sparkle": Palette.CRYSTAL_SPARKLE,
			}
		_:  # VOID
			return {
				"hi": Palette.VOID, "lo": Palette.VOID_ABYSS,
				"seam": Palette.VOID_ABYSS,
				"fleck": Palette.VOID, "fleck_dk": Palette.VOID_ABYSS, "fleck_n": 0,
			}
