extends Control
## Menú principal. Dos páginas estilo Clash Royale: la principal (nombre, partida rápida,
## salas, local) y, a la izquierda, la de colores. Se pasa de una a otra con swipe o con la
## flecha. La dirección del servidor vive en una cascada arriba a la derecha.

signal local_requested
signal online_requested(kind: String, code: String)
signal cancel_requested

const Profile := preload("res://scripts/profile.gd")

const COLOR_BG := Color("14151f")
const COLOR_CELL := Color("2d3048")
const COLOR_ACTIVE := Color("3d4a7a")
const COLOR_TEXT := Color("e8eaf6")
const COLOR_MUTED := Color("8a8fa8")

const PRESETS := ["e5484d", "f97316", "facc15", "22c55e", "06b6d4", "3b82f6", "a855f7", "ec4899"]
const NAV_HEIGHT := 170.0
const SWIPE_START_PX := 40.0
const SWIPE_OPEN_FRACTION := 0.3

var profile: Profile
var color_x: Color
var color_o: Color
var selected_mark := "X"
var colors_open := false

var name_edit: LineEdit
var code_edit: LineEdit
var url_edit: LineEdit
var status_label: Label
var cancel_button: Button
var picker: ColorPicker
var server_panel: PanelContainer
var server_button: Button
var main_page: Control
var colors_page: Control
var pager: Control
var nav: NavBar

var _action_buttons: Array[Button] = []
var _swatch_x: Button
var _swatch_o: Button
var _page_offset := 0.0
var _pressing := false
var _dragging := false
var _press_pos := Vector2.ZERO
var _press_offset := 0.0
var _block_taps_until := 0
var _tween: Tween


func _ready() -> void:
	if profile == null:
		profile = Profile.new()
	color_x = profile.color_x
	color_o = profile.color_o
	_build_ui()
	_select_mark("X")


func set_status(text: String) -> void:
	status_label.text = text


func set_busy(busy: bool) -> void:
	for button in _action_buttons:
		button.disabled = busy
	cancel_button.visible = busy
	if busy:
		server_panel.visible = false
		set_colors_open(false)


## El botón atrás de Android cierra primero lo que esté abierto. Devuelve true si lo consumió.
func handle_back() -> bool:
	if server_panel.visible:
		server_panel.visible = false
		return true
	if colors_open:
		set_colors_open(false)
		return true
	return false


func set_colors_open(open: bool, animate := true) -> void:
	colors_open = open
	if open:
		server_panel.visible = false
		get_viewport().gui_release_focus()
	var target := pager.size.x if open else 0.0
	if _tween != null:
		_tween.kill()
	if animate:
		_tween = create_tween()
		_tween.tween_method(_set_offset, _page_offset, target, 0.22) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_set_offset(target)


# ---------------------------------------------------------------- construcción

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	pager = Control.new()
	pager.set_anchors_preset(Control.PRESET_FULL_RECT)
	pager.offset_bottom = -NAV_HEIGHT
	pager.clip_contents = true
	add_child(pager)
	pager.resized.connect(_layout_pages)

	# Barra de pestañas de abajo (como Clash Royale): la pestaña activa sube y muestra su nombre.
	nav = NavBar.new()
	nav.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	nav.offset_top = -NAV_HEIGHT
	nav.tab_pressed.connect(func(index: int) -> void:
		if _taps_allowed():
			set_colors_open(index == 0))
	add_child(nav)

	main_page = Control.new()
	pager.add_child(main_page)
	colors_page = Control.new()
	pager.add_child(colors_page)

	_build_main_page()
	_build_colors_page()
	_build_server_panel()
	_layout_pages.call_deferred()


func _page_root(page: Control) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 60)
	page.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 28)
	margin.add_child(root)
	return root


func _build_main_page() -> void:
	var root := _page_root(main_page)

	var top := HBoxContainer.new()
	root.add_child(top)
	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(top_spacer)
	server_button = _make_small_button("Servidor")
	server_button.pressed.connect(_toggle_server_panel)
	top.add_child(server_button)

	var title := Label.new()
	title.text = "Mega Tac Toe"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	root.add_child(title)

	root.add_child(_caption("Tu nombre"))
	name_edit = _make_edit(profile.player_name, "Nombre")
	name_edit.max_length = 16
	root.add_child(name_edit)

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
		if not _taps_allowed():
			return
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

	# Flecha suave al centro del borde izquierdo: lleva a los colores.
	var to_colors := Chevron.new(-1)
	to_colors.pressed.connect(func() -> void:
		if _taps_allowed():
			set_colors_open(true))
	main_page.add_child(to_colors)
	_anchor_chevron(to_colors, false)


func _build_colors_page() -> void:
	var root := _page_root(colors_page)

	var top := HBoxContainer.new()
	root.add_child(top)
	var heading := Label.new()
	heading.text = "Tus colores"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size", 64)
	heading.add_theme_color_override("font_color", COLOR_TEXT)
	top.add_child(heading)

	root.add_child(_caption("Elegí una pieza y cambiale el color"))
	var swatches := HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 24)
	root.add_child(swatches)
	_swatch_x = _make_swatch("X")
	_swatch_o = _make_swatch("O")
	swatches.add_child(_swatch_x)
	swatches.add_child(_swatch_o)

	# Selector grande: cuadro de saturación/brillo y barra de tono a lo ancho de la pantalla.
	var center := CenterContainer.new()
	root.add_child(center)
	picker = ColorPicker.new()
	picker.edit_alpha = false
	picker.sliders_visible = false
	picker.hex_visible = false
	picker.color_modes_visible = false
	picker.sampler_visible = false
	picker.presets_visible = false
	picker.can_add_swatches = false
	picker.add_theme_constant_override("sv_width", 760)
	picker.add_theme_constant_override("sv_height", 620)
	picker.add_theme_constant_override("h_width", 110)
	picker.add_theme_constant_override("margin", 20)
	picker.color_changed.connect(_on_picker_changed)
	center.add_child(picker)

	root.add_child(_caption("Atajos"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	root.add_child(grid)
	for hex in PRESETS:
		var preset := Button.new()
		preset.custom_minimum_size = Vector2(0, 100)
		preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(preset, Color(hex))
		preset.pressed.connect(func() -> void:
			if _taps_allowed():
				_set_selected_color(Color(hex)))
		grid.add_child(preset)

	var reset := _make_small_button("Volver a rojo y azul")
	reset.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reset.pressed.connect(func() -> void:
		if not _taps_allowed():
			return
		color_x = Profile.DEFAULT_X
		color_o = Profile.DEFAULT_O
		_select_mark(selected_mark))
	root.add_child(reset)

	var to_main := Chevron.new(1)
	to_main.pressed.connect(func() -> void:
		if _taps_allowed():
			set_colors_open(false))
	colors_page.add_child(to_main)
	_anchor_chevron(to_main, true)


func _build_server_panel() -> void:
	server_panel = PanelContainer.new()
	server_panel.visible = false
	server_panel.custom_minimum_size = Vector2(900, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1f2133")
	style.border_color = COLOR_ACTIVE
	style.set_border_width_all(3)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(28)
	server_panel.add_theme_stylebox_override("panel", style)
	main_page.add_child(server_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	server_panel.add_child(box)
	box.add_child(_caption("Servidor"))
	url_edit = _make_edit(profile.server_url, "wss://...")
	url_edit.add_theme_font_size_override("font_size", 34)
	url_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	box.add_child(url_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	var default_button := _make_small_button("Usar el de Render")
	default_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	default_button.pressed.connect(func() -> void:
		url_edit.text = Profile.DEFAULT_SERVER_URL)
	row.add_child(default_button)
	var done := _make_small_button("Listo")
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.pressed.connect(func() -> void: server_panel.visible = false)
	row.add_child(done)


## Pega la flecha al borde (izquierdo o derecho) de su página, centrada en vertical.
func _anchor_chevron(chevron: Control, right_edge: bool) -> void:
	var edge := 1.0 if right_edge else 0.0
	chevron.anchor_left = edge
	chevron.anchor_right = edge
	chevron.anchor_top = 0.5
	chevron.anchor_bottom = 0.5
	chevron.offset_left = -64.0 if right_edge else 0.0
	chevron.offset_right = 0.0 if right_edge else 64.0
	chevron.offset_top = -120.0
	chevron.offset_bottom = 120.0


func _toggle_server_panel() -> void:
	if not _taps_allowed():
		return
	server_panel.visible = not server_panel.visible
	if server_panel.visible:
		server_panel.reset_size()
		var button_rect := server_button.get_global_rect()
		var origin := main_page.get_global_rect().position
		server_panel.position = Vector2(
			button_rect.end.x - origin.x - server_panel.size.x,
			button_rect.end.y - origin.y + 16)


# ---------------------------------------------------------------- páginas y swipe

func _layout_pages() -> void:
	main_page.size = pager.size
	colors_page.size = pager.size
	if _tween == null or not _tween.is_running():
		_set_offset(pager.size.x if colors_open else 0.0)
	else:
		_set_offset(_page_offset)


func _set_offset(offset: float) -> void:
	_page_offset = clampf(offset, 0.0, pager.size.x)
	main_page.position.x = _page_offset
	colors_page.position.x = _page_offset - pager.size.x
	if nav != null:
		nav.set_progress(1.0 - _page_offset / maxf(pager.size.x, 1.0))


func _input(event: InputEvent) -> void:
	if pager == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = _swipe_allowed(event.position)
			_dragging = false
			_press_pos = event.position
			_press_offset = _page_offset
		else:
			if _dragging:
				_finish_drag()
				_block_taps_until = Time.get_ticks_msec() + 200
			_pressing = false
			_dragging = false
	elif event is InputEventMouseMotion and _pressing:
		var delta: Vector2 = event.position - _press_pos
		if not _dragging and absf(delta.x) > SWIPE_START_PX and absf(delta.x) > absf(delta.y) * 1.5:
			_dragging = true
			if _tween != null:
				_tween.kill()
			get_viewport().gui_release_focus()
		if _dragging:
			_set_offset(_press_offset + delta.x)
			get_viewport().set_input_as_handled()


func _swipe_allowed(point: Vector2) -> bool:
	if server_panel.visible and server_panel.get_global_rect().has_point(point):
		return false
	# En la página de colores, arrastrar sobre el selector es para elegir color, no para pasar de página.
	if colors_open and picker.get_global_rect().has_point(point):
		return false
	return true


func _finish_drag() -> void:
	var width := pager.size.x
	if _press_offset < width * 0.5:
		set_colors_open(_page_offset > width * SWIPE_OPEN_FRACTION)
	else:
		set_colors_open(_page_offset > width * (1.0 - SWIPE_OPEN_FRACTION))


func _taps_allowed() -> bool:
	return Time.get_ticks_msec() >= _block_taps_until


# ---------------------------------------------------------------- colores

func _select_mark(mark: String) -> void:
	selected_mark = mark
	picker.color = color_x if mark == "X" else color_o
	_refresh_swatches()


func _set_selected_color(color: Color) -> void:
	if selected_mark == "X":
		color_x = color
	else:
		color_o = color
	picker.color = color
	_refresh_swatches()


func _on_picker_changed(color: Color) -> void:
	if selected_mark == "X":
		color_x = color
	else:
		color_o = color
	_refresh_swatches()


func _refresh_swatches() -> void:
	_style_swatch(_swatch_x, color_x, selected_mark == "X")
	_style_swatch(_swatch_o, color_o, selected_mark == "O")
	nav.colors = [color_x, color_o]
	nav.queue_redraw()


func _make_swatch(mark: String) -> Button:
	var button := Button.new()
	button.text = mark
	button.custom_minimum_size = Vector2(0, 150)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 72)
	button.pressed.connect(func() -> void:
		if _taps_allowed():
			_select_mark(mark))
	return button


func _style_swatch(button: Button, color: Color, selected: bool) -> void:
	var text_color := Color.BLACK if color.get_luminance() > 0.55 else Color.WHITE
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(18)
		if selected:
			style.border_color = Color.WHITE
			style.set_border_width_all(8)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_focus_color", text_color)


# ---------------------------------------------------------------- acciones

func _request(kind: String, code: String) -> void:
	if not _taps_allowed():
		return
	if kind == "join" and code.length() != 4:
		set_status("El código tiene 4 letras")
		return
	_save_profile()
	online_requested.emit(kind, code)


func _save_profile() -> void:
	var player_name := name_edit.text.strip_edges()
	profile.player_name = player_name if not player_name.is_empty() else "Jugador"
	profile.color_x = color_x
	profile.color_o = color_o
	var url := url_edit.text.strip_edges()
	profile.server_url = url if not url.is_empty() else Profile.DEFAULT_SERVER_URL
	profile.save_to_disk()


# ---------------------------------------------------------------- helpers de UI

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


func _make_small_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 90)
	button.add_theme_font_size_override("font_size", 36)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	_style_button(button, COLOR_CELL)
	return button


func _make_button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 120)
	button.add_theme_font_size_override("font_size", 44)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	_style_button(button, color)
	_action_buttons.append(button)
	return button


func _style_button(button: Button, color: Color) -> void:
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
				style.bg_color = color.darkened(0.3)
		button.add_theme_stylebox_override(state, style)


## Flecha chiquita y suave, sin texto, para pasar de página.
class Chevron extends Button:
	var dir := -1  # -1 apunta a la izquierda, 1 a la derecha

	func _init(p_dir: int) -> void:
		dir = p_dir
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(64, 240)

	func _draw() -> void:
		var c := size / 2.0
		var alpha := 0.55 if get_draw_mode() == DRAW_PRESSED else 0.28
		draw_polyline(PackedVector2Array([
			Vector2(c.x - dir * 14.0, c.y - 46.0),
			Vector2(c.x + dir * 14.0, c.y),
			Vector2(c.x - dir * 14.0, c.y + 46.0)]),
			Color(1, 1, 1, alpha), 9.0, true)


## Barra de pestañas de abajo. `position_f` es el índice (fraccional) de la página visible,
## así la pestaña activa se desliza junto con el dedo.
class NavBar extends Control:
	signal tab_pressed(index: int)

	const LABELS := ["Colores", "Jugar"]
	const BAR := Color("181a29")
	const PILL := Color("34406b")
	const ACCENT := Color("ffd24d")

	var position_f := 1.0
	var colors: Array = [Color("e5484d"), Color("3b82f6")]
	var _press_index := -1
	var _pill := StyleBoxFlat.new()

	func _init() -> void:
		custom_minimum_size = Vector2(0, 170)
		mouse_filter = Control.MOUSE_FILTER_STOP
		_pill.set_corner_radius_all(26)

	func set_progress(value: float) -> void:
		position_f = value
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			var index := clampi(int(event.position.x / (size.x / LABELS.size())), 0, LABELS.size() - 1)
			if event.pressed:
				_press_index = index
			else:
				if _press_index == index:
					tab_pressed.emit(index)
				_press_index = -1

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), BAR)
		draw_line(Vector2.ZERO, Vector2(size.x, 0), Color("2d3048"), 3.0)
		var tab_w := size.x / LABELS.size()
		var font := ThemeDB.fallback_font
		for i in LABELS.size():
			var w := clampf(1.0 - absf(position_f - i), 0.0, 1.0)
			var rect := Rect2(i * tab_w + 14.0, 8.0 - 4.0 * w, tab_w - 28.0, size.y - 16.0 + 4.0 * w)
			_pill.bg_color = BAR.lerp(PILL, w)
			draw_style_box(_pill, rect)
			draw_rect(Rect2(rect.position.x + 36.0, rect.position.y, rect.size.x - 72.0, 8.0), Color(ACCENT, w))
			var center := Vector2(rect.position.x + rect.size.x / 2.0, size.y * 0.42 - 16.0 * w)
			var scale := 1.0 + 0.3 * w
			var alpha := 0.55 + 0.45 * w
			if i == 0:
				draw_circle(center + Vector2(-17, 0) * scale, 27.0 * scale, Color(colors[0], alpha))
				draw_circle(center + Vector2(17, 0) * scale, 27.0 * scale, Color(colors[1], alpha))
			else:
				var half := 30.0 * scale
				var third := half * 2.0 / 3.0
				var line := Color(0.91, 0.92, 0.96, alpha)
				for k in [1, 2]:
					var offset: float = -half + k * third
					draw_line(center + Vector2(offset, -half), center + Vector2(offset, half), line, 7.0 * scale, true)
					draw_line(center + Vector2(-half, offset), center + Vector2(half, offset), line, 7.0 * scale, true)
			if w > 0.01:
				var text_size := font.get_string_size(LABELS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 34)
				draw_string(font, Vector2(center.x - text_size.x / 2.0, size.y - 26.0), LABELS[i],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(1, 1, 1, w))
