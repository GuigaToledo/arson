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
var _ground_mat: ShaderMaterial
var _decals: Node2D
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
	Boot.step("mapa")
	map = WorldMap.load_file(MAP_PATH)
	Player.map_hash = FileAccess.get_file_as_string(MAP_PATH).hash()
	Actor.walkable = map.walkable
	Rules.sight_check = map.line_clear
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
	# sombras do sol por oclusor saíam como faixas retas e duras; agora cada peça tem sombra
	# macia própria no chão (prop.gd), e só as luzes de perto (lampiões) projetam sombra
	sun.shadow_enabled = false
	sun.shadow_color = Color(0, 0, 0, 0.45)
	sun.max_distance = 600.0
	add_child(sun)
	day_night = DayNight.new()
	day_night.cm = cm
	day_night.sun = sun
	add_child(day_night)
	Boot.step("chão")
	_build_ground()
	entities = Node2D.new()
	entities.name = "Entidades"
	entities.y_sort_enabled = true
	add_child(entities)
	Boot.step("construções")
	_build_buildings()
	Boot.step("detalhes")
	_build_details()
	Boot.step("luzes")
	_build_lights()
	Boot.step("regiões e monstros")
	_build_regions()
	Boot.step("cogumelos e cristais")
	_build_glow()
	Boot.step("detalhes do chão")
	_decals = GroundDecals.build(self, map)
	_safety()
	Boot.step("tela inicial")
	add_to_group("qualidade")
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
	# app: reiniciou sozinho para atualizar no meio do jogo -> entra direto no mesmo personagem
	if FileAccess.file_exists(AppUpdate.RETOMAR):
		var r2 := int(FileAccess.get_file_as_string(AppUpdate.RETOMAR))
		DirAccess.remove_absolute(AppUpdate.RETOMAR)
		if r2 >= 1 and r2 <= Chars.MAX and Chars.info(r2).existe:
			Chars.use(r2)
			start_game(r2)
			_mark_ok()
			return
	# ?autoteste=classe (só para testes automáticos): pula a tela inicial na vaga 4
	# (no computador, sem janela: --autoteste=classe na linha de comando)
	var at := ""
	for ua in OS.get_cmdline_user_args():
		if str(ua).begins_with("--autoteste="):
			at = str(ua).split("=")[1]
	if OS.has_feature("web") or at != "":
		if OS.has_feature("web"):
			at = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('autoteste') || ''", true))
		if MageClass.valid(at):
			var nm2 := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('nome') || 'Teste'", true)) if OS.has_feature("web") else "Teste"
			Chars.create(4, at, nm2)
			Chars.use(4)
			start_game(4)
			for k in player.skills:
				player.skills[k] = [40, 0.0]
			get_tree().create_timer(12.0).timeout.connect(func():
				player.mp = player.max_mp
				player.cast_spell(player.elem_a() + ":5")
				player.mp = player.max_mp
				player.cast_spell("luz:2"))
			return
	var ts := TitleScreen.new()
	add_child(ts)
	ts.setup()
	Boot.step("tela inicial montada")
	_mark_ok()
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


## Ganchos de teste: linha de comando (-- --teste-x) ou, no navegador, ?teste=x,y=1 (vira --teste-x, --teste-y=1).
func _test_args() -> Array:
	var out: Array = Array(OS.get_cmdline_user_args())
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('teste') || ''", true))
		for t in q.split(",", false):
			out.append("--teste-" + t)
	return out


## Começa o jogo com o personagem da vaga escolhida (chamado pela tela inicial).
## Depois de alguns quadros desenhados (shaders compilados), marca que o app abriu bem.
func _mark_ok() -> void:
	for i in 20:
		await get_tree().process_frame
		if i == 0 or i == 2 or i == 8:
			Boot.step("quadro %d" % (i + 1))
	Boot.step("ok")


## App Android que fechou sozinho várias vezes seguidas: desliga uma camada a mais a cada vez,
## para descobrir qual derruba o celular (2: chão simples, 3: sem luzes, 4: sem detalhes do chão
## e sem brilhos, 5: sem peças do cenário).
func _safety() -> void:
	var boot := get_node_or_null("/root/Boot")
	var n: int = boot.crashes if boot else 0
	if n >= 3:
		for l in find_children("*", "Light2D", true, false):
			l.visible = false
		Boot.step("sem luzes")
	if n >= 4:
		if _decals:
			_decals.visible = false
		for gnode in get_tree().get_nodes_in_group("luz_extra"):
			gnode.get_parent().visible = false
		Boot.step("sem detalhes")
	if n >= 5:
		for pr in find_children("*", "Prop", true, false):
			pr.visible = false
		Boot.step("sem peças")


func start_game(slot: int) -> void:
	Boot.step("entrando no jogo")
	# app de celular: confere atualização a cada minuto e se atualiza sozinho (como o navegador)
	if OS.has_feature("android"):
		var up := AppUpdate.new()
		up.em_jogo = true
		add_child(up)
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
	if "--teste-magias" in OS.get_cmdline_user_args():
		_teste_magias.call_deferred()
	if "--teste-summon" in OS.get_cmdline_user_args():
		_teste_summon.call_deferred()
	if "--teste-npc" in OS.get_cmdline_user_args():
		_teste_npc.call_deferred()
	if "--teste-etapa1" in OS.get_cmdline_user_args():
		_teste_etapa1.call_deferred()
	if "--teste-continente" in OS.get_cmdline_user_args():
		# leva o jogador ao meio dos campos (e depois à caverna) para testar monstros e magias deles
		player.global_position = Iso.to_screen(Vector2(84.5, 30.5))
		get_tree().create_timer(4.0).timeout.connect(func(): player.global_position = Iso.to_screen(Vector2(116.5, 22.5)))
		get_tree().create_timer(8.0).timeout.connect(func(): player.global_position = Iso.to_screen(Vector2(76.5, 62.5)))
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
	_mark_ok()
	var dlg := NpcDialog.new()
	add_child(dlg)
	var gm := GameMenu.new()
	add_child(gm)
	gm.bind(player, perf)
	if "--teste-celular" in OS.get_cmdline_user_args():
		Settings._mobile = 1
	var post := PostFx.new()
	add_child(post)
	post.player = player
	post.map = map
	post.setup_dust(entities)
	var hud := Hud.new()
	add_child(hud)
	hud.bind(player, net, ui)
	hud.set_map(map)
	hud.game_menu = gm
	gm.on_chat = hud._open_chat
	gm.on_equip = hud._toggle_panel
	gm.on_full = hud._fullscreen
	if "--teste-noite" in OS.get_cmdline_user_args():
		DayNight.force = 0.85
	if "--teste-ui" in OS.get_cmdline_user_args():
		_teste_ui(ui, dlg, gm)
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--teste-fotos="):
			_fotos(str(arg).split("=")[1], hud)
	for arg in _test_args():
		# --teste-chefe=<tipo>[:ataque|:morte]: vai até o chefe (forte o bastante para não morrer)
		if str(arg).begins_with("--teste-chefe="):
			var pp := str(arg).split("=")[1].split(":")
			var boss: Monster = null
			for c in get_tree().get_nodes_in_group("monsters"):
				if c.mtype == pp[0]:
					boss = c
			if boss:
				player.level = 80
				player._recalc()
				player.camera.position_smoothing_enabled = false
				player.global_position = boss.global_position + Vector2(190, 70)
				var acao := pp[1] if pp.size() > 1 else ""
				get_tree().create_timer(1.2).timeout.connect(func():
					if acao == "ataque":
						boss.facing = "SE"
						boss.play_action("attack", 0.8)
					elif acao == "morte":
						boss.hp = 0.0
						boss._die(player)
					print("TESTE chefe ", boss.display_name, " nivel=", boss.level, " vida=", int(boss.max_hp), " corpo=", boss.body_path))
			else:
				print("TESTE chefe nao achou ", pp[0])
		if str(arg).begins_with("--teste-vermagia="):
			for k in player.skills:
				player.skills[k] = [40, 0.0]
			player.level = 15
			player._recalc()
			var mm: Monster = null
			for c in get_tree().get_nodes_in_group("monsters"):
				if c.mtype != "boneco":
					mm = c
					break
			player.global_position = mm.global_position + Vector2(150, 50)
			player.foe = mm
			var sid := str(arg).split("=")[1]
			get_tree().create_timer(0.2).timeout.connect(func():
				player.max_mp = 9999.0
				player.mp = 9999.0
				var mp0 := player.mp
				player.cast_spell(sid)
				print("TESTE vermagia ", sid, " gastou=", mp0 - player.mp, " seguro=", Rules.is_safe(player.global_position), " acao=", player._action_time, " liberada=", player.spell_unlocked(sid), " textos=", CombatText.items.map(func(x): return x.get("text", x.get("t", "")))))
		if str(arg) == "--teste-skins":
			var k := 0
			for cl in MageClass.ORDER:
				if cl == player.classe:
					continue
				k += 1
				var rp := RemotePlayer.new()
				rp.start_items = MageClass.info(cl).itens.duplicate()
				rp.position = player.position + Vector2(-260 + k * 90, 60 + (k % 2) * 20)
				entities.add_child(rp)
				rp.apply_state({"x": rp.position.x, "y": rp.position.y, "c": cl, "n": MageClass.info(cl).nome, "f": "S", "a": "idle"})
		if str(arg).begins_with("--teste-zoom="):
			player.camera.position_smoothing_enabled = false
			player.global_position = Iso.to_screen(map.spawn)
			player.camera.zoom = Vector2.ONE * float(str(arg).split("=")[1])
		if str(arg) == "--teste-invocacoes":
			var anims := ["idle", "punch", "kick", "spin", "headbutt", "grab", "walk", "punch"]
			var i := 0
			for el in ["terra", "lava", "gelo", "fogo", "vento", "raio", "agua", "natureza"]:
				var sm := Summon.make(null, [el], false)
				sm.puppet = true
				sm.position = player.position + Vector2(-330 + (i % 4) * 150, -40 + (i / 4) * 150)
				sm.puppet_target = sm.position
				entities.add_child(sm)
				sm.anim = anims[i]
				sm.facing = "SE"
				i += 1
		if str(arg) == "--teste-semsombra" or str(arg) == "--teste-semluz":
			var cnt := [0, 0]
			for l in find_children("*", "Light2D", true, false):
				cnt[0] += 1
				if l.shadow_enabled:
					cnt[1] += 1
				l.shadow_enabled = false
				if str(arg) == "--teste-semluz":
					l.visible = false
			print("TESTE luzes=", cnt[0], " com_sombra=", cnt[1])
		if str(arg) == "--teste-fps":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
			for k in 3:
				await get_tree().create_timer(3.0).timeout
				print("TESTE fps=", Engine.get_frames_per_second(), " objetos=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT), " desenhos=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " cpu_ms=", snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01))
		if str(arg) == "--teste-itens":
			var mp0 := player.max_mp
			player.equipment.unequip(EquipSlot.Slot.HEAD)
			var neg := player.try_equip(ItemDB.get_item("diadema_arcano")) if player.level < 35 else false
			player.level = 40
			player._recalc()
			for id in ["chapeu_feiticeiro", "manto_arquimago", "calca_encantada", "botas_macias", "capa_estelar", "tomo_ancestral", "cetro_magma", "amuleto_mana", "anel_energia"]:
				player.give_item(id)
				player.try_equip(ItemDB.get_item(id))
			print("TESTE itens recusou_sem_nivel=", not neg, " atributos=", player.gear(), " mana_max=", int(mp0), "->", int(player.max_mp), " bolsa=", player.bag.size())
		if str(arg) == "--teste-progressao":
			player._reset_skills()
			var b0 := player.elem_b()
			var trava := player.spell_unlocked(b0 + ":1")
			player.skills.magia = [30, 0.0]
			player.skill_gain(player.elem_a(), Rules.skill_need("magia", 30) + 1)
			print("TESTE progressao barra=", player.bar, " segundo_liberado_antes=", trava, " depois=", player.skills, " magia_b1=", player.spell_unlocked(b0 + ":1"))
			print("TESTE melhorias luz1 nivel=", player.spell_lvl("luz:1"), " melhorias=", player.spell_up("luz:1"))
		if str(arg) == "--teste-levelup":
			player.skill_gain(player.elem_a(), Rules.skill_need("magia", player.magia()))
		# --teste-escudo: lança o escudo mágico (aura de ki) para conferir o desenho
		if str(arg) == "--teste-escudo":
			player.skills.magia = [12, 0.0]
			get_tree().create_timer(1.0).timeout.connect(func():
				player.mp = player.max_mp
				player.cast_spell(player.elem_a() + ":3")
				print("TESTE escudo aura=", player.shield_hp > 0.0))
		# --teste-magiaremota (com --teste-skins): desenha magias de jogadores remotos (só o visual)
		if str(arg) == "--teste-magiaremota":
			get_tree().create_timer(1.5).timeout.connect(func():
				var n := 0
				for rp in get_tree().get_nodes_in_group("remote_players"):
					var p0: Vector2 = rp.global_position
					for sid in ["fogo:1", "fogo:2", "fogo:4", "lava:4", "fogo:6", "luz:1", "luz:2", "fus:8"]:
						net._show_spell(rp, {"id": sid, "c": "fogo", "ax": p0.x + 200, "ay": p0.y + 60, "ti": -1, "dx": 1.0, "dy": 0.0, "gx": 1.0, "gy": 0.0})
						n += 1
				print("TESTE magia remota desenhadas=", n))
		if str(arg) == "--teste-bolsa":
			ui.toggle()
		if str(arg).begins_with("--teste-vermenu="):
			gm.toggle()
			gm._show(int(str(arg).split("=")[1]))


func _process(delta: float) -> void:
	if player != null:
		Prop.update_fades(player, delta)


## Qualidade mudou (Perf): chão mais simples e menos luzes decorativas nos níveis baixos.
func on_quality(lv: int) -> void:
	if _ground_mat:
		_ground_mat.set_shader_parameter("q", 0 if lv <= 2 else (1 if lv <= 4 else 2))
	GlowProps.apply_quality()
	if _decals:
		# celular: milhares de detalhes do chão pesam no processamento (nível 2 caía de 60 para 22 FPS)
		_decals.visible = lv >= 2 and not Settings.is_mobile()


func _build_ground() -> void:
	var mat := ShaderMaterial.new()
	var simples := Settings.very_safe()
	mat.shader = load("res://shaders/terrain_simples.gdshader" if simples else "res://shaders/terrain.gdshader")
	var w := map.weight_textures()
	mat.set_shader_parameter("map_size", Vector2(map.w, map.h))
	mat.set_shader_parameter("w0", w[0])
	mat.set_shader_parameter("w1", w[1])
	if not simples:
		# Visual Factory: texturas ambientCG em 1024 (512 no celular), 9 camadas com variações
		var vf := ["grama_a", "terra", "areia", "calcamento", "floresta_a", "rocha", "grama_b", "floresta_b", "cemiterio"]
		Boot.step("texturas do chão")
		mat.set_shader_parameter("cores", _tex_array(vf.map(func(x): return VF + x + "_c")))
		mat.set_shader_parameter("cell_c", _cell_uv())
		Boot.step("relevo do chão")
		mat.set_shader_parameter("normais", _tex_array(vf.map(func(x): return VF + x + "_n"), true))
		mat.set_shader_parameter("cell_n", _cell_uv())
		_ground_mat = mat
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


## Junta as 9 texturas do chão num atlas 3x3 (uma textura só). Antes era um Texture2DArray, que
## derrubava o app em alguns celulares Android (o driver de vídeo fechava o app no primeiro desenho).
## Cada célula tem uma borda com a continuação da própria textura, para não vazar a vizinha.
const VF := "res://assets/vf/terreno/"
var atlas_tile := 512
var atlas_pad := 16


func _tex_array(names: Array, normals := false) -> Texture2D:
	# PC (navegador ou não): sempre 1024, a qualidade máxima fica guardada; celular 512
	var sz := 512 if Settings.is_mobile() else 1024
	if Settings.safe_mode():
		sz = 256
	# celular: relevo do chão (normais) em tamanho mínimo, quase não aparece e economiza vídeo
	if normals and Settings.is_mobile():
		sz = 64
	var pad := maxi(4, sz / 32)
	var cell := sz + pad * 2
	var atlas := Image.create(cell * 3, cell * 3, false, Image.FORMAT_RGB8)
	for i in names.size():
		var nm: String = names[i]
		var path: String = nm if nm.begins_with("res://") else TEX + nm
		# as texturas do chão são importadas como imagem (não vão para a placa de vídeo sozinhas)
		var res = load(path + ".jpg")
		var im: Image = (res as Image).duplicate() if res is Image else (res as Texture2D).get_image()
		if im.is_compressed():
			im.decompress()
		im.convert(Image.FORMAT_RGB8)
		if im.get_width() != sz or im.get_height() != sz:
			im.resize(sz, sz, Image.INTERPOLATE_LANCZOS)
		var o := Vector2i((i % 3) * cell, (i / 3) * cell)
		# a textura no meio e pedaços dela mesma em volta (repete sem emenda)
		_blit_wrapped(atlas, im, o, sz, pad)
	atlas.generate_mipmaps()
	atlas_tile = sz
	atlas_pad = pad
	return ImageTexture.create_from_image(atlas)


## (borda, tamanho) de uma célula do último atlas, em fração do atlas (para o shader).
func _cell_uv() -> Vector2:
	var full := float((atlas_tile + atlas_pad * 2) * 3)
	return Vector2(atlas_pad / full, atlas_tile / full)


## Copia `im` (sz x sz) para a célula em `o` com borda `pad` feita da própria textura.
static func _blit_wrapped(atlas: Image, im: Image, o: Vector2i, sz: int, pad: int) -> void:
	var cell := sz + pad * 2
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			# pedaço da cópia vizinha que cai dentro da célula
			var dst := Rect2i(o.x + pad + dx * sz, o.y + pad + dy * sz, sz, sz)
			var clip := dst.intersection(Rect2i(o.x, o.y, cell, cell))
			if clip.size.x <= 0 or clip.size.y <= 0:
				continue
			atlas.blit_rect(im, Rect2i(clip.position - dst.position, clip.size), clip.position)


const OBJ := "res://assets/objetos/"
const T := 0.643  # tiles por metro (peças desenhadas por código)

var anchors := {}


## Peça desenhada por código: a origem da imagem vai no ponto `og` da grade.
func piece(nm: String, og: Vector2, fpos: Vector2, fsize: Vector2, flip := false, shadow := true, sc := 1.0) -> Prop:
	if anchors.is_empty():
		var txt := FileAccess.get_file_as_string(OBJ + "ancoras.json")
		var parsed = JSON.parse_string(txt) if txt != "" else null
		anchors = parsed if parsed is Dictionary else {"_": 0}
	# pedras e rochas: a colisão acompanha o tamanho da pedra desenhada (antes era um quadradinho
	# fixo no meio e o personagem entrava dentro da pedra)
	if nm.begins_with("pedra") or nm.begins_with("rochedo") or nm == "pedregulho":
		var tex: Texture2D = load(OBJ + nm + ".png")
		if tex:
			var wpx := tex.get_width() * 0.5 * sc
			# rochas das paredes da caverna ficam dentro do próprio tile (não fecham passagens)
			var s := clampf(wpx / 64.0 * 0.58, 0.35, 1.0 if nm.begins_with("rochedo") else 1.25)
			fsize = Vector2(s, s)
			fpos = og - fsize * 0.5
	var p := Prop.new().setup("box", fpos, fsize, 60.0, Color(0.3, 0.2, 0.1))
	var a = anchors.get(nm)
	var an := Vector2(a[0], a[1]) if a is Array else Vector2(-1, -1)
	var center := Iso.to_screen(fpos + fsize * 0.5)
	# imagens desenhadas em resolução dupla: escala 0.5 no jogo
	p.with_image(OBJ + nm + ".png", 0.5 * sc, Iso.to_screen(og) - center, flip, an)
	p.casts_shadow = shadow
	p.trunk_solid = nm.begins_with("arvore") or nm == "pinheiro"
	entities.add_child(p)
	# variação natural (ART_DIRECTION: tom ±8%) para árvores, pedras e plantas não repetirem
	if nm.begins_with("arvore") or nm.begins_with("pedra") or nm.begins_with("rochedo") or nm == "pinheiro" or nm == "samambaia" or nm == "pedregulho":
		var hsh := absi(int(og.x * 73.0) ^ int(og.y * 151.0))
		var v := 0.92 + float(hsh % 17) / 100.0
		var w := float((hsh / 17) % 9) / 100.0
		p.modulate = Color(v - w * 0.5, v, v - w, 1.0)
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
		l.range_item_cull_mask = 3
		l.position = post.tex_foot + Vector2(23, -96)
		post.add_child(l)
	var camp := piece("fogueira", Vector2(31.0, 36.0), Vector2(30.6, 35.6), Vector2(0.8, 0.8), false, false)
	camp.fade_when_behind = false
	Fx.fire(camp, camp.tex_foot + Vector2(0, -6), 0.5)
	var fl := LightKit.make(Color(1.0, 0.55, 0.2), 1.3, 2.4, false, 0.2)
	fl.range_item_cull_mask = 3
	fl.position = camp.tex_foot + Vector2(0, -12)
	camp.add_child(fl)


var day_night: DayNight


## Brilhos do mapa: cogumelos verdes nas florestas, cristais coloridos nas cavernas,
## poças de lava no meio dos morros de pedra.
func _build_glow() -> void:
	var n := [0, 0, 0]
	for y in map.h:
		for x in map.w:
			var ch := map.at(x, y)
			var r := map.tile_rand(x, y, 41)
			var j := Vector2(map.tile_rand(x, y, 42), map.tile_rand(x, y, 43)) * 0.6 + Vector2(0.2, 0.2)
			var gp := Vector2(x, y) + j
			match ch:
				"f", "j":
					if r < 0.018:
						GlowProps.mushrooms(entities, Iso.to_screen(gp), x * 131 + y * 7)
						n[0] += 1
				"k":
					if r < 0.045:
						GlowProps.crystal(entities, Iso.to_screen(gp), x * 17 + y * 3)
						n[1] += 1
				"r":
					# lava só nas colinas de pedra do continente (longe da vila)
					if r < 0.3 and (x >= 58 or y >= 58):
						var rn := 0
						for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
							if map.at(x + d.x, y + d.y) == "r":
								rn += 1
						if rn >= 3:
							GlowProps.lava_pool(entities, Iso.to_screen(Vector2(x + 0.5, y + 0.5)), x * 7 + y * 13, 44.0 + r * 120.0)
							n[2] += 1
	print("brilhos: %d cogumelos, %d cristais, %d poças de lava" % n)


## Regiões do continente (gerar_mapa.py): cemitério, caverna, selva e acampamentos.
const CAMPS := {"b": Vector2(76.5, 66.5), "o": Vector2(124.5, 74.5), "y": Vector2(106.5, 104.5)}
var regioes: Array = []


func _region_for(ch: String, x: int, y: int) -> Dictionary:
	if x < 58 and y < 58:
		return {}
	for r in regioes:
		if str(r.get("chars", "")).contains(ch):
			return r
	return {}


func _build_regions() -> void:
	var txt := FileAccess.get_file_as_string("res://data/regioes.json")
	var parsed = JSON.parse_string(txt) if txt != "" else null
	regioes = parsed if parsed is Array else []
	for y in map.h:
		for x in map.w:
			if x < 58 and y < 58:
				continue
			var ch := map.at(x, y)
			var r1 := map.tile_rand(x, y, 21)
			var r2 := map.tile_rand(x, y, 22)
			var j := Vector2(map.tile_rand(x, y, 1), map.tile_rand(x, y, 2)) * 0.6 + Vector2(0.2, 0.2)
			var og := Vector2(x, y) + j
			var flip := map.tile_rand(x, y, 4) > 0.5
			var sc := 0.85 + map.tile_rand(x, y, 3) * 0.35
			match ch:
				"g":
					if r1 < 0.11:
						piece(["lapide", "lapide_cruz", "cruz"][int(r2 * 3.0)], og, og - Vector2(0.15, 0.08), Vector2(0.3, 0.16), flip, false)
					elif r1 < 0.14:
						var dt := piece("arvore_morta", og, og - Vector2(0.15, 0.15), Vector2(0.3, 0.3), flip, false, sc)
						dt.fade_when_behind = true
					elif r1 > 0.98:
						piece("ossos", og, og, Vector2(0.05, 0.05), flip, false)
				"R":
					var edge := false
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						if map.walkable_grid(Vector2(x + d.x + 0.5, y + d.y + 0.5)):
							edge = true
					if (edge and r1 < 0.6) or r1 < 0.05:
						piece("rochedo" if r2 < 0.5 else "rochedo2", Vector2(x + 0.5, y + 0.5), Vector2(x + 0.1, y + 0.1), Vector2(0.8, 0.8), flip, false, 0.9 + r2 * 0.3)
				"k":
					if r1 < 0.035:
						piece("estalagmite", og, og - Vector2(0.15, 0.15), Vector2(0.3, 0.3), flip, false, sc)
					elif r1 > 0.985:
						piece("ossos", og, og, Vector2(0.05, 0.05), flip, false)
				"j":
					if r1 < 0.15:
						var nm: String = ["arvore_selva", "arvore_selva2", "arvore_escura"][int(r2 * 3.0)]
						var jt := piece(nm, og, og - Vector2(0.2, 0.2), Vector2(0.4, 0.4), flip, false, sc)
						jt.fade_when_behind = true
					elif r1 < 0.22:
						piece("samambaia", og, og, Vector2(0.05, 0.05), flip, false, sc)
				"y", "r":
					if r1 < (0.05 if ch == "y" else 0.09):
						piece("pedregulho", og, og - Vector2(0.4, 0.4), Vector2(0.8, 0.8), flip, false, sc)
	# cripta no meio do cemitério
	var cg := Vector2(85.0, 7.0)
	if map.at(int(cg.x), int(cg.y)) == "g":
		piece("cripta", cg, cg, Vector2(1.67, 1.41))
	# acampamentos: fogueira no centro, tendas em volta, totens e paliçadas nas bordas
	for ch in CAMPS:
		var c: Vector2 = CAMPS[ch]
		var camp := piece("fogueira", c, c - Vector2(0.4, 0.4), Vector2(0.8, 0.8), false, false)
		camp.fade_when_behind = false
		Fx.fire(camp, camp.tex_foot + Vector2(0, -6), 0.5)
		var fl := LightKit.make(Color(1.0, 0.55, 0.2), 1.2, 2.2, false, 0.2)
		fl.range_item_cull_mask = 3
		fl.position = camp.tex_foot + Vector2(0, -12)
		camp.add_child(fl)
		var tent := "tenda_orc" if ch == "o" else "tenda_couro"
		for k in 4:
			var a := k * PI * 0.5 + 0.6
			var tp := c + Vector2(cos(a), sin(a)) * 3.4
			if map.walkable_grid(tp):
				piece(tent, tp, tp - Vector2(0.65, 0.65), Vector2(1.3, 1.3), k % 2 == 1)
		for k in 3:
			var a2 := k * TAU / 3.0 + 1.3
			var tt := c + Vector2(cos(a2), sin(a2)) * 1.9
			if map.walkable_grid(tt):
				piece("totem" if ch != "y" else "pedregulho", tt, tt - Vector2(0.15, 0.15), Vector2(0.3, 0.3), false, false)
		if ch != "y":
			var x0 := c.x - 6.0
			while x0 < c.x + 5.0:
				for yy in [c.y - 6.5, c.y + 6.0]:
					var pp := Vector2(x0, yy)
					if map.walkable_grid(pp + Vector2(1.0, 0)) and map.at(int(pp.x + 1.0), int(pp.y)) != ":":
						piece("palicada", pp, pp, Vector2(1.8, 0.25), false, false)
				x0 += 2.1


## Monstros fora da vila: esqueletos e carniçais nos campos, bandidos nas florestas,
## cultistas e golens nos morros de rocha ao norte. Posições fixas por tile.
func _spawn_monsters() -> void:
	Rules.town = map.spawn
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
			var reg := _region_for(ch, x, y)
			if not reg.is_empty():
				var dens: float = float(reg.get("dens", {}).get(ch, 0.0))
				var tab: Array = reg.get("tabela", {}).get(ch, [])
				if r < dens and not tab.is_empty():
					t = str(tab[int(r2 * tab.size()) % tab.size()])
			elif x >= 58 or y >= 58:
				pass
			elif ch == "f" and r < 0.035:
				t = ["bandido", "goblin", "goblin_xama", "troll_jovem", "esqueleto"][int(r2 * 5.0)]
			elif ch == "." and r < 0.016:
				t = ["slime_verde", "slime_verde", "slime_agua", "goblin", "esqueleto", "esqueleto_arqueiro"][int(r2 * 6.0)]
			elif ch == "r" and r < 0.03:
				t = "golem" if r2 < 0.25 else "cultista"
			elif ch == ":" and r < 0.01 and gp.distance_to(map.spawn) > 14.0:
				t = "cultista"
			if t == "":
				continue
			var m := Monster.new().configure(t, Iso.to_screen(gp), map.tile_rand(x, y, 31) < Monster.ELITE_CHANCE, Rules.level_cap(gp))
			m.name = "Monstro_%d" % n
			m.idx = n
			entities.add_child(m)
			n += 1
	# chefes de cada região (posição fixa em regioes.json)
	for reg in regioes:
		for b in reg.get("chefes", []):
			var bp := Vector2(float(b["pos"][0]), float(b["pos"][1]))
			if not map.walkable_grid(bp):
				bp = _free_tile(bp)
			var bm := Monster.new().configure(str(b["tipo"]), Iso.to_screen(bp), false, Rules.level_cap(bp))
			bm.name = "Chefe_%d" % n
			bm.idx = n
			entities.add_child(bm)
			n += 1
	# bonecos de treino logo fora da vila (três lado a lado, fixos no lugar) (fora do calçamento, chão livre)
	var placed: Array = []
	for rr in range(8, 13):
		for y in map.h:
			for x in map.w:
				if placed.size() >= 1:
					break
				var gp2 := Vector2(x + 0.5, y + 0.5)
				var dd := gp2.distance_to(map.spawn)
				if dd < rr or dd >= rr + 1 or not ".:".contains(map.at(x, y)) or not map.walkable_grid(gp2):
					continue
				if placed.any(func(q): return q.distance_to(gp2) < 2.5):
					continue
				# três bonecos lado a lado (para testar magia em área)
				var row := [gp2]
				for dirv in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
					var cand := [gp2 + dirv * 1.4, gp2 + dirv * 2.8]
					if cand.all(func(q): return map.walkable_grid(q) and ".:".contains(map.at(int(q.x), int(q.y)))):
						row += cand
						break
				if row.size() < 3:
					continue
				placed.append(gp2)
				for q in row:
					var dm := Monster.new().configure("boneco", Iso.to_screen(q))
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
			player.cast_slot((i / 4) % 8)
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
	var corpo := Actor.class_body(classe)
	if FileAccess.file_exists(corpo):
		player.body_path = corpo
	if day_night:
		day_night.player = player
	# skin da classe: peças, olhos e núcleo na cor do elemento
	var ci := MageClass.info(classe)
	player.start_items = ci.itens.duplicate()
	player.body_colors["eyes"] = ci.olhos
	player.body_colors["core_col"] = ci.nucleo
	player.name = "Jogador"
	player.position = Iso.to_screen(map.spawn)
	entities.add_child(player)
	# volta onde estava (se o mapa não mudou e o lugar ainda é chão livre)
	if player.saved_map == Player.map_hash and player.saved_pos.x >= 0 and map.walkable_grid(player.saved_pos):
		player.global_position = Iso.to_screen(player.saved_pos)

	var guard := Npc.new().configure("Guarda do Templo",
		{"skin": Color(0.55, 0.42, 0.33), "under": Color(0.2, 0.18, 0.16), "hair": Color(0.1, 0.08, 0.06), "eyes": Color(0.2, 0.15, 0.1)},
		["elmo_ferro", "peitoral_couro", "ombreiras_ferro", "calca_tecido", "botas_couro"], "S")
	guard.position = g(25.6, 26.5)
	entities.add_child(guard)

	var pts := []
	for p in [Vector2(27.5, 31), Vector2(27.5, 42), Vector2(27.5, 31), Vector2(12, 28), Vector2(27.5, 28),
			Vector2(27.5, 14), Vector2(27.5, 28), Vector2(45, 28)]:
		pts.append(g(p.x, p.y))
	# NPCs de conversa (como na versão 3D): mercador de poções e sacerdotisa
	var brann := Npc.new().configure("Brann, o Mercador",
		{"skin": Color(0.6, 0.45, 0.35), "under": Color(0.25, 0.2, 0.15), "hair": Color(0.3, 0.2, 0.1), "eyes": Color(0.2, 0.15, 0.1)},
		["avental_taverna", "calca_tecido", "botas_couro"], "S")
	brann.role = "mercador"
	brann.position = Iso.to_screen(_free_tile(Vector2(23.0, 25.0)))
	brann.add_to_group("npcs")
	entities.add_child(brann)
	var lira := Npc.new().configure("Lira, a Sacerdotisa",
		{"skin": Color(0.78, 0.62, 0.5), "under": Color(0.8, 0.76, 0.66), "hair": Color(0.85, 0.75, 0.45), "eyes": Color(0.3, 0.5, 0.8)},
		["capuz_sacerdotisa", "manto_sacerdotisa", "botas_couro"], "S")
	lira.role = "sacerdotisa"
	lira.position = Iso.to_screen(_free_tile(Vector2(31.6, 24.0)))
	lira.add_to_group("npcs")
	entities.add_child(lira)

	var walker := Npc.new().configure("Viajante",
		{"skin": Color(0.5, 0.38, 0.3), "under": Color(0.2, 0.17, 0.14), "hair": Color(0.15, 0.1, 0.07), "eyes": Color(0.2, 0.15, 0.1)},
		["gibao_verde", "calca_tecido", "botas_couro", "capa_viagem"], "S", pts)
	walker.position = pts[0]
	entities.add_child(walker)


## Casa de chão livre mais perto de um ponto da grade (procura em volta).
## Inspeção visual (Visual Factory): leva o jogador a cenas fixas, de dia e de noite,
## e salva um PNG de cada uma (com e sem a interface) na pasta pedida.
const FOTO_CENAS := [["vila", Vector2(27, 26)], ["vila_casas", Vector2(22, 22)], ["floresta_ilha", Vector2(12, 36)],
	["campos", Vector2(82, 30)], ["cemiterio", Vector2(86, 12)], ["caverna", Vector2(116, 22)],
	["selva", Vector2(96, 84)], ["acampamento_orc", Vector2(124, 77)], ["ciclopes_lava", Vector2(104, 100)]]


func _fotos(dir: String, hud: Node) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	player.photo_mode = true
	var pf: Perf = get_children().filter(func(n): return n is Perf)[0]
	Settings.quality = 6
	pf.apply()
	for k in Settings.auto:
		if typeof(Settings.auto[k]) == TYPE_BOOL:
			Settings.auto[k] = false
	for hora in [["dia", 0.3], ["noite", 0.86]]:
		DayNight.force = float(hora[1])
		for c in FOTO_CENAS:
			player.global_position = Iso.to_screen(c[1])
			player.joy = Vector2.ZERO
			for f in 45:
				player.immortal_t = 999.0
				await get_tree().process_frame
			var nome := "%s/%s_%s" % [dir, c[0], hora[0]]
			get_viewport().get_texture().get_image().save_png(nome + ".png")
			if hora[0] == "dia":
				hud.visible = false
				for f in 3:
					await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(nome + "_limpa.png")
				hud.visible = true
			print("FOTO ", nome)
	# diagnóstico: mesma cena da floresta desligando uma camada por vez
	DayNight.force = 0.3
	hud.visible = false
	player.global_position = Iso.to_screen(Vector2(12, 36))
	for f in 45:
		await get_tree().process_frame
	var base := "%s/_diag_floresta" % dir
	get_viewport().get_texture().get_image().save_png(base + "_0_normal.png")
	var post := get_children().filter(func(n): return n is PostFx)
	for n in post:
		n.visible = false
		n._rect.visible = false
	for f in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(base + "_1_sem_pos.png")
	var luzes := find_children("*", "Light2D", true, false)
	for l in luzes:
		if is_instance_valid(l):
			l.visible = false
	for f in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(base + "_2_sem_luzes.png")
	for sp in find_children("*", "Sprite2D", true, false):
		if sp.texture == Prop.shadow_tex():
			sp.visible = false
	for f in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(base + "_3_sem_sombras.png")
	for pr in find_children("*", "Prop", true, false):
		if pr._fade < 0.99:
			pr.visible = false
	for f in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(base + "_35_sem_transparentes.png")
	for pr in find_children("*", "Prop", true, false):
		pr.visible = false
	for f in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(base + "_4_sem_pecas.png")
	for pr in find_children("*", "Prop", true, false):
		pr.visible = true
	for l in luzes:
		if is_instance_valid(l):
			l.visible = true
	for sp in find_children("*", "Sprite2D", true, false):
		if sp.texture == Prop.shadow_tex():
			sp.visible = true
	GlowProps.apply_quality()
	# como fica no nível mais leve (começo da qualidade automática)
	Settings.quality = 1
	pf.apply()
	DayNight.force = 0.3
	for c in [["floresta_ilha", Vector2(12, 36)], ["caverna", Vector2(116, 22)]]:
		player.global_position = Iso.to_screen(c[1])
		for f in 30:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/_nivel1_%s.png" % [dir, c[0]])
	print("FOTOS ok")
	get_tree().quit()


## Teste automático do inventário, da loja (venda do saque) e do saque dos chefes.
func _teste_ui(ui: EquipmentPanel, dlg: NpcDialog, gm: GameMenu) -> void:
	for id in ["gosma_verde", "osso", "pele_lobo", "coroa_goblin"]:
		player.add_loot(id, 3)
	ui.toggle()
	ui._pick_loot(0)
	ui._cycle(EquipSlot.Slot.HEAD)
	# colar e anel: compra, sobe o nível e equipa pelo inventário
	var lv0 := player.level
	ui._cycle(EquipSlot.Slot.ACCESSORIES)
	print("TESTE colar sem item: ", ui.info_label.text)
	for idq in ["colar_protecao", "anel_energia"]:
		player.give_item(idq)
	ui._cycle(EquipSlot.Slot.ACCESSORIES)
	print("TESTE colar nivel baixo: ", ui.info_label.text)
	player.level = 15
	ui._cycle(EquipSlot.Slot.ACCESSORIES)
	ui._cycle(EquipSlot.Slot.HANDS)
	var eqa := player.equipment.get_item(EquipSlot.Slot.ACCESSORIES)
	var eqh := player.equipment.get_item(EquipSlot.Slot.HANDS)
	print("TESTE colar/anel equipados: ", eqa.display_name if eqa else "nada", " / ", eqh.display_name if eqh else "nada")
	player.level = lv0
	player.shield_hp = 10.0
	player.shield_max = 20.0
	player.shield_els = [player.elem_a()]
	player._break_shield()
	print("TESTE escudo quebrado: ", player.shield_hp)
	Settings.auto["treino"] = true
	Settings.auto["treino_id"] = "luz:1"
	player._action_time = 0.0
	player.cds.erase("luz:1")
	player.mp = player.max_mp
	player._auto_t = 0.0
	var mpa := player.mp
	player._auto_play(0.2)
	print("TESTE treino gastou=", mpa - player.mp)
	var bon := get_tree().get_nodes_in_group("monsters").filter(func(q): return q.mtype == "boneco")
	print("TESTE bonecos=", bon.size(), " em ", bon.map(func(q): return Iso.to_grid(q.global_position).round()))
	Settings.auto["treino"] = false
	for mq in get_tree().get_nodes_in_group("monsters"):
		if not mq.info.get("dummy", false):
			mq.apply_effect("fogo", 30.0, player, false)
			mq._tint(0.1)
			mq._sfx._process(0.1)
			mq._sfx.queue_redraw()
			print("TESTE queimando partes=", mq._sfx.anchors().size())
			break
	player._roll_drop("Slime Rei")
	player._roll_drop("Goblin Elite")
	for n in get_tree().get_nodes_in_group("actors"):
		if n is Npc and n.role == "mercador":
			dlg.open(n, player)
			for t in ["itens", "vender"]:
				dlg._tab = t
				dlg._render("")
			dlg._sell_all()
			dlg.close()
			break
	ui.toggle()
	gm.toggle()
	gm._show(1)
	# teste da barra: põe uma magia em cada uma das 8 casas tocando na tela de verdade
	var tr: SpellTree = gm._tree
	var res := []
	for j in 8:
		tr._sel_id = "luz:1" if j % 2 == 0 else "%s:1" % player.elem_a()
		var want := tr._sel_id
		for f in 3:
			await get_tree().process_frame
		if tr._slots.size() < 8:
			res.append("sem casas")
			break
		var r: Rect2 = tr._slots[j]
		var ev := InputEventScreenTouch.new()
		ev.pressed = true
		ev.position = tr.get_global_transform_with_canvas() * r.get_center()
		var evl := InputEventScreenTouch.new()
		evl.pressed = true
		evl.position = r.get_center()
		tr._gui_input(evl)
		await get_tree().process_frame
		var okj: bool = j < player.bar.size() and player.bar[j] == want
		if not okj:
			var hits := []
			for c in get_tree().root.find_children("*", "Control", true, false):
				if c.is_visible_in_tree() and c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.get_global_rect().has_point(ev.position):
					hits.append("%s(%s)" % [c.name, c.get_class()])
			res.append("%d:FALHOU bar=%s em=%s" % [j + 1, player.bar, hits])
		else:
			res.append("%d:ok" % (j + 1))
	print("TESTE barra ", res, " arvore=", tr.get_global_rect(), " tela=", get_viewport().get_visible_rect().size)
	gm.toggle()
	var lv := {}
	for m in get_tree().get_nodes_in_group("monsters"):
		var d := int(Iso.to_grid(m.home).distance_to(map.spawn) / 20.0) * 20
		lv[d] = maxi(int(lv.get(d, 0)), m.level)
	print("niveis por distancia: ", lv)
	print("TESTE UI ok: ouro=%d saque=%s" % [player.gold, player.loot])


func _free_tile(near: Vector2) -> Vector2:
	for r in range(0, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var gp := Vector2(floor(near.x) + dx + 0.5, floor(near.y) + dy + 0.5)
				if map.walkable_grid(gp) and gp.distance_to(map.spawn) > 1.2:
					return gp
	return near


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
	for i in [0, 1, 3, 4, 5]:
		gm._show(i)
		await get_tree().process_frame
		await get_tree().process_frame
	print("TESTE menu ok forca_max=", Perf.force_full, " habilidades=", player.skills.keys())
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


func _teste_magias() -> void:
	await get_tree().create_timer(0.3).timeout
	var m: Monster = null
	for c in get_tree().get_nodes_in_group("monsters"):
		if c.mtype != "boneco":
			m = c
			break
	for cl in MageClass.ORDER:
		player.classe = cl
		player._reset_skills()
		for k in player.skills:
			player.skills[k] = [40, 0.0]
		player.level = 20
		player._recalc()
		var ids: Array = []
		for e in Spellbook.elements_of(cl):
			for t in range(1, 7):
				ids.append("%s:%d" % [e, t])
		for t in range(1, 9):
			ids.append("luz:%d" % t)
		ids += ["fus:3", "fus:7", "fus:8"]
		var feitos := 0
		for id in ids:
			m.hp = m.max_hp
			m.dead = false
			player.global_position = m.global_position + Vector2(140, 40)
			player.foe = m
			player.mp = player.max_mp
			player.cds.clear()
			player._action_time = 0.0
			var mp0 := player.mp
			player.cast_spell(id)
			await get_tree().create_timer(0.7).timeout
			if player.mp < mp0:
				feitos += 1
		print("TESTE magias classe=", cl, " lancadas=", feitos, "/", ids.size(), " escudo=", int(player.shield_hp), " golem_vida=", int(m.hp), " barra=", player.bar)
	player.invis = false
	player.immortal_t = 0.0


func _teste_summon() -> void:
	await get_tree().create_timer(0.3).timeout
	for k in player.skills:
		player.skills[k] = [6, 0.0]
	player.level = 15
	player._recalc()
	var m: Monster = null
	for c in get_tree().get_nodes_in_group("monsters"):
		if c.mtype != "boneco":
			m = c
			break
	player.global_position = m.global_position + Vector2(200, 60)
	player.foe = m
	var xp0 := player.xp
	player.mp = player.max_mp
	player.cast_spell(player.elem_a() + ":5")
	player.mp = player.max_mp
	player.cast_spell(player.elem_b() + ":5")
	print("TESTE summon invocados=", player.summons.keys())
	await get_tree().create_timer(8.0).timeout
	var info := []
	for k in player.summons:
		var sm = player.summons[k]
		info.append([k, sm.display_name, int(sm.hp), int(sm.max_hp)])
	print("TESTE summon depois=", info, " xp_ganho=", player.xp - xp0)
	player.mp = player.max_mp
	player.cds.clear()
	player.cast_spell("fus:5")
	await get_tree().create_timer(0.5).timeout
	print("TESTE summon fundido=", player.summons.keys(), " rede=", player.summons_state())


func _teste_npc() -> void:
	await get_tree().create_timer(0.3).timeout
	var brann: Npc = null
	var lira: Npc = null
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.role == "mercador": brann = n
		else: lira = n
	print("TESTE npc brann=", Iso.to_grid(brann.position), " lira=", Iso.to_grid(lira.position), " spawn=", map.spawn)
	player.gold = 100
	var p0 := player.hp_pot
	NpcDialog.inst.open(brann, player)
	NpcDialog.inst._buy("hp", 5)
	NpcDialog.inst._buy("mp", 1)
	print("TESTE npc compra pocoes_vida=", player.hp_pot - p0, " ouro=", player.gold)
	player.task = {}
	NpcDialog.inst.open(lira, player)
	NpcDialog.inst._task()
	var tk: Dictionary = player.task
	var nm: String = Monster.TYPES[tk.type].name
	for i in int(tk.need):
		player.gain_xp(1, 0, nm)
	var xp0 := player.xp
	NpcDialog.inst._task()
	print("TESTE npc tarefa=", tk.type, " recompensa_xp=", player.xp - xp0, " tarefa_agora=", player.task)
	NpcDialog.inst.close()
	player.global_position = brann.global_position + Vector2(0, 40)
	NpcDialog.inst.open(brann, player)


func _teste_etapa1() -> void:
	await get_tree().create_timer(0.3).timeout
	for k in player.skills:
		player.skills[k] = [5, 0.0]
	player.level = 20
	player._recalc()
	player.hp = player.max_hp
	player.mp = player.max_mp
	player.cast_spell(player.elem_a() + ":3")
	print("TESTE escudo elementos=", player.shield_els, " absorcao=", int(player.shield_hp))
	player.shield_hp = 0.0
	var dm: Monster = null
	for c in get_tree().get_nodes_in_group("monsters"):
		if c.mtype == "boneco":
			dm = c
	player.global_position = dm.global_position + Vector2(160, 40)
	player.bar[4] = player.elem_a() + ":5"
	player.bar[5] = player.elem_b() + ":5"
	Settings.auto.summon_auto = true
	await get_tree().create_timer(6.0).timeout
	var hp0 := player.hp
	print("TESTE auto invocacoes=", player.summons.keys(), " vida_jogador=", int(player.hp), "/", int(player.max_hp))
	var sm = player.summons.values()[0]
	var shp: float = sm.hp
	await get_tree().create_timer(4.0).timeout
	print("TESTE boneco bate jogador_perdeu=", int(hp0 - player.hp), " (1%=", int(ceil(player.max_hp * 0.01)), ") invocacao_perdeu=", int(shp - sm.hp), " (1%=", int(ceil(sm.max_hp * 0.01)), ")")
	sm._die()
	player.cds.clear()
	player.mp = player.max_mp
	await get_tree().create_timer(2.0).timeout
	print("TESTE reinvoca depois de morrer=", player.summons.keys(), " boneco_no_lugar=", dm.global_position == dm.home)
	Settings.auto.summon_auto = false
