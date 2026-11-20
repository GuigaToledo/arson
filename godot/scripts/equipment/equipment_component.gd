class_name EquipmentComponent
extends Node
## Guarda o que o personagem está vestindo. Independente de movimento e combate.

signal equipment_changed(slot: int, item: EquipmentItem)

var _items: Dictionary = {}


func equip(item: EquipmentItem) -> bool:
	if item == null:
		return false
	_items[item.slot] = item
	equipment_changed.emit(item.slot, item)
	return true


func equip_to(slot: int, item: EquipmentItem) -> bool:
	if item != null and item.slot != slot:
		return false
	if item == null:
		unequip(slot)
		return true
	return equip(item)


func unequip(slot: int) -> EquipmentItem:
	var old: EquipmentItem = _items.get(slot)
	if old != null:
		_items.erase(slot)
		equipment_changed.emit(slot, null)
	return old


func get_item(slot: int) -> EquipmentItem:
	return _items.get(slot)


func all() -> Dictionary:
	return _items.duplicate()


func total_stats() -> Dictionary:
	var out := {}
	for it: EquipmentItem in _items.values():
		for k in it.stats:
			out[k] = out.get(k, 0) + it.stats[k]
	return out


## Formato compacto para salvar ou enviar pela rede: {slot: "id"}.
func to_ids() -> Dictionary:
	var out := {}
	for s in _items:
		out[s] = String(_items[s].id)
	return out


func load_ids(d: Dictionary) -> void:
	for s in EquipSlot.all():
		if d.has(s):
			equip(ItemDB.get_item(d[s]))
		elif _items.has(s):
			unequip(s)
