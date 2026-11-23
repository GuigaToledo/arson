class_name RemotePlayer
extends Actor
## Outro jogador vindo da rede: mostra posição, direção, animação e equipamentos.
## No anfitrião, também é alvo dos monstros: dano e experiência vão pela rede.

var uid := ""
var dead := false
var level := 1
## Vida em % (para as curas de Luz escolherem quem está mais ferido).
var hp_pct := 100
var classe := ""
var _class_aura: ClassAura
## Invocações deste jogador (só visual).
var _sm_puppets: Array = []


func take_damage(n: int, src: String) -> void:
	if NetSync.inst:
		NetSync.inst.send_to(uid, {"t": "hit", "n": n, "src": src})


func gain_xp(n: int, g: int, src: String) -> void:
	if NetSync.inst:
		NetSync.inst.send_to(uid, {"t": "xp", "n": n, "g": g, "src": src})

var _target := Vector2.ZERO
var _eq_key := ""


func _init() -> void:
	body_colors = {
		"skin": Color(0.09, 0.085, 0.09),
		"under": Color(0.11, 0.1, 0.1),
		"hair": Color(0.07, 0.065, 0.07),
		"eyes": Color(1.0, 0.62, 0.15),
		"glow_eyes": true,
		"core": true,
	}
	body_path = "res://assets/personagens/mago/corpo.tres"


func _ready() -> void:
	super()
	collision_layer = 0
	collision_mask = 0
	_target = position
	add_to_group("remote_players")


func apply_state(s: Dictionary) -> void:
	_target = Vector2(float(s.get("x", position.x)), float(s.get("y", position.y)))
	dead = int(s.get("d", 0)) == 1
	level = int(s.get("l", 1))
	hp_pct = int(s.get("hp", 100))
	var c := str(s.get("c", ""))
	if MageClass.valid(c) and c != classe:
		classe = c
		var ci := MageClass.info(c)
		visual.set_glow(ci.nucleo, ci.olhos)
		if _class_aura == null:
			_class_aura = ClassAura.new()
			add_child(_class_aura)
		_class_aura.setup(c)
		# corpo renderizado da classe (se existir)
		var corpo := Actor.class_body(c)
		if FileAccess.file_exists(corpo):
			visual.set_body(Actor.sprite_body(corpo))
	visible = not dead
	facing = str(s.get("f", "S"))
	if not Iso.DIRS.has(facing):
		facing = "S"
	anim = str(s.get("a", "idle"))
	display_name = str(s.get("n", ""))
	_sync_summons(s.get("sm", []))
	var eq: Dictionary = s.get("eq", {})
	var key := JSON.stringify(eq)
	if key != _eq_key:
		_eq_key = key
		var ids := {}
		for k in eq:
			ids[int(k)] = eq[k]
		equipment.load_ids(ids)


func _sync_summons(list) -> void:
	if not list is Array:
		list = []
	while _sm_puppets.size() > list.size():
		var p0 = _sm_puppets.pop_back()
		if is_instance_valid(p0):
			p0.queue_free()
	for i in list.size():
		var row: Array = list[i]
		var el := str(row[2])
		if not Summon.LOOK.has(el):
			continue
		var fused := int(row[3]) == 1
		var p: Summon = _sm_puppets[i] if i < _sm_puppets.size() and is_instance_valid(_sm_puppets[i]) else null
		if p != null and (p.els[0] != el or p.fused != fused):
			p.queue_free()
			p = null
		if p == null:
			var els2 := [el]
			if fused:
				for c in Spellbook.CLASS_ELEMENTS:
					if Spellbook.CLASS_ELEMENTS[c][0] == el:
						els2 = Spellbook.CLASS_ELEMENTS[c].duplicate()
			p = Summon.make(null, els2, fused, "Invocação de %s" % display_name)
			p.puppet = true
			p.position = Vector2(float(row[0]), float(row[1]))
			get_parent().add_child(p)
			if i < _sm_puppets.size():
				_sm_puppets[i] = p
			else:
				_sm_puppets.append(p)
		p.puppet_target = Vector2(float(row[0]), float(row[1]))
		p.facing = str(row[4]) if Iso.DIRS.has(str(row[4])) else "S"
		p.anim = str(row[5])


func _exit_tree() -> void:
	for p in _sm_puppets:
		if is_instance_valid(p):
			p.queue_free()


func _physics_process(delta: float) -> void:
	var to := _target - position
	if to.length() > 400.0:
		position = _target
	else:
		position += to * minf(1.0, delta * 10.0)
	var spd := 210.0 if anim == "run" else (120.0 if anim == "walk" else 0.0)
	# magia lançada andando: a posição ainda está mudando
	var andando := to.length() > 2.0
	if anim == "cast" and andando:
		spd = 120.0
	visual.tick(delta, facing, moving_anim(anim, andando, to.length() > 12.0), spd)
