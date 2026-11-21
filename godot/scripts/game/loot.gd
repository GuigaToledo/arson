class_name Loot
## Saque das criaturas (data/saque.json): materiais que caem dos monstros e
## são vendidos ao Brann. A bolsa de saque tem espaços limitados, cada um empilha até 100.

const SLOTS := 30
const STACK := 100
static var DATA := _load()


static func _load() -> Dictionary:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/saque.json"))
	if not raw is Dictionary:
		push_error("saque.json inválido")
		return {}
	for k in raw:
		raw[k].cor = Color.html(str(raw[k].cor))
	return raw


static func nome(id: String) -> String:
	return str(DATA[id].nome) if DATA.has(id) else id


static func preco(id: String) -> int:
	return int(DATA[id].preco) if DATA.has(id) else 1


static func cor(id: String) -> Color:
	return DATA[id].cor if DATA.has(id) else Color.GRAY


static func forma(id: String) -> String:
	return str(DATA[id].forma) if DATA.has(id) else "pedra"
