class_name EquipmentItem
extends Resource
## Definição de um equipamento. Cada item é um arquivo .tres em res://data/items/.
## Para criar um item novo basta criar um .tres novo: nenhum código do personagem muda.

const ALL_DIRS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const MIRROR := {"E": "W", "W": "E", "NE": "NW", "NW": "NE", "SE": "SW", "SW": "SE", "N": "N", "S": "S"}

@export var id: StringName
@export var display_name: String = ""
## armadura, arma, escudo, acessório...
@export var item_type: String = "armadura"
## Slot compatível.
@export var slot: EquipSlot.Slot = EquipSlot.Slot.CHEST

@export_group("Sprites")
## Animações nomeadas "<animação>_<direção>", ex.: "walk_SE". Vazio = arte provisória.
@export var sprite_frames: SpriteFrames
@export var directions: PackedStringArray = PackedStringArray(ALL_DIRS)
@export var animations: PackedStringArray = PackedStringArray(["idle", "walk", "run", "attack", "cast", "spell", "damage", "death"])
## Ordem extra de desenho dentro do slot (desempate).
@export var render_layer: int = 0
## Ponto de ancoragem do sprite em relação aos pés do personagem.
@export var anchor: Vector2 = Vector2.ZERO
## Ajuste fino por direção: {"SE": Vector2(2, -1)}.
@export var dir_offsets: Dictionary = {}

@export_group("Atributos")
@export var stats: Dictionary = {}

@export_group("Arte provisória")
@export var placeholder_style: StringName = &""
@export var placeholder_color: Color = Color(0.3, 0.3, 0.3)
@export var placeholder_accent: Color = Color(1.0, 0.5, 0.1)
## Intensidade da luz emitida (cajado, núcleo de fogo). 0 = sem luz.
@export var glow: float = 0.0


func supports(anim: String) -> bool:
	return animations.has(anim)


## Escolhe a animação para a direção; se faltar, usa a direção espelhada.
func resolve(anim: String, dir: String) -> Dictionary:
	if not supports(anim):
		anim = "idle"
	if directions.has(dir):
		return {"name": "%s_%s" % [anim, dir], "flip": false}
	var m: String = MIRROR.get(dir, dir)
	if directions.has(m):
		return {"name": "%s_%s" % [anim, m], "flip": true}
	return {"name": "", "flip": false}
