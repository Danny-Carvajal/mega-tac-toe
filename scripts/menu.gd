extends Control
## Menú principal: nombre, colores de las piezas, partida rápida, salas con código
## y juego local.

signal local_requested
signal online_requested(kind: String, code: String)
signal cancel_requested

const Profile := preload("res://scripts/profile.gd")

const COLOR_BG := Color("14151f")
const COLOR_CELL := Color("2d3048")
const COLOR_ACTIVE := Color("3d4a7a")
const COLOR_TEXT := Color("e8eaf6")
const COLOR_MUTED := Color("8a8fa8")

var profile: Profile

var name_edit: LineEdit
var color_x_button: ColorPickerButton
var color_o_button: ColorPickerButton
var code_edit: LineEdit
var url_edit: LineEdit
var status_label: Label
var cancel_button: Button
var _action_buttons: Array[Button] = []


func _ready() -> void:
	if profile == null:
		profile = Profile.new()
	_build_ui()


func set_status(text: String) -> void:
	status_label.text = text


func set_busy(busy: bool) -> void:
	for button in _action_buttons:
		button.disabled = busy
	cancel_button.visible = busy


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 60)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 28)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Mega Tic Toe"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	root.add_child(title)

	root.add_child(_caption("Tu nombre"))
	name_edit = _make_edit(profile.player_name, "Nombre")
	name_edit.max_length = 16
	root.add_child(name_edit)

	root.add_child(_caption("Tus colores (cuando jugás con X y con O)"))
	var colors := HBoxContainer.new()
	colors.add_theme_constant_override("separation", 24)
	root.add_child(colors)
	color_x_button = _make_color_button("X", profile.color_x, colors)
	color_o_button = _make_color_button("O", profile.color_o, colors)

	var quick := _make_button("Partida rápida", COLOR_ACTIVE)
	quick.pressed.connect(func() -> void: _request("queue", ""))
	root.add_child(quick)

	var create := _make_button("Crear sala privada", COLOR_CELL)
	create.pressed.connect(func() -> void: _request("create", ""))
	root.add_child(create)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 24)
	root.add_child(join_row)
	code_edit = _make_edit("", "Código")
	code_edit.max_length = 4
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(code_edit)
	var join := _make_button("Unirme", COLOR_CELL)
	join.size_flags_horizontal = Control.SIZE_SHRINK_END
	join.custom_minimum_size = Vector2(360, 120)
	join.pressed.connect(func() -> void: _request("join", code_edit.text.strip_edges().to_upper()))
	join_row.add_child(join)

	var local := _make_button("Jugar local (2 en el mismo cel)", COLOR_CELL)
	local.pressed.connect(func() -> void:
		_save_profile()
		local_requested.emit())
	root.add_child(local)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 40)
	status_label.add_theme_color_override("font_color", COLOR_TEXT)
	root.add_child(status_label)

	cancel_button = _make_button("Cancelar", COLOR_CELL)
	cancel_button.visible = false
	cancel_button.pressed.connect(func() -> void: cancel_requested.emit())
	root.add_child(cancel_button)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	root.add_child(_caption("Servidor"))
	url_edit = _make_edit(profile.server_url, "ws://...")
	url_edit.add_theme_font_size_override("font_size", 32)
	root.add_child(url_edit)


func _request(kind: String, code: String) -> void:
	if kind == "join" and code.length() != 4:
		set_status("El código tiene 4 letras")
		return
	_save_profile()
	online_requested.emit(kind, code)


func _save_profile() -> void:
	var player_name := name_edit.text.strip_edges()
	profile.player_name = player_name if not player_name.is_empty() else "Jugador"
	profile.color_x = color_x_button.color
	profile.color_o = color_o_button.color
	var url := url_edit.text.strip_edges()
	profile.server_url = url if not url.is_empty() else Profile.DEFAULT_SERVER_URL
	profile.save_to_disk()


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", COLOR_MUTED)
	return label


func _make_edit(text: String, placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, 110)
	edit.add_theme_font_size_override("font_size", 44)
	return edit


func _make_color_button(mark: String, color: Color, parent: Container) -> ColorPickerButton:
	var button := ColorPickerButton.new()
	button.text = "Color de " + mark
	button.color = color
	button.edit_alpha = false
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 110)
	button.add_theme_font_size_override("font_size", 40)
	parent.add_child(button)
	return button


func _make_button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 120)
	button.add_theme_font_size_override("font_size", 44)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(14)
		match state:
			"normal":
				style.bg_color = color
			"hover":
				style.bg_color = color.lightened(0.15)
			"pressed":
				style.bg_color = color.lightened(0.3)
			"disabled":
				style.bg_color = color.darkened(0.3)
		button.add_theme_stylebox_override(state, style)
	_action_buttons.append(button)
	return button
