extends Node
## Cuentas de Mega Tac Toe. Dos formas de guardar:
##   - Supabase (REST), si están SUPABASE_URL y SUPABASE_KEY (la clave "service_role").
##   - Un archivo local (user://accounts.json), para desarrollo y tests.
## Cada cuenta: {username, display, salt, hash, data, trophies}. `data` es el paquete
## que arma el cliente (monedas, cosméticos, stats, historial).
##
## Tabla en Supabase (SQL):
##   create table accounts (
##     username text primary key, display text not null, salt text not null, hash text not null,
##     data jsonb not null default '{}'::jsonb, trophies int not null default 0,
##     updated_at timestamptz not null default now());
##   alter table accounts enable row level security;

const HASH_ROUNDS := 6000
const MAX_DATA_CHARS := 250000

var supabase_url := ""
var supabase_key := ""
var secret := "dev-secret"
var path := "user://accounts.json"
var _file_db := {}


func _init() -> void:
	supabase_url = OS.get_environment("SUPABASE_URL").strip_edges().trim_suffix("/")
	supabase_key = OS.get_environment("SUPABASE_KEY").strip_edges()
	var env_secret := OS.get_environment("AUTH_SECRET")
	if not env_secret.is_empty():
		secret = env_secret
	elif not supabase_key.is_empty():
		secret = supabase_key.sha256_text()


func _ready() -> void:
	if not uses_supabase():
		_load_file()


func uses_supabase() -> bool:
	return not supabase_url.is_empty() and not supabase_key.is_empty()


# --- Validación y claves ------------------------------------------------------

static func valid_username(name: String) -> bool:
	var regex := RegEx.create_from_string("^[A-Za-z0-9_]{3,16}$")
	return regex.search(name) != null


static func valid_password(password: String) -> bool:
	return password.length() >= 6 and password.length() <= 64


static func key_of(name: String) -> String:
	return name.to_lower()


func hash_password(password: String, salt: String) -> String:
	var digest := (salt + password).to_utf8_buffer()
	for i in HASH_ROUNDS:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(digest)
		ctx.update(salt.to_utf8_buffer())
		digest = ctx.finish()
	return digest.hex_encode()


func make_salt() -> String:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(16).hex_encode()


## Token sin estado: sirve mientras no cambie la contraseña, y sobrevive a reinicios del servidor.
func make_token(record: Dictionary) -> String:
	var key := key_of(str(record["username"]))
	return key + "." + (key + "|" + str(record["hash"]) + "|" + secret).sha256_text()


## Devuelve la cuenta si el token es válido, o {}.
func check_token(token: String) -> Dictionary:
	var key := token.get_slice(".", 0)
	if key.is_empty() or not token.contains("."):
		return {}
	var record: Dictionary = await get_account(key)
	if record.is_empty() or make_token(record) != token:
		return {}
	return record


# --- Operaciones --------------------------------------------------------------

func get_account(name: String) -> Dictionary:
	var key := key_of(name)
	if uses_supabase():
		var result: Dictionary = await _request(HTTPClient.METHOD_GET, "?username=eq.%s&select=*" % key.uri_encode())
		if result["ok"] and typeof(result["body"]) == TYPE_ARRAY and not result["body"].is_empty():
			return result["body"][0]
		return {}
	return _file_db.get(key, {}).duplicate(true)


## Crea la cuenta. Devuelve {ok, record} o {ok:false, error}.
func create_account(name: String, password: String, data: Dictionary) -> Dictionary:
	if not valid_username(name):
		return {"ok": false, "error": "El usuario va de 3 a 16 letras, números o guion bajo"}
	if not valid_password(password):
		return {"ok": false, "error": "La contraseña va de 6 a 64 caracteres"}
	var existing: Dictionary = await get_account(name)
	if not existing.is_empty():
		return {"ok": false, "error": "Ese usuario ya existe"}
	var salt := make_salt()
	var record := {
		"username": key_of(name), "display": name, "salt": salt,
		"hash": hash_password(password, salt), "data": data, "trophies": 0,
	}
	if uses_supabase():
		var result: Dictionary = await _request(HTTPClient.METHOD_POST, "", record)
		if not result["ok"]:
			return {"ok": false, "error": "No pude crear la cuenta, probá de nuevo"}
	else:
		_file_db[record["username"]] = record
		_save_file()
	return {"ok": true, "record": record}


## Revisa usuario y contraseña. Devuelve la cuenta o {}.
func login(name: String, password: String) -> Dictionary:
	var record: Dictionary = await get_account(name)
	if record.is_empty():
		return {}
	if hash_password(password, str(record["salt"])) != str(record["hash"]):
		return {}
	return record


func save_data(name: String, data: Dictionary) -> bool:
	if JSON.stringify(data).length() > MAX_DATA_CHARS:
		return false
	return await _patch(name, {"data": data})


func set_trophies(name: String, trophies: int) -> bool:
	return await _patch(name, {"trophies": maxi(trophies, 0)})


func _patch(name: String, fields: Dictionary) -> bool:
	var key := key_of(name)
	if uses_supabase():
		var body := fields.duplicate()
		body["updated_at"] = Time.get_datetime_string_from_system(true) + "Z"
		var result: Dictionary = await _request(HTTPClient.METHOD_PATCH, "?username=eq.%s" % key.uri_encode(), body)
		return result["ok"]
	if not _file_db.has(key):
		return false
	for field in fields.keys():
		_file_db[key][field] = fields[field]
	_save_file()
	return true


# --- Supabase -----------------------------------------------------------------

func _request(method: int, query: String, body: Variant = null) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	var headers := PackedStringArray([
		"apikey: " + supabase_key,
		"Content-Type: application/json",
		"Prefer: return=minimal" if method != HTTPClient.METHOD_GET else "Accept: application/json",
	])
	# Las claves nuevas (sb_secret_...) no son JWT: van solo en apikey. Las viejas (service_role) también llevan Authorization.
	if not supabase_key.begins_with("sb_"):
		headers.append("Authorization: Bearer " + supabase_key)
	var text := "" if body == null else JSON.stringify(body)
	var err := http.request(supabase_url + "/rest/v1/accounts" + query, headers, method, text)
	if err != OK:
		http.queue_free()
		return {"ok": false, "body": null}
	var response: Array = await http.request_completed
	http.queue_free()
	var code: int = response[1]
	var parsed: Variant = null
	var raw: PackedByteArray = response[3]
	if raw.size() > 0:
		parsed = JSON.parse_string(raw.get_string_from_utf8())
	if code < 200 or code >= 300:
		push_warning("Supabase respondió %d: %s" % [code, raw.get_string_from_utf8().left(200)])
	return {"ok": code >= 200 and code < 300, "body": parsed}


# --- Archivo local ------------------------------------------------------------

func _load_file() -> void:
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			_file_db = parsed


func _save_file() -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_file_db))
