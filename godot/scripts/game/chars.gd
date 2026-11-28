class_name Chars
extends RefCounted
## Até 4 personagens por navegador, cada um com o seu arquivo de progresso.

const MAX := 4
const OLD_PATH := "user://arson_jogador.cfg"

## Vaga em uso (1 a 4) e nome do personagem dela.
static var slot := 1
static var nome := ""


static func path(n := -1) -> String:
	return "user://arson_p%d.cfg" % (slot if n < 0 else n)


## O progresso de antes das vagas vira o personagem 1.
static func migrate() -> void:
	if FileAccess.file_exists(OLD_PATH) and not FileAccess.file_exists(path(1)):
		DirAccess.copy_absolute(OLD_PATH, path(1))
		DirAccess.remove_absolute(OLD_PATH)
		# o nome que já era usado na rede vira o nome do personagem 1
		if OS.has_feature("web") and JavaScriptBridge.eval("typeof window.ArsonNet !== 'undefined'", true):
			var nm := str(JavaScriptBridge.get_interface("ArsonNet").savedName()).strip_edges()
			if nm != "":
				var c := ConfigFile.new()
				if c.load(path(1)) == OK:
					c.set_value("jogador", "nome", nm)
					c.save(path(1))


static func info(n: int) -> Dictionary:
	var c := ConfigFile.new()
	if c.load(path(n)) != OK:
		return {"existe": false}
	var cl := str(c.get_value("jogador", "classe", "fogo"))
	return {
		"existe": true,
		"classe": cl if MageClass.valid(cl) else "fogo",
		"nome": str(c.get_value("jogador", "nome", "Personagem %d" % n)),
		"nivel": Rules.level_for(int(c.get_value("jogador", "xp", 0))),
	}


static func create(n: int, classe: String, nm: String) -> void:
	var c := ConfigFile.new()
	c.set_value("jogador", "classe", classe)
	c.set_value("jogador", "nome", nm)
	c.set_value("jogador", "xp", 0)
	c.save(path(n))


static func delete(n: int) -> void:
	if FileAccess.file_exists(path(n)):
		DirAccess.remove_absolute(path(n))


## Escolhe a vaga para jogar.
static func use(n: int) -> void:
	slot = n
	nome = str(info(n).get("nome", ""))


## Equipamento vestido salvo do personagem da vaga ({espaço: id}); vazio se ainda não salvou.
static func equip_ids(n: int) -> Dictionary:
	var c := ConfigFile.new()
	if c.load(path(n)) != OK:
		return {}
	var eq = c.get_value("jogador", "equip", {})
	return eq if eq is Dictionary else {}
