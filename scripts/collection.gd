extends RefCounted
## Colección del jugador: monedas, cosméticos que tiene y cuáles lleva puestos.
## Se guarda en el dispositivo (user://collection.json). Cuando haya cuentas, esto se sincroniza con el servidor.

const Cosmetics := preload("res://scripts/cosmetics.gd")

const PATH := "user://collection.json"

var coins := Cosmetics.START_COINS
var owned := {}  # id -> true
var equipped := Cosmetics.DEFAULTS.duplicate()
var boxes_opened := 0
var path := PATH  # los tests usan otro archivo
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func owns(id: String) -> bool:
	return Cosmetics.is_default(id) or owned.has(id)


func add_coins(amount: int) -> void:
	coins = maxi(0, coins + amount)


func can_open_box() -> bool:
	return coins >= Cosmetics.BOX_PRICE


## Abre una caja: cobra, sortea y entrega. Devuelve {item, duplicate, refund} o {} si no alcanzan las monedas.
func open_box() -> Dictionary:
	if not can_open_box():
		return {}
	coins -= Cosmetics.BOX_PRICE
	boxes_opened += 1
	var item := Cosmetics.roll(_rng)
	var duplicate := owns(item["id"])
	var refund := 0
	if duplicate:
		refund = Cosmetics.REFUND[item["rarity"]]
		coins += refund
	else:
		owned[item["id"]] = true
	return {"item": item, "duplicate": duplicate, "refund": refund}


## Se pone un cosmético (tiene que ser tuyo). Devuelve false si no lo tenés.
func equip(id: String) -> bool:
	var item := Cosmetics.item(id)
	if item.is_empty() or not owns(id):
		return false
	equipped[item["kind"]] = id
	return true


## Lo que se manda al servidor para que el rival lo vea.
func equipped_payload() -> Dictionary:
	return {"fx": equipped["fx"], "fo": equipped["fo"], "b": equipped["banner"], "n": equipped["font"]}


func load_from_disk() -> void:
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	coins = maxi(0, int(data.get("coins", coins)))
	boxes_opened = int(data.get("boxes", 0))
	owned = {}
	for id in data.get("owned", []):
		if not Cosmetics.item(str(id)).is_empty():
			owned[str(id)] = true
	var saved: Dictionary = data.get("equipped", {})
	for kind in Cosmetics.DEFAULTS:
		var id := str(saved.get(kind, Cosmetics.DEFAULTS[kind]))
		equipped[kind] = id if (Cosmetics.item(id).get("kind", "") == kind and owns(id)) else Cosmetics.DEFAULTS[kind]


func save_to_disk() -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"coins": coins, "boxes": boxes_opened, "owned": owned.keys(), "equipped": equipped}))
