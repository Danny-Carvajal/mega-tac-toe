extends Control
## Raíz de la app: decide qué pantalla se ve y conecta el menú, el juego y la red.

const Menu := preload("res://scripts/menu.gd")
const GameScreen := preload("res://scripts/game_screen.gd")
const NetClient := preload("res://scripts/net_client.gd")
const Profile := preload("res://scripts/profile.gd")
const Fx := preload("res://scripts/fx.gd")
const Stats := preload("res://scripts/stats.gd")

var profile := Profile.new()
var stats := Stats.new()
var net: Node
var current: Control
var menu: Control
var game_screen: Control
var _pending: Dictionary = {}
## Datos para volver a una partida si se cae la conexión.
var _token := ""
var _reconnecting := false
var _reconnect_started_ms := 0
var _next_attempt_ms := 0
var _probe_deadline_ms := 0
## true cuando la ventana es más ancha que alta (compu): layout horizontal.
var wide := false


func _ready() -> void:
	get_window().size_changed.connect(_update_layout)
	_update_layout()
	profile.load_from_disk()
	stats.load_from_disk()
	net = NetClient.new()
	add_child(net)
	net.connected.connect(_on_net_connected)
	net.disconnected.connect(_on_net_disconnected)
	net.message.connect(_on_net_message)
	show_menu()


const RECONNECT_WINDOW_MS := 75000  # un poco más que la gracia del servidor (60 s)
const RETRY_MS := 2000
const PROBE_MS := 4000


## Botón "atrás" de Android: en el menú cierra la app; en una partida local o
## terminada vuelve al menú; en una partida online en curso no hace nada
## (para no rendirse sin querer, hay que usar el botón Rendirse).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_probe_connection()
		return
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if game_screen == null:
		if menu == null or not menu.handle_back():
			get_tree().quit()
	elif not game_screen.online or game_screen.finished:
		show_menu()
	else:
		game_screen.ask_resign()


func show_menu(status: String = "") -> void:
	game_screen = null
	_token = ""
	_reconnecting = false
	menu = Menu.new()
	menu.profile = profile
	menu.stats = stats
	menu.local_requested.connect(_on_local_requested)
	menu.online_requested.connect(_on_online_requested)
	menu.cancel_requested.connect(_on_cancel_requested)
	_show(menu)
	if not status.is_empty():
		menu.set_status.call_deferred(status)


func _show(screen: Control) -> void:
	if current != null:
		current.queue_free()
	current = screen
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if screen.has_method("apply_layout"):
		screen.apply_layout(wide)
	Fx.fade_in(screen, 0.22)


## Elige el layout según la forma de la ventana: vertical (celular) o ancho (compu).
func _update_layout() -> void:
	var window := get_window()
	var is_wide := window.size.x > window.size.y * 1.1
	var base := Vector2i(1920, 1080) if is_wide else Vector2i(1080, 1920)
	if window.content_scale_size != base:
		window.content_scale_size = base
	if is_wide != wide:
		wide = is_wide
		if current != null and current.has_method("apply_layout"):
			current.apply_layout(wide)


func _on_local_requested() -> void:
	game_screen = GameScreen.new()
	game_screen.setup_local(profile)
	game_screen.exit_requested.connect(show_menu)
	_show(game_screen)


func _on_online_requested(kind: String, code: String) -> void:
	var payload := {"name": profile.player_name, "colors": profile.colors_payload()}
	match kind:
		"queue":
			payload["t"] = "queue"
		"create":
			payload["t"] = "create_room"
		"join":
			payload["t"] = "join_room"
			payload["code"] = code
	menu.set_busy(true)
	if net.is_open():
		net.send(payload)
		return
	_pending = payload
	menu.set_status("Conectando...")
	if net.connect_to_server(profile.server_url) != OK:
		_pending = {}
		menu.set_busy(false)
		menu.set_status("La dirección del servidor no es válida")


func _on_cancel_requested() -> void:
	_pending = {}
	net.send({"t": "leave"})
	menu.set_busy(false)
	menu.set_status("")


func _on_net_connected() -> void:
	if _reconnecting:
		net.send({"t": "resume", "token": _token})
		return
	if not _pending.is_empty():
		net.send(_pending)
		_pending = {}


func _on_net_disconnected() -> void:
	_pending = {}
	if _reconnecting:
		return  # un intento falló: _process vuelve a probar
	if game_screen != null and game_screen.online and not game_screen.finished and not _token.is_empty():
		_reconnecting = true
		_reconnect_started_ms = Time.get_ticks_msec()
		_next_attempt_ms = _reconnect_started_ms + 1000
		game_screen.set_reconnecting(true)
	elif game_screen != null:
		game_screen.on_disconnected()
	elif menu != null:
		menu.set_busy(false)
		menu.set_status("No pude conectar con el servidor")


func _on_net_message(data: Dictionary) -> void:
	_probe_deadline_ms = 0
	match str(data.get("t", "")):
		"waiting":
			if game_screen == null:
				menu.set_status("Buscando rival...")
		"room":
			if game_screen == null:
				menu.set_status("Sala %s. Pasale el código a tu rival." % data.get("code", ""))
		"error":
			if game_screen == null:
				menu.set_busy(false)
				menu.set_status(str(data.get("msg", "Error")))
			else:
				game_screen.show_notice(str(data.get("msg", "Error")))
		"start":
			_start_online(data)
		"move":
			if game_screen != null:
				game_screen.apply_move(data)
		"skip":
			if game_screen != null:
				game_screen.apply_skip(data)
		"over":
			_token = ""
			_reconnecting = false
			if game_screen != null:
				_record_result(data)
				game_screen.apply_over(data)
		"resume_ok":
			_reconnecting = false
			if game_screen != null:
				game_screen.apply_resume(data)
		"resume_failed":
			_give_up_reconnecting()
		"opponent":
			if game_screen != null:
				game_screen.set_opponent_connected(bool(data.get("connected", true)))


func _start_online(start: Dictionary) -> void:
	_token = str(start.get("token", ""))
	game_screen = GameScreen.new()
	game_screen.setup_online(start, profile)
	game_screen.move_requested.connect(func(big: int, small: int) -> void:
		net.send({"t": "move", "big": big, "small": small}))
	game_screen.resign_requested.connect(func() -> void: net.send({"t": "resign"}))
	game_screen.exit_requested.connect(show_menu)
	_show(game_screen)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _reconnecting:
		if now - _reconnect_started_ms > RECONNECT_WINDOW_MS:
			_give_up_reconnecting()
		elif not net.is_busy() and not net.is_open() and now >= _next_attempt_ms:
			_next_attempt_ms = now + RETRY_MS
			net.connect_to_server(profile.server_url)
	if _probe_deadline_ms > 0 and now > _probe_deadline_ms:
		_probe_deadline_ms = 0
		net.force_drop()  # no contestó: la conexión estaba muerta aunque pareciera abierta


## Al volver a la app (o a la pestaña) se comprueba que la conexión siga viva.
func _probe_connection() -> void:
	if _reconnecting or game_screen == null or not game_screen.online or game_screen.finished:
		return
	if net != null and net.is_open():
		net.send({"t": "ping"})
		_probe_deadline_ms = Time.get_ticks_msec() + PROBE_MS


func _give_up_reconnecting() -> void:
	_reconnecting = false
	_token = ""
	net.close()
	if game_screen != null:
		game_screen.set_reconnecting(false)
		game_screen.on_disconnected()


## Anota el resultado de la partida online en las estadísticas (una sola vez por partida).
func _record_result(data: Dictionary) -> void:
	if game_screen.finished:
		return
	var winner := int(data.get("winner", 0))
	var result := "D" if winner == 0 else ("W" if winner == game_screen.my_seat else "L")
	stats.record(result)
	stats.save_to_disk()
