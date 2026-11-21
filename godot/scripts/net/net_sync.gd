class_name NetSync
extends Node
## Ponte entre o jogo e a rede do navegador (web/arson_net.js, PeerJS).
## Envia o estado do jogador 10x/s e cria/atualiza/remove os outros jogadores.
## Monstros compartilhados: quem hospeda roda a inteligência dos monstros e envia o
## estado deles; os outros só espelham. Dano em monstro vai para o anfitrião; a
## experiência e o dano que os monstros causam voltam para cada jogador.
## Fora do navegador (editor, PC) o jogo roda offline.

signal chat_received(who: String, text: String)

static var inst: NetSync = null

var enabled := false
var net_ready := false
var status := "offline"
var is_host := false
var online_count := 1
var uid := ""
var player: Player
var world: Node2D
var remotes: Dictionary = {}
var _net = null
var _acc := 0.0


func _enter_tree() -> void:
	inst = self


func _exit_tree() -> void:
	if inst == self:
		inst = null


## Este jogo só espelha os monstros (outro jogador hospeda o mundo)?
static func is_puppet() -> bool:
	return inst != null and inst.enabled and inst.net_ready and not inst.is_host


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


## Evento para o anfitrião (no anfitrião, cai na própria caixa de entrada).
func send(e: Dictionary) -> void:
	if enabled:
		_net.send(JSON.stringify(e))


## Anfitrião -> um jogador.
func send_to(to: String, e: Dictionary) -> void:
	if enabled:
		_net.sendTo(to, JSON.stringify(e))


func _monsters() -> Array:
	return get_tree().get_nodes_in_group("monsters")


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
			"d": player.dead, "sf": Rules.is_safe(player.global_position), "l": player.level,
		}))
		if is_host and net_ready:
			var ms := []
			for m in _monsters():
				ms.append([m.idx, snappedf(m.global_position.x, 0.1), snappedf(m.global_position.y, 0.1), m.facing, m.anim,
					int(round(100.0 * m.hp / m.max_hp)), 1 if m.dead else 0])
			_net.setWorld(JSON.stringify(ms))
	var d = JSON.parse_string(str(_net.poll()))
	if typeof(d) != TYPE_DICTIONARY:
		return
	status = str(d.get("status", ""))
	is_host = bool(d.get("host", false))
	net_ready = bool(d.get("ready", false))
	uid = str(d.get("uid", ""))
	for c in d.get("chat", []):
		chat_received.emit(str(c.get("n", "?")), str(c.get("text", "")))
	var players: Dictionary = d.get("players", {})
	online_count = 1 + players.size() if net_ready else 1
	for id in players:
		var s: Dictionary = players[id]
		var r: RemotePlayer = remotes.get(id)
		if r == null:
			r = RemotePlayer.new()
			r.name = "Remoto_" + str(id)
			r.uid = str(id)
			r.position = Vector2(float(s.get("x", 0)), float(s.get("y", 0)))
			world.add_child(r)
			remotes[id] = r
		r.apply_state(s)
	for id in remotes.keys():
		if not players.has(id):
			remotes[id].queue_free()
			remotes.erase(id)
	# cliente: espelha os monstros do anfitrião
	var w = d.get("world")
	if w is Array:
		var by_idx := {}
		for m in _monsters():
			by_idx[m.idx] = m
		for row in w:
			if row is Array and row.size() >= 7:
				var m = by_idx.get(int(row[0]))
				if m != null:
					m.apply_remote(row)
	# anfitrião: eventos dos jogadores (dano nos monstros)
	for item in d.get("inbox", []):
		var e = item.get("e")
		if not e is Dictionary:
			continue
		var from := str(item.get("from", ""))
		if str(e.get("t", "")) == "dmg":
			var who: Node2D = player if from == uid else remotes.get(from)
			for m in _monsters():
				if m.idx == int(e.get("i", -1)):
					m.take_damage(clampi(int(e.get("n", 0)), 0, 99999), who, true)
					break
	# eventos para mim (experiência, dano dos monstros)
	for e in d.get("events", []):
		if not e is Dictionary:
			continue
		match str(e.get("t", "")):
			"xp":
				player.gain_xp(int(e.get("n", 0)), int(e.get("g", 0)), str(e.get("src", "")))
			"hit":
				player.take_damage(int(e.get("n", 0)), str(e.get("src", "monstro")))
