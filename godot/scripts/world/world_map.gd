class_name WorldMap
extends RefCounted
## Mapa em texto (godot/data/maps/*.txt). Cada caractere é um tile.
## ~ água  , areia  . grama  : terra  # calçamento  f floresta  r rocha
## = ponte/píer  H construção  T templo  @ início do jogador
## g cemitério  j selva  k chão de caverna  R parede de caverna  b/o/y acampamentos

const BLOCKED := "~HR"

var rows: PackedStringArray = PackedStringArray()
var w := 0
var h := 0
var spawn := Vector2(1, 1)


static func load_file(path: String) -> WorldMap:
	var m := WorldMap.new()
	var txt := FileAccess.get_file_as_string(path)
	for line in txt.split("\n"):
		if line.strip_edges() != "":
			m.rows.append(line)
	m.h = m.rows.size()
	for r in m.rows:
		m.w = maxi(m.w, r.length())
	for y in m.h:
		var x := m.rows[y].find("@")
		if x >= 0:
			m.spawn = Vector2(x + 0.5, y + 0.5)
	return m


func at(x: int, y: int) -> String:
	if y < 0 or y >= h or x < 0 or x >= rows[y].length():
		return "~"
	return rows[y][x]


## Número pseudoaleatório fixo por tile (para espalhar árvores sempre igual).
func tile_rand(x: int, y: int, k: int = 0) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (k * 83492791)
	return float(posmod(h, 10007)) / 10007.0


func walkable_grid(g: Vector2) -> bool:
	return not BLOCKED.contains(at(int(floor(g.x)), int(floor(g.y))))


func walkable(screen_pos: Vector2) -> bool:
	return walkable_grid(Iso.to_grid(screen_pos))


## Texturas de peso para o shader do chão (uma cor por tipo de terreno).
func weight_textures() -> Array:
	var i0 := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var i1 := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := at(x, y)
			var a := Color(0, 0, 0, 0)
			var b := Color(0, 0, 0, 0)
			match c:
				".", "@": a.r = 1
				":", "b", "o", "y": a.g = 1
				",": a.b = 1
				"#", "=", "H", "T": a.a = 1
				"f", "j": b.r = 1
				"r", "k", "R": b.g = 1
				"g": b.a = 1
				_: b.b = 1
			i0.set_pixel(x, y, a)
			i1.set_pixel(x, y, b)
	return [ImageTexture.create_from_image(i0), ImageTexture.create_from_image(i1)]


## Retângulos de construções (componentes conectados de um caractere).
func blocks(ch: String) -> Array:
	var seen := {}
	var out: Array = []
	for y in h:
		for x in w:
			if at(x, y) != ch or seen.has(Vector2i(x, y)):
				continue
			var stack := [Vector2i(x, y)]
			var mn := Vector2i(x, y)
			var mx := Vector2i(x, y)
			seen[Vector2i(x, y)] = true
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				mn = Vector2i(mini(mn.x, p.x), mini(mn.y, p.y))
				mx = Vector2i(maxi(mx.x, p.x), maxi(mx.y, p.y))
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = p + d
					if at(q.x, q.y) == ch and not seen.has(q):
						seen[q] = true
						stack.append(q)
			out.append(Rect2(Vector2(mn), Vector2(mx - mn + Vector2i.ONE)))
	return out
