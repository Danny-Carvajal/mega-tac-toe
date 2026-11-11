extends Control
## Dibuja una figura (la X o la O de un jugador) con vectores, del color que se le pase.

var figure := "x_classic"
var color := Color.WHITE

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_figure(id: String, new_color: Color) -> void:
	figure = id
	color = new_color
	queue_redraw()

func _line(from: Vector2, to: Vector2, width: float) -> void:
	draw_line(from, to, color, width, true)
	draw_circle(from, width / 2.0, color)
	draw_circle(to, width / 2.0, color)

func _star(center: Vector2, points: int, outer: float, inner: float, rotation := -PI / 2.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var radius := outer if i % 2 == 0 else inner
		var angle := rotation + i * PI / points
		pts.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return pts

func _scaled(points: Array, center: Vector2, scale_by: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in points:
		pts.append(center + (p as Vector2) * scale_by)
	return pts

func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) * 0.34
	var t := r * 0.42
	match figure:
		"x_classic":
			_line(c + Vector2(-r, -r), c + Vector2(r, r), t)
			_line(c + Vector2(-r, r), c + Vector2(r, -r), t)
		"plus":
			_line(c + Vector2(-r * 1.1, 0), c + Vector2(r * 1.1, 0), t)
			_line(c + Vector2(0, -r * 1.1), c + Vector2(0, r * 1.1), t)
		"star":
			draw_colored_polygon(_star(c + Vector2(0, r * 0.06), 5, r * 1.2, r * 0.5), color)
		"diamond":
			draw_colored_polygon(_scaled([Vector2(0, -1), Vector2(0.8, 0), Vector2(0, 1), Vector2(-0.8, 0)], c, r * 1.15), color)
		"triangle":
			draw_colored_polygon(_scaled([Vector2(0, -1), Vector2(1, 0.8), Vector2(-1, 0.8)], c, r * 1.05), color)
		"bolt":
			draw_colored_polygon(_scaled([Vector2(0.15, -1), Vector2(-0.55, 0.15), Vector2(-0.05, 0.15),
					Vector2(-0.2, 1), Vector2(0.55, -0.2), Vector2(0.05, -0.2)], c, r * 1.15), color)
		"heart":
			var pts := PackedVector2Array()
			for i in 48:
				var a := i * TAU / 48.0
				var x := 16.0 * pow(sin(a), 3.0)
				var y := -(13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a))
				pts.append(c + Vector2(x, y + 1.5) * (r * 1.1 / 16.0))
			draw_colored_polygon(pts, color)
		"shuriken":
			draw_colored_polygon(_star(c, 4, r * 1.25, r * 0.38, PI / 4.0), color)
		"crown":
			draw_colored_polygon(_scaled([Vector2(-1, 0.7), Vector2(-1, -0.5), Vector2(-0.5, 0.05), Vector2(0, -0.8),
					Vector2(0.5, 0.05), Vector2(1, -0.5), Vector2(1, 0.7)], c, r * 1.1), color)
		"flower":
			for i in 6:
				var a := i * TAU / 6.0
				draw_circle(c + Vector2(cos(a), sin(a)) * r * 0.58, r * 0.4, color)
			draw_circle(c, r * 0.3, color.lightened(0.55))
		"o_classic":
			draw_arc(c, r * 0.85, 0.0, TAU, 48, color, t, true)
		"dot":
			draw_circle(c, r * 0.85, color)
		"square":
			draw_rect(Rect2(c - Vector2(r, r) * 0.85, Vector2(r, r) * 1.7), color, false, t)
		"target":
			draw_arc(c, r * 0.95, 0.0, TAU, 48, color, t * 0.8, true)
			draw_circle(c, r * 0.4, color)
		"hex":
			var pts := PackedVector2Array()
			for i in 7:
				var a := i * TAU / 6.0 + PI / 6.0
				pts.append(c + Vector2(cos(a), sin(a)) * r * 1.02)
			draw_polyline(pts, color, t * 0.85, true)
		"diamond_ring":
			draw_polyline(_scaled([Vector2(0, -1), Vector2(0.85, 0), Vector2(0, 1), Vector2(-0.85, 0), Vector2(0, -1)], c, r * 1.05), color, t * 0.85, true)
		"moon":
			var pts := PackedVector2Array()
			for i in 25:  # arco de afuera: de 56.8° a 303.2° pasando por 180°
				var a := deg_to_rad(56.8 + (303.2 - 56.8) * i / 24.0)
				pts.append(c + Vector2(cos(a), sin(a)) * r * 1.1)
			for i in 25:  # arco de adentro, de vuelta
				var a := deg_to_rad(280.0 - (280.0 - 80.0) * i / 24.0)
				pts.append(c + (Vector2(0.4, 0) + Vector2(cos(a), sin(a)) * 0.85) * r * 1.1)
			draw_colored_polygon(pts, color)
		"sun":
			draw_circle(c, r * 0.55, color)
			for i in 8:
				var a := i * TAU / 8.0
				_line(c + Vector2(cos(a), sin(a)) * r * 0.82, c + Vector2(cos(a), sin(a)) * r * 1.18, t * 0.6)
		"spiral":
			var pts := PackedVector2Array()
			for k in 61:
				var a := k * 0.34
				pts.append(c + Vector2(cos(a), sin(a)) * (r * 0.12 + r * 0.9 * k / 60.0))
			draw_polyline(pts, color, t * 0.7, true)
		"ring_double":
			draw_arc(c, r * 1.0, 0.0, TAU, 48, color, t * 0.5, true)
			draw_arc(c, r * 0.5, 0.0, TAU, 40, color, t * 0.5, true)
		"draw":  # empate de un tablero chico: un "="
			_line(c + Vector2(-r, -r * 0.4), c + Vector2(r, -r * 0.4), t)
			_line(c + Vector2(-r, r * 0.4), c + Vector2(r, r * 0.4), t)
		_:
			_line(c + Vector2(-r, -r), c + Vector2(r, r), t)
			_line(c + Vector2(-r, r), c + Vector2(r, -r), t)
