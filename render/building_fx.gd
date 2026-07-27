class_name BuildingFX
extends Node2D
## Decorative idle overlays anchored on a building's art — smokestack plumes,
## venting steam, ground dust, ember sparks, crystal shimmer, blinking warning
## lamps and soft glows. This is the cheap way to make static building sprites
## look alive without animating the art itself.
##
## Purely a view: the effects come from the building def's `fx` list in
## data/buildings.json, and the only sim input is set_active() (a shut-down
## building stops venting and its lamps go dark).
##
## ANCHORING: the node sits at the building sprite's own anchor — the bottom
## centre of its front footprint cell — so an fx `at` offset is simply a pixel
## position in the source PNG, converted with:
##     at = pixel - Vector2(tex_w / 2, tex_h - IsoGrid.TILE_H / 2)
## i.e. measure the smokestack's mouth in the art, subtract that, done.

## Discs a glow is built from, outermost first.
const RINGS := 4

## Effect kinds accepted in a def's `fx` list (data/buildings.json).
const TYPES := ["smoke", "steam", "dust", "sparks", "shimmer", "lamp", "glow"]

# Emitters are particle nodes; lamps/glows are drawn here (cheaper than a
# particle system for one or two pulsing dots).
var _emitters: Array[CPUParticles2D] = []
var _lamps: Array[Dictionary] = []
var _glows: Array[Dictionary] = []
var _active := true
var _t := 0.0
var _redraw_accum := 0.0

# The soft round puff every emitter draws, built once and shared. Kept tiny so
# nearest-neighbour scaling keeps it chunky rather than blurry.
static var _puff_texture: Texture2D = null

## Builds the effects for one building. `phase` (seconds) offsets every cycle so
## two identical buildings don't blink and puff in lockstep.
func configure(specs: Array, phase := 0.0) -> void:
	for spec in specs:
		if not (spec is Dictionary):
			continue
		var type := str(spec.get("type", ""))
		var at := _spec_at(spec)
		match type:
			"lamp":
				_lamps.append({
					"at": at,
					"color": spec.get("color_value", Palette.LIGHT_ON) as Color,
					"period": maxf(0.2, float(spec.get("period", 1.8))),
					"duty": clampf(float(spec.get("duty", 0.22)), 0.02, 1.0),
					"radius": float(spec.get("radius", 1.6)),
					"phase": phase + float(_lamps.size()) * 0.6,
				})
			"glow":
				_glows.append({
					"at": at,
					"color": spec.get("color_value", Palette.LIGHT_ON) as Color,
					"period": maxf(0.2, float(spec.get("period", 2.4))),
					"radius": float(spec.get("radius", 6.0)),
					"alpha": clampf(float(spec.get("alpha", 0.5)), 0.0, 1.0),
					"phase": phase + float(_glows.size()) * 1.1,
				})
			_:
				var emitter := _make_emitter(type, spec)
				if emitter == null:
					push_warning("[BuildingFX] unknown fx type '%s'" % type)
					continue
				emitter.position = at
				add_child(emitter)
				_emitters.append(emitter)
	set_process(not _lamps.is_empty() or not _glows.is_empty())
	queue_redraw()

## Shut-down buildings stop venting and go dark; restarting resumes emission.
func set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	for e in _emitters:
		e.emitting = active
	queue_redraw()

func _process(delta: float) -> void:
	# ~12 fps is plenty for blinking lamps; matches BuildingSprite's throttle.
	_t += delta
	_redraw_accum += delta
	if _redraw_accum >= 0.08:
		_redraw_accum = 0.0
		queue_redraw()

func _draw() -> void:
	for lamp in _lamps:
		_draw_lamp(lamp)
	for glow in _glows:
		_draw_glow(glow)

## How lit a blinking lamp is (0..1) at time `t`: a smooth bump that peaks in the
## middle of the `duty` fraction of each `period`, dark for the rest of the cycle.
static func lamp_intensity(t: float, period: float, duty: float) -> float:
	var ph := fmod(t, period) / period
	var half := duty * 0.5
	return 1.0 - smoothstep(0.0, 1.0, clampf(absf(ph - half) / half, 0.0, 1.0))

# A bulb that ramps up and back down inside its lit window, with a soft halo —
# reads as a blinking beacon rather than a hard-toggled pixel.
func _draw_lamp(lamp: Dictionary) -> void:
	var lit := 0.0
	if _active:
		lit = lamp_intensity(_t + lamp.phase, lamp.period, lamp.duty)
	var at: Vector2 = lamp.at
	var radius: float = lamp.radius
	if lit > 0.02:
		var halo: Color = lamp.color
		halo.a = 0.16 * lit
		draw_circle(at, radius * 3.0, halo)
		halo.a = 0.34 * lit
		draw_circle(at, radius * 1.9, halo)
	draw_circle(at, radius, Palette.LIGHT_OFF.lerp(lamp.color, lit))

# Nested discs, brightest in the middle — a pulsing bloom for a furnace mouth or
# a crystal hopper. Four rings rather than three, and each carries more alpha:
# the old version was so faint that a furnace read as unlit next to its own
# baked-in art.
func _draw_glow(glow: Dictionary) -> void:
	if not _active:
		return
	var k := 0.6 + 0.4 * sin(_t * TAU / float(glow.period) + float(glow.phase))
	var col: Color = glow.color
	for i in RINGS:
		# Wide and faint on the outside, tight and hot in the middle.
		col.a = float(glow.alpha) * k * (0.22 + i * 0.20)
		draw_circle(glow.at, float(glow.radius) * (1.0 - i * 0.22), col)

# --- emitters ---------------------------------------------------------------

# Builds one particle emitter, or null if the type isn't a particle effect.
# Every preset is tuned in screen pixels at the game's 1280x720 viewport.
func _make_emitter(type: String, spec: Dictionary) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = _puff()
	p.randomness = 0.5
	var col := Color.WHITE
	var alpha := 0.5
	var life := 2.0
	var rate := 4.0
	match type:
		"smoke":
			col = Palette.SMOKE
			life = 2.6
			rate = 8.0
			alpha = 0.55
			p.direction = Vector2(0, -1)
			p.spread = 12.0
			p.initial_velocity_min = 5.0
			p.initial_velocity_max = 11.0
			p.gravity = Vector2(3.0, -5.0)   # rises, drifting downwind
			p.damping_min = 0.5
			p.damping_max = 1.5
			p.scale_amount_min = 0.55
			p.scale_amount_max = 1.0
			p.scale_amount_curve = _ramp_curve(0.7, 2.4)
		"steam":
			col = Color("dceff2")
			life = 1.5
			rate = 14.0
			alpha = 0.6
			p.direction = Vector2(0, -1)
			p.spread = 20.0
			p.initial_velocity_min = 12.0
			p.initial_velocity_max = 22.0
			p.gravity = Vector2(2.0, -10.0)
			p.damping_min = 2.0
			p.damping_max = 5.0
			p.scale_amount_min = 0.35
			p.scale_amount_max = 0.6
			p.scale_amount_curve = _ramp_curve(0.5, 2.6)
		"dust":
			col = Color("cbb392")
			life = 1.3
			rate = 18.0
			alpha = 0.55
			p.direction = Vector2(0, -0.4)
			p.spread = 75.0
			p.initial_velocity_min = 6.0
			p.initial_velocity_max = 16.0
			p.gravity = Vector2(0, 14.0)     # kicked up, then settles back
			p.damping_min = 3.0
			p.damping_max = 6.0
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			p.emission_rect_extents = Vector2(8, 3)
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.1
			p.scale_amount_curve = _ramp_curve(0.6, 1.8)
		"sparks":
			col = Color("ffb347")
			life = 0.9
			rate = 16.0
			alpha = 1.0
			p.direction = Vector2(0, -1)
			p.spread = 30.0
			p.initial_velocity_min = 18.0
			p.initial_velocity_max = 38.0
			p.gravity = Vector2(0, 46.0)     # embers arc and fall
			p.scale_amount_min = 0.3
			p.scale_amount_max = 0.45
		"shimmer":
			col = Palette.CRYSTAL_SPARKLE
			life = 1.6
			rate = 12.0
			alpha = 0.9
			p.direction = Vector2(0, -1)
			p.spread = 35.0
			p.initial_velocity_min = 4.0
			p.initial_velocity_max = 10.0
			p.gravity = Vector2(0, -3.0)     # motes float up and wink out
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			p.emission_rect_extents = Vector2(4, 2)
			p.scale_amount_min = 0.3
			p.scale_amount_max = 0.5
		_:
			p.free()
			return null

	if spec.has("color_value"):
		col = spec.color_value
	alpha = clampf(float(spec.get("alpha", alpha)), 0.0, 1.0)
	life = maxf(0.05, life * float(spec.get("life_scale", 1.0)))
	rate = maxf(0.2, float(spec.get("rate", rate)))
	var size := float(spec.get("scale", 1.0))
	p.scale_amount_min *= size
	p.scale_amount_max *= size
	p.lifetime = life
	p.amount = maxi(1, roundi(rate * life))
	p.preprocess = life          # a placed building already has a full plume
	p.color_ramp = _fade_ramp(col, alpha)
	return p

# Fades in quickly, then out over the particle's life.
static func _fade_ramp(col: Color, peak_alpha: float) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.18, 1.0])
	g.colors = PackedColorArray([
		Color(col, peak_alpha * 0.35), Color(col, peak_alpha), Color(col, 0.0)])
	return g

# Curve from `a` to `b` over a particle's life (multiplies scale_amount).
static func _ramp_curve(a: float, b: float) -> Curve:
	var c := Curve.new()
	c.max_value = maxf(a, b)
	c.add_point(Vector2(0.0, a))
	c.add_point(Vector2(1.0, b))
	return c

# `at` is authored as [x, y] pixels relative to the sprite anchor (see header).
static func _spec_at(spec: Dictionary) -> Vector2:
	var at: Array = spec.get("at", [])
	if at.size() < 2:
		return Vector2.ZERO
	return Vector2(float(at[0]), float(at[1]))

# A small filled disc — soft enough to read as a puff, blocky enough to stay
# pixel-art under the project's nearest-neighbour filtering.
static func _puff() -> Texture2D:
	if _puff_texture == null:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 0))
		for y in 8:
			for x in 8:
				if Vector2(x - 3.5, y - 3.5).length() <= 3.6:
					img.set_pixel(x, y, Color.WHITE)
		_puff_texture = ImageTexture.create_from_image(img)
	return _puff_texture
