class_name TerrainView
extends TileMapLayer
## A view of ColonyMap. Builds a procedural isometric tileset (Milestone 8 retro
## art pass): each terrain gets several dithered, raised-edge variants for a
## textured SC2000-ish ground, and the special terrains (ice, crystal) get a few
## animation frames so they shimmer. All colours come from Palette.

# 4x4 ordered (Bayer) dither matrix — the classic pixel-art gradient technique.
const BAYER := [
	[0, 8, 2, 10],
	[12, 4, 14, 6],
	[3, 11, 1, 9],
	[15, 7, 13, 5],
]

# Distinct static variants and animation frames per terrain.
const SPEC := {
	ColonyMap.Terrain.REGOLITH: {"variants": 4, "frames": 1},
	ColonyMap.Terrain.HIGHLANDS: {"variants": 4, "frames": 1},
	ColonyMap.Terrain.ICE: {"variants": 2, "frames": 3},
	ColonyMap.Terrain.CRYSTAL: {"variants": 2, "frames": 3},
	ColonyMap.Terrain.VOID: {"variants": 2, "frames": 1},
}

# Representative base tone per terrain, used by the minimap.
const TERRAIN_COLORS := {
	ColonyMap.Terrain.REGOLITH: Palette.REGOLITH,
	ColonyMap.Terrain.HIGHLANDS: Palette.HIGHLANDS,
	ColonyMap.Terrain.ICE: Palette.ICE,
	ColonyMap.Terrain.CRYSTAL: Palette.CRYSTAL,
	ColonyMap.Terrain.VOID: Palette.VOID,
}

var _variant_coords: Dictionary = {}  # terrain -> Array[Vector2i] (each variant's base atlas cell)

func _ready() -> void:
	tile_set = _build_tileset()

func render_map(map: ColonyMap) -> void:
	clear()
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var coords: Array = _variant_coords[map.get_terrain(cell)]
			set_cell(cell, 0, coords[_cell_variant(cell, coords.size())])

# Deterministic per-cell variant pick, so the ground looks varied but stable.
func _cell_variant(cell: Vector2i, n: int) -> int:
	return abs((cell.x * 73856093) ^ (cell.y * 19349663)) % n

func _build_tileset() -> TileSet:
	var w := IsoGrid.TILE_W
	var h := IsoGrid.TILE_H
	var total := 0
	for t in SPEC:
		total += int(SPEC[t].variants) * int(SPEC[t].frames)
	var img := Image.create(total * w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Draw every variant (and its animation frames) into successive atlas columns.
	_variant_coords.clear()
	var col := 0
	for t in SPEC:
		var frames := int(SPEC[t].frames)
		var coords := []
		for vi in int(SPEC[t].variants):
			coords.append(Vector2i(col, 0))
			for fi in frames:
				_draw_terrain(img, col, t, vi, fi)
				col += 1
		_variant_coords[t] = coords

	var src := TileSetAtlasSource.new()
	src.texture_region_size = Vector2i(w, h)
	src.texture = ImageTexture.create_from_image(img)
	for t in _variant_coords:
		var frames := int(SPEC[t].frames)
		for base in _variant_coords[t]:
			src.create_tile(base)
			if frames > 1:
				src.set_tile_animation_frames_count(base, frames)
				for fi in frames:
					src.set_tile_animation_frame_duration(base, fi, 0.4)

	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(w, h)
	ts.add_source(src, 0)
	return ts

# Draws one terrain diamond into the atlas column `col`: a Bayer-dithered,
# top-lit fill with a raised bevel, sparse flecks, and (for ice/crystal) sparkle
# that shifts per animation frame.
func _draw_terrain(img: Image, col: int, terrain: int, variant: int, frame: int) -> void:
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
			if d > 1.0:
				continue
			# A gentle top-lit gradient plus per-variant mottling, dithered
			# between the light and dark tones.
			var shade := 0.55 - 0.42 * dy
			shade += 0.12 * sin(lx * 0.5 + variant * 2.1) + 0.12 * sin(ly * 0.8 + variant * 1.3)
			var c: Color = pal.hi if clampf(shade, 0.0, 1.0) > BAYER[ly % 4][lx % 4] / 16.0 else pal.lo
			# Raised edge: dark rim outline, lit top bevel, shadowed bottom bevel.
			if d > 0.9:
				c = pal.edge
			elif d > 0.74:
				c = pal.rim_hi if dy < 0.0 else pal.rim_lo
			img.set_pixel(ox + lx, ly, c)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash([terrain, variant])
	for i in int(pal.fleck_n):
		var fx := rng.randi_range(8, w - 9)
		var fy := rng.randi_range(4, h - 5)
		if _in_diamond(fx, fy, cx, cy, w, h):
			img.set_pixel(ox + fx, fy, pal.fleck if rng.randf() > 0.5 else pal.fleck_dk)

	if pal.has("sparkle"):
		var srng := RandomNumberGenerator.new()
		srng.seed = hash([terrain, variant, frame, 977])
		for i in 3:
			var sx := srng.randi_range(10, w - 11)
			var sy := srng.randi_range(6, h - 7)
			if _in_diamond(sx, sy, cx, cy, w, h):
				img.set_pixel(ox + sx, sy, pal.sparkle)

func _in_diamond(px: float, py: float, cx: float, cy: float, w: int, h: int) -> bool:
	return absf((px - cx) / (w / 2.0)) + absf((py - cy) / (h / 2.0)) <= 0.85

# Colour set per terrain: light/dark dither tones, bevel colours, flecks, and an
# optional sparkle for animated terrains.
func _palette(terrain: int) -> Dictionary:
	match terrain:
		ColonyMap.Terrain.REGOLITH:
			return {
				"hi": Palette.REGOLITH_HI, "lo": Palette.REGOLITH_LO, "edge": Palette.EDGE,
				"rim_hi": Palette.RIM_LIGHT, "rim_lo": Palette.REGOLITH_LO.darkened(0.2),
				"fleck": Palette.REGOLITH_FLECK, "fleck_dk": Palette.REGOLITH_FLECK_DK, "fleck_n": 12,
			}
		ColonyMap.Terrain.HIGHLANDS:
			return {
				"hi": Palette.HIGHLANDS_HI, "lo": Palette.HIGHLANDS_LO, "edge": Palette.EDGE,
				"rim_hi": Palette.HIGHLANDS_HI.lightened(0.2), "rim_lo": Palette.HIGHLANDS_LO.darkened(0.2),
				"fleck": Palette.HIGHLANDS_FLECK, "fleck_dk": Palette.HIGHLANDS_FLECK_DK, "fleck_n": 16,
			}
		ColonyMap.Terrain.ICE:
			return {
				"hi": Palette.ICE_HI, "lo": Palette.ICE_LO, "edge": Palette.ICE_LO.darkened(0.35),
				"rim_hi": Palette.ICE_HI.lightened(0.2), "rim_lo": Palette.ICE_LO,
				"fleck": Palette.ICE_HI, "fleck_dk": Palette.ICE_LO, "fleck_n": 6,
				"sparkle": Palette.ICE_SPARKLE,
			}
		ColonyMap.Terrain.CRYSTAL:
			return {
				"hi": Palette.CRYSTAL_HI, "lo": Palette.CRYSTAL_LO, "edge": Palette.CRYSTAL_LO.darkened(0.4),
				"rim_hi": Palette.CRYSTAL_HI.lightened(0.25), "rim_lo": Palette.CRYSTAL_LO,
				"fleck": Palette.CRYSTAL_HI, "fleck_dk": Palette.CRYSTAL_LO, "fleck_n": 8,
				"sparkle": Palette.CRYSTAL_SPARKLE,
			}
		_:  # VOID
			return {
				"hi": Palette.VOID_HI, "lo": Palette.VOID, "edge": Palette.VOID,
				"rim_hi": Palette.VOID_HI, "rim_lo": Palette.VOID,
				"fleck": Palette.VOID_STAR, "fleck_dk": Palette.VOID, "fleck_n": 5,
			}
