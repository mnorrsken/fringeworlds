extends RefCounted
## IsoGrid must agree with Godot's own isometric TileMapLayer, or the hover
## highlight drifts from the tiles you see. Pin both directions.

func _iso_layer() -> TileMapLayer:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(IsoGrid.TILE_W, IsoGrid.TILE_H)
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	return layer

func test_grid_to_screen_matches_tilemap(t: Object) -> void:
	var layer := _iso_layer()
	for cy in range(-3, 6):
		for cx in range(-3, 6):
			var cell := Vector2i(cx, cy)
			t.eq(IsoGrid.grid_to_screen(cell), layer.map_to_local(cell),
				"grid_to_screen matches map_to_local at %s" % cell)
	layer.free()

func test_screen_to_grid_round_trip(t: Object) -> void:
	for cy in range(0, 24):
		for cx in range(0, 24):
			var cell := Vector2i(cx, cy)
			t.eq(IsoGrid.screen_to_grid(IsoGrid.grid_to_screen(cell)), cell,
				"round trip at %s" % cell)
