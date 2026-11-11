extends Control
## Pantalla de partida: tablero 9x9 + relojes. Sirve para juego local (dos
## personas en el mismo cel) y online (el servidor decide y manda cada jugada).

signal move_requested(big: int, small: int)
signal resign_requested
signal exit_requested

const UltimateGame := preload("res://scripts/ultimate_game.gd")
const Profile := preload("res://scripts/profile.gd")
const Fx := preload("res://scripts/fx.gd")

const COLOR_BG := Color("14151f")
const COLOR_PANEL := Color("22253a")
const COLOR_ACTIVE := Color("3d4a7a")
const COLOR_CELL := Color("2d3048")
const COLOR_DRAW := Color("8a8fa8")
const COLOR_TEXT := Color("e8eaf6")
const ARROW_ALPHA := 0.7

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
## Aviso temporal que reemplaza el estado (errores del servidor, reglas distintas).
var _notice := ""
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
	colors = [COLOR_DRAW, profile.color_x, profile.color_o]
	names = ["", "X", "O"]


## Juego online: `start` es el mensaje {t:"start"} del servidor.
func setup_online(start: Dictionary, profile: Profile) -> void:
	online = true
	arrow_tip_color = profile.color_x
	arrow_base_color = profile.color_o
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
	# Un servidor viejo no manda "rules": cuenta como versión 1.
	if int(start.get("rules", 1)) != UltimateGame.RULES_VERSION:
		_notice = "El servidor tiene otras reglas (todavía no se actualizó). Algunas jugadas no van a pasar."
		_notice_until_ms = 1 << 60
	var clocks: Array = start.get("clocks", [0, 0])
	clocks_ms = [0, int(clocks[0]), int(clocks[1])]
	_clock_received_ms = Time.get_ticks_msec()


func _ready() -> void:
	_build_ui()
	_refresh()


func _process(_delta: float) -> void:
	if online:
		_refresh_clocks()
	if not _notice.is_empty() and Time.get_ticks_msec() > _notice_until_ms:
		_notice = ""
		_refresh_status()


## Muestra un aviso en lugar del estado (por ejemplo, un error del servidor).
func show_notice(text: String, duration_ms := 3500) -> void:
	_notice = text
	_notice_until_ms = Time.get_ticks_msec() + duration_ms
	_refresh_status()


# --- Eventos del servidor ---------------------------------------------------

func apply_move(data: Dictionary) -> void:
	var big := int(data.get("big", -1))
	var small := int(data.get("small", -1))
	var mover := game.current_player
	if game.play(big, small):
		last_move = Vector2i(big, small)
		last_move_player = mover
	else:
		push_warning("El servidor mandó una jugada que no es legal acá: %d,%d" % [big, small])
	_set_clocks(data)
	_refresh()


## Al jugador de turno se le acabó el tiempo: le saltan el turno sin jugar.
func apply_skip(data: Dictionary) -> void:
	game.skip_turn()
	last_move = Vector2i(-1, -1)  # la jugada anterior se deshizo
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

	var root := BoxContainer.new()
	root.vertical = true
	root.add_theme_constant_override("separation", 28)
	margin.add_child(root)
	root_box = root

	if online:
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
	root.add_child(status_label)

	var ratio := AspectRatioContainer.new()
	ratio.ratio = 1.0
	ratio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ratio.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(ratio)
	ratio_box = ratio

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

	left_button = _make_button("Menú", COLOR_CELL)
	left_button.pressed.connect(_on_left_pressed)
	buttons.add_child(left_button)

	if not online:
		new_game_button = _make_button("Nueva partida", COLOR_ACTIVE)
		new_game_button.pressed.connect(_on_new_game_pressed)
		buttons.add_child(new_game_button)

	notes_button = _make_button("Apuntes", COLOR_CELL)
	notes_button.toggle_mode = true
	notes_button.add_theme_stylebox_override("pressed", _flat(Color("3b6f8f")))
	notes_button.add_theme_stylebox_override("hover_pressed", _flat(Color("3b6f8f")))
	notes_button.toggled.connect(_on_notes_toggled)
	buttons.add_child(notes_button)
	clear_notes_button = _make_button("Borrar", COLOR_CELL)
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
	for part in [clock_row, status_label, ratio_box, buttons_row, side_box, side_spacer]:
		if part != null and part.get_parent() != null:
			part.get_parent().remove_child(part)
	if wide:
		root_box.vertical = false
		root_box.add_child(ratio_box)
		root_box.add_child(side_box)
		if clock_row != null:
			side_box.add_child(clock_row)
		side_box.add_child(status_label)
		side_box.add_child(side_spacer)
		side_box.add_child(buttons_row)
	else:
		root_box.vertical = true
		if clock_row != null:
			root_box.add_child(clock_row)
		root_box.add_child(status_label)
		root_box.add_child(ratio_box)
		root_box.add_child(buttons_row)
	if clock_row != null:
		clock_row.vertical = wide
	buttons_row.vertical = wide
	if notes_layer != null:
		notes_layer.queue_redraw.call_deferred()


func _make_button(text: String, color: Color) -> Button:
	var button := Button.new()
	Fx.press_feedback(button)
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
	else:
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
	var style := _flat(Color("1f2133"), 24)
	style.border_color = COLOR_ACTIVE
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
	title.add_theme_color_override("font_color", COLOR_TEXT)
	box.add_child(title)
	var note := Label.new()
	note.text = "Perdés la partida."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 38)
	note.add_theme_color_override("font_color", COLOR_DRAW)
	box.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var keep := _make_button("Seguir jugando", COLOR_ACTIVE)
	keep.pressed.connect(func() -> void: confirm_layer.visible = false)
	row.add_child(keep)
	var yes := _make_button("Rendirme", Color("8f2f34"))
	yes.pressed.connect(_confirm_resign)
	row.add_child(yes)


func _on_new_game_pressed() -> void:
	game.reset()
	last_move = Vector2i(-1, -1)
	clear_arrows()
	_refresh()


# --- Última jugada del rival -------------------------------------------------

## Resalta (borde del color de quien jugó + brillo suave) la última jugada a la que hay
## que responder. En online solo se marca la del rival, no la propia.
func _apply_highlight() -> void:
	var target := Vector2i(-1, -1)
	if last_move.x >= 0 and (not online or last_move_player != my_seat):
		target = last_move
	if target == _highlighted:
		return
	if _highlight_tween != null:
		_highlight_tween.kill()
		_highlight_tween = null
	if _highlighted.x >= 0:
		var old: Button = small_buttons[_highlighted.x][_highlighted.y]
		old.modulate.a = 1.0
		_style_button(old, COLOR_CELL)
	_highlighted = target
	if target.x >= 0:
		var button: Button = small_buttons[target.x][target.y]
		var color: Color = colors[last_move_player]
		var base := COLOR_CELL.lerp(color, 0.28)
		for state in ["normal", "hover", "pressed", "disabled"]:
			var style := _flat(base)
			style.border_color = color
			style.set_border_width_all(5)
			button.add_theme_stylebox_override(state, style)
		_highlight_tween = Fx.glow(button)


# --- Apuntes: flechas sobre el tablero -----------------------------------------

func _on_notes_toggled(on: bool) -> void:
	notes_mode = on
	clear_notes_button.visible = on
	_drag_from = Vector2i(-1, -1)
	notes_layer.queue_redraw()
	if on:
		show_notice("Apuntes: arrastrá sobre el tablero para dibujar una flecha", 3000)


func clear_arrows() -> void:
	arrows.clear()
	notes_layer.queue_redraw()


func _input(event: InputEvent) -> void:
	if not notes_mode or notes_layer == null or confirm_layer.visible:
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
			if mark != UltimateGame.NONE and _prev_cells[big * 9 + small] == UltimateGame.NONE:
				Fx.pop(button)
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
	_refresh_status()
	_refresh_clocks()


func _refresh_status() -> void:
	if not _notice.is_empty() and not finished:
		status_label.text = _notice
		status_label.add_theme_color_override("font_color", Color("ffd24d"))
		return
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


## Capa transparente encima del tablero donde se dibujan las flechas de apuntes.
class ArrowLayer extends Control:
	var screen: Control

	func _draw() -> void:
		if screen != null:
			screen.draw_arrows_on(self)
