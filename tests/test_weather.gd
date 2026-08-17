extends RefCounted
## Dust storms: the schedule, what a storm does to the colony, and the fact that
## it does it deterministically and survives a save.

func _balance() -> Balance:
	var b := Balance.new()
	# Short, sharp weather so a test doesn't have to tick for minutes.
	b.storm_grace_ticks = 10
	b.storm_warning_ticks = 4
	b.storm_duration_ticks = 8
	b.storm_duration_jitter = 0
	b.storm_interval_ticks = 20
	b.storm_interval_jitter = 0
	b.storm_power_factor = 0.5
	return b

func _defs() -> Dictionary:
	return {
		"solar": {  # exposed to the sky: dimmed by a storm
			"name": "Solar", "size": 1, "cost": {}, "power": 10, "exposed": true,
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"reactor": {  # sheltered: unaffected
			"name": "Reactor", "size": 1, "cost": {}, "power": 10,
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"drain": {
			"name": "Drain", "size": 1, "cost": {}, "power": -8,
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"station": {
			"name": "Station", "size": 1, "cost": {}, "power": 0,
			"scan": {"max_radius": 3, "ticks_per_ring": 1},
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
	}

func _colony(b: Balance = null) -> Colony:
	var c := Colony.new(ColonyMap.new(16, 16), _defs(), {}, b if b != null else _balance())
	c.population = 0
	return c

# Ticks until the weather reaches `phase`, up to a sane cap. Returns the tick it
# landed on, or -1.
func _tick_until(c: Colony, phase: int, cap := 400) -> int:
	for i in cap:
		c.tick()
		if c.weather.phase == phase:
			return i
	return -1

func test_cycle_runs_clear_warning_storm(t: Object) -> void:
	var w := Weather.new(_balance(), 1)
	t.eq(w.phase, Weather.Phase.CLEAR, "starts clear")
	var seen := []
	for i in 60:
		var e := w.advance()
		if e != Weather.NONE:
			seen.append(e)
	t.eq(seen[0], Weather.WARNING, "warning comes first")
	t.eq(seen[1], Weather.STORM, "then the storm")
	t.eq(seen[2], Weather.CLEAR, "then it passes")
	t.ok(seen.size() >= 4, "and it comes round again")

func test_grace_period_before_first_storm(t: Object) -> void:
	var w := Weather.new(_balance(), 1)
	for i in 9:
		t.eq(w.advance(), Weather.NONE, "quiet during the grace period")
	t.eq(w.advance(), Weather.WARNING, "the first warning lands after it")

func test_warning_precedes_the_storm(t: Object) -> void:
	# The lead time is the whole counterplay: no storm may arrive unannounced.
	var w := Weather.new(_balance(), 7)
	var warned_at := -1
	for i in 200:
		var e := w.advance()
		if e == Weather.WARNING:
			warned_at = i
		elif e == Weather.STORM:
			t.ok(warned_at >= 0, "a storm is always announced first")
			t.eq(i - warned_at, 4, "with the configured lead time")
			return
	t.ok(false, "a storm should have arrived")

func test_storm_dims_exposed_power(t: Object) -> void:
	var c := _colony()
	c.place("solar", Vector2i(1, 1))
	c.place("reactor", Vector2i(2, 1))
	c.tick()
	t.eq(c.power_produced, 20, "full output under clear skies")
	_tick_until(c, Weather.Phase.STORM)
	t.eq(c.power_produced, 15, "the panel halves; the sheltered reactor doesn't")
	t.eq(c.power_of("solar"), 5, "power_of reports the dimmed figure")
	t.eq(c.power_of("reactor"), 10, "and leaves sheltered buildings alone")
	_tick_until(c, Weather.Phase.CLEAR)
	t.eq(c.power_produced, 20, "output returns when the dust settles")

func test_storm_never_dims_consumption(t: Object) -> void:
	var c := _colony()
	c.place("reactor", Vector2i(1, 1))
	c.place("drain", Vector2i(2, 1))
	_tick_until(c, Weather.Phase.STORM)
	t.eq(c.power_of("drain"), -8, "a storm doesn't make a consumer cheaper")

func test_storm_sheds_the_newest_consumer(t: Object) -> void:
	# The whole point: a storm arrives through the power balance, where the
	# player has a lever (switching something off) rather than as arbitrary damage.
	var c := _colony()
	c.place("solar", Vector2i(1, 1))     # 10 clear, 5 in a storm
	var d = c.place("drain", Vector2i(2, 1))  # needs 8
	c.tick()
	t.ok(d.active, "runs under clear skies")
	_tick_until(c, Weather.Phase.STORM)
	t.ok(not d.active, "shed once the panel dims")
	t.eq(str(d.idle_reason), "No power", "and says why")
	_tick_until(c, Weather.Phase.CLEAR)
	t.ok(d.active, "back on afterwards")

func test_storm_halts_prospecting(t: Object) -> void:
	var c := _colony()
	c.place("reactor", Vector2i(1, 1))
	var s = c.place("station", Vector2i(8, 8))
	_tick_until(c, Weather.Phase.STORM)
	var ring := int(s.scan_ring)
	var scanned := 0
	for i in 5:
		c.tick()
		scanned += c.scan_changes.size()
	t.eq(int(s.scan_ring), ring, "the sweep holds where it was")
	t.eq(scanned, 0, "no tiles scanned in a storm")
	t.eq(str(s.idle_reason), "Dust storm", "and the station explains itself")
	_tick_until(c, Weather.Phase.CLEAR)
	c.tick()
	c.tick()
	t.ok(int(s.scan_ring) != ring or not c.scan_changes.is_empty(),
		"scanning resumes when it passes")

func test_storms_can_be_switched_off(t: Object) -> void:
	var b := _balance()
	b.storms_enabled = false
	var c := _colony(b)
	c.place("solar", Vector2i(1, 1))
	for i in 200:
		c.tick()
	t.eq(c.weather.phase, Weather.Phase.CLEAR, "calm-weather game stays clear")
	t.eq(c.power_produced, 10, "and the panels never dim")

func test_schedule_is_deterministic(t: Object) -> void:
	# Same seed, same weather — this is what lets the pacing harness measure a
	# storm's cost instead of averaging over noise.
	var b := _balance()
	b.storm_duration_jitter = 5
	b.storm_interval_jitter = 7
	var w1 := Weather.new(b, 99)
	var w2 := Weather.new(b, 99)
	var w3 := Weather.new(b, 100)
	var s1 := []
	var s2 := []
	var s3 := []
	for i in 300:
		s1.append(w1.advance())
		s2.append(w2.advance())
		s3.append(w3.advance())
	t.eq(s1, s2, "the same seed gives the same weather")
	t.ok(s1 != s3, "a different seed gives different weather")

func test_jitter_stays_in_range(t: Object) -> void:
	var b := _balance()
	b.storm_duration_jitter = 3
	var w := Weather.new(b, 5)
	for i in 400:
		if w.advance() == Weather.STORM:
			t.ok(w.ticks_left >= 5 and w.ticks_left <= 11,
				"duration stays within base ± jitter (got %d)" % w.ticks_left)

func test_weather_event_is_reported_once(t: Object) -> void:
	var c := _colony()
	var storms := 0
	var events := 0
	for i in 60:
		c.tick()
		if c.weather_event != Weather.NONE:
			events += 1
		if c.weather_event == Weather.STORM:
			storms += 1
	t.ok(storms >= 1, "at least one storm announced")
	t.ok(events < 20, "phase changes are edges, not every tick (%d)" % events)

func test_alerts_announce_the_weather(t: Object) -> void:
	var c := _colony()
	var mon := AlertMonitor.new()
	var texts := []
	for i in 40:
		c.tick()
		for a in mon.check(c):
			texts.append(str(a.text))
	var joined := " | ".join(texts)
	t.ok(joined.contains("approaching"), "the warning is announced")
	t.ok(joined.contains("Dust storm — solar"), "so is the storm itself")

func test_weather_survives_save_load(t: Object) -> void:
	var c := _colony()
	c.place("solar", Vector2i(1, 1))
	_tick_until(c, Weather.Phase.STORM)
	c.tick()
	var left := c.weather.ticks_left
	var round_trip := Colony.from_dict(c.map, c.defs,
		JSON.parse_string(JSON.stringify(c.to_dict())), c.balance)
	t.eq(round_trip.weather.phase, Weather.Phase.STORM, "still storming after a reload")
	t.eq(round_trip.weather.ticks_left, left, "with the same time left to run")
	round_trip.tick()
	t.eq(round_trip.power_produced, 5, "and the panel is still dimmed")

func test_old_saves_load_clear(t: Object) -> void:
	var c := _colony()
	var d := c.to_dict()
	d.erase("weather")   # a save written before storms existed
	var loaded := Colony.from_dict(c.map, c.defs, d, c.balance)
	t.eq(loaded.weather.phase, Weather.Phase.CLEAR, "resumes under clear skies")

func test_report_carries_the_dimmed_figure(t: Object) -> void:
	var c := _colony()
	var s = c.place("solar", Vector2i(1, 1))
	var rep := c.building_report(int(s.id))
	t.eq(int(rep.power), 10, "nominal power is the def figure")
	t.eq(int(rep.power_now), 10, "which is what it makes under clear skies")
	_tick_until(c, Weather.Phase.STORM)
	t.eq(int(c.building_report(int(s.id)).power_now), 5, "and the dimmed one in a storm")
	t.eq(int(c.building_report(int(s.id)).power), 10, "nominal is unchanged")
