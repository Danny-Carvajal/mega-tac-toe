extends RefCounted
## Paleta de la interfaz: oscuro por defecto, con modo claro. Se lee al construir cada pantalla.

static var light := false
static var bg := Color("14151f")
static var cell := Color("2d3048")
static var active := Color("3d4a7a")
static var text := Color("e8eaf6")
static var muted := Color("8a8fa8")
static var panel := Color("22253a")
static var card := Color("1f2133")
static var cell_off := Color("2a2d45")
static var banner := Color("3a3f5c")
static var bar := Color("181a29")
static var pill := Color("34406b")
static var accent := Color("8f95ad")
static var notes_on := Color("3b6f8f")
static var notice := Color("ffd24d")


static func apply(use_light: bool) -> void:
	light = use_light
	if light:
		bg = Color("eef0f7")
		cell = Color("d3d8ec")
		active = Color("aab8ee")
		text = Color("1d2033")
		muted = Color("6b7088")
		panel = Color("dfe3f2")
		card = Color("ffffff")
		cell_off = Color("e1e4f0")
		banner = Color("cdd2e8")
		bar = Color("ffffff")
		pill = Color("c7d0f2")
		accent = Color("5d6fbf")
		notes_on = Color("9bc7e6")
		notice = Color("a06a00")
	else:
		bg = Color("14151f")
		cell = Color("2d3048")
		active = Color("3d4a7a")
		text = Color("e8eaf6")
		muted = Color("8a8fa8")
		panel = Color("22253a")
		card = Color("1f2133")
		cell_off = Color("2a2d45")
		banner = Color("3a3f5c")
		bar = Color("181a29")
		pill = Color("34406b")
		accent = Color("8f95ad")
		notes_on = Color("3b6f8f")
		notice = Color("ffd24d")
	RenderingServer.set_default_clear_color(bg)
