extends RefCounted
## Catálogo de cosméticos: figuras (una por lado, X y O), banners de jugador y fuentes del nombre.
## Todo se dibuja por código (sin imágenes), así pesa nada y se puede reemplazar por arte propio después.

const Pal := preload("res://scripts/pal.gd")

enum Rarity { COMMON, RARE, EPIC, LEGENDARY }

const RARITY_NAMES := ["Común", "Rara", "Épica", "Legendaria"]
const RARITY_COLORS := [Color("9aa3b8"), Color("4f8ff7"), Color("a855f7"), Color("f5b83d")]
## Probabilidad de cada rareza al abrir una caja (suman 100).
const RARITY_WEIGHTS := [60, 28, 9, 3]
## Si toca algo que ya tenés, te devuelven monedas según la rareza.
const REFUND := [40, 80, 150, 250]

const BOX_PRICE := 300
const START_COINS := 600
const COINS_WIN := 100
const COINS_DRAW := 50
const COINS_LOSS := 25
## Monedas por ganar en práctica, según el nivel de la IA (1 a 5).
const COINS_PRACTICE_WIN := [5, 10, 15, 20, 25]

const KIND_NAMES := {"fx": "Figura de X", "fo": "Figura de O", "banner": "Banner", "font": "Fuente"}
const DEFAULTS := {"fx": "x_classic", "fo": "o_classic", "banner": "banner_classic", "font": "font_classic"}

const FIGURES_X := [
	{"id": "x_classic", "name": "X clásica", "rarity": 0},
	{"id": "plus", "name": "Cruz", "rarity": 0},
	{"id": "star", "name": "Estrella", "rarity": 1},
	{"id": "diamond", "name": "Rombo", "rarity": 1},
	{"id": "triangle", "name": "Triángulo", "rarity": 1},
	{"id": "bolt", "name": "Rayo", "rarity": 2},
	{"id": "heart", "name": "Corazón", "rarity": 2},
	{"id": "shuriken", "name": "Shuriken", "rarity": 2},
	{"id": "crown", "name": "Corona", "rarity": 3},
	{"id": "flower", "name": "Flor", "rarity": 3},
]
const FIGURES_O := [
	{"id": "o_classic", "name": "O clásica", "rarity": 0},
	{"id": "dot", "name": "Punto", "rarity": 0},
	{"id": "square", "name": "Cuadrado", "rarity": 1},
	{"id": "target", "name": "Diana", "rarity": 1},
	{"id": "hex", "name": "Hexágono", "rarity": 1},
	{"id": "moon", "name": "Luna", "rarity": 2},
	{"id": "spiral", "name": "Espiral", "rarity": 2},
	{"id": "ring_double", "name": "Doble aro", "rarity": 2},
	{"id": "sun", "name": "Sol", "rarity": 3},
	{"id": "diamond_ring", "name": "Rombo hueco", "rarity": 3},
]

## Banners: dos colores en diagonal, un patrón encima y, si `anim`, se mueve despacio. `neutral` usa los colores del tema.
const BANNERS := {
	"banner_classic": {"name": "Clásico", "rarity": 0, "neutral": true},
	"banner_slate": {"name": "Pizarra", "rarity": 0, "c1": "3a4258", "c2": "20263a"},
	"banner_forest": {"name": "Bosque", "rarity": 0, "c1": "2f7d52", "c2": "174a30"},
	"banner_wine": {"name": "Vino", "rarity": 0, "c1": "8c2f55", "c2": "4a1730"},
	"banner_sunset": {"name": "Atardecer", "rarity": 1, "c1": "f97316", "c2": "ec4899", "pattern": "stripes"},
	"banner_ocean": {"name": "Océano", "rarity": 1, "c1": "0ea5b7", "c2": "2563eb", "pattern": "waves"},
	"banner_mint": {"name": "Menta", "rarity": 1, "c1": "34d399", "c2": "06b6d4", "pattern": "dots"},
	"banner_steel": {"name": "Acero", "rarity": 1, "c1": "64748b", "c2": "1e293b", "pattern": "grid"},
	"banner_magma": {"name": "Magma", "rarity": 2, "c1": "ef4444", "c2": "f59e0b", "pattern": "stripes", "anim": true},
	"banner_neon": {"name": "Neón", "rarity": 2, "c1": "d946ef", "c2": "22d3ee", "pattern": "grid", "anim": true},
	"banner_aurora": {"name": "Aurora", "rarity": 3, "c1": "22c55e", "c2": "8b5cf6", "pattern": "stars", "anim": true},
	"banner_galaxy": {"name": "Galaxia", "rarity": 3, "c1": "4338ca", "c2": "0b0b1e", "pattern": "stars", "anim": true},
	"banner_gold": {"name": "Oro", "rarity": 3, "c1": "fcd34d", "c2": "b45309", "pattern": "rings", "anim": true},
}

## Fuentes del nombre: variaciones de la fuente base (negrita, cursiva, espaciado) y colores.
const FONTS := {
	"font_classic": {"name": "Clásica", "rarity": 0},
	"font_bold": {"name": "Negrita", "rarity": 0, "embolden": 0.7},
	"font_italic": {"name": "Cursiva", "rarity": 0, "skew": 0.25},
	"font_wide": {"name": "Espaciada", "rarity": 1, "spacing": 8, "embolden": 0.3},
	"font_outline": {"name": "Contorno", "rarity": 1, "embolden": 0.5, "outline": "101018", "outline_size": 10},
	"font_neon": {"name": "Neón", "rarity": 2, "color": "7df9ff", "outline": "0a4aff", "outline_size": 8, "embolden": 0.4},
	"font_gold": {"name": "Dorada", "rarity": 2, "color": "ffd24a", "shadow": "5a3a00", "embolden": 0.6},
	"font_fire": {"name": "Fuego", "rarity": 3, "color": "ffb347", "outline": "b3260e", "outline_size": 9, "embolden": 0.8, "skew": 0.18},
	"font_ice": {"name": "Hielo", "rarity": 3, "color": "e6fbff", "outline": "2a8fd1", "outline_size": 9, "embolden": 0.6, "spacing": 4},
}


## Todos los cosméticos como lista de {id, kind, name, rarity}.
static func all_items() -> Array:
	var items: Array = []
	for entry in FIGURES_X:
		items.append({"id": entry["id"], "kind": "fx", "name": entry["name"], "rarity": entry["rarity"]})
	for entry in FIGURES_O:
		items.append({"id": entry["id"], "kind": "fo", "name": entry["name"], "rarity": entry["rarity"]})
	for id in BANNERS:
		items.append({"id": id, "kind": "banner", "name": BANNERS[id]["name"], "rarity": BANNERS[id]["rarity"]})
	for id in FONTS:
		items.append({"id": id, "kind": "font", "name": FONTS[id]["name"], "rarity": FONTS[id]["rarity"]})
	return items


static func items_of_kind(kind: String) -> Array:
	var result: Array = []
	for entry in all_items():
		if entry["kind"] == kind:
			result.append(entry)
	return result


## Datos de un cosmético ({} si no existe).
static func item(id: String) -> Dictionary:
	for entry in all_items():
		if entry["id"] == id:
			return entry
	return {}


static func is_default(id: String) -> bool:
	return DEFAULTS.values().has(id)


## Los que se pueden ganar en cajas (todos menos los de inicio).
static func droppable() -> Array:
	var result: Array = []
	for entry in all_items():
		if not is_default(entry["id"]):
			result.append(entry)
	return result


## Devuelve `id` si es un cosmético de ese tipo; si no, el de inicio (protege de datos raros del rival).
static func safe(id: Variant, kind: String) -> String:
	var text := str(id)
	var found := item(text)
	if found.is_empty() or found["kind"] != kind:
		return DEFAULTS[kind]
	return text


## Sortea el contenido de una caja: primero la rareza y después uno de esa rareza.
static func roll(rng: RandomNumberGenerator) -> Dictionary:
	var pool := droppable()
	var pick := rng.randi_range(1, 100)
	var rarity := 0
	var acc := 0
	for i in RARITY_WEIGHTS.size():
		acc += RARITY_WEIGHTS[i]
		if pick <= acc:
			rarity = i
			break
	var candidates: Array = []
	for entry in pool:
		if entry["rarity"] == rarity:
			candidates.append(entry)
	if candidates.is_empty():
		candidates = pool
	return candidates[rng.randi() % candidates.size()]


static func banner_data(id: String) -> Dictionary:
	return BANNERS.get(id, BANNERS["banner_classic"])


## Le pone al texto el estilo de la fuente elegida (variaciones de la fuente base).
static func apply_font(label: Control, id: String) -> void:
	var data: Dictionary = FONTS.get(id, FONTS["font_classic"])
	var variation := FontVariation.new()
	variation.base_font = ThemeDB.fallback_font
	variation.variation_embolden = float(data.get("embolden", 0.0))
	var skew := float(data.get("skew", 0.0))
	if skew != 0.0:
		variation.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(skew, 1.0), Vector2.ZERO)
	variation.spacing_glyph = int(data.get("spacing", 0))
	label.add_theme_font_override("font", variation)
	if data.has("color"):
		label.add_theme_color_override("font_color", Color.html(str(data["color"])))
	if data.has("outline"):
		label.add_theme_color_override("font_outline_color", Color.html(str(data["outline"])))
		label.add_theme_constant_override("outline_size", int(data.get("outline_size", 6)))
	else:
		label.add_theme_constant_override("outline_size", 0)
	if data.has("shadow"):
		label.add_theme_color_override("font_shadow_color", Color.html(str(data["shadow"])))
		label.add_theme_constant_override("shadow_offset_x", 4)
		label.add_theme_constant_override("shadow_offset_y", 4)
