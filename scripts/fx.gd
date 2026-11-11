extends RefCounted
## Animaciones chiquitas y reutilizables (todas con Tween, sin assets).


## La pieza "salta" al aparecer: arranca chica y rebota hasta su tamaño.
static func pop(control: Control, from_scale := 0.5, duration := 0.28) -> void:
	if not control.is_inside_tree():
		return
	control.pivot_offset = control.size / 2.0
	control.scale = Vector2(from_scale, from_scale)
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2.ONE, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Aparece con fundido (opcionalmente después de un retraso).
static func fade_in(control: CanvasItem, duration := 0.22, delay := 0.0) -> void:
	if not control.is_inside_tree():
		return
	control.modulate.a = 0.0
	var tween := control.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(control, "modulate:a", 1.0, duration)


## Varios controles aparecen uno tras otro.
static func stagger_in(controls: Array, step := 0.05, duration := 0.25) -> void:
	var index := 0
	for control in controls:
		if control is CanvasItem and control.visible:
			fade_in(control, duration, index * step)
			index += 1


## Los botones NO cambian de tamaño al apretarlos (el zoom al tocar descuadraba la pantalla si se
## clickeaba rápido varias veces). Se deja la función para no tocar los llamados, pero no hace nada.
static func press_feedback(_button: Button) -> void:
	pass


static func _scale_to(control: Control, target: Vector2, duration: float, bounce: bool) -> void:
	if not control.is_inside_tree():
		return
	var tween := control.create_tween()
	var step := tween.tween_property(control, "scale", target, duration)
	if bounce:
		step.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Brillo suave en bucle (devuelve el tween para poder pararlo con kill()).
static func glow(control: CanvasItem) -> Tween:
	var tween := control.create_tween().set_loops()
	tween.tween_property(control, "modulate:a", 0.6, 0.7).set_trans(Tween.TRANS_SINE)
	tween.tween_property(control, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	return tween
