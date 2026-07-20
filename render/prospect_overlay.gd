class_name ProspectOverlay
extends TileMapLayer
## Toggleable prospecting overlay (P): tints each tile by its scan state and, once
## confirmed, by deposit type. Semi-transparent diamonds over the terrain. Only a
## view of scan state — updated incrementally as scans land.

# Overlay categories (atlas tile x-index) and their tint colors (with alpha).
enum Cat { UNSCANNED, COARSE_EMPTY, COARSE_DEP, CONFIRMED_EMPTY, IRON, COPPER, XENITE }

const COLORS := {
	Cat.UNSCANNED: Color(0.10, 0.10, 0.20, 0.55),
	Cat.COARSE_EMPTY: Color(0.30, 0.30, 0.34, 0.30),
	Cat.COARSE_DEP: Color(0.90, 0.80, 0.30, 0.45),
	Cat.CONFIRMED_EMPTY: Color(0.30, 0.55, 0.40, 0.25),
	Cat.IRON: Color(0.88, 0.50, 0.24, 0.62),
	Cat.COPPER: Color(0.28, 0.76, 0.70, 0.62),
	Cat.XENITE: Color(0.70, 0.40, 0.85, 0.62),
}

var _map: ColonyMap

func setup(map: ColonyMap) -> void:
	_map = map
	tile_set = _build_tileset()
	Events.scan_changed.connect(_on_scan_changed)

## Repaints every cell from current scan state (call when the overlay is shown).
func rebuild() -> void:
	if _map == null:
		return
	for y in _map.height:
		for x in _map.width:
			_paint(Vector2i(x, y))

func _on_scan_changed(cells: Array) -> void:
	if not visible:
		return  # a full rebuild runs when it's next shown
	for c in cells:
		_paint(c)

func _paint(cell: Vector2i) -> void:
	set_cell(cell, 0, Vector2i(_category(cell), 0))

func _category(cell: Vector2i) -> int:
	var dep := _map.get_deposit(cell)
	match _map.get_scan(cell):
		ColonyMap.Scan.COARSE:
			return Cat.COARSE_DEP if dep != ColonyMap.Deposit.NONE else Cat.COARSE_EMPTY
		ColonyMap.Scan.CONFIRMED:
			match dep:
				ColonyMap.Deposit.IRON: return Cat.IRON
				ColonyMap.Deposit.COPPER: return Cat.COPPER
				ColonyMap.Deposit.XENITE: return Cat.XENITE
				_: return Cat.CONFIRMED_EMPTY
	return Cat.UNSCANNED

func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(IsoGrid.TILE_W, IsoGrid.TILE_H)
	var src := TileSetAtlasSource.new()
	src.texture = _build_atlas()
	src.texture_region_size = Vector2i(IsoGrid.TILE_W, IsoGrid.TILE_H)
	for i in COLORS.size():
		src.create_tile(Vector2i(i, 0))
	ts.add_source(src, 0)
	return ts

func _build_atlas() -> ImageTexture:
	var w := IsoGrid.TILE_W
	var h := IsoGrid.TILE_H
	var img := Image.create(w * COLORS.size(), h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in COLORS.size():
		_draw_diamond(img, i * w, COLORS[i])
	return ImageTexture.create_from_image(img)

# Flat semi-transparent diamond (terrain shows through).
func _draw_diamond(img: Image, ox: int, col: Color) -> void:
	var w := IsoGrid.TILE_W
	var h := IsoGrid.TILE_H
	var cx := (w - 1) / 2.0
	var cy := (h - 1) / 2.0
	for ly in h:
		for lx in w:
			if absf(lx - cx) / (w / 2.0) + absf(ly - cy) / (h / 2.0) <= 1.0:
				img.set_pixel(ox + lx, ly, col)
