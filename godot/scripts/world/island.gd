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


func _exit_tree() -> void:
	# solta referências estáticas para a ilha (evita travar ao fechar o jogo)
	Rules.safe_check = Callable()
	Actor.walkable = Callable()
	CombatText.items.clear()


func _ready() -> void:
	map = WorldMap.load_file(MAP_PATH)
	Actor.walkable = map.walkable
	# zona segura: calçamento e construções da vila
	Rules.safe_check = func(pos: Vector2) -> bool:
		var gp := Iso.to_grid(pos)
		return "#TH".contains(map.at(int(floor(gp.x)), int(floor(gp.y))))
	var cm := CanvasModulate.new()
	cm.color = Color(0.34, 0.31, 0.32)
	add_child(cm)
	var sun := DirectionalLight2D.new()
	sun.color = Color(1.0, 0.78, 0.55)
	sun.energy = 0.22
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
	_build_details()
	_build_lights()
	# câmera da tela inicial (o mundo aparece escuro ao fundo)
	var intro := Camera2D.new()
	intro.name = "CameraInicial"
	intro.position = Iso.to_screen(map.spawn) + Vector2(0, -40)
	intro.zoom = Vector2(1.3, 1.3)
	add_child(intro)
	intro.make_current()
	Chars.migrate()
	var testing: bool = Array(OS.get_cmdline_user_args()).any(func(a): return str(a).begins_with("--teste")) or DisplayServer.get_name() == "headless"
	if "--teste-titulo" in OS.get_cmdline_user_args():
		testing = false
	if testing:
		if not Chars.info(1).existe:
			Chars.create(1, "fogo", "Teste")
		Chars.use(1)
		start_game(1)
		return
	if OS.has_feature("web") and JavaScriptBridge.eval("typeof window.ArsonNet !== 'undefined'", true):
		# voltou de uma atualização automática: entra direto no mesmo personagem
		var r := int(JavaScriptBridge.get_interface("ArsonNet").takeResume())
		if r >= 1 and r <= Chars.MAX and Chars.info(r).existe:
			Chars.use(r)
			start_game(r)
			return
	var ts := TitleScreen.new()
	add_child(ts)
	ts.setup()
	ts.chosen.connect(start_game)
	if "--teste-titulo" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.5).timeout
		Chars.delete(3)
		ts._show_create(3)
		ts._select("agua")
		ts._name.text = "Aguinha"
		ts._create()
		await get_tree().create_timer(0.5).timeout
		print("TESTE titulo vaga=", Chars.slot, " classe=", player.classe, " cajado=", player.equipment.get_item(EquipSlot.Slot.MAIN_HAND).id, " salvo=", Chars.info(3), " nome=", player.display_name)


## Começa o jogo com o personagem da vaga escolhida (chamado pela tela inicial).
func start_game(slot: int) -> void:
	var inf := Chars.info(slot)
	var nome: String = inf.get("nome", "")
	if nome != "" and OS.has_feature("web") and JavaScriptBridge.eval("typeof window.ArsonNet !== 'undefined'", true):
		JavaScriptBridge.get_interface("ArsonNet").saveName(nome)
	_spawn_characters(inf.get("classe", "fogo"))
	if nome != "":
		player.display_name = nome
	_spawn_monsters()
	if has_node("CameraInicial"):
		get_node("CameraInicial").queue_free()
	if "--teste-combate" in OS.get_cmdline_user_args():
		_teste_combate()
	if "--teste-menu" in OS.get_cmdline_user_args():
		_teste_menu.call_deferred()
	if "--teste-boneco" in OS.get_cmdline_user_args():
		_teste_boneco()
	var net := NetSync.new()
	net.name = "Rede"
	add_child(net)
	net.setup(player, entities)
	var ui := EquipmentPanel.new()
	ui.layer = 2
	add_child(ui)
	ui.bind(player)
	var perf := Perf.new()
	perf.name = "Desempenho"
	add_child(perf)
	var gm := GameMenu.new()
	add_child(gm)
	gm.bind(player, perf)
	var hud := Hud.new()
	add_child(hud)
	hud.bind(player, net, ui)
	hud.game_menu = gm


func _build_ground() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	var w := map.weight_textures()
	mat.set_shader_parameter("map_size", Vector2(map.w, map.h))
	mat.set_shader_parameter("w0", w[0])
	mat.set_shader_parameter("w1", w[1])
	mat.set_shader_parameter("cores", _tex_array(["grass_c", "path_c", "sand_c", "stone_c", "forest_c", "ash_c"]))
	mat.set_shader_parameter("normais", _tex_array(["grass_n", "path_n", "stone_n"]))
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


## Junta várias texturas do chão num Texture2DArray (1 unidade de textura em vez de várias).
func _tex_array(names: Array) -> Texture2DArray:
	var imgs: Array[Image] = []
	for nm in names:
		var im: Image = (load(TEX + nm + ".jpg") as Texture2D).get_image()
		if im.is_compressed():
			im.decompress()
		im.convert(Image.FORMAT_RGBA8)
		if im.get_width() != 512 or im.get_height() != 512:
			im.resize(512, 512)
		im.generate_mipmaps()
		imgs.append(im)
	var arr := Texture2DArray.new()
	arr.create_from_images(imgs)
	return arr


const OBJ := "res://assets/objetos/"
const T := 0.643  # tiles por metro (peças desenhadas por código)

var anchors := {}


## Peça desenhada por código: a origem da imagem vai no ponto `og` da grade.
func piece(nm: String, og: Vector2, fpos: Vector2, fsize: Vector2, flip := false, shadow := true, sc := 1.0) -> Prop:
	if anchors.is_empty():
		var txt := FileAccess.get_file_as_string(OBJ + "ancoras.json")
		var parsed = JSON.parse_string(txt) if txt != "" else null
		anchors = parsed if parsed is Dictionary else {"_": 0}
	var p := Prop.new().setup("box", fpos, fsize, 60.0, Color(0.3, 0.2, 0.1))
	var a = anchors.get(nm)
	var an := Vector2(a[0], a[1]) if a is Array else Vector2(-1, -1)
	var center := Iso.to_screen(fpos + fsize * 0.5)
	# imagens desenhadas em resolução dupla: escala 0.5 no jogo
	p.with_image(OBJ + nm + ".png", 0.5 * sc, Iso.to_screen(og) - center, flip, an)
	p.casts_shadow = shadow
	entities.add_child(p)
	return p


func _build_details() -> void:
	# poço no meio da praça
	piece("poco", Vector2(27.5, 30.2), Vector2(27.5, 30.2) - Vector2(0.51, 0.51), Vector2(1.03, 1.03))
	# bancos perto da fogueira
	piece("banco", Vector2(29.0, 36.9), Vector2(28.95, 36.9), Vector2(1.16, 0.27))
	piece("banco", Vector2(32.2, 35.4), Vector2(32.2, 35.35), Vector2(0.27, 1.16), true)
	# caixotes e barris ao lado das casas
	for r: Rect2 in map.blocks("H"):
		var cx := Vector2(r.end.x + 0.55, r.position.y + 0.5)
		if map.walkable_grid(cx):
			piece("caixotes", cx, cx - Vector2(0.32, 0.32), Vector2(0.8, 0.64))
		var bx := Vector2(r.end.x + 0.45, r.position.y + 1.5)
		if map.walkable_grid(bx):
			piece("barril", bx, bx - Vector2(0.23, 0.23), Vector2(0.46, 0.46))
	# cercas ao longo das estradas do sul e do leste
	var y := 34.0
	while y < 43.0:
		for x in [26.55, 29.45]:
			if map.walkable_grid(Vector2(x, y + 1.0)):
				piece("cerca", Vector2(x, y), Vector2(x - 0.05, y), Vector2(0.1, 2.06), true, false)
		y += 2.2
	var x2 := 40.0
	while x2 < 50.0:
		for yy in [26.55, 29.45]:
			if map.walkable_grid(Vector2(x2 + 1.0, yy)):
				piece("cerca", Vector2(x2, yy), Vector2(x2, yy - 0.05), Vector2(2.06, 0.1), false, false)
		x2 += 2.2


func _build_buildings() -> void:
	# casas (desenhadas por código), alternando modelo e lado
	var k := 0
	for r: Rect2 in map.blocks("H"):
		var og := r.position + Vector2(0.15, 0.15)
		var p := piece("casa" if k % 2 == 0 else "casa2", og, r.position + Vector2(0.1, 0.1), r.size - Vector2(0.2, 0.2), k % 3 == 1)
		var door := LightKit.make(Color(1.0, 0.6, 0.25), 0.7, 1.1, false, 0.1)
		door.position = Iso.to_screen(r.end) - p.position + Vector2(0, -30)
		p.add_child(door)
		k += 1
	# templo de pedra com torre do sino
	for r: Rect2 in map.blocks("T"):
		var t := piece("templo", r.position, r.position + Vector2(0.05, 0.05), Vector2(5.8, 2.85))
		t.name = "Templo"
		var tower := StaticBody2D.new()
		var cp := CollisionPolygon2D.new()
		var t0 := r.position + Vector2(5.75, 0.58)
		cp.polygon = PackedVector2Array([Iso.to_screen(t0), Iso.to_screen(t0 + Vector2(1.55, 0)), Iso.to_screen(t0 + Vector2(1.55, 1.55)), Iso.to_screen(t0 + Vector2(0, 1.55))])
		tower.add_child(cp)
		add_child(tower)
	# árvores, pinheiros e pedras espalhados conforme o terreno
	var kinds := ["arvore", "arvore_outono", "arvore_escura"]
	for y in map.h:
		for x in map.w:
			var ch := map.at(x, y)
			var r1 := map.tile_rand(x, y)
			var j := Vector2(map.tile_rand(x, y, 1), map.tile_rand(x, y, 2)) * 0.6 + Vector2(0.2, 0.2)
			var og := Vector2(x, y) + j
			var flip := map.tile_rand(x, y, 4) > 0.5
			var sc := 0.85 + map.tile_rand(x, y, 3) * 0.35
			if (ch == "f" and r1 < 0.26) or (ch == "." and r1 < 0.025):
				var nm: String = kinds[int(map.tile_rand(x, y, 5) * 3) % 3] if map.tile_rand(x, y, 6) > 0.25 else "pinheiro"
				var tr := piece(nm, og, og - Vector2(0.17, 0.17), Vector2(0.34, 0.34), flip, false, sc)
				tr.fade_when_behind = true
			elif ch == "r" and r1 < 0.12:
				piece("pinheiro" if map.tile_rand(x, y, 7) > 0.6 else ("pedra" if flip else "pedra2"), og, og - Vector2(0.3, 0.3), Vector2(0.6, 0.6), flip, false, sc)
			elif ch == "." and r1 > 0.985:
				piece("pedra2", og, og - Vector2(0.25, 0.25), Vector2(0.5, 0.5), flip, false, 0.7)
	# carroças na estrada do sul e tendas na praça
	piece("carroca", Vector2(24.0, 37.4), Vector2(24.0, 37.4), Vector2(1.45, 0.72))
	piece("carroca", Vector2(31.2, 39.6), Vector2(31.2, 39.6), Vector2(0.72, 1.45), true)
	piece("tenda", Vector2(24.4, 31.6), Vector2(24.4, 31.6), Vector2(1.5, 1.1))
	piece("tenda", Vector2(29.4, 31.6), Vector2(29.4, 31.6), Vector2(1.1, 1.5), true)


func _build_lights() -> void:
	for c in [Vector2(22.5, 26.6), Vector2(33.5, 26.6), Vector2(22.5, 32.5), Vector2(33.5, 32.5)]:
		var post := piece("lampiao", c, c - Vector2(0.07, 0.07), Vector2(0.14, 0.14), false, false)
		var l := LightKit.make(Color(1.0, 0.65, 0.3), 1.1, 1.9, false, 0.12)
		l.position = post.tex_foot + Vector2(23, -96)
		post.add_child(l)
	var camp := piece("fogueira", Vector2(31.0, 36.0), Vector2(30.6, 35.6), Vector2(0.8, 0.8), false, false)
	camp.fade_when_behind = false
	Fx.fire(camp, camp.tex_foot + Vector2(0, -6), 0.5)
	var fl := LightKit.make(Color(1.0, 0.55, 0.2), 1.3, 2.4, true, 0.2)
	fl.position = camp.tex_foot + Vector2(0, -12)
	camp.add_child(fl)


## Monstros fora da vila: esqueletos e carniçais nos campos, bandidos nas florestas,
## cultistas e golens nos morros de rocha ao norte. Posições fixas por tile.
func _spawn_monsters() -> void:
	var n := 0
	for y in map.h:
		for x in map.w:
			var ch := map.at(x, y)
			var gp := Vector2(x + 0.5, y + 0.5)
			if gp.distance_to(map.spawn) < 10.0 or not map.walkable_grid(gp):
				continue
			var r := map.tile_rand(x, y, 11)
			var r2 := map.tile_rand(x, y, 12)
			var t := ""
			if ch == "f" and r < 0.035:
				t = "bandido" if r2 < 0.6 else "esqueleto"
			elif ch == "." and r < 0.014:
				t = "carnical" if r2 < 0.45 else "esqueleto"
			elif ch == "r" and r < 0.03:
				t = "golem" if r2 < 0.25 else "cultista"
			elif ch == ":" and r < 0.01 and gp.distance_to(map.spawn) > 14.0:
				t = "cultista"
			if t == "":
				continue
			var m := Monster.new().configure(t, Iso.to_screen(gp))
			m.name = "Monstro_%d" % n
			m.idx = n
			entities.add_child(m)
			n += 1
	# bonecos de treino logo fora da vila (fora do calçamento, chão livre)
	var placed: Array = []
	for rr in range(8, 13):
		for y in map.h:
			for x in map.w:
				if placed.size() >= 4:
					break
				var gp2 := Vector2(x + 0.5, y + 0.5)
				var dd := gp2.distance_to(map.spawn)
				if dd < rr or dd >= rr + 1 or not ".:".contains(map.at(x, y)) or not map.walkable_grid(gp2):
					continue
				if placed.any(func(q): return q.distance_to(gp2) < 2.5):
					continue
				placed.append(gp2)
				var dm := Monster.new().configure("boneco", Iso.to_screen(gp2))
				dm.name = "Boneco_%d" % n
				dm.idx = n
				entities.add_child(dm)
				n += 1


## Só para testes automáticos (godot ... -- --teste-combate): leva o jogador até
## monstros, mira e ataca sozinho, e escreve o resultado no console.
func _teste_combate() -> void:
	await get_tree().create_timer(0.3).timeout
	var mons := get_tree().get_nodes_in_group("monsters")
	print("TESTE monstros=", mons.size())
	var m: Monster = null
	for c in mons:
		if c.mtype == "esqueleto" or c.mtype == "carnical":
			m = c
			break
	if m == null:
		return
	player.global_position = m.home + Vector2(120, 40)
	# nível alto só no teste, para lançar todas as magias
	player.level = 12
	player._recalc()
	player.mp = player.max_mp
	for i in 30:
		await get_tree().create_timer(0.25).timeout
		if not player._alive_foe():
			player.target_nearest()
		if i % 4 == 0:
			player.mp = player.max_mp
			player.cast_slot((i / 4) % Player.SPELLS.size())
	print("TESTE nivel=", player.level, " xp=", player.xp, " ouro=", player.gold, " vida=", int(player.hp), " alvo_vivo=", player._alive_foe())


func _teste_boneco() -> void:
	await get_tree().create_timer(0.3).timeout
	var dm: Monster = null
	for c in get_tree().get_nodes_in_group("monsters"):
		if c.mtype == "boneco":
			dm = c
			break
	player.global_position = dm.home + Vector2(130, 30)
	player.foe = dm
	for i in 40:
		await get_tree().create_timer(0.25).timeout
		if i % 6 == 0:
			player.mp = player.max_mp
			player.cast_slot(0)
	print("TESTE boneco vida=", dm.hp, "/", dm.max_hp, " morto=", dm.dead, " habilidades=", player.skills, " vida_jogador=", int(player.hp))


func _spawn_characters(classe: String) -> void:
	player = Player.new()
	player.classe = classe
	var cj: String = MageClass.info(classe).cajado
	player.start_items = player.start_items.map(func(it): return cj if it == "cajado_brasa" else it)
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


func _teste_menu() -> void:
	await get_tree().create_timer(0.3).timeout
	var gm: GameMenu = null
	var pf: Perf = null
	for c in get_children():
		if c is GameMenu: gm = c
		if c is Perf: pf = c
	gm.toggle()
	for i in 4:
		gm._tabs.current_tab = i
		await get_tree().process_frame
	gm.toggle()
	for lv in range(1, 7):
		Settings.quality = lv
		pf.apply()
		await get_tree().process_frame
		print("TESTE resolucao nivel=", lv, " modo=", get_window().content_scale_mode, " desenho=", get_window().content_scale_size, " fator=", snappedf(get_window().content_scale_factor, 0.01), " tela_logica=", get_viewport().get_visible_rect().size)
	Settings.quality = 0
	pf.apply()
	var code := gm._export_code()
	var xp0 := player.xp
	player.xp = 999999
	gm.import_code(code)
	print("TESTE export/import ok=", player.xp == xp0, " tamanho_codigo=", code.length())
	var m: Monster = null
	for c in get_tree().get_nodes_in_group("monsters"):
		if c.mtype == "esqueleto" or c.mtype == "carnical":
			m = c
			break
	player.global_position = m.home + Vector2(150, 50)
	player.level = 12
	player._recalc()
	player.hp = player.max_hp * 0.3
	for k in ["alvo", "ataque", "cura", "pocao_mana", "infinitas"]:
		Settings.auto[k] = true
	var hp0 := player.hp
	await get_tree().create_timer(8.0).timeout
	print("TESTE automacao alvo=", player.foe != null, " xp_ganho=", player.xp - xp0, " curou=", player.hp > hp0, " vida=", int(player.hp), "/", int(player.max_hp))
	for k in ["alvo", "ataque", "cura", "pocao_mana", "infinitas"]:
		Settings.auto[k] = false
	player.set_zoom(2.5)
	print("TESTE zoom=", player.camera.zoom)
