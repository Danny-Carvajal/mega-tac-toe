extends Control
## Pantalla de partida: tablero 9x9 + relojes. Sirve para juego local (dos
## personas en el mismo cel) y online (el servidor decide y manda cada jugada).

signal move_requested(big: int, small: int)
signal resign_requested
signal exit_requested

const Pal := preload("res://scripts/pal.gd")
const History := preload("res://scripts/history.gd")
const UltimateGame := preload("res://scripts/ultimate_game.gd")
const Profile := preload("res://scripts/profile.gd")
const Fx := preload("res://scripts/fx.gd")
const UltimateAI := preload("res://scripts/ai.gd")

## Casilla vacía de un tablero donde no se puede jugar: apagada pero que se siga viendo (para los apuntes).
const ARROW_ALPHA := 0.7

var game := UltimateGame.new()
var online := false
## Modo práctica: una persona contra la IA (ver UltimateAI). La persona es X y empieza.
var vs_ai := false
var ai_level := 1
var ai_seat := UltimateGame.O
const AI_MIN_THINK_MS := 650
var _ai_busy := false
var _ai_threaded := false
var _ai_thread: Thread
var _ai_runner: UltimateAI
var _ai_started_ms := 0
var my_seat := 0
var finished := false
var disconnected := false
## Colores, nombres y relojes por asiento. Índice 1 = X, 2 = O (el 0 no se usa).
var colors: Array = [Pal.muted, Profile.DEFAULT_X, Profile.DEFAULT_O]
var names: Array = ["", "X", "O"]
var clocks_ms: Array = [0, 0, 0]
## Saltos por tiempo de cada jugador; con `max_skips` pierde.
var skips: Array = [0, 0, 0]
var max_skips := 3
## Para reconstruir la partida si el servidor se reinicia (ver restore_payload).
var move_log: Array = []
var session_id := ""
var _start_names: Array = []
var _start_colors: Array = []
var _clock_received_ms := 0
var _result_text := ""
## Fin de partida: cartel grande al medio (Ganaste / Perdiste / Empate) con "Ver tablero" y "Volver al menú".
var result_layer: Control

## Modo repetición: se ve una partida guardada, paso a paso o en vivo.
var replay := false
var replay_log: Array = []
var replay_index := 0
var replay_record := {}
var replay_playing := false
var replay_row: BoxContainer
var replay_play_button: Button
var _replay_next_ms := 0
var _replay_mover := 0
var _replay_skipped := false
var _replay_note := ""
var _replay_animate := false
const REPLAY_STEP_MS := 1100
var _result_title := ""
var _result_sub := ""
var _result_color := Color.WHITE
var _result_shown := false
## Aviso temporal que reemplaza el estado (errores del servidor, reglas distintas).
var _notice := ""
const NOTICE_RECONNECTING := "Reconectando..."
const NOTICE_OPPONENT_GONE := "El rival perdió la conexión. Lo esperamos un rato..."
var reconnecting := false
var _notice_until_ms := 0

## En pantallas anchas (compu) el tablero va a la izquierda y los datos a la derecha.
var wide := false
var root_box: BoxContainer
var clock_row: BoxContainer
var buttons_row: BoxContainer
var ratio_box: AspectRatioContainer
var side_box: VBoxContainer
var side_spacer: Control

## Última jugada (para resaltarla) y marcas ya dibujadas (para animar las nuevas).
var last_move := Vector2i(-1, -1)
var last_move_player := 0
var _highlighted := Vector2i(-1, -1)
var _highlight_tween: Tween
var _prev_cells: Array[int] = []
var _prev_results: Array[int] = []

## Apuntes: flechas semitransparentes que el jugador dibuja arrastrando sobre el tablero.
var notes_mode := false
var arrows: Array[Dictionary] = []
## Las flechas van en degradé: la base con el color de la O y la punta con el de la X del jugador.
var arrow_base_color := Profile.DEFAULT_O
var arrow_tip_color := Profile.DEFAULT_X
var notes_button: Button
var clear_notes_button: Button
var notes_layer: Control
var big_grid: GridContainer
var _drag_from := Vector2i(-1, -1)
var _drag_point := Vector2.ZERO

## Confirmación de rendirse.
var confirm_layer: Control

var status_label: Label
var clock_labels: Array = [null, null, null]
var left_button: Button
var bottom_row: BoxContainer
var turn_banner: PanelContainer
var _last_banner_key := ""
const COLOR_RESIGN := Color("a8323a")
const COLOR_WIN := Color("3ecf8e")
const COLOR_LOSS := Color("e5484d")
var new_game_button: Button
var panels: Array[PanelContainer] = []
var grids: Array[GridContainer] = []
var result_labels: Array[Label] = []
## small_buttons[big][small] -> Button
var small_buttons: Array = []


## Juego local: los dos jugadores comparten el cel, sin reloj.
func setup_local(profile: Profile) -> void:
	online = false
	arrow_tip_color = profile.color_x
	arrow_base_color = profile.color_o
	colors = [Pal.muted, profile.color_x, profile.color_o]
	names = ["", "X", "O"]


## Práctica contra la IA: la persona juega con X (empieza) y la IA con O.
func setup_practice(profile: Profile, level: int) -> void:
	online = false
	vs_ai = true
	ai_level = clampi(level, 1, 5)
	my_seat = UltimateGame.X
	ai_seat = UltimateGame.O
	arrow_tip_color = profile.color_x
	arrow_base_color = profile.color_o
	colors = [Pal.muted, profile.color_x, profile.color_o]
	names = ["", profile.player_name, "IA %s" % UltimateAI.LEVEL_NAMES[ai_level - 1]]


## Repetición de una partida guardada (ver History.make_record).
func setup_replay(record: Dictionary) -> void:
	replay = true
	online = false
	replay_record = record
	replay_log = History.decode(str(record.get("m", "")))
	var recorded_names: Array = record.get("n", ["X", "O"])
	names = ["", str(recorded_names[0]), str(recorded_names[1])]
	colors = [Pal.muted, Profile.DEFAULT_X, Profile.DEFAULT_O]
	var recorded_colors: Array = record.get("c", [])
	if recorded_colors.size() == 2:
		colors[1] = Color.html(str(recorded_colors[0]))
		colors[2] = Color.html(str(recorded_colors[1]))
	_resolve_color_clash()
	arrow_tip_color = colors[1]
	arrow_base_color = colors[2]
	_result_shown = true  # en la repetición no sale el cartel de fin


## Juego online: `start` es el mensaje {t:"start"} del servidor.
func setup_online(start: Dictionary, profile: Profile) -> void:
	online = true
	arrow_tip_color = profile.color_x
	arrow_base_color = profile.color_o
	my_seat = int(start.get("you", 0))
	var server_names: Array = start.get("names", ["X", "O"])
	var server_colors: Array = start.get("colors", [])
	session_id = str(start.get("sid", ""))
	_start_names = server_names.duplicate()
	_start_colors = server_colors.duplicate()
	move_log = []
	names = ["", str(server_names[0]), str(server_names[1])]
	colors = [Pal.muted, Profile.DEFAULT_X, Profile.DEFAULT_O]
	if server_colors.size() == 2:
		colors[1] = Color.html(str(server_colors[0]))
		colors[2] = Color.html(str(server_colors[1]))
	_resolve_color_clash()
	max_skips = int(start.get("max_skips", 3))
	# Un servidor viejo no manda "rules": cuenta como versión 1.
	if int(start.get("rules", 1)) != UltimateGame.RULES_VERSION:
		_notice = "El servidor tiene otras reglas (todavía no se actualizó). Algunas jugadas no van a pasar."
		_notice_until_ms = 1 << 60
	var clocks: Array = start.get("clocks", [0, 0])
	clocks_ms = [0, int(clocks[0]), int(clocks[1])]
	_clock_received_ms = Time.get_ticks_msec()


func _ready() -> void:
	_build_ui()
	if replay:
		replay_goto(0)
	else:
		_refresh()


func _process(_delta: float) -> void:
	if online:
		_refresh_clocks()
	if vs_ai:
		_ai_poll()
	if replay and replay_playing and Time.get_ticks_msec() >= _replay_next_ms:
		if replay_index >= replay_log.size():
			_set_replay_playing(false)
		else:
			replay_goto(replay_index + 1)
			_replay_next_ms = Time.get_ticks_msec() + REPLAY_STEP_MS
	if not _notice.is_empty() and Time.get_ticks_msec() > _notice_until_ms:
		_notice = ""
		_refresh_status()


## Muestra un aviso en lugar del estado (por ejemplo, un error del servidor).
func show_notice(text: String, duration_ms := 3500) -> void:
	_notice = text
	_notice_until_ms = Time.get_ticks_msec() + duration_ms
	_refresh_status()


func _exit_tree() -> void:
	_ai_cancel()


# --- IA (modo práctica) -----------------------------------------------------

## ¿Hay una sola persona con asiento propio (online o contra la IA)?
func _single_seat() -> bool:
	return online or vs_ai


## Si le toca a la IA, empieza a pensar (en un hilo si se puede, para que la pantalla no se congele).
func _ai_maybe_start() -> void:
	if not vs_ai or _ai_busy or game.is_over() or game.current_player != ai_seat:
		return
	_ai_busy = true
	_ai_started_ms = Time.get_ticks_msec()
	_ai_runner = UltimateAI.new()
	_ai_runner.load_state(game.cells, game.board_results, game.forced_board, game.current_player)
	_ai_threaded = not OS.has_feature("web")  # en la web no hay hilos: ahí piensa menos y sin hilo
	if _ai_threaded:
		_ai_thread = Thread.new()
		_ai_thread.start(_ai_runner.choose.bind(ai_level, true))


func _ai_poll() -> void:
	if not _ai_busy:
		return
	var elapsed := Time.get_ticks_msec() - _ai_started_ms
	if elapsed < AI_MIN_THINK_MS:
		return  # un mínimo de "pensando" para que las jugadas no aparezcan de golpe
	var move := Vector2i(-1, -1)
	if _ai_threaded:
		if _ai_thread.is_alive():
			return
		move = _ai_thread.wait_to_finish()
		_ai_thread = null
	else:
		move = _ai_runner.choose(ai_level, false)
	_ai_runner = null
	_ai_busy = false
	if game.is_over() or game.current_player != ai_seat:
		return
	var mover := game.current_player
	if game.play(move.x, move.y):
		last_move = move
		last_move_player = mover
	_refresh()


func _ai_cancel() -> void:
	if _ai_runner != null:
		_ai_runner.cancelled = true
	if _ai_thread != null:
		_ai_thread.wait_to_finish()
		_ai_thread = null
	_ai_runner = null
	_ai_busy = false


# --- Eventos del servidor ---------------------------------------------------

func apply_move(data: Dictionary) -> void:
	var big := int(data.get("big", -1))
	var small := int(data.get("small", -1))
	var mover := game.current_player
	if game.play(big, small):
		last_move = Vector2i(big, small)
		last_move_player = mover
		move_log.append([big, small])
	else:
		push_warning("El servidor mandó una jugada que no es legal acá: %d,%d" % [big, small])
	_set_clocks(data)
	_refresh()


## Al jugador de turno se le acabó el tiempo: le saltan el turno sin jugar.
func apply_skip(data: Dictionary) -> void:
	game.skip_turn()
	move_log.append("s")
	last_move = Vector2i(-1, -1)  # la jugada anterior se deshizo
	var counts: Array = data.get("skips", [])
	if counts.size() == 2:
		skips = [0, int(counts[0]), int(counts[1])]
	_set_clocks(data)
	_refresh()


func apply_over(data: Dictionary) -> void:
	if confirm_layer != null:
		confirm_layer.visible = false  # si se estaba por rendir justo cuando terminó, ya no tiene sentido
	_set_clocks(data)
	finished = true
	var winner := int(data.get("winner", 0))
	var reason := str(data.get("reason", ""))
	if winner == 0:
		_result_text = "Empate"
		_result_title = "EMPATE"
		_result_color = Pal.muted
		_result_sub = ""
	elif winner == my_seat:
		_result_text = "Ganaste" + _reason_suffix(reason, true)
		_result_title = "¡GANASTE!"
		_result_color = COLOR_WIN
		_result_sub = _reason_suffix(reason, true).strip_edges().trim_prefix("(").trim_suffix(")")
	else:
		_result_text = "Perdiste" + _reason_suffix(reason, false)
		_result_title = "PERDISTE"
		_result_color = COLOR_LOSS
		_result_sub = _reason_suffix(reason, false).strip_edges().trim_prefix("(").trim_suffix(")")
	_refresh()


## Mientras la app intenta volver a la partida se muestra "Reconectando...".
func set_reconnecting(on: bool) -> void:
	reconnecting = on
	if on:
		_notice = NOTICE_RECONNECTING
		_notice_until_ms = 1 << 60
	elif _notice == NOTICE_RECONNECTING:
		_notice = ""
	_refresh_status()


func set_opponent_connected(connected: bool) -> void:
	if not connected:
		_notice = NOTICE_OPPONENT_GONE
		_notice_until_ms = 1 << 60
	elif _notice == NOTICE_OPPONENT_GONE:
		_notice = ""
	_refresh_status()


## Reconstruye la partida a partir de las jugadas guardadas en el servidor.
func apply_resume(data: Dictionary) -> void:
	game = UltimateGame.new()
	last_move = Vector2i(-1, -1)
	for entry in data.get("log", []):
		if entry is Array:
			var mover := game.current_player
			if game.play(int(entry[0]), int(entry[1])):
				last_move = Vector2i(int(entry[0]), int(entry[1]))
				last_move_player = mover
		else:
			game.skip_turn()
			last_move = Vector2i(-1, -1)
	var counts: Array = data.get("skips", [])
	if counts.size() == 2:
		skips = [0, int(counts[0]), int(counts[1])]
	move_log = Array(data.get("log", [])).duplicate()
	_set_clocks(data)
	finished = false
	disconnected = false
	_prev_cells.assign(game.cells)
	_prev_results.assign(game.board_results)
	set_reconnecting(false)
	set_opponent_connected(bool(data.get("opponent_connected", true)))
	_refresh()


## Lo que este cliente sabe de la partida: si el servidor se reinició y la perdió, los dos jugadores
## se la devuelven (mensaje "restore") y la partida sigue donde estaba.
func restore_payload(token: String) -> Dictionary:
	var now := Time.get_ticks_msec()
	var clocks: Array = []
	for seat in [1, 2]:
		var ms: int = clocks_ms[seat]
		if not finished and not game.is_over() and game.current_player == seat:
			ms = maxi(0, ms - (now - _clock_received_ms))
		clocks.append(ms)
	return {
		"t": "restore",
		"sid": session_id,
		"token": token,
		"seat": my_seat,
		"names": _start_names,
		"colors": _start_colors,
		"log": move_log,
		"skips": [skips[1], skips[2]],
		"clocks": clocks,
	}


func on_disconnected() -> void:
	if finished:
		return
	disconnected = true
	finished = true
	_result_text = "Se cayó la conexión"
	_refresh()


func _reason_suffix(reason: String, won: bool) -> String:
	match reason:
		"skips":
			return " (el rival se pasó de tiempo %d veces)" % max_skips if won else " (%d saltos por tiempo)" % max_skips
		"resign":
			return " (el rival se rindió)" if won else " (te rendiste)"
		"disconnect":
			return " (el rival se desconectó)" if won else ""
	return ""


func _set_clocks(data: Dictionary) -> void:
	var clocks: Array = data.get("clocks", [])
	if clocks.size() == 2:
		clocks_ms = [0, int(clocks[0]), int(clocks[1])]
		_clock_received_ms = Time.get_ticks_msec()


## Si los dos eligieron colores casi iguales, el rival se ve con su color por defecto.
func _resolve_color_clash() -> void:
	var mine: int = my_seat if my_seat != 0 else 1
	var theirs := 3 - mine
	if _color_distance(colors[mine], colors[theirs]) < 0.35:
		colors[theirs] = Profile.DEFAULT_X if theirs == 1 else Profile.DEFAULT_O
		if _color_distance(colors[mine], colors[theirs]) < 0.35:
			colors[theirs] = Pal.muted


func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


# --- Construcción de la pantalla --------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Pal.bg
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)

	var root := BoxContainer.new()
	root.vertical = true
	root.add_theme_constant_override("separation", 28)
	margin.add_child(root)
	root_box = root

	if online or replay:
		clock_row = BoxContainer.new()
		clock_row.add_theme_constant_override("separation", 24)
		root.add_child(clock_row)
		for seat in [1, 2]:
			var label := Label.new()
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 44)
			clock_row.add_child(label)
			clock_labels[seat] = label

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 52)
	turn_banner = PanelContainer.new()
	turn_banner.custom_minimum_size = Vector2(0, 170)  # alto fijo (2 líneas): el tablero no cambia de tamaño al cambiar el texto
	turn_banner.add_child(status_label)
	_style_banner(Pal.banner, false)
	root.add_child(turn_banner)

	var ratio := AspectRatioContainer.new()
	ratio.ratio = 1.0
	ratio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ratio.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(ratio)
	ratio_box = ratio
	if replay:
		_build_replay_row()

	big_grid = GridContainer.new()
	big_grid.columns = 3
	big_grid.add_theme_constant_override("h_separation", 16)
	big_grid.add_theme_constant_override("v_separation", 16)
	ratio.add_child(big_grid)
	for big in 9:
		_build_big_cell(big_grid, big)

	var buttons := BoxContainer.new()
	buttons.add_theme_constant_override("separation", 24)
	root.add_child(buttons)
	buttons_row = buttons

	bottom_row = BoxContainer.new()
	root.add_child(bottom_row)
	left_button = _make_button("Volver al historial" if replay else "Menú", Pal.cell)
	left_button.pressed.connect(_on_left_pressed)
	bottom_row.add_child(left_button)

	if not online and not replay:
		new_game_button = _make_button("Nueva partida", Pal.active)
		new_game_button.pressed.connect(_on_new_game_pressed)
		buttons.add_child(new_game_button)

	notes_button = _make_button("Apuntes", Pal.cell)
	notes_button.toggle_mode = true
	notes_button.add_theme_stylebox_override("pressed", _flat(Pal.notes_on))
	notes_button.add_theme_stylebox_override("hover_pressed", _flat(Pal.notes_on))
	for font_state in ["font_pressed_color", "font_hover_pressed_color", "font_hover_color", "font_focus_color"]:
		notes_button.add_theme_color_override(font_state, Pal.text)
	notes_button.toggled.connect(_on_notes_toggled)
	buttons.add_child(notes_button)
	clear_notes_button = _make_button("Borrar", Pal.cell)
	clear_notes_button.visible = false
	clear_notes_button.pressed.connect(clear_arrows)
	buttons.add_child(clear_notes_button)

	notes_layer = ArrowLayer.new()
	notes_layer.screen = self
	notes_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	notes_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(notes_layer)

	big_grid.resized.connect(notes_layer.queue_redraw)
	_build_confirm_dialog()
	_build_result_overlay()


	side_box = VBoxContainer.new()
	side_box.custom_minimum_size = Vector2(640, 0)
	side_box.add_theme_constant_override("separation", 28)
	side_spacer = Control.new()
	side_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL


## Reacomoda la pantalla: vertical (celular) o ancha (compu).
func apply_layout(is_wide: bool) -> void:
	wide = is_wide
	if root_box == null:
		return
	for part in [clock_row, turn_banner, ratio_box, replay_row, buttons_row, bottom_row, side_box, side_spacer]:
		if part != null and part.get_parent() != null:
			part.get_parent().remove_child(part)
	if wide:
		root_box.vertical = false
		root_box.add_child(ratio_box)
		root_box.add_child(side_box)
		if clock_row != null:
			side_box.add_child(clock_row)
		side_box.add_child(turn_banner)
		side_box.add_child(side_spacer)
		if replay_row != null:
			side_box.add_child(replay_row)
		side_box.add_child(buttons_row)
		side_box.add_child(bottom_row)
	else:
		root_box.vertical = true
		if clock_row != null:
			root_box.add_child(clock_row)
		root_box.add_child(turn_banner)
		root_box.add_child(ratio_box)
		if replay_row != null:
			root_box.add_child(replay_row)
		root_box.add_child(buttons_row)
		root_box.add_child(bottom_row)
	if clock_row != null:
		clock_row.vertical = wide
	buttons_row.vertical = wide
	bottom_row.vertical = wide
	if notes_layer != null:
		notes_layer.queue_redraw.call_deferred()


func _make_button(text: String, color: Color) -> Button:
	var button := Button.new()
	Fx.press_feedback(button)
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 120)
	button.add_theme_font_size_override("font_size", 44)
	for font_state in ["font_color", "font_pressed_color", "font_hover_pressed_color", "font_hover_color", "font_focus_color"]:
		button.add_theme_color_override(font_state, Pal.text)
	_style_button(button, color)
	return button


func _build_big_cell(parent: GridContainer, big: int) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	panels.append(panel)

	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(inner)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	inner.add_child(grid)
	grids.append(grid)

	var row: Array[Button] = []
	for small in 9:
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 56)
		_style_button(button, Pal.cell)
		button.pressed.connect(_on_small_pressed.bind(big, small))
		grid.add_child(button)
		row.append(button)
	small_buttons.append(row)

	var result_label := Label.new()
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 220)
	result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_label.visible = false
	panel.add_child(result_label)
	result_labels.append(result_label)


# --- Acciones del jugador ---------------------------------------------------

func _on_small_pressed(big: int, small: int) -> void:
	if replay:
		return
	if online:
		# El servidor es quien decide: acá solo se pide la jugada.
		if finished or game.current_player != my_seat or not game.is_legal(big, small):
			return
		move_requested.emit(big, small)
	else:
		if vs_ai and (game.current_player != my_seat or _ai_busy):
			return
		var mover := game.current_player
		if game.play(big, small):
			last_move = Vector2i(big, small)
			last_move_player = mover
			_refresh()


func _on_left_pressed() -> void:
	if online and not finished:
		ask_resign()
	else:
		exit_requested.emit()


## Pide confirmación antes de rendirse (para no perder la partida de un toque).
func ask_resign() -> void:
	if confirm_layer == null or finished:
		return
	confirm_layer.visible = true
	Fx.fade_in(confirm_layer, 0.15)


func _confirm_resign() -> void:
	confirm_layer.visible = false
	resign_requested.emit()


func _build_confirm_dialog() -> void:
	confirm_layer = Control.new()
	confirm_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	confirm_layer.visible = false
	add_child(confirm_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm_layer.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(820, 0)
	var style := _flat(Pal.card, 24)
	style.border_color = Pal.active
	style.set_border_width_all(3)
	style.set_content_margin_all(48)
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 28)
	card.add_child(box)
	var title := Label.new()
	title.text = "¿Seguro que te rendís?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Pal.text)
	box.add_child(title)
	var note := Label.new()
	note.text = "Perdés la partida."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 38)
	note.add_theme_color_override("font_color", Pal.muted)
	box.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var keep := _make_button("Seguir jugando", Pal.active)
	keep.pressed.connect(func() -> void: confirm_layer.visible = false)
	row.add_child(keep)
	var yes := _make_button("Rendirme", Color("8f2f34"))
	_white_text(yes)
	yes.pressed.connect(_confirm_resign)
	row.add_child(yes)


## Cartel de fin de partida. Se arma al terminar y se descarta con "Ver tablero".
func _build_result_overlay() -> void:
	result_layer = Control.new()
	result_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	result_layer.visible = false
	add_child(result_layer)


func _show_result_overlay() -> void:
	for child in result_layer.get_children():
		child.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(Pal.bg, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_layer.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 28)
	box.custom_minimum_size = Vector2(820, 0)
	center.add_child(box)
	var title := Label.new()
	title.text = _result_title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 160)
	title.add_theme_color_override("font_color", _result_color)
	title.add_theme_constant_override("outline_size", 0)
	box.add_child(title)
	if not _result_sub.is_empty():
		var sub := Label.new()
		sub.text = _result_sub
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.add_theme_font_size_override("font_size", 40)
		sub.add_theme_color_override("font_color", Pal.muted)
		box.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	box.add_child(spacer)
	var view := _make_button("Ver tablero", Pal.cell)
	view.pressed.connect(_dismiss_result_overlay)
	box.add_child(view)
	var back := _make_button("Volver al menú", Pal.active)
	back.pressed.connect(func() -> void: exit_requested.emit())
	box.add_child(back)
	result_layer.visible = true
	_result_shown = true
	_update_notes_enabled()
	Fx.fade_in(result_layer, 0.25)
	Fx.pop(title, 0.6, 0.45)
	Fx.stagger_in([view, back], 0.1, 0.3)


func _dismiss_result_overlay() -> void:
	result_layer.visible = false
	_update_notes_enabled()


func _update_notes_enabled() -> void:
	pass  # Apuntes funciona normal; mientras el cartel está puesto, el cartel tapa todo y no deja tocar nada


func _check_result_overlay() -> void:
	if result_layer == null or _result_shown:
		return
	if online:
		if not finished or disconnected or _result_title.is_empty():
			return
	elif game.is_over():
		if game.result == UltimateGame.DRAW:
			_result_title = "EMPATE"
			_result_color = Pal.muted
		elif vs_ai:
			var won := game.result == my_seat
			_result_title = "¡GANASTE!" if won else "PERDISTE"
			_result_color = COLOR_WIN if won else COLOR_LOSS
		else:
			_result_title = "¡GANÓ %s!" % _mark_text(game.result)
			_result_color = _mark_color(game.result)
		_result_sub = "Práctica contra %s" % names[ai_seat] if vs_ai else ""
	else:
		return
	_show_result_overlay()


func _on_new_game_pressed() -> void:
	_result_shown = false
	result_layer.visible = false
	_update_notes_enabled()
	_ai_cancel()
	game.reset()
	last_move = Vector2i(-1, -1)
	clear_arrows()
	_refresh()


# --- Última jugada del rival -------------------------------------------------

## Resalta (borde del color de quien jugó + brillo suave) la última jugada a la que hay
## que responder. En online solo se marca la del rival, no la propia.
func _apply_highlight() -> void:
	var target := Vector2i(-1, -1)
	if last_move.x >= 0 and (not _single_seat() or last_move_player != my_seat):
		target = last_move
	if target == _highlighted:
		return
	if _highlight_tween != null:
		_highlight_tween.kill()
		_highlight_tween = null
	if _highlighted.x >= 0:
		var old: Button = small_buttons[_highlighted.x][_highlighted.y]
		old.modulate.a = 1.0
		_style_button(old, Pal.cell)
	_highlighted = target
	if target.x >= 0:
		var button: Button = small_buttons[target.x][target.y]
		var color: Color = colors[last_move_player]
		var base := Pal.cell.lerp(color, 0.28)
		for state in ["normal", "hover", "pressed", "disabled"]:
			var style := _flat(base)
			style.border_color = color
			style.set_border_width_all(5)
			button.add_theme_stylebox_override(state, style)
		_highlight_tween = Fx.glow(button)


# --- Apuntes: flechas sobre el tablero -----------------------------------------

# --- Repetición de partidas -------------------------------------------------

func _build_replay_row() -> void:
	replay_row = BoxContainer.new()
	replay_row.add_theme_constant_override("separation", 14)
	var specs := [["|<", "start"], ["<", "back"], ["Play", "play"], [">", "next"], [">|", "end"]]
	for spec in specs:
		var button := _make_button(spec[0], Pal.active if spec[1] == "play" else Pal.cell)
		button.add_theme_font_size_override("font_size", 40)
		var action: String = spec[1]
		button.pressed.connect(func() -> void: _on_replay_button(action))
		replay_row.add_child(button)
		if action == "play":
			replay_play_button = button


func _on_replay_button(action: String) -> void:
	match action:
		"start":
			_set_replay_playing(false)
			replay_goto(0)
		"back":
			_set_replay_playing(false)
			replay_goto(replay_index - 1)
		"next":
			_set_replay_playing(false)
			replay_goto(replay_index + 1)
		"end":
			_set_replay_playing(false)
			replay_goto(replay_log.size())
		"play":
			if replay_playing:
				_set_replay_playing(false)
			else:
				if replay_index >= replay_log.size():
					replay_goto(0)
				_set_replay_playing(true)


func _set_replay_playing(on: bool) -> void:
	replay_playing = on
	_replay_next_ms = Time.get_ticks_msec() + REPLAY_STEP_MS
	if replay_play_button != null:
		replay_play_button.text = "Pausa" if on else "Play"


## Va a la posición `index` (cantidad de jugadas ya hechas) rearmando la partida desde cero.
func replay_goto(index: int) -> void:
	var previous := replay_index
	replay_index = clampi(index, 0, replay_log.size())
	_replay_animate = replay_index == previous + 1  # solo se anima el paso de a una jugada
	game = UltimateGame.new()
	last_move = Vector2i(-1, -1)
	last_move_player = 0
	_replay_mover = 0
	_replay_skipped = false
	_replay_note = ""
	for i in replay_index:
		var entry = replay_log[i]
		_replay_mover = game.current_player
		if entry is Array:
			var board_before: int = game.board_results[int(entry[0])]
			if game.play(int(entry[0]), int(entry[1])):
				last_move = Vector2i(int(entry[0]), int(entry[1]))
				last_move_player = _replay_mover
			_replay_skipped = false
			# Notación: casilla (a1-i9), "+" si ganó una casilla grande, "#" si ganó la partida.
			_replay_note = History.cell_name(int(entry[0]), int(entry[1]))
			if game.is_over() and game.result != UltimateGame.DRAW:
				_replay_note += "#"
			elif board_before == UltimateGame.NONE and game.board_results[int(entry[0])] != UltimateGame.NONE:
				_replay_note += "+"
		else:
			game.skip_turn()
			last_move = Vector2i(-1, -1)
			_replay_skipped = true
			_replay_note = "salto"
	_refresh()
	if replay_index >= replay_log.size() and replay_playing:
		_set_replay_playing(false)


func _refresh_replay_status() -> void:
	var total := replay_log.size()
	var text: String
	if replay_index == 0:
		text = "Inicio · %d jugadas" % total
		_style_banner(Pal.banner, false)
		status_label.add_theme_color_override("font_color", Pal.text)
	else:
		if _replay_skipped:
			text = "%d/%d · Salto de turno de %s" % [replay_index, total, names[_replay_mover]]
		else:
			text = "%d/%d · %s (%s)" % [replay_index, total, names[_replay_mover], _mark_text(_replay_mover)]
		_style_banner(_mark_color(_replay_mover), true)
		status_label.add_theme_color_override("font_color", Color.WHITE)
	if replay_index > 0:
		text += "\n" + _replay_note
	if replay_index >= total:
		var winner := int(replay_record.get("w", 0))
		text += "  ·  " + ("Empate" if winner == 0 else "Ganó %s" % names[winner])
	status_label.text = text


func _on_notes_toggled(on: bool) -> void:
	notes_mode = on
	clear_notes_button.visible = on
	_drag_from = Vector2i(-1, -1)
	notes_layer.queue_redraw()


func clear_arrows() -> void:
	arrows.clear()
	notes_layer.queue_redraw()


func _input(event: InputEvent) -> void:
	if replay and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT:
				_on_replay_button("back")
			KEY_RIGHT:
				_on_replay_button("next")
			KEY_SPACE:
				_on_replay_button("play")
	if not notes_mode or notes_layer == null or confirm_layer.visible or result_layer.visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var in_board := big_grid.get_global_rect().has_point(event.position)
		if event.pressed:
			if in_board:
				_drag_from = _cell_at(event.position)
				_drag_point = event.position
				notes_layer.queue_redraw()
				get_viewport().set_input_as_handled()
		elif _drag_from.x >= 0:
			var target := _cell_at(event.position)
			if target == _drag_from:
				_delete_arrow_near(event.position)
			elif in_board:
				_toggle_arrow(_drag_from, target)
			_drag_from = Vector2i(-1, -1)
			notes_layer.queue_redraw()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag_from.x >= 0:
		_drag_point = event.position
		notes_layer.queue_redraw()
		get_viewport().set_input_as_handled()


## Dibujar la misma flecha otra vez la borra.
func _toggle_arrow(from: Vector2i, to: Vector2i) -> void:
	for i in arrows.size():
		if arrows[i]["from"] == from and arrows[i]["to"] == to:
			arrows.remove_at(i)
			return
	arrows.append({"from": from, "to": to})


## Tocar una flecha la borra.
func _delete_arrow_near(point: Vector2) -> void:
	for i in range(arrows.size() - 1, -1, -1):
		var a := _cell_center(arrows[i]["from"])
		var b := _cell_center(arrows[i]["to"])
		var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
		if closest.distance_to(point) < 34.0:
			arrows.remove_at(i)
			return


func _cell_center(cell: Vector2i) -> Vector2:
	var button: Button = small_buttons[cell.x][cell.y]
	return button.get_global_rect().get_center()


func _cell_at(point: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for big in 9:
		for small in 9:
			var distance := _cell_center(Vector2i(big, small)).distance_squared_to(point)
			if distance < best_distance:
				best_distance = distance
				best = Vector2i(big, small)
	return best


func draw_arrows_on(layer: Control) -> void:
	var inverse := layer.get_global_transform().affine_inverse()
	for arrow in arrows:
		_draw_arrow(layer, inverse * _cell_center(arrow["from"]), inverse * _cell_center(arrow["to"]), ARROW_ALPHA)
	if _drag_from.x >= 0:
		_draw_arrow(layer, inverse * _cell_center(_drag_from), inverse * _drag_point, ARROW_ALPHA * 0.6)


func _draw_arrow(layer: Control, from: Vector2, to: Vector2, alpha: float) -> void:
	var length := from.distance_to(to)
	if length < 12.0:
		return
	var direction := (to - from) / length
	var head := minf(46.0, length * 0.6)
	var perpendicular := Vector2(-direction.y, direction.x)
	var base := to - direction * head
	var half_body := 7.0
	var half_head := 26.0
	# Degradé a lo largo de la flecha: base = color de la O, punta = color de la X.
	var t_head := 1.0 - head / length
	var c_start := _arrow_color_at(0.0, alpha)
	var c_head := _arrow_color_at(t_head, alpha)
	var c_tip := _arrow_color_at(1.0, alpha)
	layer.draw_circle(from, 9.0, c_start)
	layer.draw_polygon(PackedVector2Array([
		from + perpendicular * half_body, from - perpendicular * half_body,
		base - perpendicular * half_body, base + perpendicular * half_body]),
		PackedColorArray([c_start, c_start, c_head, c_head]))
	layer.draw_polygon(PackedVector2Array([
		to, base + perpendicular * half_head, base - perpendicular * half_head]),
		PackedColorArray([c_tip, c_head, c_head]))


func _arrow_color_at(t: float, alpha: float) -> Color:
	var color := arrow_base_color.lerp(arrow_tip_color, t)
	color.a = alpha
	return color


# --- Refrescar lo que se ve -------------------------------------------------

func _refresh() -> void:
	if _prev_cells.is_empty():
		_prev_cells.resize(81)
		_prev_cells.fill(UltimateGame.NONE)
		_prev_results.resize(9)
		_prev_results.fill(UltimateGame.NONE)
	var legal := {}
	if not finished:
		for move in game.legal_moves():
			legal[move] = true
	var can_play := not finished and not replay and (not _single_seat() or game.current_player == my_seat)
	# Tableros donde hay que jugar ahora (un tablero ganado sigue contando si le quedan casillas).
	var playable_boards := {}
	for move in legal:
		playable_boards[move.x] = true

	for big in 9:
		var board_result: int = game.board_results[big]
		var decided := board_result != UltimateGame.NONE
		var panel_color := Pal.active if playable_boards.has(big) else Pal.panel
		if decided:
			panel_color = panel_color.lerp(_mark_color(board_result), 0.12)
		panels[big].add_theme_stylebox_override("panel", _flat(panel_color, 18))

		for small in 9:
			var mark := game.get_cell(big, small)
			var button: Button = small_buttons[big][small]
			button.text = _mark_text(mark)
			if mark != UltimateGame.NONE and _prev_cells[big * 9 + small] == UltimateGame.NONE:
				if not replay:
					Fx.pop(button)
				elif _replay_animate:
					Fx.drop_in(button)  # en la repetición las jugadas caen suave una tras otra
			button.disabled = not (can_play and legal.has(Vector2i(big, small)))
			button.add_theme_color_override("font_disabled_color", _mark_color(mark))

		var label := result_labels[big]
		label.visible = decided
		label.text = _mark_text(board_result)
		# Translúcida para que se vean y se puedan tocar las casillas de abajo.
		var label_color := _mark_color(board_result)
		label_color.a = 0.3
		label.add_theme_color_override("font_color", label_color)
		if decided and _prev_results[big] == UltimateGame.NONE:
			Fx.fade_in(label, 0.35)
			Fx.pop(label, 0.4, 0.45)

	_prev_cells.assign(game.cells)
	_prev_results.assign(game.board_results)
	_apply_highlight()

	if online:
		left_button.text = "Volver al menú" if finished else "Rendirse"
		_style_button(left_button, Pal.cell if finished else COLOR_RESIGN)
	_refresh_status()
	_refresh_clocks()
	_check_result_overlay()
	_ai_maybe_start()


func _refresh_status() -> void:
	if replay:
		_refresh_replay_status()
		return
	if not _notice.is_empty() and not finished:
		status_label.text = _notice
		status_label.add_theme_color_override("font_color", Pal.text)
		_style_banner(Pal.banner, false)
		return
	if finished and online:
		status_label.text = _result_text
		status_label.add_theme_color_override("font_color", Pal.text)
		_style_banner(Pal.banner, false)
		return
	if game.is_over():
		if game.result == UltimateGame.DRAW:
			status_label.text = "Empate"
			status_label.add_theme_color_override("font_color", Pal.muted)
			_style_banner(Pal.muted, false)
		elif vs_ai:
			status_label.text = "¡Ganaste!" if game.result == my_seat else "Ganó %s" % names[ai_seat]
			status_label.add_theme_color_override("font_color", Color.WHITE)
			_style_banner(_mark_color(game.result), true)
		else:
			status_label.text = "Ganó %s" % _mark_text(game.result)
			status_label.add_theme_color_override("font_color", Color.WHITE)
			_style_banner(_mark_color(game.result), true)
		return

	var text: String
	if online:
		text = "Tu turno" if game.current_player == my_seat else "Turno de %s" % names[game.current_player]
	elif vs_ai:
		text = "Tu turno" if game.current_player == my_seat else "%s está pensando..." % names[ai_seat]
	else:
		text = "Turno de %s" % _mark_text(game.current_player)
	if game.forced_board == -1 and (not _single_seat() or game.current_player == my_seat):
		text += " - elegí cualquier tablero"
	status_label.text = text
	status_label.add_theme_color_override("font_color", Color.WHITE if (not _single_seat() or game.current_player == my_seat) else _mark_color(game.current_player))
	var mine := not _single_seat() or game.current_player == my_seat
	_style_banner(_mark_color(game.current_player), mine)
	var key := "%d:%d" % [game.current_player, game.cells.count(UltimateGame.NONE)]
	if key != _last_banner_key:
		_last_banner_key = key
		Fx.pop(turn_banner, 0.92, 0.25)


func _refresh_clocks() -> void:
	if replay and clock_labels[1] != null:
		var winner := int(replay_record.get("w", 0))
		for seat in [1, 2]:
			var tag := "Empate" if winner == 0 else ("Ganó" if winner == seat else "Perdió")
			var replay_label: Label = clock_labels[seat]
			replay_label.text = "%s (%s)\n%s" % [names[seat], _mark_text(seat), tag]
			replay_label.add_theme_color_override("font_color", colors[seat])
			replay_label.modulate.a = 1.0 if (winner == 0 or winner == seat) else 0.55
		return
	if not online or clock_labels[1] == null:
		return
	var now := Time.get_ticks_msec()
	for seat in [1, 2]:
		var ms: int = clocks_ms[seat]
		var running: bool = not finished and not game.is_over() and game.current_player == seat
		if running:
			ms = maxi(0, ms - (now - _clock_received_ms))
		var seconds := ceili(ms / 1000.0)
		var label: Label = clock_labels[seat]
		label.text = "%s\n%d:%02d" % [names[seat], seconds / 60, seconds % 60]
		if skips[seat] > 0:
			label.text += "\nSaltos %d/%d" % [skips[seat], max_skips]
		label.add_theme_color_override("font_color", colors[seat])
		label.modulate.a = 1.0 if running else 0.5


## Cartel del turno: relleno fuerte con el color del jugador cuando te toca, tenue cuando espera.
func _style_banner(color: Color, solid: bool) -> void:
	if turn_banner == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.15) if solid else Color(color, 0.16)
	style.border_color = color
	style.set_border_width_all(6 if solid else 3)
	style.set_corner_radius_all(22)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	turn_banner.add_theme_stylebox_override("panel", style)
	turn_banner.pivot_offset = turn_banner.size / 2.0


func _mark_text(mark: int) -> String:
	match mark:
		UltimateGame.X:
			return "X"
		UltimateGame.O:
			return "O"
		UltimateGame.DRAW:
			return "="
	return ""


func _mark_color(mark: int) -> Color:
	match mark:
		UltimateGame.X:
			return colors[1]
		UltimateGame.O:
			return colors[2]
	return Pal.muted


func _white_text(button: Button, white := true) -> void:
	var color := Color.WHITE if white else Pal.text
	for font_state in ["font_color", "font_pressed_color", "font_hover_pressed_color", "font_hover_color", "font_focus_color"]:
		button.add_theme_color_override(font_state, color)


func _flat(color: Color, radius: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style


func _style_button(button: Button, color: Color) -> void:
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("normal", _flat(color))
	button.add_theme_stylebox_override("hover", _flat(color.lightened(0.15)))
	button.add_theme_stylebox_override("pressed", _flat(color.lightened(0.3)))
	var off := Pal.cell_off if color == Pal.cell else color.darkened(0.25)
	button.add_theme_stylebox_override("disabled", _flat(off))


## Capa transparente encima del tablero donde se dibujan las flechas de apuntes.
class ArrowLayer extends Control:
	var screen: Control

	func _draw() -> void:
		if screen != null:
			screen.draw_arrows_on(self)
