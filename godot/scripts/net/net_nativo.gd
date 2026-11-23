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


static func disponivel() -> bool:
	if not ClassDB.class_exists("WebRTCPeerConnection"):
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


func _diag(m: String) -> void:
	_status = m
	print("[arson-net] ", m)


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


func _ws_send(d: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(d))


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
				_conns[cid].pc.set_remote_description("answer", str(sdp.get("sdp", "")))
		"CANDIDATE":
			var p2: Dictionary = m.get("payload", {})
			var cid2 := str(p2.get("connectionId", ""))
			if _conns.has(cid2):
				var c: Dictionary = p2.get("candidate", {})
				_conns[cid2].pc.add_ice_candidate(str(c.get("sdpMid", "0")), int(c.get("sdpMLineIndex", 0)), str(c.get("candidate", "")))


# ------------------------------------------------------------ WebRTC
func _new_pc(cid: String, peer: String) -> WebRTCPeerConnection:
	var pc := WebRTCPeerConnection.new()
	# se a lista com TURN não for aceita (alguns aparelhos), tenta só STUN e depois o padrão
	var err := pc.initialize(ICE)
	if err != OK:
		err = pc.initialize(ICE_STUN)
		if err != OK:
			err = pc.initialize({})
	print("[arson-net] conexão %s iniciada (erro %d)" % [cid, err])
	pc.session_description_created.connect(func(tipo: String, sdp: String):
		pc.set_local_description(tipo, sdp)
		var payload := {"sdp": {"type": tipo, "sdp": sdp}, "type": "data", "connectionId": cid, "browser": "godot"}
		if tipo == "offer":
			payload.merge({"label": cid, "serialization": "json", "reliable": true, "metadata": null})
		_ws_send({"type": tipo.to_upper(), "payload": payload, "dst": peer}))
	pc.ice_candidate_created.connect(func(mid: String, idx: int, cand: String):
		_ws_send({"type": "CANDIDATE", "payload": {"candidate": {"candidate": cand, "sdpMid": mid, "sdpMLineIndex": idx}, "type": "data", "connectionId": cid}, "dst": peer}))
	return pc


## Cliente: conecta no anfitrião (eu ofereço, como o PeerJS do navegador faz).
func _connect_to_host() -> void:
	var cid := "dc_" + _rnd(12)
	var pc := _new_pc(cid, _host_id())
	var ch := pc.create_data_channel(cid, {"ordered": true})
	if ch == null:
		ch = pc.create_data_channel(cid)
	_conns[cid] = {"pc": pc, "ch": ch, "peer": _host_id(), "uid": "", "open": false, "t0": Time.get_ticks_msec(), "st": -1}
	_host_conn = cid
	var eo := pc.create_offer()
	print("[arson-net] canal %s, oferta (erro %d)" % ["ok" if ch != null else "NULO", eo])


## Anfitrião: alguém pediu para entrar.
func _on_offer(src: String, p) -> void:
	if not _is_host or not p is Dictionary:
		return
	if _conns.size() >= MAX_PLAYERS:
		return
	var cid := str(p.get("connectionId", "dc_" + _rnd(12)))
	var pc := _new_pc(cid, src)
	_conns[cid] = {"pc": pc, "ch": null, "peer": src, "uid": "", "open": false, "t0": Time.get_ticks_msec()}
	pc.data_channel_received.connect(func(ch: WebRTCDataChannel):
		if _conns.has(cid):
			_conns[cid].ch = ch)
	var sdp: Dictionary = p.get("sdp", {})
	pc.set_remote_description("offer", str(sdp.get("sdp", "")))


func _drop(cid: String) -> void:
	if not _conns.has(cid):
		return
	var c: Dictionary = _conns[cid]
	if c.uid != "":
		_players.erase(c.uid)
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
	var st := pc.get_connection_state()
	if int(c.get("st", -1)) != st:
		c["st"] = st
		print("[arson-net] %s estado %d gelo %d" % [cid, st, pc.get_gathering_state()])
	if st == WebRTCPeerConnection.STATE_FAILED or st == WebRTCPeerConnection.STATE_CLOSED:
		_drop(cid)
		if cid == _host_conn:
			_retry("Conexão com o anfitrião perdida.", 1.2)
		return
	if ch == null:
		if Time.get_ticks_msec() - int(c.t0) > 15000:
			_drop(cid)
			if cid == _host_conn:
				_retry("Não deu para abrir o canal com o anfitrião.")
		return
	if not c.open:
		if ch.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			c.open = true
			if cid == _host_conn:
				_ready = true
				_last_rx = Time.get_ticks_msec()
				_diag("Online — conectado ao mundo.")
		elif Time.get_ticks_msec() - int(c.t0) > 15000:
			_drop(cid)
			if cid == _host_conn:
				_retry("A conexão com o anfitrião demorou demais.")
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
