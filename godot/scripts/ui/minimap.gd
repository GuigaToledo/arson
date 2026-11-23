extends Control
## Minimapa (canto de cima à direita do HUD).
## Textura de 1 pixel por tile, no mesmo losango isométrico da tela, centrada no jogador.

## WorldMap (godot/scripts/world/world_map.gd): .w, .h, .at(x, y) -> String (1 caractere por tile).
var map
## Jogador (Player): .global_position, .facing (String "E","SE","S",...), .dead.
var player: Node2D

var _tex: ImageTexture
var _ex := Vector2.ZERO
var _ey := Vector2.ZERO
var _origem := Vector2.ZERO
var _acc := 0.0

## No máximo 10 redesenhos por segundo.
const INTERVALO := 0.1
## Tiles de grade até a borda esquerda/direita (em cima e embaixo cabe cerca do dobro, pelo 2:1).
const RAIO_TILES := 45.0
const MOLDURA := Color(0.7, 0.55, 0.32)
const FUNDO := Color(0, 0, 0, 0.6)
const COR_NENHUMA := Color(0.13, 0.12, 0.12)

const C_AGUA := Color(0.07, 0.13, 0.22)
const C_AREIA := Color(0.46, 0.40, 0.26)
const C_GRAMA := Color(0.22, 0.32, 0.16)
const C_TERRA := Color(0.36, 0.28, 0.17)
const C_CALCA := Color(0.56, 0.53, 0.48)
const C_FLORESTA := Color(0.10, 0.22, 0.10)
const C_SELVA := Color(0.05, 0.14, 0.07)
const C_ROCHA := Color(0.33, 0.31, 0.29)
const C_PAREDE := Color(0.04, 0.04, 0.045)
const C_CAVERNA := Color(0.18, 0.16, 0.15)
const C_CEMITERIO := Color(0.22, 0.26, 0.20)
const C_CASA := Color(0.40, 0.25, 0.13)
const C_TEMPLO := Color(0.58, 0.46, 0.18)
const C_PONTE := Color(0.45, 0.32, 0.16)
const C_CAMP_B := Color(0.34, 0.26, 0.15)
const C_CAMP_O := Color(0.30, 0.20, 0.12)
const C_CAMP_Y := Color(0.40, 0.32, 0.17)


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	clip_contents = true
	texture_filter = TEXTURE_FILTER_NEAREST


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	clip_contents = true
	texture_filter = TEXTURE_FILTER_NEAREST
	if _tex != null:
		queue_redraw()


func setup(m, p) -> void:
	map = m
	player = p
	_montar()
	queue_redraw()


## Monta a textura inteira uma vez (1 pixel por tile).
func _montar() -> void:
	_tex = null
	if map == null:
		return
	var mw: int = int(map.w)
	var mh: int = int(map.h)
	if mw < 1 or mh < 1:
		return
	var img := Image.create(mw, mh, false, Image.FORMAT_RGBA8)
	for y in mh:
		for x in mw:
			var ch: String = str(map.at(x, y))
			img.set_pixel(x, y, _cor(ch))
	_tex = ImageTexture.create_from_image(img)


func _cor(ch: String) -> Color:
	match ch:
		"~":
			return C_AGUA
		",":
			return C_AREIA
		".", "@":
			return C_GRAMA
		":":
			return C_TERRA
		"#":
			return C_CALCA
		"f":
			return C_FLORESTA
		"j":
			return C_SELVA
		"r":
			return C_ROCHA
		"R":
			return C_PAREDE
		"k":
			return C_CAVERNA
		"g":
			return C_CEMITERIO
		"H":
			return C_CASA
		"T":
			return C_TEMPLO
		"=":
			return C_PONTE
		"b":
			return C_CAMP_B
		"o":
			return C_CAMP_O
		"y":
			return C_CAMP_Y
		_:
			return COR_NENHUMA


func _process(delta: float) -> void:
	_acc += delta
	if _acc < INTERVALO:
		return
	_acc = 0.0
	queue_redraw()


func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), FUNDO, true)
	if _tex != null and player != null and is_instance_valid(player):
		_projecao()
		# Losango: eixo X da grade = (1, 0.5)*k, eixo Y = (-1, 0.5)*k. O jogador cai no centro.
		draw_set_transform_matrix(Transform2D(_ex, _ey, _origem))
		draw_texture(_tex, Vector2.ZERO)
		draw_set_transform_matrix(Transform2D())
		_marcadores()
		_seta()
	_moldura()


## k deixa uns 45 tiles de raio na horizontal, seja qual for o size do Control.
func _projecao() -> void:
	var meio: float = minf(size.x, size.y) * 0.5
	var k: float = meio / (RAIO_TILES * sqrt(2.0))
	_ex = Vector2(1.0, 0.5) * k
	_ey = Vector2(-1.0, 0.5) * k
	var g: Vector2 = Iso.to_grid(player.global_position)
	_origem = size * 0.5 - _ex * g.x - _ey * g.y


## Posição de tela (mundo) -> ponto local do minimapa, com a mesma projeção da textura.
func _no_mapa(tela: Vector2) -> Vector2:
	var g: Vector2 = Iso.to_grid(tela)
	return _origem + _ex * g.x + _ey * g.y


func _dentro(p: Vector2) -> bool:
	return p.x >= 3.0 and p.y >= 3.0 and p.x <= size.x - 3.0 and p.y <= size.y - 3.0


func _marcadores() -> void:
	var arvore := get_tree()
	if arvore == null:
		return
	_monstros(arvore)
	_pontos(arvore, "npcs", Color(0.95, 0.95, 0.92), 1.8)
	_pontos(arvore, "remote_players", Color(0.30, 0.74, 0.32), 2.1)


func _monstros(arvore: SceneTree) -> void:
	var lista := arvore.get_nodes_in_group("monsters")
	for i in lista.size():
		var n: Node = lista[i]
		if not is_instance_valid(n) or not (n is Node2D):
			continue
		if bool(n.get("dead")):
			continue
		var corpo := n as Node2D
		var p: Vector2 = _no_mapa(corpo.global_position)
		if not _dentro(p):
			continue
		if bool(n.get("boss")):
			# Contorno escuro + miolo vermelho-alaranjado, maior que o monstro comum.
			ElemArt.circle(self, p, 4.2, Color(0.22, 0.07, 0.03))
			ElemArt.circle(self, p, 2.7, Color(0.88, 0.34, 0.10))
		else:
			ElemArt.circle(self, p, 1.7, Color(0.75, 0.16, 0.12))


func _pontos(arvore: SceneTree, grupo: String, cor: Color, raio: float) -> void:
	var lista := arvore.get_nodes_in_group(grupo)
	for i in lista.size():
		var n: Node = lista[i]
		if not is_instance_valid(n) or not (n is Node2D):
			continue
		var corpo := n as Node2D
		var p: Vector2 = _no_mapa(corpo.global_position)
		if not _dentro(p):
			continue
		ElemArt.circle(self, p, raio, cor)


## Triângulo na direção da tela de player.facing (Iso.dir_vector). Sombra para ler em chão claro.
func _seta() -> void:
	var face := str(player.get("facing"))
	if not Iso.DIRS.has(face):
		face = "S"
	var dir: Vector2 = Iso.dir_vector(face)
	if dir.length_squared() < 0.01:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var c := size * 0.5
	var lado := Vector2(-dir.y, dir.x)
	var sombra := PackedVector2Array([
		c + dir * 8.2,
		c - dir * 5.2 + lado * 5.0,
		c - dir * 5.2 - lado * 5.0,
	])
	var pts := PackedVector2Array([
		c + dir * 6.6,
		c - dir * 4.2 + lado * 3.8,
		c - dir * 4.2 - lado * 3.8,
	])
	ElemArt.poly(self, sombra, Color(0.08, 0.05, 0.02))
	ElemArt.poly(self, pts, Color(1.0, 0.91, 0.48))


func _moldura() -> void:
	var b := 2.0
	draw_rect(Rect2(0, 0, size.x, b), MOLDURA, true)
	draw_rect(Rect2(0, size.y - b, size.x, b), MOLDURA, true)
	draw_rect(Rect2(0, 0, b, size.y), MOLDURA, true)
	draw_rect(Rect2(size.x - b, 0, b, size.y), MOLDURA, true)
