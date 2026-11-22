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
## Primeiros segundos: sobe de nível mais rápido (começa no mais leve).
var _warm := 45.0
var _ceil_t := 0.0
static var fps := 60.0
## Menu aberto: desenha tudo em resolução máxima (texto nítido).
static var force_full := false


func _ready() -> void:
	Settings.load_all()
	if Settings.quality == 0:
		# automática: sempre começa no mais leve e sobe enquanto o FPS aguentar
		Settings.level_now = 1
		if Settings.safe_mode():
			_ceil = 2
			_ceil_t = 600.0
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
	# efeitos acompanham o nível real (não o do menu aberto)
	if is_inside_tree():
		get_tree().call_group("qualidade", "on_quality", clampi(Settings.level_now, 1, 6))
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
	_warm -= delta
	_ceil_t -= delta
	if _ceil_t <= 0.0:
		_ceil = 6
	_frames += 1
	if _acc < 2.0:
		return
	fps = _frames / _acc
	_perf_log(_frames)
	_acc = 0.0
	_frames = 0
	if Settings.quality != 0 or force_full:
		return
	# automática: 2 medições ruins seguidas baixam; 8 boas seguidas (16 s) sobem
	# subir: medições a 54+ contam; uma queda curta (luta) só desconta 1, não zera.
	# baixar: 2 medições seguidas abaixo de 40.
	if fps < 40.0:
		_bad += 1
		_good = 0
	elif fps >= 54.0:
		_good += 1
		_bad = 0
	else:
		_bad = 0
		_good = maxi(0, _good - 1)
	if _bad >= 2 and Settings.level_now > 1:
		_ceil = Settings.level_now - 1
		_ceil_t = 120.0
		Settings.level_now -= 1
		_bad = 0
		apply()
	elif _good >= (2 if _warm > 0.0 else 5) and Settings.level_now < _ceil:
		Settings.level_now += 1
		_good = 0
		apply()


var _log_n := 0


## A cada ~5 s (no Android): FPS, tempo de processamento, desenhos, objetos e o tempo de cada parte.
func _perf_log(frames: int) -> void:
	if not Prof.on:
		return
	_log_n += 1
	if _log_n % 2 != 0:
		Prof.report(frames)
		return
	var vis := 0
	for a in get_tree().get_nodes_in_group("actors"):
		if a.visual and a.visual.visible:
			vis += 1
	var lights := 0
	for l in get_tree().root.find_children("*", "PointLight2D", true, false):
		if l.visible and l.enabled:
			lights += 1
	print("ARSONPERF fps=%.1f nivel=%d proc=%.1fms fis=%.1fms desenhos=%d objs=%d prims=%d nos=%d atores_visiveis=%d luzes=%d mem=%dMB | %s" % [fps, Settings.level_now,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		vis, lights, int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0), Prof.report(frames)])
	if _log_n % 6 == 0:
		_census()


## Quantos objetos de cada tipo existem (e quantos visíveis), para achar o que pesa.
func _census() -> void:
	var tot := {}
	var vis := {}
	var procs := {}
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var k := n.get_class()
		var sc = n.get_script()
		if sc:
			k = str(sc.resource_path).get_file().get_basename() + ":" + k
		tot[k] = int(tot.get(k, 0)) + 1
		if n is CanvasItem and n.is_visible_in_tree():
			vis[k] = int(vis.get(k, 0)) + 1
		if n.is_processing() or n.is_physics_processing():
			procs[k] = int(procs.get(k, 0)) + 1
	var keys := tot.keys()
	keys.sort_custom(func(x, y): return tot[x] > tot[y])
	var out := PackedStringArray()
	for k in keys.slice(0, 18):
		out.append("%s=%d/vis%d/proc%d" % [k, tot[k], int(vis.get(k, 0)), int(procs.get(k, 0))])
	print("ARSONCENSO ", " ".join(out))

