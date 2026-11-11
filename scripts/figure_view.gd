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

## Elipse como línea (sin usar draw_set_transform, que no se ve bien con varias seguidas).
func _ellipse(center: Vector2, rx: float, ry: float, rot: float, width: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		var a := i * TAU / 48.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	draw_polyline(pts, col, width, true)

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
		"paw":
			draw_circle(c + Vector2(0, r * 0.35), r * 0.5, color)
			for toe in [Vector2(-0.78, -0.05), Vector2(-0.3, -0.6), Vector2(0.3, -0.6), Vector2(0.78, -0.05)]:
				draw_circle(c + toe * r, r * 0.22, color)
		"drop":
			draw_circle(c + Vector2(0, r * 0.3), r * 0.7, color)
			draw_colored_polygon(_scaled([Vector2(0, -1.15), Vector2(0.65, 0.12), Vector2(-0.65, 0.12)], c, r), color)
		"leaf":
			var axis := Vector2(1, -1).normalized()
			var normal := Vector2(1, 1).normalized()
			var top := PackedVector2Array()
			var bottom := PackedVector2Array()
			for i in 21:
				var u := -1.0 + 2.0 * i / 20.0
				var w := 0.55 * (1.0 - u * u)
				top.append(c + axis * u * r * 1.2 + normal * w * r)
				bottom.append(c + axis * u * r * 1.2 - normal * w * r)
			bottom.reverse()
			top.append_array(bottom)
			draw_colored_polygon(top, color)
			draw_line(c - axis * r * 1.2, c + axis * r * 1.0, Color(0, 0, 0, 0.35), t * 0.25, true)
		"sword":
			var axis := Vector2(1, -1).normalized()
			var normal := Vector2(1, 1).normalized()
			_line(c - axis * r * 0.2, c + axis * r * 1.15, t * 0.65)
			_line(c - axis * r * 0.2 - normal * r * 0.55, c - axis * r * 0.2 + normal * r * 0.55, t * 0.5)
			_line(c - axis * r * 0.2, c - axis * r * 0.85, t * 0.45)
			draw_circle(c - axis * r * 0.95, t * 0.4, color)
		"rocket":
			draw_colored_polygon(_scaled([Vector2(0, -1.2), Vector2(0.45, -0.4), Vector2(0.45, 0.7), Vector2(-0.45, 0.7), Vector2(-0.45, -0.4)], c, r), color)
			draw_colored_polygon(_scaled([Vector2(-0.45, 0.1), Vector2(-0.95, 0.95), Vector2(-0.45, 0.7)], c, r), color)
			draw_colored_polygon(_scaled([Vector2(0.45, 0.1), Vector2(0.45, 0.7), Vector2(0.95, 0.95)], c, r), color)
			draw_colored_polygon(_scaled([Vector2(-0.25, 0.75), Vector2(0.25, 0.75), Vector2(0, 1.25)], c, r), color.lightened(0.5))
			draw_circle(c + Vector2(0, -0.15) * r, r * 0.2, Color(0, 0, 0, 0.4))
		"skull":
			draw_circle(c + Vector2(0, -0.15) * r, r * 0.85, color)
			draw_rect(Rect2(c + Vector2(-0.45, 0.4) * r, Vector2(0.9, 0.6) * r), color)
			for eye in [-0.33, 0.33]:
				draw_circle(c + Vector2(eye, -0.15) * r, r * 0.22, Color(0, 0, 0, 0.7))
		"gem":
			draw_colored_polygon(_scaled([Vector2(-0.55, -0.85), Vector2(0.55, -0.85), Vector2(1, -0.2), Vector2(0, 1.05), Vector2(-1, -0.2)], c, r * 1.05), color)
			var facet := Color(1, 1, 1, 0.45)
			for seg in [[Vector2(-1, -0.2), Vector2(1, -0.2)], [Vector2(-0.55, -0.85), Vector2(-0.35, -0.2)], [Vector2(0.55, -0.85), Vector2(0.35, -0.2)], [Vector2(-0.35, -0.2), Vector2(0, 1.05)], [Vector2(0.35, -0.2), Vector2(0, 1.05)]]:
				draw_line(c + seg[0] * r * 1.05, c + seg[1] * r * 1.05, facet, t * 0.2, true)
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
			for i in range(1, 24):  # arco de adentro, de vuelta (sin repetir los puntos de las puntas)
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
				var a := k * 0.21
				pts.append(c + Vector2(cos(a), sin(a)) * (r * 0.1 + r * 0.95 * k / 60.0))
			draw_polyline(pts, color, t * 0.55, true)
		"ring_double":
			draw_arc(c, r * 1.0, 0.0, TAU, 48, color, t * 0.5, true)
			draw_arc(c, r * 0.5, 0.0, TAU, 40, color, t * 0.5, true)
		"dashed":
			for i in 12:
				var start := i * TAU / 12.0
				draw_arc(c, r * 0.9, start, start + TAU / 12.0 * 0.6, 8, color, t * 0.85, true)
		"pixel":
			var s := r * 0.62
			for gx in range(-1, 2):
				for gy in range(-1, 2):
					if gx != 0 or gy != 0:
						draw_rect(Rect2(c + Vector2(gx, gy) * s - Vector2(s, s) * 0.45, Vector2(s, s) * 0.9), color)
		"eye":
			var lens := PackedVector2Array()
			for i in 21:
				var x := -1.2 + 2.4 * i / 20.0
				lens.append(c + Vector2(x, -0.6 * (1.0 - pow(x / 1.2, 2.0))) * r)
			for i in 21:
				var x := 1.2 - 2.4 * i / 20.0
				lens.append(c + Vector2(x, 0.6 * (1.0 - pow(x / 1.2, 2.0))) * r)
			lens.append(lens[0])
			draw_polyline(lens, color, t * 0.5, true)
			draw_circle(c, r * 0.38, color)
			draw_circle(c, r * 0.15, Color(0, 0, 0, 0.6))
		"shield":
			var outline := _scaled([Vector2(-0.85, -0.8), Vector2(0.85, -0.8), Vector2(0.85, 0.1), Vector2(0, 1.1), Vector2(-0.85, 0.1), Vector2(-0.85, -0.8)], c, r)
			draw_polyline(outline, color, t * 0.8, true)
		"planet":
			draw_circle(c, r * 0.6, color)
			_ellipse(c, r * 1.25, r * 0.48, -0.35, t * 0.5, color.lightened(0.35))
		"snowflake":
			for i in 6:
				var dir := Vector2.from_angle(i * TAU / 6.0)
				_line(c, c + dir * r * 1.1, t * 0.45)
				var branch := c + dir * r * 0.62
				_line(branch, branch + dir.rotated(0.8) * r * 0.35, t * 0.4)
				_line(branch, branch + dir.rotated(-0.8) * r * 0.35, t * 0.4)
		"atom":
			draw_circle(c, r * 0.2, color)
			for k in 3:
				_ellipse(c, r * 1.15, r * 0.45, k * PI / 3.0, t * 0.4, color)
		"draw":  # empate de un tablero chico: un "="
			_line(c + Vector2(-r, -r * 0.4), c + Vector2(r, -r * 0.4), t)
			_line(c + Vector2(-r, r * 0.4), c + Vector2(r, r * 0.4), t)
		_:
			_line(c + Vector2(-r, -r), c + Vector2(r, r), t)
			_line(c + Vector2(-r, r), c + Vector2(r, -r), t)
