class_name CombatText
extends RefCounted
## Números de dano, cura e experiência que sobem sobre os personagens.
## Ficam numa lista; o HUD desenha (assim não escurecem com a luz da cena).

static var items: Array = []


static func add(world_pos: Vector2, text: String, color: Color, big := false) -> void:
	items.append({"p": world_pos + Vector2(randf_range(-6, 6), 0), "text": text, "c": color, "t": 0.0, "big": big})
	if items.size() > 80:
		items.remove_at(0)


static func step(delta: float) -> void:
	for i in range(items.size() - 1, -1, -1):
		items[i].t += delta
		if items[i].t > (1.6 if items[i].big else 1.0):
			items.remove_at(i)
