extends Control
## Tienda y colección: se abren cajas con monedas, y se elige qué figura, banner y fuente llevar puestos.

signal back_requested

const Pal := preload("res://scripts/pal.gd")
const Fx := preload("res://scripts/fx.gd")
const Cosmetics := preload("res://scripts/cosmetics.gd")
const Collection := preload("res://scripts/collection.gd")
const Profile := preload("res://scripts/profile.gd")
const FigureView := preload("res://scripts/figure_view.gd")
const BannerView := preload("res://scripts/banner_view.gd")

const TABS := [["fx", "Figura X"], ["fo", "Figura O"], ["banner", "Banner"], ["font", "Fuente"]]

var collection: Collection
var profile: Profile

var tab := "fx"
var wide := false
var coins_label: Label
var box_button: Button
var preview_banner: Control
var preview_name: Label
var preview_fx: Control
var preview_fo: Control
var tab_buttons: Dictionary = {}
var grid: GridContainer
var overlay: Control
var notice_label: Label
var left_box: VBoxContainer
var right_box: VBoxContainer
var _margin: MarginContainer
var _root: BoxContainer
var _scroll: ScrollContainer


## Monedita dorada dibujada por código.
class CoinIcon:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(56, 56)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		draw_circle(c, r, Color("a9781a"))
		draw_circle(c, r * 0.86, Color("f5c342"))
		draw_arc(c, r * 0.6, 0.0, TAU, 40, Color("c8921f"), 3.0, true)
		draw_line(c + Vector2(0, -r * 0.3), c + Vector2(0, r * 0.3), Color("a9781a"), 4.0, true)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Pal.bg
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	_root = BoxContainer.new()
	_root.add_theme_constant_override("separation", 40)
	_margin.add_child(_root)

	# --- Columna de la izquierda (arriba en celular): volver, monedas, tu tarjeta y la caja ---
	left_box = VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 22)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	left_box.add_child(top)
	var back := _button("Volver", Pal.cell)
	back.custom_minimum_size = Vector2(230, 96)
	back.pressed.connect(func() -> void: back_requested.emit())
	top.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var pill := PanelContainer.new()
	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = Pal.card
	pill_style.border_color = Color("f5c342")
	pill_style.set_border_width_all(3)
	pill_style.set_corner_radius_all(48)
	pill_style.content_margin_left = 22
	pill_style.content_margin_right = 30
	pill_style.content_margin_top = 12
	pill_style.content_margin_bottom = 12
	pill.add_theme_stylebox_override("panel", pill_style)
	top.add_child(pill)
	var pill_row := HBoxContainer.new()
	pill_row.add_theme_constant_override("separation", 14)
	pill.add_child(pill_row)
	var coin_icon := CoinIcon.new()
	coin_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill_row.add_child(coin_icon)
	coins_label = Label.new()
	coins_label.add_theme_font_size_override("font_size", 46)
	coins_label.add_theme_color_override("font_color", Pal.text)
	pill_row.add_child(coins_label)

	var preview_title := Label.new()
	preview_title.text = "Tu tarjeta"
	preview_title.add_theme_font_size_override("font_size", 34)
	preview_title.add_theme_color_override("font_color", Pal.muted)
	left_box.add_child(preview_title)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 250)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0, 0, 0, 0)
	card_style.border_color = Pal.active
	card_style.set_border_width_all(5)
	card_style.set_corner_radius_all(30)
	card_style.set_content_margin_all(18)
	card.add_theme_stylebox_override("panel", card_style)
	left_box.add_child(card)
	preview_banner = BannerView.new()
	preview_banner.radius = 24.0
	card.add_child(preview_banner)
	var card_row := HBoxContainer.new()
	card_row.add_theme_constant_override("separation", 8)
	card.add_child(card_row)
	preview_name = Label.new()
	preview_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_name.add_theme_font_size_override("font_size", 84)
	card_row.add_child(preview_name)
	preview_fx = FigureView.new()
	preview_fx.custom_minimum_size = Vector2(120, 120)
	preview_fx.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card_row.add_child(preview_fx)
	preview_fo = FigureView.new()
	preview_fo.custom_minimum_size = Vector2(120, 120)
	preview_fo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card_row.add_child(preview_fo)

	box_button = _button("", Color("d99a1c"))
	box_button.custom_minimum_size = Vector2(0, 140)
	box_button.add_theme_font_size_override("font_size", 54)
	box_button.pressed.connect(_on_box_pressed)
	left_box.add_child(box_button)

	notice_label = Label.new()
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label.add_theme_font_size_override("font_size", 30)
	notice_label.add_theme_color_override("font_color", Pal.muted)
	notice_label.text = "Probabilidades: 60% común, 28% rara, 9% épica y 3% legendaria. Si te sale una repetida, te devuelven monedas."
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_box.add_child(notice_label)

	# --- Columna de la derecha (abajo en celular): pestañas y colección con scroll ---
	right_box = VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 18)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	right_box.add_child(tabs)
	for entry in TABS:
		var kind: String = entry[0]
		var tab_button := _button(entry[1], Pal.cell)
		tab_button.custom_minimum_size = Vector2(0, 96)
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_button.add_theme_font_size_override("font_size", 34)
		tab_button.pressed.connect(func() -> void: _select_tab(kind))
		tabs.add_child(tab_button)
		tab_buttons[kind] = tab_button

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_box.add_child(_scroll)
	grid = GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	_scroll.add_child(grid)

	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)

	wide = get_viewport_rect().size.x > get_viewport_rect().size.y * 1.1
	apply_layout(wide)
	_refresh()


## Celular: todo en una columna. Compu: tarjeta y caja a la izquierda, colección con scroll a la derecha.
func apply_layout(is_wide: bool) -> void:
	wide = is_wide
	if _root == null:
		return
	for part in [left_box, right_box]:
		if part.get_parent() != null:
			part.get_parent().remove_child(part)
	_root.vertical = not wide
	_root.add_child(left_box)
	_root.add_child(right_box)
	if wide:
		left_box.custom_minimum_size = Vector2(700, 0)
		left_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		left_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	else:
		left_box.custom_minimum_size = Vector2.ZERO
		left_box.size_flags_horizontal = Control.SIZE_FILL
		left_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var side := 70 if wide else 40
	_margin.add_theme_constant_override("margin_left", side)
	_margin.add_theme_constant_override("margin_right", side)
	_margin.add_theme_constant_override("margin_top", 50 if wide else 60)
	_margin.add_theme_constant_override("margin_bottom", 40)
	grid.columns = 4 if wide else 3
	if collection != null:
		_refresh()


func _select_tab(kind: String) -> void:
	tab = kind
	_refresh()


## Vuelve a dibujar todo con el estado actual de la colección.
func _refresh() -> void:
	coins_label.text = "%d monedas" % collection.coins
	box_button.text = "Abrir caja  ·  %d monedas" % Cosmetics.BOX_PRICE
	box_button.disabled = not collection.can_open_box()
	var equipped: Dictionary = collection.equipped
	preview_banner.set_banner(equipped["banner"])
	preview_name.text = profile.player_name
	preview_name.add_theme_color_override("font_color", Color.WHITE)
	Cosmetics.apply_font(preview_name, equipped["font"])
	preview_fx.set_figure(equipped["fx"], profile.color_x)
	preview_fo.set_figure(equipped["fo"], profile.color_o)
	for kind in tab_buttons:
		_style_button(tab_buttons[kind], Pal.active if kind == tab else Pal.cell)
	for child in grid.get_children():
		child.queue_free()
	var items := Cosmetics.items_of_kind(tab)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_owned := collection.owns(a["id"])
		var b_owned := collection.owns(b["id"])
		if a_owned != b_owned:
			return a_owned
		return a["rarity"] < b["rarity"])
	for entry in items:
		grid.add_child(_tile(entry))


func _tile(entry: Dictionary) -> Button:
	var id: String = entry["id"]
	var owned := collection.owns(id)
	var equipped: bool = collection.equipped.get(entry["kind"], "") == id
	var rarity_color: Color = Cosmetics.RARITY_COLORS[entry["rarity"]]
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(230, 300)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Pal.card if state != "hover" else Pal.cell
		style.set_corner_radius_all(24)
		style.border_color = Pal.accent if equipped else (rarity_color if owned else rarity_color.darkened(0.45))
		style.set_border_width_all(6 if equipped else 3)
		tile.add_theme_stylebox_override(state, style)
	tile.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	tile.pressed.connect(func() -> void: _on_tile_pressed(id))

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 14.0
	box.offset_right = -14.0
	box.offset_top = 14.0
	box.offset_bottom = -12.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	tile.add_child(box)

	# La vista previa va en un recuadro más oscuro, así se luce sobre cualquier color.
	var inset := PanelContainer.new()
	var inset_style := StyleBoxFlat.new()
	inset_style.bg_color = Pal.panel
	inset_style.set_corner_radius_all(16)
	inset_style.set_content_margin_all(8)
	inset.add_theme_stylebox_override("panel", inset_style)
	inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(inset)
	var preview := _preview_for(entry)
	preview.modulate.a = 1.0 if owned else 0.3
	inset.add_child(preview)
	var name_label := Label.new()
	name_label.text = entry["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 32)
	name_label.add_theme_color_override("font_color", Pal.text if owned else Pal.muted)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	var state_label := Label.new()
	if equipped:
		state_label.text = "EQUIPADA"
		state_label.add_theme_color_override("font_color", Pal.accent)
	else:
		state_label.text = Cosmetics.RARITY_NAMES[entry["rarity"]] + ("" if owned else " · bloqueada")
		state_label.add_theme_color_override("font_color", rarity_color if owned else Pal.muted)
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_label.add_theme_font_size_override("font_size", 26)
	state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(state_label)
	return tile


## Vista previa de un cosmético, tal como se va a ver.
func _preview_for(entry: Dictionary) -> Control:
	var preview: Control
	match entry["kind"]:
		"fx", "fo":
			var figure := FigureView.new()
			figure.set_figure(entry["id"], profile.color_x if entry["kind"] == "fx" else profile.color_o)
			figure.custom_minimum_size = Vector2(0, 130)
			preview = figure
		"banner":
			var banner := BannerView.new()
			banner.radius = 16.0
			banner.set_banner(entry["id"])
			banner.custom_minimum_size = Vector2(0, 130)
			preview = banner
		_:
			var label := Label.new()
			label.text = "Aa"
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 90)
			label.add_theme_color_override("font_color", Color.WHITE)
			Cosmetics.apply_font(label, entry["id"])
			preview = label
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return preview


func _on_tile_pressed(id: String) -> void:
	if collection.equip(id):
		collection.save_to_disk()
		_refresh()


# --- Cajas ------------------------------------------------------------------

func _on_box_pressed() -> void:
	if overlay.visible:
		return
	var result := collection.open_box()
	if result.is_empty():
		notice_label.text = "No te alcanzan las monedas para una caja."
		return
	collection.save_to_disk()
	_refresh()
	_show_box_opening(result)


func _show_box_opening(result: Dictionary) -> void:
	for child in overlay.get_children():
		child.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(Pal.bg, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 26)
	column.custom_minimum_size = Vector2(760, 0)
	center.add_child(column)
	overlay.visible = true
	Fx.fade_in(overlay, 0.2)

	# La caja tiembla un rato y después se abre.
	var crate := PanelContainer.new()
	crate.custom_minimum_size = Vector2(380, 380)
	crate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var crate_style := StyleBoxFlat.new()
	crate_style.bg_color = Pal.active
	crate_style.set_corner_radius_all(40)
	crate.add_theme_stylebox_override("panel", crate_style)
	var question := Label.new()
	question.text = "?"
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	question.add_theme_font_size_override("font_size", 260)
	question.add_theme_color_override("font_color", Color.WHITE)
	crate.add_child(question)
	column.add_child(crate)
	crate.pivot_offset = crate.custom_minimum_size / 2.0
	var shake := crate.create_tween()
	for i in 6:
		shake.tween_property(crate, "rotation_degrees", 9.0 if i % 2 == 0 else -9.0, 0.09)
	shake.tween_property(crate, "rotation_degrees", 0.0, 0.08)
	shake.tween_callback(func() -> void: _reveal(column, crate, result))


func _reveal(column: VBoxContainer, crate: Control, result: Dictionary) -> void:
	if not is_instance_valid(column) or not overlay.visible:
		return
	crate.queue_free()
	var item: Dictionary = result["item"]
	var rarity_color: Color = Cosmetics.RARITY_COLORS[item["rarity"]]
	var rarity_label := Label.new()
	rarity_label.text = Cosmetics.RARITY_NAMES[item["rarity"]].to_upper()
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_label.add_theme_font_size_override("font_size", 70)
	rarity_label.add_theme_color_override("font_color", rarity_color)
	column.add_child(rarity_label)
	var tile_preview := _preview_for(item)
	tile_preview.custom_minimum_size = Vector2(0, 260)
	column.add_child(tile_preview)
	var name_label := Label.new()
	name_label.text = "%s · %s" % [Cosmetics.KIND_NAMES[item["kind"]], item["name"]]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 52)
	name_label.add_theme_color_override("font_color", Pal.text)
	column.add_child(name_label)
	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 40)
	if result["duplicate"]:
		status.text = "Repetida: te devuelven %d monedas" % result["refund"]
		status.add_theme_color_override("font_color", Pal.muted)
	else:
		status.text = "¡Nueva!"
		status.add_theme_color_override("font_color", Pal.accent)
	column.add_child(status)
	var buttons: Array = []
	if not result["duplicate"]:
		var equip := _button("Equipar", Pal.active)
		equip.pressed.connect(func() -> void:
			collection.equip(item["id"])
			collection.save_to_disk()
			_close_overlay())
		column.add_child(equip)
		buttons.append(equip)
	var done := _button("Listo", Pal.cell)
	done.pressed.connect(_close_overlay)
	column.add_child(done)
	buttons.append(done)
	Fx.pop(tile_preview, 0.3, 0.5)
	Fx.pop(rarity_label, 0.5, 0.4)
	Fx.stagger_in(buttons, 0.1, 0.3)
	_refresh()


func _close_overlay() -> void:
	overlay.visible = false
	_refresh()


# --- Botones ----------------------------------------------------------------

func _button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 120)
	button.add_theme_font_size_override("font_size", 44)
	for font_state in ["font_color", "font_pressed_color", "font_hover_pressed_color", "font_hover_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(font_state, Pal.text)
	_style_button(button, color)
	return button


func _style_button(button: Button, color: Color) -> void:
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
