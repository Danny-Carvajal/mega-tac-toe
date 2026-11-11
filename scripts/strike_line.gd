extends Control
## Raya que se dibuja encima de un 3 en línea, de una punta a la otra.

var from_target: Control
var to_target: Control
var color := Color.WHITE
var width := 12.0
var progress := 1.0
## Identifica la raya actual: si no cambia, no se vuelve a animar.
var key := ""
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Muestra la raya entre dos controles. `animate` hace que se vaya dibujando.
func show_line(from_control: Control, to_control: Control, new_color: Color, new_width: float, new_key: String, animate: bool) -> void:
	from_target = from_control
	to_target = to_control
	color = new_color
	width = new_width
	visible = true
	if new_key == key:
		queue_redraw()
		return
	key = new_key
	if _tween != null:
		_tween.kill()
	if animate:
		progress = 0.0
		_tween = create_tween()
		_tween.tween_method(_set_progress, 0.0, 1.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		progress = 1.0
	queue_redraw()


func hide_line() -> void:
	if _tween != null:
		_tween.kill()
	visible = false
	key = ""


func _set_progress(value: float) -> void:
	progress = value
	queue_redraw()


func _draw() -> void:
	if from_target == null or to_target == null or not is_instance_valid(from_target) or not is_instance_valid(to_target):
		return
	var inverse := get_global_transform().affine_inverse()
	var a: Vector2 = inverse * from_target.get_global_rect().get_center()
	var b: Vector2 = inverse * to_target.get_global_rect().get_center()
	var extend := (b - a) * 0.22
	a -= extend
	b += extend
	var end := a.lerp(b, progress)
	var shadow := Color(0, 0, 0, 0.35)
	draw_line(a, end, shadow, width + 6.0, true)
	draw_circle(a, (width + 6.0) / 2.0, shadow)
	draw_circle(end, (width + 6.0) / 2.0, shadow)
	draw_line(a, end, color, width, true)
	draw_circle(a, width / 2.0, color)
	draw_circle(end, width / 2.0, color)
