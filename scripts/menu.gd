extends Control
## Menú principal. Dos páginas estilo Clash Royale: la principal (nombre, partida rápida,
## salas, local) y, a la izquierda, la de colores. Se pasa de una a otra con swipe o con la
## flecha. La dirección del servidor vive en una cascada arriba a la derecha.

signal local_requested
signal online_requested(kind: String, code: String)
signal cancel_requested

const Profile := preload("res://scripts/profile.gd")
const Fx := preload("res://scripts/fx.gd")
const Stats := preload("res://scripts/stats.gd")

const COLOR_BG := Color("14151f")
const COLOR_CELL := Color("2d3048")
const COLOR_ACTIVE := Color("3d4a7a")
const COLOR_TEXT := Color("e8eaf6")
const COLOR_MUTED := Color("8a8fa8")

const PRESETS := ["e5484d", "f97316", "facc15", "22c55e", "06b6d4", "3b82f6", "a855f7", "ec4899"]
const NAV_HEIGHT := 170.0
## En pantalla ancha las dos páginas van lado a lado, achicadas para que entren.
const WIDE_SCALES := [0.62, 0.9, 0.62]
const WIDE_CONTENT_W := 1000.0
const EDGE_W := 190.0
const SWIPE_START_PX := 40.0
const SWIPE_OPEN_FRACTION := 0.3
const COLOR_WIN := Color("3ecf8e")
const COLOR_LOSS := Color("e5484d")
const COLOR_DRAW := Color("8a8fa8")
const COLOR_CARD := Color("1f2133")

var profile: Profile
var color_x: Color
var color_o: Color
var selected_mark := "X"
var colors_open := false
## Página visible: 0 colores, 1 jugar, 2 estadísticas.
var page := 1
var stats: Stats
var wide := false

var name_edit: LineEdit
var code_edit: LineEdit
var url_edit: LineEdit
var status_label: Label
var cancel_button: Button
var picker: ColorPicker
var server_panel: PanelContainer
var server_button: Button
var private_button: Button
var private_box: VBoxContainer
var main_page: Control
var colors_page: Control
var stats_page: Control
var stats_donut: DonutChart
var pager: Control
var nav: NavBar

var _action_buttons: Array[Button] = []
var _chevrons: Array[Control] = []
var _dividers: Array[ColorRect] = []
var _edges: Array[EdgeZone] = []
var _reset_armed := false
var _swatch_x: Button
var _swatch_o: Button
var _page_f := 1.0
var _pressing := false
var _dragging := false
var _press_pos := Vector2.ZERO
var _press_f := 1.0
var _press_page := 1
var _block_taps_until := 0
var _tween: Tween


func _ready() -> void:
	if profile == null:
		profile = Profile.new()
	if stats == null:
		stats = Stats.new()
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
	if not wide and page != 1:
		set_page(1)
		return true
	return false


func set_colors_open(open: bool, animate := true) -> void:
	set_page(0 if open else 1, animate)


## Va a una página (0 colores, 1 jugar, 2 estadísticas).
func set_page(index: int, animate := true) -> void:
	page = clampi(index, 0, 2)
	colors_open = page == 0
	server_panel.visible = false
	_update_edges()
	get_viewport().gui_release_focus()
	if page == 2 and stats_donut != null:
		stats_donut.play()
	var target := float(page)
	if _tween != null:
		_tween.kill()
	if animate:
		_tween = create_tween()
		_tween.tween_method(_set_page_f, _page_f, target, 0.22) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_set_page_f(target)


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
			set_page(index))
	add_child(nav)

	for i in 2:
		var divider := ColorRect.new()
		divider.color = COLOR_CELL
		divider.visible = false
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(divider)
		_dividers.append(divider)

	main_page = Control.new()
	pager.add_child(main_page)
	colors_page = Control.new()
	pager.add_child(colors_page)
	stats_page = Control.new()
	pager.add_child(stats_page)

	_build_main_page()
	_build_colors_page()
	_build_stats_page()
	_build_server_panel()
	for dir in [-1, 1]:
		var edge := EdgeZone.new()
		edge.dir = dir
		edge.visible = false
		edge.activated.connect(func() -> void: set_page(page + edge.dir))
		add_child(edge)
		_edges.append(edge)
	_layout_pages.call_deferred()


func _page_root(page: Control) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 60)
	page.add_child(margin)
	page.set_meta("margin", margin)
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
	title.add_theme_font_size_override("font_size", 120)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	root.add_child(title)

	root.add_child(_caption("Tu nombre"))
	name_edit = _make_edit(profile.player_name, "Nombre")
	name_edit.max_length = 16
	root.add_child(name_edit)

	# Fila principal: Local (chico) - JUGAR (grande) - Privado (chico)
	var play_row := HBoxContainer.new()
	play_row.add_theme_constant_override("separation", 20)
	root.add_child(play_row)

	var local := _make_button("Local", COLOR_CELL)
	local.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	local.size_flags_stretch_ratio = 1.0
	local.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	local.custom_minimum_size = Vector2(0, 110)
	local.add_theme_font_size_override("font_size", 38)
	local.pressed.connect(func() -> void:
		if not _taps_allowed():
			return
		_save_profile()
		local_requested.emit())
	play_row.add_child(local)

	var quick := _make_button("JUGAR", COLOR_ACTIVE)
	quick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quick.size_flags_stretch_ratio = 2.4
	quick.custom_minimum_size = Vector2(0, 220)
	quick.add_theme_font_size_override("font_size", 84)
	quick.pressed.connect(func() -> void: _request("queue", ""))
	play_row.add_child(quick)

	private_button = _make_button("Privado", COLOR_CELL)
	private_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	private_button.size_flags_stretch_ratio = 1.0
	private_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	private_button.custom_minimum_size = Vector2(0, 110)
	private_button.add_theme_font_size_override("font_size", 38)
	private_button.pressed.connect(func() -> void: _set_private_open(not private_box.visible))
	play_row.add_child(private_button)

	# Sala privada: recién aparece al tocar "Privado".
	private_box = VBoxContainer.new()
	private_box.add_theme_constant_override("separation", 20)
	private_box.visible = false
	root.add_child(private_box)
	var create := _make_button("Crear sala", COLOR_CELL)
	create.pressed.connect(func() -> void: _request("create", ""))
	private_box.add_child(create)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 24)
	private_box.add_child(join_row)
	code_edit = _make_edit("", "Código")
	code_edit.max_length = 4
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(code_edit)
	var join := _make_button("Unirme", COLOR_CELL)
	join.size_flags_horizontal = Control.SIZE_SHRINK_END
	join.custom_minimum_size = Vector2(360, 120)
	join.pressed.connect(func() -> void: _request("join", code_edit.text.strip_edges().to_upper()))
	join_row.add_child(join)

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
	Fx.stagger_in.call_deferred(root.get_children())

	# Flecha suave al centro del borde izquierdo: lleva a los colores.
	var to_colors := Chevron.new(-1)
	to_colors.pressed.connect(func() -> void:
		if _taps_allowed():
			set_colors_open(true))
	main_page.add_child(to_colors)
	_chevrons.append(to_colors)
	var to_stats := Chevron.new(1)
	to_stats.pressed.connect(func() -> void:
		if _taps_allowed():
			set_page(2))
	main_page.add_child(to_stats)
	_chevrons.append(to_stats)
	_anchor_chevron(to_stats, true)
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
	_chevrons.append(to_main)
	_anchor_chevron(to_main, true)


## Página de estadísticas: dona con el porcentaje de victorias, barra, racha y últimas partidas.
func _build_stats_page() -> void:
	for child in stats_page.get_children():
		child.queue_free()
	_chevrons = _chevrons.filter(func(chevron: Control) -> bool: return is_instance_valid(chevron) and chevron.get_parent() != null and chevron.get_parent() != stats_page)
	var root := _page_root(stats_page)

	var heading := Label.new()
	heading.text = "Estadísticas"
	heading.add_theme_font_size_override("font_size", 64)
	heading.add_theme_color_override("font_color", COLOR_TEXT)
	root.add_child(heading)
	root.add_child(_caption("Tus partidas online"))

	var center := CenterContainer.new()
	root.add_child(center)
	stats_donut = DonutChart.new()
	stats_donut.stats = stats
	center.add_child(stats_donut)

	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 20)
	root.add_child(tiles)
	tiles.add_child(_stat_tile("Victorias", str(stats.wins), COLOR_WIN))
	tiles.add_child(_stat_tile("Empates", str(stats.draws), COLOR_DRAW))
	tiles.add_child(_stat_tile("Derrotas", str(stats.losses), COLOR_LOSS))

	var bar := StackBar.new()
	bar.stats = stats
	root.add_child(bar)

	var streaks := HBoxContainer.new()
	streaks.add_theme_constant_override("separation", 20)
	root.add_child(streaks)
	var streak_text := "—"
	var streak_color := COLOR_MUTED
	if stats.streak > 0:
		streak_text = "%d %s" % [stats.streak, "victoria" if stats.streak == 1 else "victorias"]
		streak_color = COLOR_WIN
	elif stats.streak < 0:
		streak_text = "%d %s" % [-stats.streak, "derrota" if stats.streak == -1 else "derrotas"]
		streak_color = COLOR_LOSS
	streaks.add_child(_stat_tile("Racha actual", streak_text, streak_color, 44))
	streaks.add_child(_stat_tile("Mejor racha", str(stats.best_streak) if stats.best_streak > 0 else "—", COLOR_TEXT, 44))

	root.add_child(_caption("Últimas partidas"))
	var dots := RecentDots.new()
	dots.stats = stats
	root.add_child(dots)

	var reset := _make_small_button("Borrar estadísticas")
	reset.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reset.pressed.connect(func() -> void:
		if not _taps_allowed():
			return
		if not _reset_armed:
			_reset_armed = true
			reset.text = "Tocá otra vez para borrar"
			get_tree().create_timer(3.0).timeout.connect(func() -> void:
				if is_instance_valid(reset):
					_reset_armed = false
					reset.text = "Borrar estadísticas")
		else:
			_reset_armed = false
			stats.reset()
			stats.save_to_disk()
			_build_stats_page()
			stats_donut.play())
	root.add_child(reset)

	var back := Chevron.new(-1)
	back.pressed.connect(func() -> void:
		if _taps_allowed():
			set_page(1))
	stats_page.add_child(back)
	_chevrons.append(back)
	_anchor_chevron(back, false)
	back.visible = not wide
	if pager != null:
		_layout_pages()


func _stat_tile(label_text: String, value_text: String, color: Color, value_size := 72) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_CARD
	style.set_corner_radius_all(18)
	style.set_content_margin_all(22)
	card.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var value := Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", value_size)
	value.add_theme_color_override("font_color", color)
	box.add_child(value)
	var caption := Label.new()
	caption.text = label_text
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 32)
	caption.add_theme_color_override("font_color", COLOR_MUTED)
	box.add_child(caption)
	return card


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
		var page_scale := main_page.scale.x
		server_panel.position = Vector2(
			(button_rect.end.x - origin.x) / page_scale - server_panel.size.x,
			(button_rect.end.y - origin.y) / page_scale + 16.0)


# ---------------------------------------------------------------- páginas y swipe

## Reacomoda el menú: celular (páginas con swipe y barra de abajo) o compu (todo a la vista).
func apply_layout(is_wide: bool) -> void:
	wide = is_wide
	if pager == null:
		return
	pager.offset_bottom = 0.0 if wide else -NAV_HEIGHT
	nav.visible = not wide
	for divider in _dividers:
		divider.visible = false
	for edge in _edges:
		edge.visible = wide
	for chevron in _chevrons:
		chevron.visible = not wide
	server_panel.visible = false
	_layout_pages()
	_update_edges()


func _layout_pages() -> void:
	var pages := [colors_page, main_page, stats_page]
	for i in 3:
		var page_control: Control = pages[i]
		var page_scale := 1.0
		if wide:
			page_scale = WIDE_SCALES[i]
		page_control.scale = Vector2(page_scale, page_scale)
		page_control.size = pager.size / page_scale
		var margin: MarginContainer = page_control.get_meta("margin")
		var side := 60
		if wide:
			side = maxi(60, int((page_control.size.x - WIDE_CONTENT_W) / 2.0))
		margin.add_theme_constant_override("margin_left", side)
		margin.add_theme_constant_override("margin_right", side)
		var vertical := 40 if wide else 60
		margin.add_theme_constant_override("margin_top", vertical)
		margin.add_theme_constant_override("margin_bottom", vertical)
	_layout_edges()
	if _tween == null or not _tween.is_running():
		_set_page_f(float(page))
	else:
		_set_page_f(_page_f)


func _set_private_open(open: bool) -> void:
	private_box.visible = open
	_style_button(private_button, COLOR_ACTIVE if open else COLOR_CELL)
	if open:
		Fx.pop(private_box, 0.9, 0.2)


func _layout_edges() -> void:
	for edge in _edges:
		edge.size = Vector2(EDGE_W, pager.size.y)
		edge.position = Vector2(0.0 if edge.dir < 0 else size.x - EDGE_W, 0.0)


## Los costados de compu: se ven solo si hay página en esa dirección.
func _update_edges() -> void:
	var names := ["Colores", "Jugar", "Estadísticas"]
	for edge in _edges:
		var target: int = page + edge.dir
		edge.visible = wide and target >= 0 and target <= 2
		if edge.visible:
			edge.label = names[target]
			edge.queue_redraw()


func _set_page_f(f: float) -> void:
	_page_f = clampf(f, 0.0, 2.0)
	var width := pager.size.x
	colors_page.position.x = (0.0 - _page_f) * width
	main_page.position.x = (1.0 - _page_f) * width
	stats_page.position.x = (2.0 - _page_f) * width
	if nav != null:
		nav.set_progress(_page_f)


func _input(event: InputEvent) -> void:
	if pager == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = _swipe_allowed(event.position)
			_dragging = false
			_press_pos = event.position
			_press_f = _page_f
			_press_page = page
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
			_set_page_f(_press_f - delta.x / maxf(pager.size.x, 1.0))
			get_viewport().set_input_as_handled()


func _swipe_allowed(point: Vector2) -> bool:
	if wide:
		return false
	if server_panel.visible and server_panel.get_global_rect().has_point(point):
		return false
	# En la página de colores, arrastrar sobre el selector es para elegir color, no para pasar de página.
	if page == 0 and picker.get_global_rect().has_point(point):
		return false
	return true


func _finish_drag() -> void:
	var moved := _page_f - _press_f
	var target := _press_page
	if absf(moved) > SWIPE_OPEN_FRACTION:
		target = clampi(_press_page + (1 if moved > 0.0 else -1), 0, 2)
	set_page(target)


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
	Fx.press_feedback(button)
	button.custom_minimum_size = Vector2(0, 90)
	button.add_theme_font_size_override("font_size", 36)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	_style_button(button, COLOR_CELL)
	return button


func _make_button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	Fx.press_feedback(button)
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

	const LABELS := ["Colores", "Jugar", "Estadísticas"]
	const BAR := Color("181a29")
	const PILL := Color("34406b")
	const ACCENT := Color("8f95ad")

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
			elif i == 2:
				# Barritas de gráfico.
				var bar := Color(0.91, 0.92, 0.96, alpha)
				for k in 3:
					var bar_height: float = [26.0, 46.0, 36.0][k] * scale
					var bar_x := center.x + (k - 1) * 22.0 * scale
					draw_line(Vector2(bar_x, center.y + 28.0 * scale), Vector2(bar_x, center.y + 28.0 * scale - bar_height), bar, 14.0 * scale)
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


## Dona con el porcentaje de victorias (verde = victorias, gris = empates, rojo = derrotas).
class DonutChart extends Control:
	const WIN := Color("3ecf8e")
	const LOSS := Color("e5484d")
	const DRAW := Color("8a8fa8")

	var stats
	var sweep := 1.0:
		set(value):
			sweep = value
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(620, 620)

	## Anima el barrido de la dona de cero a su valor.
	func play() -> void:
		sweep = 0.0
		var tween := create_tween()
		tween.tween_property(self, "sweep", 1.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		var center := size / 2.0
		var radius := 250.0
		var width := 64.0
		draw_arc(center, radius, 0.0, TAU, 96, Color("22253a"), width, true)
		var total: int = stats.total()
		var font := ThemeDB.fallback_font
		if total == 0:
			_text(font, "—", center + Vector2(0, 30), 140, Color("8a8fa8"))
			_text(font, "Sin partidas todavía", center + Vector2(0, 100), 36, Color("8a8fa8"))
			return
		var parts := [[stats.wins, WIN], [stats.draws, DRAW], [stats.losses, LOSS]]
		var visible_parts := 0
		for part in parts:
			if part[0] > 0:
				visible_parts += 1
		var gap := 0.06 if visible_parts > 1 else 0.0
		var start := -PI / 2.0
		for part in parts:
			if part[0] <= 0:
				continue
			var span: float = TAU * float(part[0]) / total * sweep
			var a0 := start + gap / 2.0
			var a1 := start + span - gap / 2.0
			if a1 > a0:
				draw_arc(center, radius, a0, a1, maxi(8, int(span * 30.0)), part[1], width, true)
			start += span
		var shown := int(round(stats.win_rate() * sweep))
		_text(font, "%d%%" % shown, center + Vector2(0, 30), 150, Color("e8eaf6"))
		_text(font, "de victorias", center + Vector2(0, 100), 40, Color("8a8fa8"))

	func _text(font: Font, text: String, anchor: Vector2, font_size: int, color: Color) -> void:
		var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(anchor.x - text_width / 2.0, anchor.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Barra apilada: la misma proporción que la dona, de un vistazo.
class StackBar extends Control:
	var stats

	func _init() -> void:
		custom_minimum_size = Vector2(0, 44)

	func _draw() -> void:
		var back := StyleBoxFlat.new()
		back.bg_color = Color("22253a")
		back.set_corner_radius_all(14)
		draw_style_box(back, Rect2(Vector2.ZERO, size))
		var total: int = stats.total()
		if total == 0:
			return
		var parts := [[stats.wins, Color("3ecf8e")], [stats.draws, Color("8a8fa8")], [stats.losses, Color("e5484d")]]
		var x := 0.0
		for part in parts:
			if part[0] <= 0:
				continue
			var segment_width: float = size.x * float(part[0]) / total
			var segment := StyleBoxFlat.new()
			segment.bg_color = part[1]
			segment.set_corner_radius_all(14)
			draw_style_box(segment, Rect2(x + 2.0, 2.0, maxf(segment_width - 4.0, 8.0), size.y - 4.0))
			x += segment_width


## Puntos con los últimos resultados (el más reciente a la derecha).
class RecentDots extends Control:
	var stats

	func _init() -> void:
		custom_minimum_size = Vector2(0, 64)

	func _draw() -> void:
		var recent: Array = stats.recent
		if recent.is_empty():
			var font := ThemeDB.fallback_font
			draw_string(font, Vector2(0, 40), "Todavía no jugaste partidas online", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color("8a8fa8"))
			return
		var step := 52.0
		var count := mini(recent.size(), int(size.x / step))
		var first := recent.size() - count
		var offset := size.x - count * step
		for i in count:
			var result: String = recent[first + i]
			var color := Color("3ecf8e") if result == "W" else (Color("e5484d") if result == "L" else Color("8a8fa8"))
			draw_circle(Vector2(offset + i * step + step / 2.0, size.y / 2.0), 20.0, color)


## Zona del borde para compu: al pasar el mouse un momento cambia de pantalla.
class EdgeZone extends Control:
	signal activated

	var dir := -1
	var label := ""
	var hover_t := 0.0
	var hovering := false
	const DWELL := 0.2

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: hovering = true)
		mouse_exited.connect(func() -> void: hovering = false)

	func _process(delta: float) -> void:
		if not visible:
			hover_t = 0.0
			return
		var before := hover_t
		if hovering:
			hover_t += delta
			if hover_t >= DWELL:
				hover_t = 0.0
				hovering = false
				activated.emit()
		else:
			hover_t = maxf(0.0, hover_t - delta * 3.0)
		if before != hover_t:
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			hover_t = 0.0
			activated.emit()

	func _draw() -> void:
		var f := clampf(hover_t / DWELL, 0.0, 1.0)
		var edge_alpha := 0.35 + 0.35 * f
		var outer := Color(0.0, 0.0, 0.0, edge_alpha)
		var inner := Color(0.0, 0.0, 0.0, 0.0)
		var left_colors := PackedColorArray([outer, inner, inner, outer])
		var points := PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(0, size.y)])
		if dir > 0:
			left_colors = PackedColorArray([inner, outer, outer, inner])
		draw_polygon(points, left_colors)
		var mid := size.y / 2.0
		var cx := size.x * 0.5
		var alpha := 0.35 + 0.65 * f
		var tint := Color(0.91, 0.92, 0.96, alpha)
		var tip := Vector2(cx + dir * 14.0, mid)
		draw_line(tip, tip + Vector2(dir * -26.0, -34.0), tint, 6.0, true)
		draw_line(tip, tip + Vector2(dir * -26.0, 34.0), tint, 6.0, true)
		var font := ThemeDB.fallback_font
		var text_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
		draw_string(font, Vector2(cx - text_w / 2.0, mid + 90.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, tint)
