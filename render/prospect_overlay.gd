class_name ProspectOverlay
extends TileMapLayer
## Toggleable prospecting overlay (P): tints each tile by its scan state and, once
## confirmed, by deposit type *and by how much of the deposit is left* — bright and
## solid for a fat seam, fading to a dim grey as it is worked out. Only a view of
## scan state and reserves — updated incrementally as scans land and as extractors
## draw tiles down.

# Overlay categories (atlas tile x-index) and their tint colors (with alpha). For
# the shaded categories this is the *full* color; _shade() dims it per band.
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

# Categories whose tint varies with the reading: the confirmed ores/crystal shade
# by what is left in the ground, and a coarse hit shades by the size its rough
# reading suggests. The rest are flat — there is no quantity to show.
const SHADED := [Cat.COARSE_DEP, Cat.IRON, Cat.COPPER, Cat.XENITE]

## Shade bands (atlas tile y-index). Band 0 is the worked-out look, bands 1..4 run
## thin -> fat, so a live deposit never reads as dead ground.
const BANDS := 5

## Lower bounds of bands 2, 3 and 4, as fractions of a full-richness deposit of
## that type (see ColonyMap.remaining_fraction — that's where the per-type scale
## lives, so 30 units of xenite and 600 of iron both count as "full"). Tuned to
## how the generator actually spreads richness: a median seam lands near 0.35, so
## the top band means a genuinely fat find rather than an unreachable ideal.
const BAND_FLOORS := [0.15, 0.30, 0.50]

# What a spent tile's tint fades toward.
const DIM := Color(0.32, 0.32, 0.36)

var _map: ColonyMap

func setup(map: ColonyMap) -> void:
	_map = map
	tile_set = _build_tileset()
	Events.scan_changed.connect(_on_cells_changed)
	Events.reserves_changed.connect(_on_cells_changed)

## Repaints every cell from current scan state (call when the overlay is shown).
func rebuild() -> void:
	if _map == null:
		return
	for y in _map.height:
		for x in _map.width:
			_paint(Vector2i(x, y))

func _on_cells_changed(cells: Array) -> void:
	if not visible:
		return  # a full rebuild runs when it's next shown
	for c in cells:
		_paint(c)

func _paint(cell: Vector2i) -> void:
	set_cell(cell, 0, _atlas_coords(cell))

# Atlas coords are (category, shade band).
func _atlas_coords(cell: Vector2i) -> Vector2i:
	var dep := _map.get_deposit(cell)
	match _map.get_scan(cell):
		ColonyMap.Scan.COARSE:
			if dep == ColonyMap.Deposit.NONE:
				return Vector2i(Cat.COARSE_EMPTY, 0)
			# A coarse hit only has a jittered richness estimate to go on, and it
			# never reads as worked out — nothing can have mined it yet.
			return Vector2i(Cat.COARSE_DEP, _band(_map.coarse_richness(cell)))
		ColonyMap.Scan.CONFIRMED:
			var band := _band(_map.remaining_fraction(cell))
			match dep:
				ColonyMap.Deposit.IRON: return Vector2i(Cat.IRON, band)
				ColonyMap.Deposit.COPPER: return Vector2i(Cat.COPPER, band)
				ColonyMap.Deposit.XENITE: return Vector2i(Cat.XENITE, band)
			return Vector2i(Cat.CONFIRMED_EMPTY, 0)
	return Vector2i(Cat.UNSCANNED, 0)

# Fraction (0..1 of a full deposit of that type) -> shade band.
func _band(fraction: float) -> int:
	if fraction <= 0.0:
		return 0
	var b := 1
	for floor_f in BAND_FLOORS:
		if fraction >= floor_f:
			b += 1
	return b

# Dims a category's full color for band `b`: the top band is the color as listed,
# lower bands fade toward DIM and toward transparent, so a nearly-spent tile
# barely marks the terrain while a fat one is unmissable.
func _shade(base: Color, b: int) -> Color:
	var t := float(b) / float(BANDS - 1)
	var col := DIM.lerp(base, lerpf(0.25, 1.0, t))
	col.a = lerpf(0.26, base.a, t)
	return col

func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(IsoGrid.TILE_W, IsoGrid.TILE_H)
	var src := TileSetAtlasSource.new()
	src.texture = _build_atlas()
	src.texture_region_size = Vector2i(IsoGrid.TILE_W, IsoGrid.TILE_H)
	for cat in COLORS:
		for b in _bands_for(cat):
			src.create_tile(Vector2i(cat, b))
	ts.add_source(src, 0)
	return ts

func _build_atlas() -> ImageTexture:
	var w := IsoGrid.TILE_W
	var h := IsoGrid.TILE_H
	var img := Image.create(w * COLORS.size(), h * BANDS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for cat in COLORS:
		for b in _bands_for(cat):
			_draw_diamond(img, cat * w, b * h, _shade(COLORS[cat], b))
	return ImageTexture.create_from_image(img)

# Flat categories only need their single band-0 tile.
func _bands_for(cat: int) -> Array:
	return range(BANDS) if cat in SHADED else [0]

# Flat semi-transparent diamond (terrain shows through).
func _draw_diamond(img: Image, ox: int, oy: int, col: Color) -> void:
	var w := IsoGrid.TILE_W
	var h := IsoGrid.TILE_H
	var cx := (w - 1) / 2.0
	var cy := (h - 1) / 2.0
	for ly in h:
		for lx in w:
			if absf(lx - cx) / (w / 2.0) + absf(ly - cy) / (h / 2.0) <= 1.0:
				img.set_pixel(ox + lx, oy + ly, col)
