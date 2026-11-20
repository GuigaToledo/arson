extends Node
## Catálogo de itens (autoload "ItemDB"). Lê todos os .tres de res://data/items/.

const ITEMS_DIR := "res://data/items"

var items: Dictionary = {}


func _ready() -> void:
	var dir := DirAccess.open(ITEMS_DIR)
	if dir == null:
		push_error("ItemDB: pasta de itens não encontrada")
		return
	for f in dir.get_files():
		var file := f.trim_suffix(".remap")
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var res = load(ITEMS_DIR + "/" + file)
		if res is EquipmentItem:
			items[res.id] = res


func get_item(id) -> EquipmentItem:
	return items.get(StringName(str(id)))


func for_slot(slot: int) -> Array:
	var out: Array = []
	for it: EquipmentItem in items.values():
		if it.slot == slot:
			out.append(it)
	out.sort_custom(func(a, b): return String(a.id) < String(b.id))
	return out
