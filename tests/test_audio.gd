extends RefCounted
## Guards the audio contract: data/audio.json must define every cue the game can
## ask for (AudioCues.required()), each pointing at a sound file that exists, and
## the event → cue mapping must be total.
##
## Playback itself isn't testable headlessly (the audio driver is a dummy), so
## this covers the parts that are: the manifest and the pure mapping logic.

const MANIFEST := "res://data/audio.json"
const BUSES := ["Music", "SFX"]

func _cues() -> Dictionary:
	var arr: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var out := {}
	for e in arr:
		out[e.id] = e
	return out

func test_every_required_cue_is_defined(t: Object) -> void:
	var cues := _cues()
	for cue in AudioCues.required():
		t.ok(cues.has(cue), "data/audio.json is missing cue '%s'" % cue)

func test_cue_files_exist(t: Object) -> void:
	var cues := _cues()
	for id in cues:
		var path := str(cues[id].get("file", ""))
		t.ok(path != "", "%s: no file" % id)
		t.ok(FileAccess.file_exists(path), "%s: missing sound file %s" % [id, path])

func test_cue_fields_are_sane(t: Object) -> void:
	var cues := _cues()
	for id in cues:
		var def: Dictionary = cues[id]
		t.ok(BUSES.has(str(def.get("bus", ""))), "%s: unknown bus '%s'"
			% [id, def.get("bus", "")])
		var db := float(def.get("volume_db", 0.0))
		t.ok(db <= 0.0 and db >= -40.0, "%s: volume_db %f out of range" % [id, db])
		var lo := float(def.get("pitch_min", 1.0))
		var hi := float(def.get("pitch_max", 1.0))
		t.ok(lo > 0.0 and lo <= hi, "%s: bad pitch range %f..%f" % [id, lo, hi])

# Only the ambient bed loops; a one-shot left looping would never stop.
func test_only_the_bed_loops(t: Object) -> void:
	var cues := _cues()
	for id in cues:
		var loops: bool = bool(cues[id].get("loop", false))
		t.eq(loops, id == AudioCues.AMBIENT, "%s: unexpected loop flag" % id)

func test_alert_levels_map_to_tiers(t: Object) -> void:
	t.eq(AudioCues.for_alert(AlertMonitor.Level.INFO), "alert_info", "info tier")
	t.eq(AudioCues.for_alert(AlertMonitor.Level.WARN), "alert_warn", "warn tier")
	t.eq(AudioCues.for_alert(AlertMonitor.Level.CRIT), "alert_crit", "crit tier")

# A level outside the table must still make a sound rather than fall silent.
func test_unknown_alert_levels_clamp(t: Object) -> void:
	t.eq(AudioCues.for_alert(-3), "alert_info", "below the range clamps to info")
	t.eq(AudioCues.for_alert(99), "alert_crit", "above the range clamps to crit")

func test_game_over_cues(t: Object) -> void:
	t.eq(AudioCues.for_game_over(true), "win", "victory cue")
	t.eq(AudioCues.for_game_over(false), "lose", "defeat cue")
