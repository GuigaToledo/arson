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
## Registro da rede em memória (aba Diagnóstico do menu): últimas linhas, com a hora.
static var diag_lines: PackedStringArray = PackedStringArray()


static func diag_log(m: String) -> void:
	diag_lines.append("%s %s" % [Time.get_time_string_from_system(), m])
	if diag_lines.size() > 120:
		diag_lines = diag_lines.slice(diag_lines.size() - 120)
var is_host := false
var online_count := 1
var uid := ""
var player: Player
var world: Node2D
var remotes: Dictionary = {}
var _net = null
var _acc := 0.0
## Diagnóstico (?debug=1 no endereço): escreve no console do navegador a cada 5 s.
var debug := false
var _dbg_t := 0.0
var _dbg := {"mundo": 0, "dano_env": 0, "dano_rec": 0, "xp": 0, "hit": 0}


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
		# app (celular): mesma rede do navegador, em GDScript com WebRTC nativo. No computador só
		# com --rede (testes), e --sala=x usa uma sala separada.
		var args := OS.get_cmdline_user_args()
		var quer: bool = OS.has_feature("android") or args.has("--rede")
		var NN = load("res://scripts/net/net_nativo.gd")
		if not quer or not NN.disponivel():
			status = "offline" if not quer else "offline (rede indisponível)"
			return
		_net = NN.new()
		for a in args:
			if str(a).begins_with("--sala="):
				_net.sala = str(a).split("=")[1]
		add_child(_net)
		enabled = true
		var nm0 := player.display_name if player.display_name != "" else str(_net.savedName())
		if nm0 == "":
			nm0 = "Mago %d" % randi_range(100, 999)
		_net.saveName(nm0)
		player.display_name = nm0
		_net.start(nm0)
		return
	if not JavaScriptBridge.eval("typeof window.ArsonNet !== 'undefined'", true):
		status = "offline (rede não carregou)"
		return
	_net = JavaScriptBridge.get_interface("ArsonNet")
	enabled = true
	debug = bool(JavaScriptBridge.eval("/[?&]debug=1/.test(location.search)", true))
	var nm := str(_net.savedName()).strip_edges()
	if nm == "":
		nm = str(JavaScriptBridge.eval("(prompt('Nome do seu personagem:', '') || '')", true)).strip_edges().substr(0, 16)
		if nm == "":
			nm = "Mago %d" % randi_range(100, 999)
		_net.saveName(nm)
	player.display_name = nm
	_net.start(nm)


var _upd_t := 5.0


func _check_update(delta: float) -> void:
	_upd_t -= delta
	if _upd_t > 0.0 or _net == null:
		return
	_upd_t = 5.0
	if _net.updateReady():
		_upd_t = 1e9
		player.save()
		CombatText.add(player.global_position + Vector2(0, -140), "Nova versão do jogo — atualizando…", Color(1, 0.85, 0.4), true)
		get_tree().create_timer(2.0).timeout.connect(func(): _net.reloadForUpdate(Chars.slot))


func say(text: String) -> void:
	if enabled:
		_net.say(text)
	else:
		chat_received.emit(player.display_name, text)


## Evento para o anfitrião (no anfitrião, cai na própria caixa de entrada).
func send(e: Dictionary) -> void:
	if enabled:
		_dbg.dano_env += 1
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
	_check_update(delta)
	_acc += delta
	if _acc >= 0.1:
		_acc = 0.0
		var eq := {}
		var ids := player.equipment.to_ids()
		for k in ids:
			eq[str(k)] = ids[k]
		_net.setMe(JSON.stringify({
			"x": snappedf(player.global_position.x, 0.1), "y": snappedf(player.global_position.y, 0.1),
			"vx": snappedf(player.velocity.x, 1.0), "vy": snappedf(player.velocity.y, 1.0),
			"sh": player.shield_els if player.shield_hp > 0.0 else [], "shf": snappedf(player.shield_hp / maxf(1.0, player.shield_max), 0.01) if player.shield_hp > 0.0 else 0.0,
			"f": player.facing, "a": player.anim, "n": player.display_name, "eq": eq,
			"d": player.dead, "sf": Rules.is_safe(player.global_position), "l": player.level, "c": player.classe, "hp": int(round(player.hp * 100.0 / player.max_hp)), "sm": player.summons_state(),
		}))
		if is_host and net_ready:
			var ms := []
			for m in _monsters():
				ms.append([m.idx, snappedf(m.global_position.x, 0.1), snappedf(m.global_position.y, 0.1), m.facing, m.anim,
					int(round(100.0 * m.hp / m.max_hp)), 1 if m.dead else 0])
			_net.setWorld(JSON.stringify(ms))
	if debug:
		_dbg_t += delta
		if _dbg_t >= 5.0:
			_dbg_t = 0.0
			var alive := 0
			for m in _monsters():
				if not m.dead:
					alive += 1
			var rinfo := []
			for rp in get_tree().get_nodes_in_group("remote_players"):
				rinfo.append("%s:%s:hp%d:inv%d" % [rp.display_name, rp.classe, rp.hp_pct, rp._sm_puppets.size()])
			print("ARSONDBG host=%s pronto=%s jogadores=%d monstros_vivos=%d %s outros=%s aliado=%d hot=%d janela=%s fps=%d" % [is_host, net_ready, online_count, alive, JSON.stringify(_dbg), rinfo, _dbg.get("aliado", 0), int(player.hot_t), get_window().size, Engine.get_frames_per_second()])
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
		_dbg.mundo += 1
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
			_dbg.dano_rec += 1
			var who: Node2D = player if from == uid else remotes.get(from)
			for m in _monsters():
				if m.idx == int(e.get("i", -1)):
					m.take_damage(clampi(int(e.get("n", 0)), 0, 99999), who, true)
					break
		elif str(e.get("t", "")) == "ally":
			# magia de Luz de um jogador para outro: o anfitrião repassa
			send_to(str(e.get("to", "")), e)
		elif str(e.get("t", "")) == "sp":
			# magia lançada: o anfitrião mostra (se não foi ele) e repassa a todos os outros
			e["from"] = from
			if from != uid:
				_show_spell(remotes.get(from), e)
			for rid in remotes:
				if str(rid) != from:
					send_to(str(rid), e)
		elif str(e.get("t", "")) == "fx":
			var who2: Node2D = player if from == uid else remotes.get(from)
			for m in _monsters():
				if m.idx == int(e.get("i", -1)):
					m.apply_effect(str(e.get("el", "")), clampf(float(e.get("p", 0)), 0, 9999), who2, bool(e.get("h", false)), true)
					break
	# eventos para mim (experiência, dano dos monstros)
	for e in d.get("events", []):
		if not e is Dictionary:
			continue
		match str(e.get("t", "")):
			"sp":
				if str(e.get("from", "")) != uid:
					_show_spell(remotes.get(str(e.get("from", ""))), e)
			"xp":
				_dbg.xp += 1
				player.gain_xp(int(e.get("n", 0)), int(e.get("g", 0)), str(e.get("src", "")))
			"hit":
				_dbg.hit += 1
				player.take_damage(int(e.get("n", 0)), str(e.get("src", "monstro")))
			"ally":
				_dbg["aliado"] = int(_dbg.get("aliado", 0)) + 1
				player.receive_ally(e)


## Desenha a magia que outro jogador lançou (só o visual: o dano é do anfitrião).
func _show_spell(caster, e: Dictionary) -> void:
	if caster == null or not is_instance_valid(caster) or world == null:
		return
	var sp := Spells.get_spell(str(e.get("id", "")), str(e.get("c", "")))
	if sp.is_empty():
		return
	var parent: Node = world
	var pos: Vector2 = caster.global_position
	var els: Array = sp.els
	var aim := Vector2(float(e.get("ax", pos.x)), float(e.get("ay", pos.y)))
	if caster.has_method("play_action"):
		caster.play_action("cast", 0.45)
	SpellArt.boost = clampi(int(e.get("up", 0)), 0, 4)
	match str(sp.type):
		"single":
			var tgt: Node2D = null
			var ti := int(e.get("ti", -1))
			for m in _monsters():
				if m.idx == ti:
					tgt = m
					break
			var temp := false
			if tgt == null:
				tgt = Node2D.new()
				tgt.global_position = aim
				parent.add_child(tgt)
				temp = true
			var big: bool = sp.get("big", false)
			var pel: String = els[els.size() - 1] if big else els[0]
			var alvo := tgt
			if caster.has_method("staff_tip"):
				caster.facing = Iso.dir_from_vector(tgt.global_position - pos)
				pos = caster.staff_tip()
			SpellArt.projectile(parent, pos, tgt, pel, big, els, func():
				if is_instance_valid(alvo):
					for el in els:
						SpellArt.impact(parent, alvo.global_position, el, big))
			if temp:
				get_tree().create_timer(4.0).timeout.connect(func(): if is_instance_valid(alvo): alvo.queue_free())
		"cc":
			for el in els:
				SpellArt.cc(parent, aim, float(sp.radius), el)
		"cone", "line":
			var sd := Vector2(float(e.get("dx", 1.0)), float(e.get("dy", 0.0)))
			if str(sp.type) == "cone":
				SpellArt.cone(parent, pos, sd, float(sp.range) * 64.0, float(sp.ang), els[0])
			else:
				var gd := Vector2(float(e.get("gx", 1.0)), float(e.get("gy", 0.0)))
				SpellArt.line(parent, pos, Iso.to_screen(Iso.to_grid(pos) + gd * float(sp.range)), els[0])
		"area":
			SpellArt.area(parent, aim, float(sp.radius), els[0], func(): pass, els)
		"heal":
			SpellArt.light(parent, "heal", pos)
			if sp.has("ring"):
				SpellArt.light(parent, "ring", pos)
		"chainheal":
			SpellArt.light(parent, "heal", pos)
		"hot":
			SpellArt.light(parent, "bless", pos)
		"buff":
			SpellArt.light(parent, "brave", pos)
		"invis":
			SpellArt.light(parent, "veil", pos)
		"immortal":
			SpellFx.level_up(parent, pos, sp.color)
	SpellArt.boost = 0
