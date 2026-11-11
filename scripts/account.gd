extends Node
## Cuenta del jugador: registro, login y sincronización con el servidor.
## Usa su propia conexión (aparte de la de las partidas). Si hay sesión, cada cambio en
## monedas, cosméticos, stats, historial o perfil se sube solo a los pocos segundos.

signal changed       # cambió el estado (entró, salió, error, sincronizó)
signal data_applied  # se bajaron datos de la cuenta y se pisó lo local

const NetClient := preload("res://scripts/net_client.gd")
const Cosmetics := preload("res://scripts/cosmetics.gd")
const Profile := preload("res://scripts/profile.gd")
const CHECK_MS := 3000

var profile
var stats
var history
var collection

var path := "user://account.json"
var user := ""
var token := ""
var trophies := 0
var status := ""
var busy := false
var _fresh := false  # true mientras se espera la respuesta de un login/registro/arranque

var _net: Node
var _queue: Array = []
var _authed := false
var _last_check_ms := 0
var _synced_signature := ""
var _connecting_url := ""


func is_logged_in() -> bool:
	return not user.is_empty() and not token.is_empty()


func _ready() -> void:
	_net = NetClient.new()
	add_child(_net)
	_net.connected.connect(_on_connected)
	_net.disconnected.connect(func() -> void:
		_authed = false
		if busy:
			busy = false
			_fresh = false
			status = "No pude conectar con el servidor, probá de nuevo."
			_queue = _queue.filter(func(item: Dictionary) -> bool: return not item["plain"])
			changed.emit())
	_net.message.connect(_on_message)
	_load()


## Se llama cuando ya están cargados los datos locales: si había sesión guardada, la retoma.
func start() -> void:
	if is_logged_in():
		status = "Entrando..."
		busy = true
		_fresh = true
		_send({"t": "auth", "token": token}, true)
		changed.emit()


func register(name: String, password: String) -> void:
	busy = true
	status = "Creando cuenta..."
	_fresh = true
	changed.emit()
	_send({"t": "register", "user": name, "pass": password, "data": build_data()}, true)


func login(name: String, password: String) -> void:
	busy = true
	status = "Entrando..."
	_fresh = true
	changed.emit()
	_send({"t": "login", "user": name, "pass": password}, true)


func logout() -> void:
	if _net.is_open():
		_net.send({"t": "logout"})
	user = ""
	token = ""
	trophies = 0
	status = ""
	_authed = false
	_queue.clear()
	_save()
	changed.emit()


## Sube los datos ya mismo (el botón "Guardar ahora").
func sync_now() -> void:
	if not is_logged_in():
		return
	_synced_signature = _signature()
	_send({"t": "save", "data": build_data()}, false)


func _process(_delta: float) -> void:
	if not is_logged_in() or busy:
		return
	var now := Time.get_ticks_msec()
	if now - _last_check_ms < CHECK_MS:
		return
	_last_check_ms = now
	if _signature() != _synced_signature:
		sync_now()


# --- Conexión -----------------------------------------------------------------

## `plain` = mensaje que no necesita sesión previa (auth, login, register).
func _send(msg: Dictionary, plain: bool) -> void:
	_queue.append({"msg": msg, "plain": plain})
	if _net.is_open():
		_flush()
	elif not _net.is_busy():
		var err: int = _net.connect_to_server(profile.server_url)
		if err != OK:
			_fail("No pude conectarme al servidor")


func _on_connected() -> void:
	_authed = false
	# En una conexión nueva, lo primero es retomar la sesión si ya había una.
	if is_logged_in() and not _has_plain_auth():
		_net.send({"t": "auth", "token": token})
	_flush()


func _has_plain_auth() -> bool:
	for item in _queue:
		if item["plain"]:
			return true
	return false


func _flush() -> void:
	var rest: Array = []
	for item in _queue:
		if item["plain"] or _authed:
			_net.send(item["msg"])
		else:
			rest.append(item)
	_queue = rest


func _fail(text: String) -> void:
	busy = false
	status = text
	changed.emit()


func _on_message(data: Dictionary) -> void:
	match str(data.get("t", "")):
		"auth":
			_authed = true
			busy = false
			if not _fresh:
				# Reconexión: solo se retoma la sesión, lo local manda.
				trophies = int(data.get("trophies", trophies))
				_flush()
				return
			_fresh = false
			user = str(data.get("user", ""))
			token = str(data.get("token", ""))
			trophies = int(data.get("trophies", 0))
			var server_data = data.get("data", {})
			if bool(data.get("created", false)):
				status = "Cuenta creada. Ya se guarda todo solo."
			elif typeof(server_data) == TYPE_DICTIONARY and server_data.has("coins"):
				apply_data(server_data)
				status = "Sesión iniciada: bajé lo de tu cuenta."
			else:
				status = "Sesión iniciada."
				_synced_signature = ""
			if bool(data.get("created", false)) or (typeof(server_data) == TYPE_DICTIONARY and server_data.has("coins")):
				_synced_signature = _signature()
			_save()
			_flush()
			changed.emit()
		"auth_error":
			busy = false
			_fresh = false
			status = str(data.get("msg", "No pude entrar"))
			if bool(data.get("expired", false)):
				user = ""
				token = ""
				_save()
			_queue = _queue.filter(func(item: Dictionary) -> bool: return item["plain"])
			changed.emit()
		"saved":
			if bool(data.get("ok", false)):
				status = "Guardado en tu cuenta."
			else:
				status = "No se pudo guardar, reintento."
				_synced_signature = ""
			changed.emit()


# --- Datos --------------------------------------------------------------------

func build_data() -> Dictionary:
	return {
		"coins": collection.coins,
		"boxes": collection.boxes_opened,
		"owned": collection.owned.keys(),
		"equipped": collection.equipped,
		"stats": {
			"w": stats.wins, "l": stats.losses, "d": stats.draws,
			"streak": stats.streak, "best": stats.best_streak, "recent": "".join(stats.recent),
		},
		"history": history.games,
		"profile": {
			"name": profile.player_name,
			"x": "#" + profile.color_x.to_html(false),
			"o": "#" + profile.color_o.to_html(false),
		},
	}


## Pisa lo local con lo de la cuenta.
func apply_data(data: Dictionary) -> void:
	collection.coins = maxi(0, int(data.get("coins", collection.coins)))
	collection.boxes_opened = int(data.get("boxes", 0))
	collection.owned = {}
	for id in data.get("owned", []):
		if not Cosmetics.item(str(id)).is_empty():
			collection.owned[str(id)] = true
	var saved: Dictionary = data.get("equipped", {})
	for kind in Cosmetics.DEFAULTS:
		var id := str(saved.get(kind, Cosmetics.DEFAULTS[kind]))
		collection.equipped[kind] = id if (Cosmetics.item(id).get("kind", "") == kind and collection.owns(id)) else Cosmetics.DEFAULTS[kind]
	collection.save_to_disk()
	var s: Dictionary = data.get("stats", {})
	stats.wins = int(s.get("w", 0))
	stats.losses = int(s.get("l", 0))
	stats.draws = int(s.get("d", 0))
	stats.streak = int(s.get("streak", 0))
	stats.best_streak = int(s.get("best", 0))
	stats.recent = []
	for item in str(s.get("recent", "")):
		if item in ["W", "L", "D"]:
			stats.recent.append(item)
	stats.save_to_disk()
	var games = data.get("history", [])
	history.games = games if typeof(games) == TYPE_ARRAY else []
	history.save_to_disk()
	var p: Dictionary = data.get("profile", {})
	if p.has("name"):
		profile.player_name = str(p["name"]).left(16)
	if p.has("x"):
		profile.color_x = Color.html(str(p["x"]))
	if p.has("o"):
		profile.color_o = Color.html(str(p["o"]))
	profile.save_to_disk()
	data_applied.emit()


## Huella barata de lo que se sube: si cambia, hay algo nuevo para guardar.
func _signature() -> String:
	return "%d|%d|%d|%s|%d,%d,%d,%d|%d|%d|%s|%s|%s" % [
		collection.coins, collection.boxes_opened, collection.owned.size(), JSON.stringify(collection.equipped),
		stats.wins, stats.losses, stats.draws, stats.best_streak,
		history.games.size(), int(history.games[0].get("t", 0)) if not history.games.is_empty() else 0,
		profile.player_name, profile.color_x.to_html(false), profile.color_o.to_html(false)]


func _save() -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"user": user, "token": token}))


func _load() -> void:
	if not FileAccess.file_exists(path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) == TYPE_DICTIONARY:
		user = str(data.get("user", ""))
		token = str(data.get("token", ""))
