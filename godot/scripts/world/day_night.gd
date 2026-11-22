class_name DayNight
extends Node
## Passagem do tempo: um dia inteiro dura CYCLE segundos, com o dia ocupando 3/4 do tempo
## e a noite 1/4. Usa o relógio do sistema, então todos os jogadores online veem a mesma hora.
## Muda a cor do mundo (CanvasModulate) e o sol (DirectionalLight2D); luzes, cogumelos,
## cristais e lava brilham muito mais à noite.

const CYCLE := 1200.0  # 20 minutos: 15 de dia, 5 de noite
const DAY := 0.75
const C_DAY := Color(0.62, 0.6, 0.55)
const C_DUSK := Color(0.5, 0.36, 0.32)
const C_NIGHT := Color(0.13, 0.15, 0.27)
const C_DAWN := Color(0.46, 0.4, 0.46)

var cm: CanvasModulate
var sun: DirectionalLight2D
var player: Node2D
## 0..1 no ciclo (0 = nascer do sol).
var phase := 0.0
var _was_night := -1
## Teste: força uma fase (-1 = relógio).
static var force := -1.0


static func now_phase() -> float:
	if force >= 0.0:
		return force
	return fmod(Time.get_unix_time_from_system(), CYCLE) / CYCLE


static func is_night_now() -> bool:
	return now_phase() >= DAY


func _process(_d: float) -> void:
	phase = now_phase()
	var col: Color
	var sun_e: float
	var sun_c := Color(1.0, 0.85, 0.65)
	# dia: amanhecer (0-0.06), dia cheio, entardecer (0.66-0.75); noite: 0.75-0.97, aurora 0.97-1
	if phase < 0.06:
		var k := phase / 0.06
		col = C_DAWN.lerp(C_DAY, k)
		sun_e = lerpf(0.12, 0.38, k)
		sun_c = Color(1.0, 0.7, 0.55).lerp(sun_c, k)
	elif phase < 0.66:
		col = C_DAY
		sun_e = 0.38
	elif phase < DAY:
		var k := (phase - 0.66) / (DAY - 0.66)
		col = C_DAY.lerp(C_DUSK, minf(1.0, k * 1.6)).lerp(C_NIGHT, maxf(0.0, k - 0.6) / 0.4)
		sun_e = lerpf(0.38, 0.06, k)
		sun_c = Color(1.0, 0.55, 0.35)
	elif phase < 0.97:
		col = C_NIGHT
		sun_e = 0.06
		sun_c = Color(0.55, 0.65, 1.0)
	else:
		var k := (phase - 0.97) / 0.03
		col = C_NIGHT.lerp(C_DAWN, k)
		sun_e = lerpf(0.06, 0.12, k)
		sun_c = Color(0.55, 0.65, 1.0).lerp(Color(1.0, 0.7, 0.55), k)
	if cm:
		cm.color = col
	if sun:
		sun.energy = sun_e
		sun.color = sun_c
	var night := 1 if phase >= DAY else 0
	if night != _was_night:
		if _was_night != -1 and is_instance_valid(player):
			CombatText.add(player.global_position + Vector2(0, -150), "A noite caiu..." if night else "O sol nasceu!", Color(0.6, 0.7, 1.0) if night else Color(1, 0.85, 0.45), true)
		_was_night = night


## Hora do jogo em texto (06:00 = nascer do sol, 21:00 = começo da noite).
static func clock_text() -> String:
	var p := now_phase()
	var h := 6.0 + p / DAY * 15.0 if p < DAY else fmod(21.0 + (p - DAY) / (1.0 - DAY) * 9.0, 24.0)
	return "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)]
