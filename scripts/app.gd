extends Control
## Raíz de la app: decide qué pantalla se ve y conecta el menú, el juego y la red.

const Menu := preload("res://scripts/menu.gd")
const GameScreen := preload("res://scripts/game_screen.gd")
const NetClient := preload("res://scripts/net_client.gd")
const Profile := preload("res://scripts/profile.gd")

var profile := Profile.new()
var net: Node
var current: Control
var menu: Control
var game_screen: Control
var _pending: Dictionary = {}
## true cuando la ventana es más ancha que alta (compu): layout horizontal.
var wide := false


func _ready() -> void:
	get_window().size_changed.connect(_update_layout)
	_update_layout()
	profile.load_from_disk()
	net = NetClient.new()
	add_child(net)
	net.connected.connect(_on_net_connected)
	net.disconnected.connect(_on_net_disconnected)
	net.message.connect(_on_net_message)
	show_menu()


## Botón "atrás" de Android: en el menú cierra la app; en una partida local o
## terminada vuelve al menú; en una partida online en curso no hace nada
## (para no rendirse sin querer, hay que usar el botón Rendirse).
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if game_screen == null:
		if menu == null or not menu.handle_back():
			get_tree().quit()
	elif not game_screen.online or game_screen.finished:
		show_menu()


func show_menu(status: String = "") -> void:
	game_screen = null
	menu = Menu.new()
	menu.profile = profile
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
	if not _pending.is_empty():
		net.send(_pending)
		_pending = {}


func _on_net_disconnected() -> void:
	_pending = {}
	if game_screen != null:
		game_screen.on_disconnected()
	elif menu != null:
		menu.set_busy(false)
		menu.set_status("No pude conectar con el servidor")


func _on_net_message(data: Dictionary) -> void:
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
			if game_screen != null:
				game_screen.apply_over(data)


func _start_online(start: Dictionary) -> void:
	game_screen = GameScreen.new()
	game_screen.setup_online(start, profile)
	game_screen.move_requested.connect(func(big: int, small: int) -> void:
		net.send({"t": "move", "big": big, "small": small}))
	game_screen.resign_requested.connect(func() -> void: net.send({"t": "resign"}))
	game_screen.exit_requested.connect(show_menu)
	_show(game_screen)
