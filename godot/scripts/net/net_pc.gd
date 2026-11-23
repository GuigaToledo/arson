extends Node
## Uma ligação WebRTC. No Android a extensão não entrega o sinal para lambda nem para
## Callable com bind — só para um método direto deste nó. O dono é o net_nativo.

var cid := ""
var peer_id := ""
var dono: Node = null
var pc: WebRTCPeerConnection = null
var ch: WebRTCDataChannel = null


func montar(ice: Dictionary) -> int:
	pc = WebRTCPeerConnection.new()
	var err := pc.initialize(ice)
	if err != OK:
		err = pc.initialize({})
	pc.session_description_created.connect(_ao_sdp)
	pc.ice_candidate_created.connect(_ao_gelo)
	pc.data_channel_received.connect(_ao_canal)
	return err


func fechar() -> void:
	if ch:
		ch.close()
		ch = null
	if pc:
		pc.close()
		pc = null


func _ao_sdp(tipo: String, sdp: String) -> void:
	if dono and is_instance_valid(dono):
		dono._on_sdp(tipo, sdp, cid, peer_id)


func _ao_gelo(mid: String, idx: int, cand: String) -> void:
	if dono and is_instance_valid(dono):
		dono._on_ice(mid, idx, cand, cid, peer_id)


func _ao_canal(canal: WebRTCDataChannel) -> void:
	ch = canal
	if dono and is_instance_valid(dono):
		dono._on_canal(canal, cid)
