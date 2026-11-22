extends Node
## App Android: carrega a versão do jogo baixada pela atualização automática.
## É o primeiro autoload e roda antes de qualquer outro script do jogo ser lido, então tudo que
## vem depois (inclusive o ItemDB) já sai do pacote novo. Este arquivo não deve mudar: o app
## instalado sempre usa a cópia dele que veio no APK.

const PACK := "user://jogo.pck"
const INFO := "user://jogo_info.json"

## Assinatura do app instalado (classes, autoloads e versão do Godot). Um pacote só serve
## para um app com a mesma assinatura; se mudar, é preciso baixar o app novo.
var app_sig := ""
var pack_loaded := false
## Quantas vezes seguidas o app fechou antes de terminar de abrir o jogo (0 = abriu bem).
var crashes := 0
## Em que etapa ele parou da última vez (para mostrar na tela).
var last_step := ""
## Todas as etapas da abertura anterior (mostradas na tela de abertura).
var prev_steps := ""
const STEPS := "user://etapas.txt"


func _init() -> void:
	app_sig = _read("res://app/assinatura.txt")
	if not OS.has_feature("android"):
		return
	var prev := _read(STEPS).split("\n", false)
	prev_steps = " → ".join(prev.slice(1))
	if prev.size() >= 2:
		crashes = int(prev[0])
		last_step = prev[prev.size() - 1]
		if last_step != "ok":
			crashes += 1
		else:
			crashes = 0
	step("inicio")
	step("boot")
	if not FileAccess.file_exists(PACK) or not FileAccess.file_exists(INFO):
		return
	var info = JSON.parse_string(_read(INFO))
	if typeof(info) != TYPE_DICTIONARY or str(info.get("assinatura", "")) != app_sig:
		return
	pack_loaded = ProjectSettings.load_resource_pack(PACK, true)


## Marca até onde o jogo chegou ao abrir (grava na hora: se o app fechar, a próxima abertura sabe).
func step(name: String) -> void:
	if not OS.has_feature("android"):
		return
	var f := FileAccess.open(STEPS, FileAccess.READ_WRITE if FileAccess.file_exists(STEPS) else FileAccess.WRITE)
	if f == null:
		return
	if name == "inicio":
		f.close()
		f = FileAccess.open(STEPS, FileAccess.WRITE)
		f.store_line(str(crashes))
	else:
		f.seek_end()
	f.store_line(name)
	f.close()


func _ready() -> void:
	step("autoloads")
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_keep_on(true)
	step("tela ligada")


static func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text().strip_edges() if f else ""


## Fim do arquivo de log do Godot (para mostrar na tela depois de uma falha).
static func log_tail(lines := 14) -> String:
	var d := DirAccess.open("user://logs")
	if d == null:
		return ""
	var files := Array(d.get_files()).filter(func(x): return x.ends_with(".log"))
	files.sort()
	var out := []
	# o log da execução anterior é o penúltimo (o último é o desta)
	for nm in files.slice(maxi(0, files.size() - 2), files.size() - 1):
		out.append_array(_read("user://logs/" + nm).split("\n", false))
	return "\n".join(out.slice(maxi(0, out.size() - lines)))
