extends RefCounted
## Estadísticas de las partidas online del jugador. Se guardan en el dispositivo.

const PATH := "user://stats.cfg"
const RECENT_MAX := 20

var wins := 0
var losses := 0
var draws := 0
## Racha actual: positiva = victorias seguidas, negativa = derrotas seguidas.
var streak := 0
var best_streak := 0
## Últimos resultados ("W", "L" o "D"), el más nuevo al final.
var recent: Array = []


func total() -> int:
	return wins + losses + draws


## Porcentaje de partidas ganadas (0 a 100).
func win_rate() -> float:
	if total() == 0:
		return 0.0
	return 100.0 * wins / total()


## Anota el resultado de una partida: "W" ganó, "L" perdió, "D" empató.
func record(result: String) -> void:
	match result:
		"W":
			wins += 1
			streak = streak + 1 if streak > 0 else 1
			best_streak = maxi(best_streak, streak)
		"L":
			losses += 1
			streak = streak - 1 if streak < 0 else -1
		"D":
			draws += 1
			streak = 0
		_:
			return
	recent.append(result)
	while recent.size() > RECENT_MAX:
		recent.pop_front()


func reset() -> void:
	wins = 0
	losses = 0
	draws = 0
	streak = 0
	best_streak = 0
	recent = []


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	wins = int(cfg.get_value("stats", "wins", 0))
	losses = int(cfg.get_value("stats", "losses", 0))
	draws = int(cfg.get_value("stats", "draws", 0))
	streak = int(cfg.get_value("stats", "streak", 0))
	best_streak = int(cfg.get_value("stats", "best_streak", 0))
	recent = []
	for item in str(cfg.get_value("stats", "recent", "")):
		if item in ["W", "L", "D"]:
			recent.append(item)


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "wins", wins)
	cfg.set_value("stats", "losses", losses)
	cfg.set_value("stats", "draws", draws)
	cfg.set_value("stats", "streak", streak)
	cfg.set_value("stats", "best_streak", best_streak)
	cfg.set_value("stats", "recent", "".join(recent))
	cfg.save(PATH)
