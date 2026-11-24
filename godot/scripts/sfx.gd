class_name Sfx
extends Node
## أصوات مولّدة برمجياً (لا تحتاج ملفات): صفارة الشرطة، المحرك، المطر، الإنذار، النقود، الاصطدام.

const RATE := 22050

var muted := false
var siren: AudioStreamPlayer
var engine: AudioStreamPlayer
var rain: AudioStreamPlayer
var _beep_players: Array[AudioStreamPlayer] = []
var _cache := {}


func _ready() -> void:
	siren = _loop(_siren_wave(), -80.0)
	engine = _loop(_engine_wave(), -80.0)
	rain = _loop(_noise_wave(2.0, 0.9), -80.0)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_beep_players.append(p)


func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w


func _loop(stream: AudioStreamWAV, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	p.play()
	return p


func _siren_wave() -> AudioStreamWAV:
	var n := RATE * 2
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 760.0 + 420.0 * (0.5 + 0.5 * sin(t * PI))   # صعود وهبوط خلال ثانيتين
		ph += f / RATE
		var tri := 4.0 * absf(fposmod(ph, 1.0) - 0.5) - 1.0
		s[i] = tri * 0.5
	return _wav(s, true)


func _engine_wave() -> AudioStreamWAV:
	var n := RATE / 4
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var saw := fposmod(t * 48.0, 1.0) * 2.0 - 1.0
		var sq := 1.0 if fposmod(t * 24.0, 1.0) < 0.5 else -1.0
		s[i] = (saw * 0.6 + sq * 0.3) * 0.5
	# تنعيم (low-pass بسيط)
	for k in 3:
		for i in range(1, n):
			s[i] = s[i - 1] * 0.7 + s[i] * 0.3
	return _wav(s, true)


func _noise_wave(seconds: float, amp: float) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var s := PackedFloat32Array()
	s.resize(n)
	var prev := 0.0
	for i in n:
		var w := randf_range(-1.0, 1.0)
		s[i] = (w - prev * 0.6) * amp * 0.5   # high-pass خفيف = صوت مطر
		prev = w
	return _wav(s, true)


func _tone(freq: float, dur: float, square := true) -> AudioStreamWAV:
	var key := "%s_%s_%s" % [freq, dur, square]
	if _cache.has(key):
		return _cache[key]
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 6.0 / dur)
		var v := sin(TAU * freq * t)
		if square:
			v = signf(v) * 0.6
		s[i] = v * env * 0.5
	var w := _wav(s)
	_cache[key] = w
	return w


func _play(stream: AudioStream, db := -10.0) -> void:
	if muted:
		return
	for p in _beep_players:
		if not p.playing:
			p.stream = stream
			p.volume_db = db
			p.play()
			return


func beep(freq := 1250.0, dur := 0.1) -> void:
	_play(_tone(freq, dur), -18.0)


func cash() -> void:
	for i in 3:
		get_tree().create_timer(i * 0.08).timeout.connect(func(): _play(_tone([880.0, 1175.0, 1568.0][i], 0.18, false), -8.0))


func horn() -> void:
	_play(_tone(392.0, 0.35), -12.0)


func busted() -> void:
	_play(_tone(220.0, 0.5), -8.0)
	get_tree().create_timer(0.3).timeout.connect(func(): _play(_tone(165.0, 0.7), -8.0))


func crash(v: float) -> void:
	if not _cache.has("crash"):
		var n := RATE / 3
		var s := PackedFloat32Array()
		s.resize(n)
		var lp := 0.0
		for i in n:
			lp = lp * 0.85 + randf_range(-1, 1) * 0.15
			s[i] = lp * 3.0 * exp(-float(i) / n * 5.0)
		_cache["crash"] = _wav(s)
	_play(_cache["crash"], linear_to_db(clampf(v / 25.0, 0.1, 1.0)))


func update(siren_vol: float, engine_speed: float, throttle: float, in_car: bool, rain_on: bool) -> void:
	var m := 0.0 if muted else 1.0
	siren.volume_db = linear_to_db(maxf(siren_vol * 0.35 * m, 0.0001))
	engine.volume_db = linear_to_db(maxf((0.22 + throttle * 0.1) * m if in_car else 0.0, 0.0001))
	engine.pitch_scale = 0.8 + engine_speed * 0.09 + throttle * 0.2
	rain.volume_db = linear_to_db(maxf(0.12 * m if rain_on else 0.0, 0.0001))
