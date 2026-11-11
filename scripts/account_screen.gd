extends Control
## Pantalla de cuenta: crear cuenta, entrar, salir y guardar ahora.

signal back_requested
signal guest_requested
signal logged_out

const Pal := preload("res://scripts/pal.gd")

var account  # Account
## true = es la pantalla de arranque: primero se entra o se elige invitado.
var gate := false

var _user_edit: LineEdit
var _pass_edit: LineEdit
var _status: Label
var _box: VBoxContainer
var _buttons: Array = []


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Pal.bg
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 60)
	add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(900, 0)
	_box.add_theme_constant_override("separation", 24)
	center.add_child(_box)
	account.changed.connect(_build)
	_build()


func apply_layout(_is_wide: bool) -> void:
	pass


func _build() -> void:
	for child in _box.get_children():
		child.queue_free()
		_box.remove_child(child)
	_buttons.clear()
	if gate and account.is_logged_in():
		back_requested.emit.call_deferred()
		return
	var title := _add_label("Mega Tac Toe" if gate else "Cuenta", 110 if gate else 72, Pal.text)
	if gate:
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if account.is_logged_in():
		_add_label("Sesión: %s" % account.user, 48, Pal.accent)
		_add_label("Tus monedas, cosméticos, stats e historial se guardan solos en tu cuenta y los tenés en cualquier dispositivo.", 34, Pal.muted)
		var save := _button("Guardar ahora", Pal.active)
		save.pressed.connect(func() -> void:
			account.sync_now()
			account.status = "Guardando..."
			_refresh_status())
		_box.add_child(save)
		var out := _button("Cerrar sesión", Pal.cell)
		out.pressed.connect(func() -> void:
			account.logout()
			logged_out.emit())
		_box.add_child(out)
	else:
		_add_label("Entrá o creá una cuenta para no perder nada y jugar clasificatorias. Como invitado jugás con el nombre Guest.", 34, Pal.muted)
		_user_edit = _edit("Usuario", false)
		_box.add_child(_user_edit)
		_pass_edit = _edit("Contraseña", true)
		_box.add_child(_pass_edit)
		var enter := _button("Entrar", Pal.active)
		enter.pressed.connect(func() -> void:
			if not account.busy:
				account.login(_user_edit.text.strip_edges(), _pass_edit.text))
		_box.add_child(enter)
		var create := _button("Crear cuenta", Pal.cell)
		create.pressed.connect(func() -> void:
			if not account.busy:
				account.register(_user_edit.text.strip_edges(), _pass_edit.text))
		_box.add_child(create)
		if gate:
			var guest := _button("Entrar como invitado", Pal.cell)
			guest.pressed.connect(func() -> void: guest_requested.emit())
			_box.add_child(guest)
		_add_label("Al crear la cuenta se sube lo que ya tenés en este dispositivo. Al entrar a una cuenta que ya existe, se baja lo de la cuenta y reemplaza lo de acá.", 30, Pal.muted)
	_status = _add_label(account.status, 36, Pal.text)
	if not gate:
		var back := _button("Volver", Pal.cell)
		back.pressed.connect(func() -> void: back_requested.emit())
		_box.add_child(back)


func _refresh_status() -> void:
	if _status != null:
		_status.text = account.status


func _add_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_box.add_child(label)
	return label


func _edit(placeholder: String, secret: bool) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.secret = secret
	edit.max_length = 64
	edit.custom_minimum_size = Vector2(0, 110)
	edit.add_theme_font_size_override("font_size", 44)
	var style := StyleBoxFlat.new()
	style.bg_color = Pal.panel
	style.set_corner_radius_all(14)
	style.content_margin_left = 20
	style.content_margin_right = 20
	edit.add_theme_stylebox_override("normal", style)
	edit.add_theme_stylebox_override("focus", style)
	edit.add_theme_color_override("font_color", Pal.text)
	edit.add_theme_color_override("font_placeholder_color", Pal.muted)
	edit.add_theme_color_override("caret_color", Pal.text)
	return edit


func _button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 120)
	button.add_theme_font_size_override("font_size", 44)
	for font_state in ["font_color", "font_pressed_color", "font_hover_pressed_color", "font_hover_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(font_state, Pal.text)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(14)
		style.set_content_margin_all(20)
		match state:
			"normal":
				style.bg_color = color
			"hover":
				style.bg_color = color.lightened(0.15)
			"pressed":
				style.bg_color = color.lightened(0.3)
			"disabled":
				style.bg_color = color.darkened(0.35)
		button.add_theme_stylebox_override(state, style)
	return button
