class_name Settings
extends RefCounted
## Configurações do jogador (salvas separadas do progresso): automação, zoom e resolução.

const PATH := "user://arson_config.cfg"

## Automação (menu → Automação). Porcentagens de 5 a 95.
static var auto := {
	"alvo": false, "ataque": false,
	"cura": false, "cura_pct": 60,
	"pocao_vida": false, "pocao_vida_pct": 35,
	"pocao_mana": false, "pocao_mana_pct": 25,
	"infinitas": false,
	"summon_agressivo": true,
	"summon_auto": true,
	"escudo_auto": true,
	"treino": false, "treino_id": "luz:1",
}
static var zoom := 1.9
## 0 = automática; 1 (mais leve) a 6 (resolução total).
static var quality := 0
## Nível em uso agora (na automática, muda sozinho conforme o desempenho).
static var level_now := 6

## Fração da resolução da tela usada em cada nível (1 a 6).
const LEVELS := [0.0, 0.4, 0.5, 0.6, 0.72, 0.85, 1.0]
const LEVEL_NAMES := ["Automática", "1 · muito leve", "2 · leve", "3 · média", "4 · boa", "5 · alta", "6 · máxima"]
const ZOOM_MIN := 1.1
const ZOOM_MAX := 3.0

static var _loaded := false


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	var a = c.get_value("config", "auto", {})
	if a is Dictionary:
		for k in auto:
			if a.has(k) and typeof(a[k]) == typeof(auto[k]):
				auto[k] = a[k]
	zoom = clampf(float(c.get_value("config", "zoom", zoom)), ZOOM_MIN, ZOOM_MAX)
	quality = clampi(int(c.get_value("config", "qualidade", 0)), 0, 6)


static func save() -> void:
	var c := ConfigFile.new()
	c.set_value("config", "auto", auto)
	c.set_value("config", "zoom", zoom)
	c.set_value("config", "qualidade", quality)
	c.save(PATH)


## Quantas vezes por segundo os monstros e outros personagens são redesenhados (o jogador sempre 24).
static func anim_hz() -> float:
	return 12.0 if level_now <= 2 else (18.0 if level_now <= 4 else 24.0)


## Quantas das 6 "faixas" de luzes decorativas (cogumelos, cristais) ficam acesas em cada nível.
static func light_share() -> int:
	return [0, 1, 2, 2, 3, 4, 6][clampi(level_now, 0, 6)]


static var _mobile := -1
static var _leve := -1


## Modo leve de segurança: a página liga quando o vídeo do celular reiniciou (falta de memória
## de vídeo). Começa no nível 1, com texturas pequenas, até o jogador escolher outra qualidade.
static func safe_mode() -> bool:
	if _leve < 0:
		_leve = 0
		var boot = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Boot")
		if boot and boot.crashes >= 1:
			_leve = 1
		if OS.has_feature("web"):
			_leve = 1 if str(JavaScriptBridge.eval("(function(){try{return localStorage.getItem('arson-leve')||''}catch(e){return ''}})()", true)) == "1" else 0
	return _leve == 1


## App fechou sozinho 2 vezes seguidas: abre o chão sem texturas (só cores).
static func very_safe() -> bool:
	var boot = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Boot")
	return boot != null and boot.crashes >= 2


## Celular/tablet? (Android, iPhone, iPad — inclusive o iPad que se diz "Mac").
static func is_mobile() -> bool:
	if _mobile < 0:
		var m := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
		if not m and OS.has_feature("web"):
			m = bool(JavaScriptBridge.eval("/Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent) || (navigator.maxTouchPoints > 1 && /Macintosh/.test(navigator.userAgent))", true))
		_mobile = 1 if m else 0
	return _mobile == 1
