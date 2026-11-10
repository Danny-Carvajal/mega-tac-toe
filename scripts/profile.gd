extends RefCounted
## Perfil local del jugador: nombre y colores de sus piezas.
## Por defecto X es rojo y O es azul; cada jugador puede cambiarlos antes de empezar.

const PATH := "user://profile.cfg"
const DEFAULT_X := Color("e5484d")
const DEFAULT_O := Color("3b82f6")

var player_name := "Jugador"
var color_x := DEFAULT_X
var color_o := DEFAULT_O


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	player_name = str(cfg.get_value("profile", "name", player_name))
	color_x = Color.html(str(cfg.get_value("profile", "color_x", "#" + DEFAULT_X.to_html(false))))
	color_o = Color.html(str(cfg.get_value("profile", "color_o", "#" + DEFAULT_O.to_html(false))))


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "name", player_name)
	cfg.set_value("profile", "color_x", "#" + color_x.to_html(false))
	cfg.set_value("profile", "color_o", "#" + color_o.to_html(false))
	cfg.save(PATH)


func colors_payload() -> Dictionary:
	return {"x": "#" + color_x.to_html(false), "o": "#" + color_o.to_html(false)}
