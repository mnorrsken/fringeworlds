class_name TerrainView
extends TileMapLayer
## A view of ColonyMap. Builds a placeholder iso tileset procedurally (no
## external art to commit yet — Kenney/custom sprites replace this in Milestone
## 8) and paints one atlas tile per terrain type.

const TERRAIN_COLORS := {
	ColonyMap.Terrain.REGOLITH: Color(0.42, 0.35, 0.29),
	ColonyMap.Terrain.HIGHLANDS: Color(0.33, 0.30, 0.33),
	ColonyMap.Terrain.ICE: Color(0.60, 0.78, 0.82),
	ColonyMap.Terrain.CRYSTAL: Color(0.55, 0.34, 0.68),
	ColonyMap.Terrain.VOID: Color(0.07, 0.06, 0.09),
}

func _ready() -> void:
	tile_set = _build_tileset()

func render_map(map: ColonyMap) -> void:
	clear()
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			set_cell(cell, 0, Vector2i(map.get_terrain(cell), 0))

func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(IsoGrid.TILE_W, IsoGrid.TILE_H)
	var src := TileSetAtlasSource.new()
	src.texture = _build_atlas()
	src.texture_region_size = Vector2i(IsoGrid.TILE_W, IsoGrid.TILE_H)
	for i in TERRAIN_COLORS.size():
		src.create_tile(Vector2i(i, 0))
	ts.add_source(src, 0)
	return ts

func _build_atlas() -> ImageTexture:
	var w := IsoGrid.TILE_W
	var h := IsoGrid.TILE_H
	var img := Image.create(w * TERRAIN_COLORS.size(), h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in TERRAIN_COLORS.size():
		_draw_diamond(img, i * w, TERRAIN_COLORS[i])
	return ImageTexture.create_from_image(img)

# Fills one 64x32 diamond into the atlas at x-offset `ox`, with a lit top face,
# shaded bottom face and a dark edge — the SC2000-ish raised-tile read.
func _draw_diamond(img: Image, ox: int, base: Color) -> void:
	var w := IsoGrid.TILE_W
	var h := IsoGrid.TILE_H
	var cx := (w - 1) / 2.0
	var cy := (h - 1) / 2.0
	var top := base.lightened(0.18)
	var bottom := base.darkened(0.15)
	var edge := base.darkened(0.45)
	for ly in h:
		for lx in w:
			var d := absf(lx - cx) / (w / 2.0) + absf(ly - cy) / (h / 2.0)
			if d > 1.0:
				continue
			var c := edge if d > 0.82 else (top if ly < cy else bottom)
			img.set_pixel(ox + lx, ly, c)
