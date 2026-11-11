extends Control
## Raíz de la app: decide qué pantalla se ve y conecta el menú, el juego y la red.

const Menu := preload("res://scripts/menu.gd")
const GameScreen := preload("res://scripts/game_screen.gd")
const NetClient := preload("res://scripts/net_client.gd")
const Profile := preload("res://scripts/profile.gd")
const Fx := preload("res://scripts/fx.gd")
const Pal := preload("res://scripts/pal.gd")
const Stats := preload("res://scripts/stats.gd")
const History := preload("res://scripts/history.gd")
const HistoryScreen := preload("res://scripts/history_screen.gd")
const UltimateGame := preload("res://scripts/ultimate_game.gd")
const Collection := preload("res://scripts/collection.gd")
const Account := preload("res://scripts/account.gd")
const AccountScreen := preload("res://scripts/account_screen.gd")
const Cosmetics := preload("res://scripts/cosmetics.gd")
const ShopScreen := preload("res://scripts/shop_screen.gd")

var profile := Profile.new()
var stats := Stats.new()
var history := History.new()
var collection := Collection.new()
var account: Account
## Pantalla auxiliar abierta desde el menú: "" ninguna, "history" lista, "replay" repetición.
var _view := ""
var net: Node
var current: Control
var menu: Control
var game_screen: Control
var _pending: Dictionary = {}
## Datos para volver a una partida si se cae la conexión.
var _token := ""
var _restore_sent := false
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
	Pal.apply(profile.light_mode)
	stats.load_from_disk()
	history.load_from_disk()
	collection.load_from_disk()
	account = Account.new()
	account.profile = profile
	account.stats = stats
	account.history = history
	account.collection = collection
	add_child(account)
	account.data_applied.connect(_on_account_data)
	account.changed.connect(_on_account_changed)
	account.start()
	net = NetClient.new()
	add_child(net)
	net.connected.connect(_on_net_connected)
	net.disconnected.connect(_on_net_disconnected)
	net.message.connect(_on_net_message)
	if account.is_logged_in():
		show_menu()
	else:
		show_login_gate()


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
	if _view == "shop" or _view == "account":
		show_menu()
	elif _view == "replay":
		show_history()
	elif _view == "history":
		show_menu("", 2)
	elif game_screen == null:
		if menu == null or not menu.handle_back():
			get_tree().quit()
	elif not game_screen.online or game_screen.finished:
		show_menu()
	else:
		game_screen.ask_resign()


func show_menu(status: String = "", page := 1) -> void:
	_enforce_name()
	game_screen = null
	_view = ""
	_token = ""
	_reconnecting = false
	menu = Menu.new()
	menu.profile = profile
	menu.stats = stats
	menu.collection = collection
	menu.account = account
	menu.account_requested.connect(show_account)
	menu.history_requested.connect(show_history)
	menu.appearance_changed.connect(func() -> void:
		Pal.apply(profile.light_mode)
		show_menu()
		menu.open_settings.call_deferred())
	menu.local_requested.connect(_on_local_requested)
	menu.shop_requested.connect(show_shop)
	menu.practice_requested.connect(_on_practice_requested)
	menu.online_requested.connect(_on_online_requested)
	menu.cancel_requested.connect(_on_cancel_requested)
	_show(menu)
	if page != 1:
		menu.set_page.call_deferred(page, false)
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


## Lista de partidas guardadas (se abre desde la pantalla de estadísticas).
func show_history() -> void:
	if menu != null and is_instance_valid(menu) and menu.cancel_button.visible:
		_on_cancel_requested()  # si estaba buscando rival, se cancela antes de salir del menú
	menu = null
	game_screen = null
	_view = "history"
	var screen := HistoryScreen.new()
	screen.history = history
	screen.back_requested.connect(func() -> void: show_menu("", 2))
	screen.game_selected.connect(show_replay)
	_show(screen)


## Tienda y colección (monedas, cajas y cosméticos).
func show_shop() -> void:
	if menu != null and is_instance_valid(menu) and menu.cancel_button.visible:
		_on_cancel_requested()
	menu = null
	game_screen = null
	_view = "shop"
	var screen := ShopScreen.new()
	screen.collection = collection
	screen.profile = profile
	screen.back_requested.connect(func() -> void: show_menu())
	_show(screen)


## El nombre en partida es el de la cuenta, o "Guest" sin sesión.
func _enforce_name() -> void:
	var wanted: String = account.user if account.is_logged_in() else "Guest"
	if profile.player_name != wanted:
		profile.player_name = wanted
		profile.save_to_disk()


## Pantalla de arranque: entrar, crear cuenta o seguir de invitado.
func show_login_gate() -> void:
	menu = null
	game_screen = null
	_view = "gate"
	var screen := AccountScreen.new()
	screen.account = account
	screen.gate = true
	screen.back_requested.connect(func() -> void: show_menu())
	screen.guest_requested.connect(func() -> void: show_menu())
	_show(screen)


## Si al abrir la app la sesión guardada ya no sirve, se vuelve a la pantalla de entrada.
func _on_account_changed() -> void:
	if _view == "" and menu != null and is_instance_valid(menu) and not account.is_logged_in() and not account.busy and not account.status.is_empty() and not menu.cancel_button.visible:
		account.status = "Tu sesión venció, entrá de nuevo."
		show_login_gate()


## Cuenta: entrar, crear o cerrar sesión.
func show_account() -> void:
	if menu != null and is_instance_valid(menu) and menu.cancel_button.visible:
		_on_cancel_requested()
	menu = null
	game_screen = null
	_view = "account"
	var screen := AccountScreen.new()
	screen.account = account
	screen.back_requested.connect(func() -> void: show_menu())
	screen.logged_out.connect(show_login_gate)
	_show(screen)


## Se bajaron datos de la cuenta: si se está en el menú, se redibuja con lo nuevo.
func _on_account_data() -> void:
	Pal.apply(profile.light_mode)
	if _view == "" and game_screen == null and menu != null and is_instance_valid(menu) and not menu.cancel_button.visible:
		show_menu()


func show_replay(record: Dictionary) -> void:
	_view = "replay"
	game_screen = null
	var replay_screen := GameScreen.new()
	replay_screen.setup_replay(record)
	replay_screen.exit_requested.connect(show_history)
	_show(replay_screen)


func _on_local_requested() -> void:
	game_screen = GameScreen.new()
	game_screen.setup_local(profile, collection.equipped_payload())
	game_screen.exit_requested.connect(show_menu)
	_show(game_screen)


func _on_practice_requested(level: int) -> void:
	game_screen = GameScreen.new()
	game_screen.setup_practice(profile, level, collection.equipped_payload())
	game_screen.practice_over.connect(_on_practice_over)
	game_screen.exit_requested.connect(show_menu)
	_show(game_screen)


## Ganar en práctica da pocas monedas según el nivel de la IA; perder o empatar no da.
func _on_practice_over(won: bool, level: int) -> void:
	if not won:
		return
	var coins: int = Cosmetics.COINS_PRACTICE_WIN[clampi(level, 1, 5) - 1]
	collection.add_coins(coins)
	collection.save_to_disk()
	if game_screen != null:
		game_screen.coins_note = "+%d monedas" % coins


func _on_online_requested(kind: String, code: String) -> void:
	var payload := {"name": profile.player_name, "colors": profile.colors_payload(), "cos": collection.equipped_payload()}
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
		_restore_sent = false
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
			if game_screen == null and menu != null:
				menu.set_status("")
				menu.set_searching(true)
		"room":
			if game_screen == null and menu != null:
				menu.set_status("Sala %s. Pasale el código a tu rival." % data.get("code", ""))
		"error":
			if game_screen == null:
				if menu != null:
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
			# El servidor perdió la partida (se reinició): se la devolvemos con lo que sabe este cliente.
			if not _restore_sent and game_screen != null and game_screen.online and not game_screen.finished \
					and not _token.is_empty() and not game_screen.session_id.is_empty():
				_restore_sent = true
				net.send(game_screen.restore_payload(_token))
			else:
				_give_up_reconnecting()
		"restore_wait":
			pass  # falta que vuelva el rival; seguimos en "Reconectando..."
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
	var coins: int = Cosmetics.COINS_WIN if result == "W" else (Cosmetics.COINS_DRAW if result == "D" else Cosmetics.COINS_LOSS)
	collection.add_coins(coins)
	collection.save_to_disk()
	game_screen.coins_note = "+%d monedas" % coins
	history.add(History.make_record([game_screen.names[1], game_screen.names[2]], game_screen._start_colors,
			game_screen.my_seat, winner, str(data.get("reason", "")), game_screen.move_log,
			[game_screen._mark_figure(UltimateGame.X), game_screen._mark_figure(UltimateGame.O)]))
	history.save_to_disk()
