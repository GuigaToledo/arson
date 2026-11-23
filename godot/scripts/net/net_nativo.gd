extends Node
## Rede do app (celular/computador), compatível com a rede do navegador (web/arson_net.js):
## fala o mesmo protocolo do PeerJS (servidor de salas 0.peerjs.com por WebSocket, dados por WebRTC
## com mensagens JSON), então o app entra no mesmo mundo que os jogadores do navegador.
## O primeiro a chegar vira o anfitrião (ID fixo); os outros se conectam nele.
## Mesmas funções que o NetSync chama no ArsonNet do navegador.
## Precisa da extensão WebRTC nativa (addons/webrtc_native).

const SERVIDOR := "wss://0.peerjs.com/peerjs"
const CHAVE := "peerjs"
const HOST_ID := "arson-godot-taverna-v1-q9w4z"
const MAX_PLAYERS := 20
const ICE_STUN := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]}]}
## TURN gratuito (openrelay.metered.ca) está fora do ar. No celular a coleta espera
## esses servidores e a oferta não chega no navegador. Sem credencial nova, só STUN.
const ICE := {"iceServers": [
	{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302", "stun:global.stun.twilio.com:3478"]},
	{"urls": ["turn:openrelay.metered.ca:80", "turn:openrelay.metered.ca:443", "turn:openrelay.metered.ca:443?transport=tcp"],
		"username": "openrelayproject", "credential": "openrelayproject"},
]}

var uid := ""
## Sala separada (igual ao ?sala= do navegador): HOST_ID + "-" + sala.
var sala := ""
var _ws: WebSocketPeer
var _my_id := ""
var _is_host := false
var _ready := false
var _running := false
var _status := "desconectado"
var _name := "Viajante"
var _me = null
var _players := {}
var _chat: Array = []
var _events: Array = []
var _inbox: Array = []
var _world = null
var _world_in = null
## conexões: connectionId -> {pc, ch, peer, uid, open}
var _conns := {}
var _host_conn := ""
var _hb := 0.0
var _relay := 0.0
var _retry_t := -1.0
var _last_rx := 0
var _ws_open := false
var _connect_t := 0.0
var _visto := 0.0


## Texto do teste do WebRTC nativo (aba Diagnóstico): diz se a extensão carregou e se cria canal de dados.
static func teste_webrtc() -> String:
	var t := PackedStringArray()
	t.append("classe WebRTCPeerConnection: %s" % ClassDB.class_exists("WebRTCPeerConnection"))
	t.append("extensão nativa (WebRTCLibPeerConnection) carregada: %s" % ClassDB.class_exists("WebRTCLibPeerConnection"))
	if ClassDB.class_exists("WebRTCPeerConnection"):
		var pc := WebRTCPeerConnection.new()
		var e := pc.initialize({"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]})
		t.append("initialize: erro %d" % e)
		var ch := pc.create_data_channel("teste")
		t.append("create_data_channel: %s" % ("OK" if ch != null else "NULO (WebRTC não funciona neste aparelho)"))
		pc.close()
	return "\n".join(t)


static func disponivel() -> bool:
	# a classe vazia do motor responde "ok" a tudo: só vale se a extensão nativa carregou de verdade
	if not ClassDB.class_exists("WebRTCPeerConnection") or not ClassDB.class_exists("WebRTCLibPeerConnection"):
		return false
	var pc := WebRTCPeerConnection.new()
	var ok := pc.initialize({}) == OK
	pc.close()
	return ok


func _init() -> void:
	uid = _rnd(8)


func _rnd(n: int) -> String:
	var a := "abcdefghijklmnopqrstuvwxyz0123456789"
	var s := ""
	for i in n:
		s += a[randi() % a.length()]
	return s


func _log(m: String) -> void:
	print("[arson-net] ", m)
	NetSync.diag_log(m)


func _diag(m: String) -> void:
	_status = m
	_log(m)


# ------------------------------------------------------------ API (igual ao ArsonNet do navegador)
func start(nome: String) -> void:
	if _running:
		return
	_name = nome.substr(0, 16)
	_running = true
	_try_host()


func setMe(json: String) -> void:
	var s = _clean(JSON.parse_string(json))
	if s == null:
		return
	_me = s
	if not _is_host and _ready and _host_conn != "":
		_send_conn(_host_conn, {"t": "st", "uid": uid, "s": s})


func say(text: String) -> void:
	text = text.strip_edges().substr(0, 120)
	if text == "" or not _ready:
		return
	if _is_host:
		_relay_say(uid, text)
	elif _host_conn != "":
		_send_conn(_host_conn, {"t": "say", "text": text})


func poll() -> String:
	var others := {}
	for k in _players:
		if k != uid:
			others[k] = _players[k]
	var out := {"status": _status, "host": _is_host, "ready": _ready, "uid": uid, "players": others,
		"chat": _chat, "events": _events, "inbox": _inbox, "world": null if _is_host else _world_in}
	_chat = []
	_events = []
	_inbox = []
	_world_in = null
	return JSON.stringify(out)


func setWorld(json: String) -> void:
	if _is_host:
		_world = JSON.parse_string(json)


func send(json: String) -> void:
	var e = JSON.parse_string(json)
	if not e is Dictionary or not _ready:
		return
	if _is_host:
		_inbox.append({"from": uid, "e": e})
	elif _host_conn != "":
		_send_conn(_host_conn, {"t": "ev", "e": e})


func sendTo(to: String, json: String) -> void:
	var e = JSON.parse_string(json)
	if not e is Dictionary or not _is_host:
		return
	if to == uid:
		_events.append(e)
		return
	for cid in _conns:
		var c: Dictionary = _conns[cid]
		if c.uid == to and c.open:
			_send_conn(cid, {"t": "ev2", "e": e})


func savedName() -> String:
	return FileAccess.get_file_as_string("user://nome.txt").strip_edges() if FileAccess.file_exists("user://nome.txt") else ""


func saveName(n: String) -> void:
	var f := FileAccess.open("user://nome.txt", FileAccess.WRITE)
	if f:
		f.store_string(n.substr(0, 16))


func updateReady() -> bool:
	return false  # o app se atualiza pelo AppUpdate


func reloadForUpdate(_slot) -> void:
	pass


# ------------------------------------------------------------ conexão com o servidor de salas
func _kill() -> void:
	for cid in _conns:
		var c: Dictionary = _conns[cid]
		var no: Node = c.get("no")
		if no and is_instance_valid(no):
			no.fechar()
			no.queue_free()
		else:
			if c.ch:
				c.ch.close()
			if c.pc:
				c.pc.close()
	_conns.clear()
	_host_conn = ""
	if _ws:
		_ws.close()
	_ws = null
	_ws_open = false
	_ready = false
	_is_host = false


func _open_ws(id: String) -> void:
	_my_id = id
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	var url := "%s?key=%s&id=%s&token=%s&version=1.5.4" % [SERVIDOR, CHAVE, id, _rnd(10)]
	var err := _ws.connect_to_url(url)
	_ws_open = false
	_connect_t = 12.0
	if err != OK:
		_retry("Erro ao iniciar a rede.")


func _host_id() -> String:
	return HOST_ID + ("-" + sala if sala != "" else "")


func _try_host() -> void:
	_kill()
	_diag("Procurando o mundo…")
	_open_ws(_host_id())


func _join() -> void:
	_kill()
	_diag("Mundo encontrado. Entrando…")
	_open_ws("arsonapp" + _rnd(10))


func _retry(why: String, segundos := 3.0) -> void:
	_kill()
	_diag(why + " Tentando de novo…")
	_retry_t = segundos + randf()


func _ws_send(d: Dictionary) -> int:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNCONFIGURED
	return _ws.send_text(JSON.stringify(d))


func _process(delta: float) -> void:
	if not _running:
		return
	if _retry_t >= 0.0:
		_retry_t -= delta
		if _retry_t < 0.0:
			_try_host()
		return
	if _ws:
		_ws.poll()
		# lê tudo o que chegou, mesmo se o servidor já fechou (ID-TAKEN chega e ele fecha em seguida)
		var ws0 := _ws
		while ws0 == _ws and ws0.get_available_packet_count() > 0:
			_on_server(JSON.parse_string(ws0.get_packet().get_string_from_utf8()))
		if _ws == null or _ws != ws0:
			return
		var st := _ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			_hb -= delta
			if _hb <= 0.0:
				_hb = 5.0
				_ws_send({"type": "HEARTBEAT"})
		elif st == WebSocketPeer.STATE_CLOSED:
			# tentando ser o anfitrião e o servidor recusou antes de abrir: o ID já tem dono (ID-TAKEN)
			if not _ws_open and _my_id == _host_id():
				_join()
				return
			if _is_host or not _ready:
				_retry("O servidor de salas fechou a conexão (%d %s)." % [_ws.get_close_code(), _ws.get_close_reason()])
				return
		if not _ws_open:
			_connect_t -= delta
			if _connect_t <= 0.0:
				_retry("O servidor de salas não respondeu.")
				return
	for cid in _conns.keys():
		_poll_conn(cid)
	if _is_host and _ready:
		_relay -= delta
		if _relay <= 0.0:
			_relay = 0.1
			_host_tick()
	elif _ready and Time.get_ticks_msec() - _last_rx > 6000:
		_retry("O anfitrião parou de responder.", 1.2)
	elif not _is_host and not _ready and _retry_t < 0.0 and _my_id != "" and _my_id != _host_id():
		_visto += delta
		if _visto >= 2.0:
			_visto = 0.0
			_diag(_fase_txt())


func _on_server(m) -> void:
	if not m is Dictionary:
		return
	var tipo := str(m.get("type", ""))
	match tipo:
		"OPEN":
			_ws_open = true
			if _my_id == _host_id():
				_is_host = true
				_ready = true
				_players = {}
				_diag("Online — você está hospedando o mundo.")
			else:
				_ws_open = true
				_connect_to_host()
		"ID-TAKEN":
			_ws_open = true
			_join()
		"ERROR", "INVALID-KEY":
			_retry("Falha no servidor de salas.")
		"EXPIRE":
			# mensagem para alguém que não está mais lá
			if not _is_host:
				_retry("O anfitrião saiu; assumindo o mundo…", 1.2)
		"LEAVE":
			var src := str(m.get("src", ""))
			for cid in _conns.keys():
				if str(_conns[cid].peer) == src:
					_drop(cid)
			if not _is_host and src == _host_id():
				_retry("O anfitrião saiu.", 1.2)
		"OFFER":
			_on_offer(str(m.get("src", "")), m.get("payload", {}))
		"ANSWER":
			var p: Dictionary = m.get("payload", {})
			var cid := str(p.get("connectionId", ""))
			if _conns.has(cid):
				var sdp: Dictionary = p.get("sdp", {})
				var pc_r: WebRTCPeerConnection = _conns[cid].pc
				var er: int = pc_r.set_remote_description("answer", str(sdp.get("sdp", "")))
				_diag("Entrando… resposta do anfitrião (erro %d)" % er)
		"CANDIDATE":
			var p2: Dictionary = m.get("payload", {})
			var cid2 := str(p2.get("connectionId", ""))
			if _conns.has(cid2):
				var c: Dictionary = p2.get("candidate", {})
				var meio := str(c.get("sdpMid", "0"))
				if meio == "" or meio == "<null>":
					meio = "0"
				var linha := str(c.get("candidate", ""))
				var er_ice: int = _conns[cid2].pc.add_ice_candidate(meio, int(c.get("sdpMLineIndex", 0)), linha)
				if er_ice != OK:
					_log("%s candidato remoto recusado (erro %d) %s" % [cid2, er_ice, linha.substr(0, 80)])


# ------------------------------------------------------------ WebRTC
## Texto curto da etapa, o que a tela do celular mostra (o print antigo não aparecia lá).
func _fase_txt() -> String:
	if _host_conn == "" or not _conns.has(_host_conn):
		var nome := "sem sala"
		if _ws:
			var wst: int = _ws.get_ready_state()
			var nomes := PackedStringArray(["ligando na sala", "sala aberta", "fechando a sala", "sala fechada"])
			if wst >= 0 and wst < nomes.size():
				nome = nomes[wst]
		return "Entrando… " + nome
	var c: Dictionary = _conns[_host_conn]
	var pc: WebRTCPeerConnection = c.pc
	var st: int = pc.get_connection_state()
	var gs: int = pc.get_gathering_state()
	var est := PackedStringArray(["novo", "conectando", "conectado", "caiu", "falhou", "fechado"])
	var gel := PackedStringArray(["gelo novo", "gelo coletando", "gelo pronto"])
	var sn := est[st] if st >= 0 and st < est.size() else str(st)
	var gn := gel[gs] if gs >= 0 and gs < gel.size() else str(gs)
	return "Entrando… %s, %s, cand %d (host %d, pública %d)" % [sn, gn, int(c.get("nc", 0)), int(c.get("nh", 0)), int(c.get("ns", 0))]


## estado: 0 novo, 1 conectando, 2 conectado, 3 caiu, 4 falhou, 5 fechado.
func _falha_rota(st: int, c: Dictionary) -> String:
	var nh := int(c.get("nh", 0))
	var ns := int(c.get("ns", 0))
	if nh == 0 and ns == 0:
		return "Sem candidatos de rede (estado %d)." % st
	return "Rota não abriu (estado %d, host %d, pública %d)." % [st, nh, ns]


## Nó próprio por ligação: no Android a extensão não chama lambda nem Callable.bind.
func _novo_no(cid: String, peer: String) -> Node:
	var no := Node.new()
	no.set_script(load("res://scripts/net/net_pc.gd"))
	no.cid = cid
	no.peer_id = peer
	no.dono = self
	add_child(no)
	# TURN morto trava a coleta no celular. Só STUN; se o aparelho recusar, o padrão.
	var err: int = no.montar(ICE_STUN)
	_log("conexão %s iniciada (erro %d)" % [cid, err])
	if not _is_host:
		_diag("Entrando… iniciada (erro %d)" % err)
	return no


func _on_sdp(tipo: String, sdp: String, cid: String, peer: String) -> void:
	if not _conns.has(cid):
		return
	var pc: WebRTCPeerConnection = _conns[cid].pc
	pc.set_local_description(tipo, sdp)
	var payload := {"sdp": {"type": tipo, "sdp": sdp}, "type": "data", "connectionId": cid, "browser": "godot"}
	if tipo == "offer":
		payload.merge({"label": cid, "serialization": "json", "reliable": true, "metadata": null})
	var err := _ws_send({"type": tipo.to_upper(), "payload": payload, "dst": peer})
	_log("%s %s enviada (erro %d, %d bytes)" % [cid, tipo, err, sdp.length()])
	if not _is_host:
		_diag("Entrando… %s enviada (erro %d)" % [tipo, err])


func _on_ice(mid: String, idx: int, cand: String, cid: String, peer: String) -> void:
	var linha := cand
	if linha.begins_with("a="):
		linha = linha.substr(2)
	if not linha.begins_with("candidate:"):
		linha = "candidate:" + linha
	var meio := mid if mid != "" else "0"
	var tipo := "outro"
	if " typ host" in linha:
		tipo = "host"
	elif " typ srflx" in linha:
		tipo = "pública"
	elif " typ relay" in linha:
		tipo = "relay"
	if _conns.has(cid):
		var c: Dictionary = _conns[cid]
		c["nc"] = int(c.get("nc", 0)) + 1
		if tipo == "host":
			c["nh"] = int(c.get("nh", 0)) + 1
		elif tipo == "pública":
			c["ns"] = int(c.get("ns", 0)) + 1
	var err := _ws_send({"type": "CANDIDATE", "payload": {"candidate": {"candidate": linha, "sdpMid": meio, "sdpMLineIndex": idx}, "type": "data", "connectionId": cid}, "dst": peer})
	_log("%s candidato %s mid=%s (erro %d)" % [cid, tipo, meio, err])
	if not _is_host and _conns.has(cid) and int(_conns[cid].get("nc", 0)) <= 4:
		_diag(_fase_txt())


## Cliente: conecta no anfitrião (eu ofereço, como o PeerJS do navegador faz).
func _connect_to_host() -> void:
	var cid := "dc_" + _rnd(12)
	var no := _novo_no(cid, _host_id())
	var pc: WebRTCPeerConnection = no.pc
	var ch: WebRTCDataChannel = pc.create_data_channel(cid, {"ordered": true})
	if ch == null:
		ch = pc.create_data_channel(cid)
	no.ch = ch
	_conns[cid] = {"pc": pc, "ch": ch, "peer": _host_id(), "uid": "", "open": false, "t0": Time.get_ticks_msec(), "st": -1, "nc": 0, "nh": 0, "ns": 0, "no": no}
	_host_conn = cid
	_diag("Entrando… canal %s" % ["ok" if ch != null else "NULO"])
	var eo := pc.create_offer()
	pc.poll()
	if eo != OK:
		_diag("Entrando… oferta falhou (%d)" % eo)


## Anfitrião: alguém pediu para entrar.
func _on_offer(src: String, p) -> void:
	if not _is_host or not p is Dictionary:
		return
	if _conns.size() >= MAX_PLAYERS:
		return
	var cid := str(p.get("connectionId", "dc_" + _rnd(12)))
	var no := _novo_no(cid, src)
	var pc: WebRTCPeerConnection = no.pc
	_conns[cid] = {"pc": pc, "ch": null, "peer": src, "uid": "", "open": false, "t0": Time.get_ticks_msec(), "nc": 0, "nh": 0, "ns": 0, "no": no}
	var sdp: Dictionary = p.get("sdp", {})
	pc.set_remote_description("offer", str(sdp.get("sdp", "")))
	pc.poll()


func _on_canal(ch: WebRTCDataChannel, cid: String) -> void:
	if _conns.has(cid):
		_conns[cid].ch = ch


func _drop(cid: String) -> void:
	if not _conns.has(cid):
		return
	var c: Dictionary = _conns[cid]
	if c.uid != "":
		_players.erase(c.uid)
	var no: Node = c.get("no")
	if no and is_instance_valid(no):
		no.fechar()
		no.queue_free()
	else:
		if c.ch:
			c.ch.close()
		if c.pc:
			c.pc.close()
	_conns.erase(cid)


func _poll_conn(cid: String) -> void:
	var c: Dictionary = _conns[cid]
	var pc: WebRTCPeerConnection = c.pc
	pc.poll()
	var ch: WebRTCDataChannel = c.ch
	var st: int = pc.get_connection_state()
	if int(c.get("st", -1)) != st:
		c["st"] = st
		var gs: int = pc.get_gathering_state()
		_log("%s estado %d gelo %d" % [cid, st, gs])
		if cid == _host_conn and not _is_host:
			_diag(_fase_txt())
	if st == WebRTCPeerConnection.STATE_FAILED or st == WebRTCPeerConnection.STATE_CLOSED:
		var porque := _falha_rota(st, c)
		_drop(cid)
		if cid == _host_conn:
			_retry(porque, 1.2)
		return
	if ch == null:
		if Time.get_ticks_msec() - int(c.t0) > 15000:
			var porque2 := _falha_rota(st, c)
			_drop(cid)
			if cid == _host_conn:
				_retry(porque2)
		return
	if not c.open:
		if ch.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			c.open = true
			if cid == _host_conn:
				_ready = true
				_last_rx = Time.get_ticks_msec()
				_diag("Online — conectado ao mundo.")
		elif Time.get_ticks_msec() - int(c.t0) > 15000:
			var porque3 := _falha_rota(st, c)
			_drop(cid)
			if cid == _host_conn:
				_retry(porque3)
			return
	while ch.get_available_packet_count() > 0:
		var raw := ch.get_packet()
		var d = JSON.parse_string(raw.get_string_from_utf8())
		if d is Dictionary:
			_on_data(cid, d)


func _send_conn(cid: String, d: Dictionary) -> void:
	if not _conns.has(cid):
		return
	var ch: WebRTCDataChannel = _conns[cid].ch
	if ch and ch.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		# PeerJS (serialization "json") manda e lê JSON em bytes UTF-8
		ch.write_mode = WebRTCDataChannel.WRITE_MODE_BINARY
		ch.put_packet(JSON.stringify(d).to_utf8_buffer())


func _on_data(cid: String, d: Dictionary) -> void:
	var c: Dictionary = _conns[cid]
	var t := str(d.get("t", ""))
	if _is_host:
		if t == "st" and d.get("s") is Dictionary:
			c.uid = str(d.get("uid", "")).substr(0, 16)
			var s = _clean(d.s)
			if s != null:
				s["seen"] = Time.get_ticks_msec()
				_players[c.uid] = s
		elif t == "say" and c.uid != "":
			_relay_say(c.uid, str(d.get("text", "")))
		elif t == "ev" and c.uid != "" and d.get("e") is Dictionary and _inbox.size() < 200:
			_inbox.append({"from": c.uid, "e": d.e})
	else:
		_last_rx = Time.get_ticks_msec()
		if t == "w" and d.get("p") is Dictionary:
			_players = d.p
			if d.get("m") != null:
				_world_in = d.m
		elif t == "say":
			_push_chat(str(d.get("n", "?")), str(d.get("text", "")))
		elif t == "ev2" and d.get("e") is Dictionary and _events.size() < 200:
			_events.append(d.e)


func _host_tick() -> void:
	var agora := Time.get_ticks_msec()
	for k in _players.keys():
		if k != uid and agora - int(_players[k].get("seen", 0)) > 6000:
			_players.erase(k)
	if _me != null:
		var eu: Dictionary = (_me as Dictionary).duplicate()
		eu["seen"] = agora
		_players[uid] = eu
	var msg := {"t": "w", "p": _players, "m": _world}
	for cid in _conns:
		var c: Dictionary = _conns[cid]
		if c.uid != "" and c.open:
			_send_conn(cid, msg)


func _push_chat(n: String, text: String) -> void:
	_chat.append({"n": n.substr(0, 16), "text": text.substr(0, 120)})
	if _chat.size() > 30:
		_chat.pop_front()


func _relay_say(from_uid: String, text: String) -> void:
	var p = _me if from_uid == uid else _players.get(from_uid)
	var n: String = str(p.get("n", "?")) if p is Dictionary else "?"
	_push_chat(n, text)
	for cid in _conns:
		if _conns[cid].open:
			_send_conn(cid, {"t": "say", "n": n, "text": text.substr(0, 120)})


## Só campos conhecidos (igual ao clean() do navegador).
func _clean(s):
	if not s is Dictionary or not (s.get("x") is float or s.get("x") is int):
		return null
	var eq := {}
	if s.get("eq") is Dictionary:
		for k in s.eq:
			eq[str(k).substr(0, 3)] = str(s.eq[k]).substr(0, 40)
	var sm: Array = []
	if s.get("sm") is Array:
		for a in (s.sm as Array).slice(0, 2):
			if a is Array and a.size() == 6:
				sm.append(a)
	var sh: Array = []
	if s.get("sh") is Array:
		for x in (s.sh as Array).slice(0, 2):
			sh.append(str(x).substr(0, 9))
	return {
		"x": clampf(float(s.x), -20000, 20000), "y": clampf(float(s.get("y", 0)), -20000, 20000),
		"vx": clampf(float(s.get("vx", 0)), -600, 600), "vy": clampf(float(s.get("vy", 0)), -600, 600),
		"f": str(s.get("f", "S")).substr(0, 2), "a": str(s.get("a", "idle")).substr(0, 8), "n": str(s.get("n", "Viajante")).substr(0, 16),
		"eq": eq, "d": 1 if s.get("d") else 0, "sf": 1 if s.get("sf") else 0, "l": clampi(int(s.get("l", 1)), 1, 9999),
		"c": str(s.get("c", "")).substr(0, 8), "hp": clampi(int(s.get("hp", 100)), 0, 100), "sm": sm,
		"sh": sh, "shf": clampf(float(s.get("shf", 0)), 0, 1),
	}
