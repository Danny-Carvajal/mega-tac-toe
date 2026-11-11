extends Control
## Fondo de la tarjeta de un jugador: degradado en diagonal + patrón, con esquinas redondeadas.

const Cosmetics := preload("res://scripts/cosmetics.gd")
const Pal := preload("res://scripts/pal.gd")

var banner := "banner_classic"
var radius := 24.0
var time := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true  # los patrones (aros, estrellas) no se salen de la tarjeta
	resized.connect(queue_redraw)

func set_banner(id: String) -> void:
	banner = id
	set_process(bool(Cosmetics.banner_data(id).get("anim", false)))
	queue_redraw()

func _process(delta: float) -> void:
	time += delta
	queue_redraw()

func _colors() -> Array:
	var data := Cosmetics.banner_data(banner)
	if data.get("neutral", false):
		return [Pal.card, Pal.panel]
	return [Color.html(str(data["c1"])), Color.html(str(data["c2"]))]

func _draw() -> void:
	var data := Cosmetics.banner_data(banner)
	var colors := _colors()
	var animated := bool(data.get("anim", false))
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var corners := [Vector2(radius, radius), Vector2(size.x - radius, radius),
			Vector2(size.x - radius, size.y - radius), Vector2(radius, size.y - radius)]
	var starts := [PI, PI * 1.5, 0.0, PI * 0.5]
	for corner in 4:
		for step in 9:
			var a: float = starts[corner] + step * (PI / 2.0) / 8.0
			var p: Vector2 = corners[corner] + Vector2(cos(a), sin(a)) * radius
			pts.append(p)
			var t := clampf((p.x / maxf(size.x, 1.0) + p.y / maxf(size.y, 1.0)) / 2.0, 0.0, 1.0)
			if animated:
				t = 0.5 - 0.5 * cos((t + time * 0.12) * TAU)
			cols.append((colors[0] as Color).lerp(colors[1], t))
	draw_polygon(pts, cols)
	_pattern(str(data.get("pattern", "")))

func _pattern(kind: String) -> void:
	if kind.is_empty():
		return
	var u := size.y / 280.0  # escala: los patrones se ven parecidos en tarjetas de distinto tamaño
	var inset := radius * 0.5
	var area := Rect2(inset, inset, size.x - inset * 2.0, size.y - inset * 2.0)
	var light := Color(1, 1, 1, 0.16)
	var shift := time * 24.0 * u if Cosmetics.banner_data(banner).get("anim", false) else 0.0
	match kind:
		"stripes":
			var gap := 44.0 * u
			var x := area.position.x - area.size.y + fposmod(shift, gap)
			while x < area.end.x:
				var a := Vector2(maxf(x, area.position.x), area.position.y + maxf(0.0, area.position.x - x))
				var b := Vector2(minf(x + area.size.y, area.end.x), area.position.y + minf(area.size.y, area.end.x - x))
				if a.x < b.x:
					draw_line(a, b, light, 14.0 * u, true)
				x += gap
		"dots":
			var gap := 40.0 * u
			var y := area.position.y + gap / 2.0
			while y < area.end.y:
				var x := area.position.x + gap / 2.0
				while x < area.end.x:
					draw_circle(Vector2(x, y), 6.0 * u, light)
					x += gap
				y += gap
		"grid":
			var gap := 44.0 * u
			var x := area.position.x + fposmod(shift, gap)
			while x < area.end.x:
				draw_line(Vector2(x, area.position.y), Vector2(x, area.end.y), light, 2.5 * u)
				x += gap
			var y := area.position.y
			while y < area.end.y:
				draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), light, 2.5 * u)
				y += gap
		"waves":
			var row := area.position.y + 30.0 * u
			while row < area.end.y:
				var line := PackedVector2Array()
				var x := area.position.x
				while x <= area.end.x:
					line.append(Vector2(x, row + sin((x + shift * 3.0) / (36.0 * u)) * 9.0 * u))
					x += 12.0
				draw_polyline(line, light, 4.0 * u, true)
				row += 50.0 * u
		"rings":
			var center := Vector2(area.end.x - 40.0 * u, area.position.y + area.size.y / 2.0)
			for i in 5:
				var ring_radius := (50.0 + i * 46.0) * u + fposmod(shift, 46.0 * u)
				draw_arc(center, ring_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.14), 4.0 * u, true)
		"stars":
			for i in 18:
				var px := area.position.x + fposmod(float(i * 7919 % 1000) / 1000.0 * area.size.x + shift * 0.2, area.size.x)
				var py := area.position.y + float(i * 104729 % 1000) / 1000.0 * area.size.y
				var twinkle := 0.5 + 0.5 * sin(time * 2.0 + i)
				draw_circle(Vector2(px, py), (2.5 + (i % 3) * 1.5) * u, Color(1, 1, 1, 0.25 + 0.4 * twinkle))
