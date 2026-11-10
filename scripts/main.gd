extends Control
## Pantalla principal: arma el tablero 9x9 por código y lo conecta con UltimateGame.

const UltimateGame := preload("res://scripts/ultimate_game.gd")

const COLOR_BG := Color("1b1d2a")
const COLOR_PANEL := Color("2a2d40")
const COLOR_ACTIVE := Color("3d4a7a")
const COLOR_CELL := Color("353952")
const COLOR_X := Color("ff6b6b")
const COLOR_O := Color("4ecdc4")
const COLOR_DRAW := Color("8a8fa8")
const COLOR_TEXT := Color("e8eaf6")

var game := UltimateGame.new()

var status_label: Label
var panels: Array[PanelContainer] = []
var grids: Array[GridContainer] = []
var result_labels: Array[Label] = []
## small_buttons[big][small] -> Button
var small_buttons: Array = []


func _ready() -> void:
	_build_ui()
	_refresh()


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
	root.add_theme_constant_override("separation", 32)
	margin.add_child(root)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 56)
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

	var reset_button := Button.new()
	reset_button.text = "Nueva partida"
	reset_button.custom_minimum_size = Vector2(0, 120)
	reset_button.add_theme_font_size_override("font_size", 44)
	_style_button(reset_button, COLOR_ACTIVE)
	reset_button.add_theme_color_override("font_color", COLOR_TEXT)
	reset_button.pressed.connect(_on_reset_pressed)
	root.add_child(reset_button)


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

	# Marca grande que tapa el tablero cuando ya se decidió.
	var result_label := Label.new()
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 220)
	result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_label.visible = false
	panel.add_child(result_label)
	result_labels.append(result_label)


func _on_small_pressed(big: int, small: int) -> void:
	if game.play(big, small):
		_refresh()


func _on_reset_pressed() -> void:
	game.reset()
	_refresh()


func _refresh() -> void:
	var legal := {}
	for move in game.legal_moves():
		legal[move] = true

	for big in 9:
		var board_result: int = game.board_results[big]
		var decided := board_result != UltimateGame.NONE
		var active := (
			not game.is_over()
			and not decided
			and (game.forced_board == -1 or game.forced_board == big)
		)
		panels[big].add_theme_stylebox_override("panel", _flat(COLOR_ACTIVE if active else COLOR_PANEL, 18))
		grids[big].modulate.a = 0.25 if decided else 1.0

		for small in 9:
			var mark := game.get_cell(big, small)
			var button: Button = small_buttons[big][small]
			button.text = _mark_text(mark)
			button.disabled = not legal.has(Vector2i(big, small))
			button.add_theme_color_override("font_disabled_color", _mark_color(mark))

		var label := result_labels[big]
		label.visible = decided
		label.text = _mark_text(board_result)
		label.add_theme_color_override("font_color", _mark_color(board_result))

	_refresh_status()


func _refresh_status() -> void:
	if game.is_over():
		if game.result == UltimateGame.DRAW:
			status_label.text = "Empate"
			status_label.add_theme_color_override("font_color", COLOR_DRAW)
		else:
			status_label.text = "Ganó %s" % _mark_text(game.result)
			status_label.add_theme_color_override("font_color", _mark_color(game.result))
		return

	var text := "Turno de %s" % _mark_text(game.current_player)
	if game.forced_board == -1:
		text += " - elegí cualquier tablero"
	status_label.text = text
	status_label.add_theme_color_override("font_color", _mark_color(game.current_player))


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
			return COLOR_X
		UltimateGame.O:
			return COLOR_O
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
