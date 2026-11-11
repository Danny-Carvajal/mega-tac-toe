extends VBoxContainer
## Equipar cosméticos desde Personalización: solo salen los conseguidos.
## mode "pieces": figura de X y de O. mode "profile": vista previa + banner + fuente.

signal changed

const Pal := preload("res://scripts/pal.gd")
const Cosmetics := preload("res://scripts/cosmetics.gd")
const FigureView := preload("res://scripts/figure_view.gd")
const BannerView := preload("res://scripts/banner_view.gd")

var collection
var mode := "pieces"
var player_name := "Jugador"
var color_x := Color("e5484d")
var color_o := Color("3b82f6")

var _scroll: ScrollContainer
var _content: VBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", 20)


func _ready() -> void:
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 20)
	_scroll.add_child(_content)
	refresh()


## Vuelve a dibujar con el estado actual.
func refresh() -> void:
	if _content == null or collection == null:
		return
	for child in _content.get_children():
		child.queue_free()
		_content.remove_child(child)
	if mode == "pieces":
		_section("Tu figura de X", "fx", 4)
		_section("Tu figura de O", "fo", 4)
	else:
		_content.add_child(_profile_card())
		_section("Banner", "banner", 2)
		_section("Fuente", "font", 3)


func _section(title: String, kind: String, columns: int) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", Pal.text)
	_content.add_child(label)
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(grid)
	var items := Cosmetics.items_of_kind(kind)
	items = items.filter(func(entry: Dictionary) -> bool: return collection.owns(entry["id"]))
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["rarity"] < b["rarity"])
	for entry in items:
		grid.add_child(_tile(entry))


func _tile(entry: Dictionary) -> Button:
	var id: String = entry["id"]
	var kind: String = entry["kind"]
	var equipped: bool = collection.equipped.get(kind, "") == id
	var rarity_color: Color = Cosmetics.RARITY_COLORS[entry["rarity"]]
	var tall := kind == "banner"
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(0, 170 if not tall else 190)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Pal.card if state != "hover" else Pal.cell
		style.set_corner_radius_all(20)
		style.border_color = Pal.accent if equipped else rarity_color
		style.set_border_width_all(6 if equipped else 3)
		tile.add_theme_stylebox_override(state, style)
	tile.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	tile.pressed.connect(func() -> void:
		if collection.equip(id):
			collection.save_to_disk()
			refresh()
			changed.emit())
	var inner := MarginContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 10)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(inner)
	var preview: Control
	match kind:
		"fx", "fo":
			var figure := FigureView.new()
			figure.set_figure(id, color_x if kind == "fx" else color_o)
			preview = figure
		"banner":
			var banner := BannerView.new()
			banner.radius = 12.0
			banner.set_banner(id)
			preview = banner
		_:
			var text := Label.new()
			text.text = "Aa"
			text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			text.add_theme_font_size_override("font_size", 70)
			text.add_theme_color_override("font_color", Color.WHITE)
			Cosmetics.apply_font(text, id)
			preview = text
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(preview)
	return tile


## Tarjeta de perfil tal como la va a ver el rival.
func _profile_card() -> Control:
	var equipped: Dictionary = collection.equipped
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 190)
	var banner := BannerView.new()
	banner.radius = 24.0
	banner.set_banner(equipped["banner"])
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(banner)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 28.0
	row.offset_right = -28.0
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(row)
	var name_label := Label.new()
	name_label.text = player_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 60)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Cosmetics.apply_font(name_label, equipped["font"])
	row.add_child(name_label)
	for pair in [[equipped["fx"], color_x], [equipped["fo"], color_o]]:
		var figure := FigureView.new()
		figure.set_figure(pair[0], pair[1])
		figure.custom_minimum_size = Vector2(110, 0)
		figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(figure)
	return holder
