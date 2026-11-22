class_name Perf
extends Node
## Resolução em 6 níveis. Na "Automática", mede o FPS e baixa um nível quando o jogo engasga
## (celular ou PC lento), e sobe de novo quando sobra desempenho. A interface fica do mesmo tamanho;
## só o mundo é desenhado com menos pixels e ampliado.

const BASE := Vector2(960, 540)

var _acc := 0.0
var _frames := 0
var _bad := 0
var _good := 0
var _applied := -1
var _win := Vector2i.ZERO
## Depois de baixar por lag, não volta ao nível que travou por 2 minutos (evita ficar oscilando).
var _ceil := 6
var _ceil_t := 0.0
static var fps := 60.0
## Menu aberto: desenha tudo em resolução máxima (texto nítido).
static var force_full := false


func _ready() -> void:
	Settings.load_all()
	if Settings.quality == 0:
		Settings.level_now = 3 if Settings.is_mobile() else 6
		if Settings.safe_mode():
			Settings.level_now = 1
			_ceil = 2
	else:
		Settings.level_now = Settings.quality
	apply()


## Aplica Settings.level_now (ou chame depois de mudar Settings.quality).
func apply() -> void:
	if Settings.quality != 0:
		Settings.level_now = Settings.quality
	var win := get_window()
	var lv := 6 if force_full else clampi(Settings.level_now, 1, 6)
	_applied = lv
	# bordas suaves (antisserrilhamento 4x) do nível 4 para cima; no celular e nos níveis baixos, desligado
	# (no navegador o Godot não tem MSAA 2D: lá a suavidade vem da resolução dobrada no index.html)
	if not OS.has_feature("web"):
		win.msaa_2d = Viewport.MSAA_4X if lv >= 4 and not Settings.is_mobile() else Viewport.MSAA_DISABLED
	_win = win.size
	if lv >= 6:
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		win.content_scale_size = Vector2i(BASE)
		win.content_scale_factor = 1.0
		return
	# altura real de desenho = altura da janela × fração do nível (nunca abaixo de 360 px)
	var h := maxf(360.0, float(win.size.y) * float(Settings.LEVELS[lv]))
	var s := maxf(0.5, h / BASE.y)
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	win.content_scale_size = Vector2i((BASE * s).round())
	win.content_scale_factor = s


func _process(delta: float) -> void:
	if get_window().size != _win:
		apply()
	_acc += delta
	_ceil_t -= delta
	if _ceil_t <= 0.0:
		_ceil = 6
	_frames += 1
	if _acc < 2.0:
		return
	fps = _frames / _acc
	_acc = 0.0
	_frames = 0
	if Settings.quality != 0 or force_full:
		return
	# automática: 2 medições ruins seguidas baixam; 8 boas seguidas (16 s) sobem
	if fps < 42.0:
		_bad += 1
		_good = 0
	elif fps > 57.0:
		_good += 1
		_bad = 0
	else:
		_bad = 0
		_good = 0
	if _bad >= 2 and Settings.level_now > 1:
		_ceil = Settings.level_now - 1
		_ceil_t = 120.0
		Settings.level_now -= 1
		_bad = 0
		apply()
	elif _good >= 8 and Settings.level_now < _ceil:
		Settings.level_now += 1
		_good = 0
		apply()
