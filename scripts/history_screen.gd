extends Control
## Lista de partidas guardadas. Tocar una abre la repetición.

signal back_requested
signal game_selected(record: Dictionary)

const Pal := preload("res://scripts/pal.gd")
const History := preload("res://scripts/history.gd")
const Fx := preload("res://scripts/fx.gd")
const COLOR_WIN := Color("3ecf8e")
const COLOR_LOSS := Color("e5484d")

var history: History
var _margin: MarginContainer


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Pal.bg
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 24)
	_margin.add_child(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	root.add_child(top)
	var back := _button("Volver", Pal.cell)
	back.custom_minimum_size = Vector2(260, 100)
	back.pressed.connect(func() -> void: back_requested.emit())
	top.add_child(back)
	var heading := Label.new()
	heading.text = "Historial"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 64)
	heading.add_theme_color_override("font_color", Pal.text)
	top.add_child(heading)
	var balance := Control.new()
	balance.custom_minimum_size = Vector2(260, 0)
	top.add_child(balance)

	if history.games.is_empty():
		var empty := Label.new()
		empty.text = "Todavía no hay partidas guardadas.\nLas partidas online que termines aparecen acá."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 40)
		empty.add_theme_color_override("font_color", Pal.muted)
		root.add_child(empty)
	else:
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		root.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 18)
		scroll.add_child(list)
		for record in history.games:
			list.add_child(_game_card(record))
		Fx.stagger_in.call_deferred(list.get_children().slice(0, 8))
	resized.connect(_update_margins)
	_update_margins()


func _update_margins() -> void:
	var side := maxi(40, int((size.x - 1000.0) / 2.0))
	_margin.add_theme_constant_override("margin_left", side)
	_margin.add_theme_constant_override("margin_right", side)
	_margin.add_theme_constant_override("margin_top", 50)
	_margin.add_theme_constant_override("margin_bottom", 40)


func _game_card(record: Dictionary) -> Button:
	var recorded_names: Array = record.get("n", ["X", "O"])
	var my_seat := int(record.get("me", 0))
	var winner := int(record.get("w", 0))
	var result_text := "Empate"
	var color: Color = Pal.muted
	if winner != 0:
		if winner == my_seat:
			result_text = "Ganaste"
			color = COLOR_WIN
		else:
			result_text = "Perdiste"
			color = COLOR_LOSS
	var moves := History.decode(str(record.get("m", ""))).size()
	var button := Button.new()
	button.text = "%s  vs  %s\n%s · %d jugadas · %s" % [recorded_names[0], recorded_names[1], result_text, moves, History.format_time(int(record.get("t", 0)))]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 150)
	button.add_theme_font_size_override("font_size", 38)
	for font_state in ["font_color", "font_pressed_color", "font_hover_pressed_color", "font_hover_color", "font_focus_color"]:
		button.add_theme_color_override(font_state, Pal.text)
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Pal.card if state == "normal" else Pal.cell
		style.set_corner_radius_all(18)
		style.border_color = color
		style.border_width_left = 14
		style.content_margin_left = 40
		style.content_margin_right = 24
		style.content_margin_top = 18
		style.content_margin_bottom = 18
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	Fx.press_feedback(button)
	button.pressed.connect(func() -> void: game_selected.emit(record))
	return button


func _button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 120)
	button.add_theme_font_size_override("font_size", 44)
	for font_state in ["font_color", "font_pressed_color", "font_hover_pressed_color", "font_hover_color", "font_focus_color"]:
		button.add_theme_color_override(font_state, Pal.text)
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color if state == "normal" else color.lightened(0.15)
		style.set_corner_radius_all(14)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	Fx.press_feedback(button)
	return button
