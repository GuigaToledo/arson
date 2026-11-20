extends Node2D
## Ilha inicial (estrutura inspirada em Rookgaard): vila com templo e casas no
## centro, estradas para os quatro lados, morros de rocha ao norte, florestas,
## rio com ponte a leste e píer ao sul. O mapa vem de data/maps/ilha.txt.
## Construções ainda são provisórias; serão trocadas pelas peças de arte.

const MAP_PATH := "res://data/maps/ilha.txt"
const CHUNK := 8
const MARGIN := 10
const TEX := "res://assets/textures/"

var map: WorldMap
var entities: Node2D
var player: Player


func g(x: float, y: float) -> Vector2:
	return Iso.to_screen(Vector2(x, y))


func _ready() -> void:
	map = WorldMap.load_file(MAP_PATH)
	Actor.walkable = map.walkable
	var cm := CanvasModulate.new()
	cm.color = Color(0.62, 0.55, 0.5)
	add_child(cm)
	var sun := DirectionalLight2D.new()
	sun.color = Color(1.0, 0.78, 0.55)
	sun.energy = 0.35
	sun.rotation_degrees = 35.0
	sun.shadow_enabled = true
	sun.shadow_color = Color(0, 0, 0, 0.45)
	sun.max_distance = 600.0
	add_child(sun)
	_build_ground()
	entities = Node2D.new()
	entities.name = "Entidades"
	entities.y_sort_enabled = true
	add_child(entities)
	_build_buildings()
	_build_lights()
	_spawn_characters()
	var net := NetSync.new()
	net.name = "Rede"
	add_child(net)
	net.setup(player, entities)
	var hud := Hud.new()
	add_child(hud)
	hud.bind(player, net)
	var ui := EquipmentPanel.new()
	add_child(ui)
	ui.bind(player)


func _build_ground() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	var w := map.weight_textures()
	mat.set_shader_parameter("map_size", Vector2(map.w, map.h))
	mat.set_shader_parameter("w0", w[0])
	mat.set_shader_parameter("w1", w[1])
	for pair in [["tex_grass", "grass_c"], ["tex_path", "path_c"], ["tex_sand", "sand_c"], ["tex_stone", "stone_c"],
			["tex_forest", "forest_c"], ["tex_rock", "ash_c"], ["nrm_grass", "grass_n"], ["nrm_path", "path_n"], ["nrm_stone", "stone_n"]]:
		mat.set_shader_parameter(pair[0], load(TEX + pair[1] + ".jpg"))
	var ground := Node2D.new()
	ground.name = "Chao"
	ground.z_index = -20
	add_child(ground)
	# em pedaços, para cada luz só afetar o pedaço próximo
	for cy in range(-MARGIN, map.h + MARGIN, CHUNK):
		for cx in range(-MARGIN, map.w + MARGIN, CHUNK):
			var p := Polygon2D.new()
			p.polygon = PackedVector2Array([g(cx, cy), g(cx + CHUNK, cy), g(cx + CHUNK, cy + CHUNK), g(cx, cy + CHUNK)])
			p.material = mat
			ground.add_child(p)


func _build_buildings() -> void:
	for r: Rect2 in map.blocks("H"):
		var p := Prop.new().setup("house", r.position + Vector2(0.1, 0.1), r.size - Vector2(0.2, 0.2), 150.0, Color(0.42, 0.36, 0.3))
		entities.add_child(p)
	for r: Rect2 in map.blocks("T"):
		var p := Prop.new().setup("house", r.position + Vector2(0.1, 0.1), r.size - Vector2(0.2, 0.2), 230.0, Color(0.55, 0.52, 0.48))
		p.name = "Templo"
		entities.add_child(p)


func _build_lights() -> void:
	for c in [Vector2(22.5, 26.6), Vector2(33.5, 26.6), Vector2(22.5, 32.5), Vector2(33.5, 32.5)]:
		var post := LampPost.new()
		post.position = Iso.to_screen(c)
		entities.add_child(post)
		var l := LightKit.make(Color(1.0, 0.65, 0.3), 1.0, 1.8, false, 0.12)
		l.position = Vector2(10, -30)
		post.add_child(l)
	var camp := Node2D.new()
	camp.position = g(31.0, 36.0)
	entities.add_child(camp)
	Fx.fire(camp, Vector2(0, -4), 0.6)
	var fl := LightKit.make(Color(1.0, 0.55, 0.2), 1.3, 2.4, true, 0.2)
	fl.position = Vector2(0, -6)
	camp.add_child(fl)


func _spawn_characters() -> void:
	player = Player.new()
	player.name = "Jogador"
	player.position = Iso.to_screen(map.spawn)
	entities.add_child(player)

	var guard := Npc.new().configure("Guarda do Templo",
		{"skin": Color(0.55, 0.42, 0.33), "under": Color(0.2, 0.18, 0.16), "hair": Color(0.1, 0.08, 0.06), "eyes": Color(0.2, 0.15, 0.1)},
		["elmo_ferro", "peitoral_couro", "ombreiras_ferro", "calca_tecido", "botas_couro"], "S")
	guard.position = g(25.6, 26.5)
	entities.add_child(guard)

	var pts := []
	for p in [Vector2(27.5, 31), Vector2(27.5, 42), Vector2(27.5, 31), Vector2(12, 28), Vector2(27.5, 28),
			Vector2(27.5, 14), Vector2(27.5, 28), Vector2(45, 28)]:
		pts.append(g(p.x, p.y))
	var walker := Npc.new().configure("Viajante",
		{"skin": Color(0.5, 0.38, 0.3), "under": Color(0.2, 0.17, 0.14), "hair": Color(0.15, 0.1, 0.07), "eyes": Color(0.2, 0.15, 0.1)},
		["gibao_verde", "calca_tecido", "botas_couro", "capa_viagem"], "S", pts)
	walker.position = pts[0]
	entities.add_child(walker)


## Poste com lampião (provisório).
class LampPost:
	extends Node2D

	func _draw() -> void:
		PlaceholderPainter.ellipse(self, Vector2.ZERO, 6, 3, Color(0, 0, 0, 0.4))
		draw_line(Vector2.ZERO, Vector2(0, -70), Color(0.16, 0.11, 0.07), 4.0)
		draw_line(Vector2(0, -66), Vector2(10, -66), Color(0.16, 0.11, 0.07), 3.0)
		draw_rect(Rect2(5, -64, 10, 13), Color(0.12, 0.1, 0.08))
		draw_rect(Rect2(7, -62, 6, 9), Color(1, 0.75, 0.4))
