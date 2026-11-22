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


func _init() -> void:
	app_sig = _read("res://app/assinatura.txt")
	if not OS.has_feature("android"):
		return
	if not FileAccess.file_exists(PACK) or not FileAccess.file_exists(INFO):
		return
	var info = JSON.parse_string(_read(INFO))
	if typeof(info) != TYPE_DICTIONARY or str(info.get("assinatura", "")) != app_sig:
		return
	pack_loaded = ProjectSettings.load_resource_pack(PACK, true)


func _ready() -> void:
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_keep_on(true)


static func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text().strip_edges() if f else ""
