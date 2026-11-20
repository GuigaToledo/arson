class_name NetSync
extends Node
## Ponte entre o jogo e a rede do navegador (web/arson_net.js, PeerJS).
## Envia o estado do jogador 10x/s e cria/atualiza/remove os outros jogadores.
## Fora do navegador (editor, PC) o jogo roda offline.

signal chat_received(who: String, text: String)

var enabled := false
var status := "offline"
var is_host := false
var online_count := 1
var player: Player
var world: Node2D
var remotes: Dictionary = {}
var _net = null
var _acc := 0.0


func setup(p: Player, w: Node2D) -> void:
	player = p
	world = w
	if not OS.has_feature("web"):
		status = "offline (a rede funciona no navegador)"
		return
	if not JavaScriptBridge.eval("typeof window.ArsonNet !== 'undefined'", true):
		status = "offline (rede não carregou)"
		return
	_net = JavaScriptBridge.get_interface("ArsonNet")
	enabled = true
	var nm := str(_net.savedName()).strip_edges()
	if nm == "":
		nm = str(JavaScriptBridge.eval("(prompt('Nome do seu personagem:', '') || '')", true)).strip_edges().substr(0, 16)
		if nm == "":
			nm = "Mago %d" % randi_range(100, 999)
		_net.saveName(nm)
	player.display_name = nm
	_net.start(nm)


func say(text: String) -> void:
	if enabled:
		_net.say(text)
	else:
		chat_received.emit(player.display_name, text)


func _process(delta: float) -> void:
	if not enabled:
		return
	_acc += delta
	if _acc >= 0.1:
		_acc = 0.0
		var eq := {}
		var ids := player.equipment.to_ids()
		for k in ids:
			eq[str(k)] = ids[k]
		_net.setMe(JSON.stringify({
			"x": snappedf(player.global_position.x, 0.1), "y": snappedf(player.global_position.y, 0.1),
			"f": player.facing, "a": player.anim, "n": player.display_name, "eq": eq,
		}))
	var d = JSON.parse_string(str(_net.poll()))
	if typeof(d) != TYPE_DICTIONARY:
		return
	status = str(d.get("status", ""))
	is_host = bool(d.get("host", false))
	for c in d.get("chat", []):
		chat_received.emit(str(c.get("n", "?")), str(c.get("text", "")))
	var players: Dictionary = d.get("players", {})
	online_count = 1 + players.size() if bool(d.get("ready", false)) else 1
	for id in players:
		var s: Dictionary = players[id]
		var r: RemotePlayer = remotes.get(id)
		if r == null:
			r = RemotePlayer.new()
			r.name = "Remoto_" + str(id)
			r.position = Vector2(float(s.get("x", 0)), float(s.get("y", 0)))
			world.add_child(r)
			remotes[id] = r
		r.apply_state(s)
	for id in remotes.keys():
		if not players.has(id):
			remotes[id].queue_free()
			remotes.erase(id)
