class_name IntroScreen
extends Control
## Presentación de una partida online: VS grande con los dos jugadores y después la moneda
## que sortea quién es X (X siempre empieza, como las blancas en ajedrez).
## El servidor ya decidió el resultado: acá solo se anima. Dura `duration_ms`, que manda el servidor
## (en ese tiempo el servidor tampoco deja jugar ni corre los relojes).

signal finished

const Pal := preload("res://scripts/pal.gd")
const Fx := preload("res://scripts/fx.gd")

## Cómo se reparte el tiempo total: VS, moneda girando y resultado.
const VS_FRACTION := 0.45
const FLIP_FRACTION := 0.38
const COIN_COLOR := Color("e9b949")
const COIN_EDGE := Color("a9781a")

var my_name := "Jugador"
var opponent_name := "Rival"
var my_seat := 1
## Colores de la X y la O (índice 1 y 2), para pintar el resultado.
var mark_colors: Array = [Color.WHITE, Color("e5484d"), Color("3b82f6")]
var duration_ms := 8500

var coin: Coin
var vs_label: Label
var result_label: Label
var cards: Array[PanelContainer] = []  # 0 = rival, 1 = yo
var badges: Array[Label] = []

var _started_ms := 0
var _phase := 0  # 0 VS, 1 moneda, 2 resultado, 3 terminó
var _wide := false


## La moneda: se dibuja un círculo dorado con la letra de la cara que esté arriba.
class Coin:
	extends Control
	var face := 1  # 1 = X, 2 = O
	var letter_color := Color.WHITE

	func _draw() -> void:
		var center := size / 2.0
		var radius := minf(size.x, size.y) / 2.0
		draw_circle(center, radius, COIN_EDGE)
		draw_circle(center, radius * 0.9, COIN_COLOR)
		draw_arc(center, radius * 0.72, 0.0, TAU, 64, COIN_EDGE, 5.0, true)
		var font := ThemeDB.fallback_font
		var font_size := int(radius * 1.15)
		var text := "X" if face == 1 else "O"
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, Vector2(center.x - text_size.x / 2.0, center.y + font_size * 0.36), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, letter_color)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP  # tapa el tablero: nadie toca nada durante la presentación
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wide = get_viewport_rect().size.x > get_viewport_rect().size.y * 1.1
	var bg := ColorRect.new()
	bg.color = Pal.bg
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var layout := BoxContainer.new()
	layout.vertical = not _wide
	layout.add_theme_constant_override("separation", 40 if not _wide else 60)
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(layout)

	# Vertical: rival arriba, VS en el medio, yo abajo. Ancho: yo a la izquierda, rival a la derecha.
	var opponent_card := _make_card(opponent_name)
	var my_card := _make_card(my_name)
	vs_label = Label.new()
	vs_label.text = "VS"
	vs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs_label.add_theme_font_size_override("font_size", 260 if not _wide else 200)
	vs_label.add_theme_color_override("font_color", Pal.text)
	vs_label.custom_minimum_size = Vector2(380 if _wide else 0, 0)

	var middle := Control.new()  # la moneda se pone encima del VS
	middle.custom_minimum_size = Vector2(380 if _wide else 0, 330)
	middle.add_child(vs_label)
	vs_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	coin = Coin.new()
	coin.custom_minimum_size = Vector2(300, 300)
	coin.size = Vector2(300, 300)
	coin.modulate.a = 0.0
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(coin)

	if _wide:
		layout.add_child(my_card)
		layout.add_child(middle)
		layout.add_child(opponent_card)
	else:
		layout.add_child(opponent_card)
		layout.add_child(middle)
		layout.add_child(my_card)
	cards = [opponent_card, my_card]

	result_label = Label.new()
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 56)
	result_label.add_theme_color_override("font_color", Pal.text)
	result_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	result_label.offset_top = -330.0
	result_label.offset_bottom = -230.0
	result_label.offset_left = -500.0
	result_label.offset_right = 500.0
	result_label.modulate.a = 0.0
	add_child(result_label)

	_started_ms = Time.get_ticks_msec()
	# Entrada: las tarjetas se deslizan desde los costados y el VS cae con un golpe.
	for i in 2:
		var card := cards[i]
		card.modulate.a = 0.0
		var tween := create_tween().set_parallel(true)
		tween.tween_property(card, "modulate:a", 1.0, 0.35).set_delay(0.15 * i)
	vs_label.modulate.a = 0.0
	var vs_tween := create_tween().set_parallel(true)
	vs_tween.tween_property(vs_label, "modulate:a", 1.0, 0.25).set_delay(0.5)
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if is_instance_valid(vs_label):
			Fx.pop(vs_label, 2.2, 0.45))


func _make_card(player_name: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(900 if not _wide else 640, 280)
	var style := StyleBoxFlat.new()
	style.bg_color = Pal.card
	style.border_color = Pal.active
	style.set_border_width_all(6)
	style.set_corner_radius_all(28)
	style.set_content_margin_all(30)
	card.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	card.add_child(row)
	var name_label := Label.new()
	name_label.text = player_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 96)
	name_label.add_theme_color_override("font_color", Pal.text)
	row.add_child(name_label)
	# Aquí aparece la X o la O que le toca, cuando la moneda cae.
	var badge := Label.new()
	badge.text = ""
	badge.add_theme_font_size_override("font_size", 150)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.custom_minimum_size = Vector2(130, 0)
	badge.visible = false
	row.add_child(badge)
	badges.append(badge)
	return card


func _process(_delta: float) -> void:
	if _phase >= 3:
		return
	var elapsed := float(Time.get_ticks_msec() - _started_ms)
	var total := float(maxi(duration_ms, 300))
	var vs_end := total * VS_FRACTION
	var flip_end := total * (VS_FRACTION + FLIP_FRACTION)
	if elapsed < vs_end:
		return
	if elapsed < flip_end:
		if _phase == 0:
			_begin_flip()
		_update_flip((elapsed - vs_end) / (flip_end - vs_end))
		return
	if _phase < 2:
		_update_flip(1.0)
		_show_result()
	if elapsed >= total:
		_phase = 3
		finished.emit()


func _begin_flip() -> void:
	_phase = 1
	result_label.text = "Sorteando quién empieza..."
	var tween := create_tween().set_parallel(true)
	tween.tween_property(vs_label, "modulate:a", 0.0, 0.3)
	tween.tween_property(coin, "modulate:a", 1.0, 0.3)
	tween.tween_property(result_label, "modulate:a", 1.0, 0.3)
	for card in cards:
		tween.tween_property(card, "modulate:a", 0.5, 0.3)


## t de 0 a 1: la moneda sube, gira cada vez más lento y cae mostrando la cara que le tocó a este jugador.
func _update_flip(t: float) -> void:
	var half_turns := 13 if my_seat == 1 else 14  # la última media vuelta cae en X (13) o en O (14)
	var eased := 1.0 - pow(1.0 - t, 3.0)
	var angle := half_turns * PI * eased
	var index := int(floor(angle / PI))
	coin.face = 1 + (index % 2)
	coin.letter_color = Color(0.12, 0.09, 0.02)
	coin.pivot_offset = coin.size / 2.0
	coin.scale = Vector2(maxf(absf(cos(angle)), 0.04), 1.0)
	_place_coin(-sin(t * PI) * 90.0)
	coin.queue_redraw()


## Centra la moneda en su zona (la moneda sube y baja con `lift`).
func _place_coin(lift: float) -> void:
	var zone := coin.get_parent() as Control
	coin.position = Vector2((zone.size.x - coin.size.x) / 2.0, (zone.size.y - coin.size.y) / 2.0 + lift)


func _show_result() -> void:
	_phase = 2
	coin.face = my_seat
	coin.scale = Vector2.ONE
	_place_coin(0.0)
	coin.queue_redraw()
	Fx.pop(coin, 1.25, 0.35)
	result_label.text = "Te tocó X: empezás vos" if my_seat == 1 else "Te tocó O: empieza %s" % opponent_name
	# Cada tarjeta muestra la marca que le tocó, con su color.
	var seats := [3 - my_seat, my_seat]  # tarjeta 0 = rival, tarjeta 1 = yo
	for i in 2:
		var seat: int = seats[i]
		var color: Color = mark_colors[seat]
		var card := cards[i]
		card.modulate.a = 1.0
		var style := card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		style.border_color = color
		card.add_theme_stylebox_override("panel", style)
		badges[i].text = "X" if seat == 1 else "O"
		badges[i].add_theme_color_override("font_color", color)
		badges[i].visible = true
		Fx.pop(badges[i], 0.4, 0.4)
