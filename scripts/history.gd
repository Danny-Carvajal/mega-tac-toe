extends RefCounted
## Historial de partidas, guardado en el dispositivo (user://history.json).
##
## Cada partida es un registro chiquito. Las jugadas van en un byte cada una (big * 9 + small, de 0 a 80;
## 255 = salto de turno) y todo junto se guarda como texto base64: una partida de 40 jugadas pesa ~60
## caracteres. Más adelante, con cuentas de usuario, estos mismos registros se pueden subir al servidor.

const PATH := "user://history.json"
const MAX_GAMES := 300
const SKIP_BYTE := 255

## Más nueva primero.
var games: Array = []


## Jugadas ([big, small] o "s") -> texto compacto.
static func encode(log: Array) -> String:
	var bytes := PackedByteArray()
	for entry in log:
		if entry is Array:
			bytes.append(int(entry[0]) * 9 + int(entry[1]))
		else:
			bytes.append(SKIP_BYTE)
	return Marshalls.raw_to_base64(bytes)


## Texto compacto -> jugadas ([big, small] o "s").
static func decode(text: String) -> Array:
	var log: Array = []
	if text.is_empty():
		return log
	for value in Marshalls.base64_to_raw(text):
		if value == SKIP_BYTE:
			log.append("s")
		elif value <= 80:
			log.append([value / 9, value % 9])
	return log


## Arma el registro de una partida terminada.
static func make_record(names: Array, colors: Array, my_seat: int, winner: int, reason: String, log: Array) -> Dictionary:
	return {
		"t": int(Time.get_unix_time_from_system()),
		"n": names,
		"c": colors,
		"me": my_seat,
		"w": winner,
		"r": reason,
		"m": encode(log),
	}


func add(record: Dictionary) -> void:
	games.push_front(record)
	if games.size() > MAX_GAMES:
		games.resize(MAX_GAMES)


func load_from_disk() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) == TYPE_ARRAY:
		games = data


func save_to_disk() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(games))


## "10/11 21:50" en hora local.
static func format_time(unix_time: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var d := Time.get_datetime_dict_from_unix_time(unix_time + bias * 60)
	return "%02d/%02d %02d:%02d" % [d["day"], d["month"], d["hour"], d["minute"]]
