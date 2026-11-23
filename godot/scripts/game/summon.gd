class_name Summon
extends Actor
## Invocação (magia 5 de cada elemento, ou a fundida): um tanque que luta como monge shaolin do norte
## (mãos, pés e cabeçada) com dano físico imbuído no elemento. Segue o dono, sobe de nível com ele,
## fica vivo até morrer e pode ser curado. Agressivo (ataca sozinho) ou passivo (só revida).

const LOOK := {
	"fogo": {"nome": "Elemental de Fogo", "skin": Color(0.9, 0.35, 0.08), "under": Color(1, 0.6, 0.15), "hair": Color(1, 0.85, 0.3), "float": true, "scale": 1.05},
	"lava": {"nome": "Golem de Lava", "skin": Color(0.18, 0.08, 0.06), "under": Color(0.95, 0.3, 0.05), "hair": Color(0.25, 0.1, 0.06), "float": false, "scale": 1.45},
	"agua": {"nome": "Elemental de Água", "skin": Color(0.2, 0.45, 0.85), "under": Color(0.35, 0.7, 1), "hair": Color(0.6, 0.9, 1), "float": false, "scale": 1.05},
	"gelo": {"nome": "Golem de Gelo", "skin": Color(0.6, 0.8, 0.95), "under": Color(0.85, 0.95, 1), "hair": Color(0.5, 0.75, 0.95), "float": false, "scale": 1.45},
	"vento": {"nome": "Elemental de Vento", "skin": Color(0.65, 0.9, 0.82), "under": Color(0.85, 1, 0.95), "hair": Color(0.9, 1, 1), "float": true, "scale": 1.0},
	"raio": {"nome": "Elemental de Raio", "skin": Color(0.45, 0.4, 0.95), "under": Color(0.8, 0.8, 1), "hair": Color(1, 1, 0.7), "float": false, "scale": 0.95, "fast": true},
	"terra": {"nome": "Golem de Terra", "skin": Color(0.4, 0.3, 0.2), "under": Color(0.3, 0.24, 0.16), "hair": Color(0.5, 0.42, 0.3), "float": false, "scale": 1.45},
	"natureza": {"nome": "Guardião de Raízes", "skin": Color(0.32, 0.22, 0.12), "under": Color(0.3, 0.55, 0.2), "hair": Color(0.4, 0.75, 0.25), "float": false, "scale": 1.15},
}

var owner_p: Node2D
var els: Array = []
var fused := false
var hp := 100.0
var max_hp := 100.0
var dead := false
var foe: Node2D = null
## Distância máxima (em quadrados) do dono até o alvo da invocação.
const LEASH := 15.0
var _scan_t := 0.0
var last_attacker: Node2D = null
var color := Color.WHITE
var _atk_cd := 0.0
var _combo := 0
var _buff_cd := 6.0
var _t := 0.0
var _hurt := 0.0
var _aura: ClassAura
## Espelho de invocação de outro jogador (só visual, sem IA).
var puppet := false
var puppet_target := Vector2.ZERO


static func make(owner: Node2D, elements: Array, is_fused: bool, fused_name := "") -> Summon:
	var s := Summon.new()
	s.owner_p = owner
	s.els = elements
	s.fused = is_fused
	var lk: Dictionary = LOOK[elements[0]]
	s.display_name = fused_name if is_fused else str(lk.nome)
	s.color = Spellbook.ELEMENTS[elements[0]].cor
	if is_fused:
		s.color = s.color.lerp(Spellbook.ELEMENTS[elements[1]].cor, 0.5)
	# corpo feito do próprio elemento (SummonPainter): golem de blocos, chamas, raios, raízes...
	s.body_colors = {"summon": elements[0], "summon2": elements[1] if is_fused and elements.size() > 1 else "", "eyes": s.color.lightened(0.5), "core_col": s.color}
	# rápida: acompanha o dono correndo e alcança os monstros
	s.walk_speed = 195.0 if lk.get("fast", false) else 165.0
	s.run_speed = s.walk_speed * 2.0
	return s


func _ready() -> void:
	super()
	if OS.has_feature("web"):
		visual.draw_hz = 15.0
	if not puppet:
		add_to_group("summons")
	collision_layer = 0
	collision_mask = 0
	var lk: Dictionary = LOOK[els[0]]
	visual.scale = Vector2.ONE * float(lk.scale) * (1.2 if fused else 1.0)
	_aura = ClassAura.new()
	add_child(_aura)
	var cl := "fogo"
	for c in Spellbook.CLASS_ELEMENTS:
		if Spellbook.CLASS_ELEMENTS[c].has(els[0]):
			cl = c
	_aura.setup(cl)
	if not puppet:
		_recalc()
		hp = max_hp
	SpellFx.level_up(get_parent(), global_position, color)


## Vida e força acompanham o nível do dono e do elemento (fundida = mais forte).
func _recalc() -> void:
	var lv := int(owner_p.level) if is_instance_valid(owner_p) else 1
	var el_lv := 1.0
	if is_instance_valid(owner_p) and owner_p.has_method("elem_level"):
		el_lv = 0.0
		for e in els:
			el_lv += owner_p.elem_level(e)
		el_lv /= els.size()
	var f := 1.8 if fused else 1.0
	var old := max_hp
	max_hp = (140.0 + 28.0 * lv) * (1.0 + 0.05 * el_lv) * f
	if old > 0.0 and old != max_hp:
		hp = hp * max_hp / old


func power() -> float:
	var el_lv := 1.0
	if is_instance_valid(owner_p) and owner_p.has_method("elem_level"):
		el_lv = owner_p.elem_level(els[0])
	# força pelo nível de magia do elemento (a vida acompanha o nível do dono)
	if fused and is_instance_valid(owner_p) and owner_p.has_method("elem_level"):
		el_lv = float(owner_p.elem_level(els[0]) + owner_p.elem_level(els[els.size() - 1]))
	return (9.0 + 2.4 * el_lv) * (1.0 + 0.02 * el_lv) * (1.6 if fused else 1.0)


func heal(v: float) -> void:
	if dead:
		return
	hp = minf(max_hp, hp + v)
	CombatText.add(global_position + Vector2(0, -90), "+%d" % int(v), Color(0.4, 1, 0.5))


## A experiência das mortes vai para o dono.
func gain_xp(n: int, g: int, src: String) -> void:
	if is_instance_valid(owner_p) and owner_p.has_method("gain_xp"):
		owner_p.gain_xp(n, g, src)


func take_damage(n: int, src) -> void:
	if dead:
		return
	# acrobacia: esquiva de alguns golpes físicos e à distância
	if randf() < 0.2:
		CombatText.add(global_position + Vector2(0, -90), "esquivou!", color.lightened(0.4))
		var tw := create_tween()
		tw.tween_property(visual, "position:y", -26.0, 0.15)
		tw.tween_property(visual, "position:y", 0.0, 0.2)
		return
	n = maxi(1, int(round(n * (1.0 if str(src) == "Boneco de Treino" else 0.85))))
	hp -= n
	_hurt = 0.25
	SpellArt.blood(get_parent(), global_position, float(n) / max_hp, str(els[0]))
	CombatText.add(global_position + Vector2(0, -80), str(n), Color(1, 0.5, 0.3))
	if src is Node2D and is_instance_valid(src):
		last_attacker = src
	if hp <= 0.0:
		_die()


func _die() -> void:
	dead = true
	hp = 0.0
	CombatText.add(global_position + Vector2(0, -100), "%s caiu" % display_name, color)
	SpellFx.burst(get_parent(), global_position + Vector2(0, -40), 40, 120.0, 0.8, 0.1, color.lightened(0.4), color)
	if is_instance_valid(owner_p) and owner_p.has_method("summon_died"):
		owner_p.summon_died(self)
	var tw := create_tween()
	tw.tween_property(visual, "modulate", Color(1, 1, 1, 0), 0.8)
	tw.tween_callback(queue_free)


func _monsters() -> Array:
	# só monstros de verdade: o boneco de treino fica para o jogador
	return get_tree().get_nodes_in_group("monsters").filter(func(m): return not m.dead and not m.info.get("dummy", false))


func _ok(m) -> bool:
	return m != null and is_instance_valid(m) and not m.dead and not Rules.is_safe(m.global_position) and not (m is Monster and m.info.get("dummy", false))


func _physics_process(delta: float) -> void:
	if puppet:
		_t += delta
		if puppet_target != Vector2.ZERO:
			var to := puppet_target - global_position
			global_position = puppet_target if to.length() > 300.0 else global_position + to * minf(1.0, delta * 10.0)
		if LOOK[els[0]].float:
			visual.position.y = -10.0 + sin(_t * 2.5) * 4.0
		var spd := walk_speed * 2.0 if anim == "run" else (walk_speed if anim == "walk" else 0.0)
		visual.tick(delta, facing, anim, spd)
		return
	if dead or not is_instance_valid(owner_p):
		return
	_t += delta
	_atk_cd -= delta
	_buff_cd -= delta
	if fmod(_t, 1.0) < delta:
		_recalc()
	if _hurt > 0.0:
		_hurt -= delta
		visual.modulate = Color(1, 0.5, 0.45).lerp(Color.WHITE, 1.0 - _hurt / 0.25)
	if LOOK[els[0]].float:
		visual.position.y = -10.0 + sin(_t * 2.5) * 4.0
	var od := Rules.gdist(global_position, owner_p.global_position)
	if od > 20.0 or bool(owner_p.get("dead")):
		global_position = owner_p.global_position + Vector2(-40, 20)
		foe = null
	# alvo: sempre o mesmo que o dono mirar (troca na hora); sem alvo do dono, o inimigo mais perto
	# que estiver na tela (agressiva) ou quem a atacou (passiva)
	var of = owner_p.get("foe")
	if _ok(of) and of != foe and Rules.gdist(owner_p.global_position, of.global_position) < LEASH:
		foe = of
	if not _ok(foe):
		foe = null
		if Settings.auto.get("summon_agressivo", true):
			_scan_t -= delta
			if _scan_t <= 0.0:
				_scan_t = 0.25
				var bd := 1e9
				var vr := CharacterVisual.view_rect
				for m in _monsters():
					if Rules.is_safe(m.global_position):
						continue
					var na_tela := vr.size.x > 0.0 and vr.has_point(m.global_position)
					var d := Rules.gdist(owner_p.global_position, m.global_position)
					if (na_tela or d < 9.0) and d < bd:
						bd = d
						foe = m
		if foe == null and _ok(last_attacker):
			foe = last_attacker
	if foe != null and Rules.gdist(owner_p.global_position, foe.global_position) > LEASH:
		foe = null
	var d := Vector2.ZERO
	var running := false
	if foe != null:
		var dist := Rules.gdist(global_position, foe.global_position)
		if dist > 1.3:
			d = foe.global_position - global_position
			running = true
		else:
			facing = Iso.dir_from_vector(foe.global_position - global_position)
			if _atk_cd <= 0.0:
				_strike()
	elif od > 2.2:
		d = owner_p.global_position - global_position
		running = od > 5.0
	move(d, running, delta)


## Golpes em sequência, como um monge: soco, chute, cabeçada (empurra), chute giratório (área),
## agarrar e morder (prende). Sempre com o efeito do elemento; de tempos em tempos fortalece o dono.
func _strike() -> void:
	_atk_cd = 0.7 if LOOK[els[0]].get("fast", false) else 0.9
	_combo += 1
	var pw := power()
	var tgt := foe
	var kind: String = ["Soco", "Chute", "Cabeçada", "Chute giratório", "Agarrar e morder"][_combo % 5]
	# animação do golpe (mão, pé, cabeça) e o dano no instante do impacto
	play_action({"Soco": "punch", "Chute": "kick", "Cabeçada": "headbutt", "Chute giratório": "spin", "Agarrar e morder": "grab"}[kind], 0.5)
	await get_tree().create_timer(0.2).timeout
	if dead or not is_instance_valid(tgt) or tgt.dead:
		return
	match kind:
		"Chute giratório":
			SpellFx.ring(get_parent(), global_position, 1.6, color, 0.4)
			for m in _monsters():
				if Rules.gdist(global_position, m.global_position) <= 1.8:
					m.take_damage(Rules.roll(pw * 1.1, float(m.info.def)), self)
					for e in els:
						m.apply_effect(e, pw, owner_p, false)
		"Cabeçada":
			tgt.take_damage(Rules.roll(pw * 1.2, float(tgt.info.def)), self)
			tgt.apply_effect("vento", pw, self, false)  # empurrão
		"Agarrar e morder":
			tgt.take_damage(Rules.roll(pw * 1.3, float(tgt.info.def)), self)
			tgt.apply_effect("terra", pw, owner_p, true)  # preso nas garras: atordoado
		_:
			tgt.take_damage(Rules.roll(pw, float(tgt.info.def)), self)
			for e in els:
				tgt.apply_effect(e, pw, owner_p, false)
	if _combo % 5 >= 2:
		CombatText.add(global_position + Vector2(0, -105), kind, color.lightened(0.3))
	SpellFx.burst(get_parent(), tgt.global_position + Vector2(0, -36), 14, 80.0, 0.35, 0.06, color.lightened(0.5), color)
	# buff no dono: escudo pequeno do elemento
	if _buff_cd <= 0.0 and is_instance_valid(owner_p) and owner_p.get("shield_hp") != null:
		_buff_cd = 15.0
		owner_p.shield_hp = maxf(float(owner_p.shield_hp), pw * 2.0)
		owner_p.shield_t = maxf(float(owner_p.shield_t), 8.0)
		owner_p.shield_col = color
		CombatText.add(owner_p.global_position + Vector2(0, -110), "Proteção de %s" % display_name, color)
