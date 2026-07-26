extends Node
## Audio — the game's sound layer (autoload).
##
## A view-layer singleton, in the same spirit as the render nodes: it *listens*
## on Events and never touches sim state, so muting or removing it changes
## nothing about the simulation. It is an autoload (rather than a node in each
## scene) purely so the ambient bed keeps playing across the menu → game switch.
##
## Cues are data-driven: data/audio.json (loaded by Defs) maps a cue id to a
## file, bus, volume and optional pitch jitter. Adding a sound = a WAV plus a
## manifest entry — see tools/gen_audio.py, which synthesizes every WAV in the
## repo. Cue names and event mapping live in AudioCues (pure, tested).

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const SETTINGS_PATH := "user://settings.cfg"
const VOICES := 8               # simultaneous one-shots before the oldest is reused
const REPEAT_GUARD := 0.04      # seconds; drops a duplicate cue fired twice in a frame

var _streams: Dictionary = {}   # cue id -> AudioStream
var _defs: Dictionary = {}      # cue id -> manifest entry
var _voices: Array[AudioStreamPlayer] = []
var _voice := 0
var _music: AudioStreamPlayer = null
var _last_played: Dictionary = {}  # cue id -> msec of last play
var _muted := false
# Headless runs (tests, `make import`) have no audio device: the manifest is
# still validated, but nothing is loaded or played.
var _enabled := DisplayServer.get_name() != "headless"
var _music_volume := 0.8
var _sfx_volume := 0.9

func _ready() -> void:
	_load_manifest()
	if not _enabled:
		return
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	_make_players()
	_load_settings()
	_apply_volumes()

	Events.building_placed.connect(func(_i): play(AudioCues.PLACE))
	Events.building_removed.connect(func(_i): play(AudioCues.DEMOLISH))
	Events.alert.connect(func(_text, level): play(AudioCues.for_alert(level)))
	Events.game_over.connect(func(won): play(AudioCues.for_game_over(won)))

	play_music(AudioCues.AMBIENT)
	print("[Audio] loaded %d cues" % _streams.size())

## True when there's an audio device to play through (false in headless runs).
func is_enabled() -> bool:
	return _enabled

## Silences everything. Call this before quitting: a stream still playing when
## the process exits is reported as a leaked resource by the engine's teardown,
## which would bury real errors in the exit output.
func shutdown() -> void:
	stop_music()
	for p in _voices:
		p.stop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown()   # covers closing the window rather than using Quit

func _exit_tree() -> void:
	shutdown()
	for p in _voices:
		p.stream = null
	if _music != null:
		_music.stream = null
	_streams.clear()

# --- playback ----------------------------------------------------------------

## Plays a one-shot cue. Unknown or missing cues are silently ignored so a
## half-populated manifest can never crash the game.
func play(cue: String) -> void:
	var stream: AudioStream = _streams.get(cue)
	if stream == null or _voices.is_empty():
		return
	# The same cue twice in a frame just phases against itself.
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(cue, -99999)) < int(REPEAT_GUARD * 1000):
		return
	_last_played[cue] = now

	var def: Dictionary = _defs.get(cue, {})
	var p := _free_voice()
	p.stream = stream
	p.bus = str(def.get("bus", SFX_BUS))
	p.volume_db = float(def.get("volume_db", 0.0))
	p.pitch_scale = randf_range(
		float(def.get("pitch_min", 1.0)), float(def.get("pitch_max", 1.0)))
	p.play()

## Convenience for UI scripts: every button press goes through here.
func ui_click() -> void:
	play(AudioCues.UI_CLICK)

## Starts (or restarts) the looping bed. Re-requesting the playing track is a
## no-op, so scene changes don't restart the music.
func play_music(cue: String) -> void:
	var stream: AudioStream = _streams.get(cue)
	if stream == null or _music == null:
		return
	if _music.playing and _music.stream == stream:
		return
	var def: Dictionary = _defs.get(cue, {})
	_music.stream = stream
	_music.volume_db = float(def.get("volume_db", 0.0))
	_music.play()

func stop_music() -> void:
	if _music != null:
		_music.stop()

# --- settings ----------------------------------------------------------------

func is_muted() -> bool:
	return _muted

func toggle_mute() -> void:
	set_muted(not _muted)

func set_muted(muted: bool) -> void:
	_muted = muted
	_apply_volumes()
	_save_settings()

## 0.0 - 1.0, applied to the whole music/SFX bus (per-cue volume_db is relative).
func set_music_volume(v: float) -> void:
	_music_volume = clampf(v, 0.0, 1.0)
	_apply_volumes()
	_save_settings()

func set_sfx_volume(v: float) -> void:
	_sfx_volume = clampf(v, 0.0, 1.0)
	_apply_volumes()
	_save_settings()

func _apply_volumes() -> void:
	_set_bus(MUSIC_BUS, _music_volume)
	_set_bus(SFX_BUS, _sfx_volume)

func _set_bus(bus: String, volume: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, _muted or volume <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(volume, 0.0001)))

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	_muted = bool(cfg.get_value("audio", "muted", _muted))
	_music_volume = float(cfg.get_value("audio", "music", _music_volume))
	_sfx_volume = float(cfg.get_value("audio", "sfx", _sfx_volume))

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # keep any other sections intact
	cfg.set_value("audio", "muted", _muted)
	cfg.set_value("audio", "music", _music_volume)
	cfg.set_value("audio", "sfx", _sfx_volume)
	cfg.save(SETTINGS_PATH)

# --- setup -------------------------------------------------------------------

# Buses are created at runtime so the project needs no binary bus layout
# resource; both feed Master.
func _ensure_bus(name: String) -> void:
	if AudioServer.get_bus_index(name) != -1:
		return
	var idx := AudioServer.get_bus_count()
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, name)
	AudioServer.set_bus_send(idx, "Master")

func _load_manifest() -> void:
	for cue in Defs.audio:
		var def: Dictionary = Defs.audio[cue]
		var path := str(def.get("file", ""))
		if not ResourceLoader.exists(path):
			push_warning("[Audio] missing sound file for '%s': %s" % [cue, path])
			continue
		_defs[cue] = def
		if not _enabled:
			continue
		var stream: AudioStream = load(path)
		# Looping is an import setting (edit/loop_mode in the .import file); this
		# only repairs it if that was lost, e.g. after a re-import from defaults.
		# Frame count comes from the length, not data.size() — the importer may
		# store the samples compressed.
		if bool(def.get("loop", false)) and stream is AudioStreamWAV:
			var wav := stream as AudioStreamWAV
			if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
				wav.loop_begin = 0
				wav.loop_end = int(round(wav.get_length() * wav.mix_rate))
		_streams[cue] = stream
	for cue in AudioCues.required():
		if not _defs.has(cue):
			push_warning("[Audio] cue '%s' has no sound — it will be silent" % cue)

func _make_players() -> void:
	_music = AudioStreamPlayer.new()
	_music.bus = MUSIC_BUS
	add_child(_music)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_voices.append(p)

# Prefers an idle player; if every voice is busy the oldest is stolen.
func _free_voice() -> AudioStreamPlayer:
	for p in _voices:
		if not p.playing:
			return p
	_voice = (_voice + 1) % _voices.size()
	return _voices[_voice]
