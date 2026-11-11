extends Control
## Pantalla de partida: tablero 9x9 + relojes. Sirve para juego local (dos
## personas en el mismo cel) y online (el servidor decide y manda cada jugada).

signal move_requested(big: int, small: int)
signal resign_requested
signal exit_requested

const UltimateGame := preload("res://scripts/ultimate_game.gd")
const Profile := preload("res://scripts/profile.gd")

const COLOR_BG := Color("14151f")
const COLOR_PANEL := Color("22253a")
const COLOR_ACTIVE := Color("3d4a7a")
const COLOR_CELL := Color("2d3048")
const COLOR_DRAW := Color("8a8fa8")
const COLOR_TEXT := Color("e8eaf6")

var game := UltimateGame.new()
var online := false
var my_seat := 0
var finished := false
var disconnected := false
## Colores, nombres y relojes por asiento. Índice 1 = X, 2 = O (el 0 no se usa).
var colors: Array = [COLOR_DRAW, Profile.DEFAULT_X, Profile.DEFAULT_O]
var names: Array = ["", "X", "O"]
var clocks_ms: Array = [0, 0, 0]
## Saltos por tiempo de cada jugador; con `max_skips` pierde.
var skips: Array = [0, 0, 0]
var max_skips := 3
var _clock_received_ms := 0
var _result_text := ""

var status_label: Label
var clock_labels: Array = [null, null, null]
var left_button: Button
var new_game_button: Button
var panels: Array[PanelContainer] = []
var grids: Array[GridContainer] = []
var result_labels: Array[Label] = []
## small_buttons[big][small] -> Button
var small_buttons: Array = []


## Juego local: los dos jugadores comparten el cel, sin reloj.
func setup_local(profile: Profile) -> void:
	online = false
	colors = [COLOR_DRAW, profile.color_x, profile.color_o]
	names = ["", "X", "O"]


## Juego online: `start` es el mensaje {t:"start"} del servidor.
func setup_online(start: Dictionary, profile: Profile) -> void:
	online = true
	my_seat = int(start.get("you", 0))
	var server_names: Array = start.get("names", ["X", "O"])
	var server_colors: Array = start.get("colors", [])
	names = ["", str(server_names[0]), str(server_names[1])]
	colors = [COLOR_DRAW, Profile.DEFAULT_X, Profile.DEFAULT_O]
	if server_colors.size() == 2:
		colors[1] = Color.html(str(server_colors[0]))
		colors[2] = Color.html(str(server_colors[1]))
	_resolve_color_clash()
	max_skips = int(start.get("max_skips", 3))
	var clocks: Array = start.get("clocks", [0, 0])
	clocks_ms = [0, int(clocks[0]), int(clocks[1])]
	_clock_received_ms = Time.get_ticks_msec()


func _ready() -> void:
	_build_ui()
	_refresh()


func _process(_delta: float) -> void:
	if online:
		_refresh_clocks()


# --- Eventos del servidor ---------------------------------------------------

func apply_move(data: Dictionary) -> void:
	var big := int(data.get("big", -1))
	var small := int(data.get("small", -1))
	if not game.play(big, small):
		push_warning("El servidor mandó una jugada que no es legal acá: %d,%d" % [big, small])
	_set_clocks(data)
	_refresh()


## Al jugador de turno se le acabó el tiempo: le saltan el turno sin jugar.
func apply_skip(data: Dictionary) -> void:
	game.skip_turn()
	var counts: Array = data.get("skips", [])
	if counts.size() == 2:
		skips = [0, int(counts[0]), int(counts[1])]
	_set_clocks(data)
	_refresh()


func apply_over(data: Dictionary) -> void:
	_set_clocks(data)
	finished = true
	var winner := int(data.get("winner", 0))
	var reason := str(data.get("reason", ""))
	if winner == 0:
		_result_text = "Empate"
	elif winner == my_seat:
		_result_text = "Ganaste" + _reason_suffix(reason, true)
	else:
		_result_text = "Perdiste" + _reason_suffix(reason, false)
	_refresh()


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
			colors[theirs] = COLOR_DRAW


func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


# --- Construcción de la pantalla --------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 28)
	margin.add_child(root)

	if online:
		var clock_row := HBoxContainer.new()
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
	root.add_child(status_label)

	var ratio := AspectRatioContainer.new()
	ratio.ratio = 1.0
	ratio.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(ratio)

	var big_grid := GridContainer.new()
	big_grid.columns = 3
	big_grid.add_theme_constant_override("h_separation", 16)
	big_grid.add_theme_constant_override("v_separation", 16)
	ratio.add_child(big_grid)
	for big in 9:
		_build_big_cell(big_grid, big)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 24)
	root.add_child(buttons)

	left_button = _make_button("Menú", COLOR_CELL)
	left_button.pressed.connect(_on_left_pressed)
	buttons.add_child(left_button)

	if not online:
		new_game_button = _make_button("Nueva partida", COLOR_ACTIVE)
		new_game_button.pressed.connect(_on_new_game_pressed)
		buttons.add_child(new_game_button)


func _make_button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 120)
	button.add_theme_font_size_override("font_size", 44)
	button.add_theme_color_override("font_color", COLOR_TEXT)
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
		_style_button(button, COLOR_CELL)
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
	if online:
		# El servidor es quien decide: acá solo se pide la jugada.
		if finished or game.current_player != my_seat or not game.is_legal(big, small):
			return
		move_requested.emit(big, small)
	elif game.play(big, small):
		_refresh()


func _on_left_pressed() -> void:
	if online and not finished:
		resign_requested.emit()
	else:
		exit_requested.emit()


func _on_new_game_pressed() -> void:
	game.reset()
	_refresh()


# --- Refrescar lo que se ve -------------------------------------------------

func _refresh() -> void:
	var legal := {}
	if not finished:
		for move in game.legal_moves():
			legal[move] = true
	var can_play := not finished and (not online or game.current_player == my_seat)
	# Tableros donde hay que jugar ahora (un tablero ganado sigue contando si le quedan casillas).
	var playable_boards := {}
	for move in legal:
		playable_boards[move.x] = true

	for big in 9:
		var board_result: int = game.board_results[big]
		var decided := board_result != UltimateGame.NONE
		var panel_color := COLOR_ACTIVE if playable_boards.has(big) else COLOR_PANEL
		if decided:
			panel_color = panel_color.lerp(_mark_color(board_result), 0.12)
		panels[big].add_theme_stylebox_override("panel", _flat(panel_color, 18))

		for small in 9:
			var mark := game.get_cell(big, small)
			var button: Button = small_buttons[big][small]
			button.text = _mark_text(mark)
			button.disabled = not (can_play and legal.has(Vector2i(big, small)))
			button.add_theme_color_override("font_disabled_color", _mark_color(mark))

		var label := result_labels[big]
		label.visible = decided
		label.text = _mark_text(board_result)
		# Translúcida para que se vean y se puedan tocar las casillas de abajo.
		var label_color := _mark_color(board_result)
		label_color.a = 0.3
		label.add_theme_color_override("font_color", label_color)

	if online:
		left_button.text = "Volver al menú" if finished else "Rendirse"
	_refresh_status()
	_refresh_clocks()


func _refresh_status() -> void:
	if finished and online:
		status_label.text = _result_text
		status_label.add_theme_color_override("font_color", COLOR_TEXT)
		return
	if game.is_over():
		if game.result == UltimateGame.DRAW:
			status_label.text = "Empate"
			status_label.add_theme_color_override("font_color", COLOR_DRAW)
		else:
			status_label.text = "Ganó %s" % _mark_text(game.result)
			status_label.add_theme_color_override("font_color", _mark_color(game.result))
		return

	var text: String
	if online:
		text = "Tu turno" if game.current_player == my_seat else "Turno de %s" % names[game.current_player]
	else:
		text = "Turno de %s" % _mark_text(game.current_player)
	if game.forced_board == -1 and (not online or game.current_player == my_seat):
		text += " - elegí cualquier tablero"
	status_label.text = text
	status_label.add_theme_color_override("font_color", _mark_color(game.current_player))


func _refresh_clocks() -> void:
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
	return COLOR_DRAW


func _flat(color: Color, radius: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style


func _style_button(button: Button, color: Color) -> void:
	button.add_theme_stylebox_override("normal", _flat(color))
	button.add_theme_stylebox_override("hover", _flat(color.lightened(0.15)))
	button.add_theme_stylebox_override("pressed", _flat(color.lightened(0.3)))
	button.add_theme_stylebox_override("disabled", _flat(color.darkened(0.25)))
