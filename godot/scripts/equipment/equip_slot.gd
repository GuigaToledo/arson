class_name EquipSlot
extends RefCounted
## Slots de equipamento do personagem.

enum Slot { HEAD, CHEST, SHOULDERS, HANDS, LEGS, FEET, CAPE, MAIN_HAND, OFF_HAND, ACCESSORIES }

const NAMES := {
	Slot.HEAD: "Cabeça",
	Slot.CHEST: "Peito",
	Slot.SHOULDERS: "Ombros",
	Slot.HANDS: "Luvas",
	Slot.LEGS: "Pernas",
	Slot.FEET: "Botas",
	Slot.CAPE: "Capa",
	Slot.MAIN_HAND: "Arma",
	Slot.OFF_HAND: "Escudo",
	Slot.ACCESSORIES: "Acessório",
}


static func slot_name(s: int) -> String:
	return NAMES.get(s, "?")


static func all() -> Array:
	return Slot.values()
