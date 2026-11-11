class_name UltimateAI
extends RefCounted
## IA del Ultimate Tic Tac Toe para el modo práctica, con 5 niveles:
##   1 Novato:    juega al azar.
##   2 Aprendiz:  ve jugadas de un paso (gana tableros, bloquea, evita regalar tableros), con errores.
##   3 Estratega: busca 3 jugadas adelante y se equivoca de vez en cuando.
##   4 Experto:   busca 5 jugadas adelante, casi sin errores.
##   5 Maestro:   búsqueda profunda por tiempo (alfa-beta con profundidad iterativa), sin errores.
## Trabaja con su propia copia compacta del estado, así se puede correr en un hilo sin tocar la partida.

const NONE := 0
const X := 1
const O := 2
const DRAW := 3

const WIN := 100000
const INF := 1 << 30

const LEVEL_NAMES := ["Novato", "Aprendiz", "Estratega", "Experto", "Maestro"]
const LEVEL_HINTS := [
	"Juega casi al azar",
	"Ve jugadas de un paso",
	"Piensa 3 jugadas adelante",
	"Piensa 5 jugadas adelante",
	"Búsqueda profunda, casi perfecta",
]
## Tiempo máximo que piensa el nivel 5 (ms).
const MASTER_TIME_MS := 1500
const MASTER_TIME_MS_NO_THREADS := 450
const MASTER_MAX_DEPTH := 12

const LINES := [
	[0, 1, 2], [3, 4, 5], [6, 7, 8],
	[0, 3, 6], [1, 4, 7], [2, 5, 8],
	[0, 4, 8], [2, 4, 6],
]
## Para cada casilla, qué líneas pasan por ella.
const THROUGH := [
	[0, 3, 6], [0, 4], [0, 5, 7],
	[1, 3], [1, 4, 6, 7], [1, 5],
	[2, 3, 7], [2, 4], [2, 5, 6],
]
const BOARD_WEIGHT := [60, 50, 60, 50, 75, 50, 60, 50, 60]

var cells := PackedInt32Array()
var res := PackedInt32Array()
var empties := PackedInt32Array()
var forced := -1
var player := X
var result := NONE
## Si se pone en true, la búsqueda corta lo antes posible.
var cancelled := false

var _rng := RandomNumberGenerator.new()
var _deadline_ms := 0
var _nodes := 0
var _aborted := false
## Última búsqueda: profundidad completada y puntaje (para tests y ajustes).
var last_depth := 0
var last_score := 0


func _init() -> void:
	_rng.randomize()


## Copia el estado de una partida (mismos arreglos que UltimateGame).
func load_state(game_cells: Array, game_results: Array, game_forced: int, game_player: int) -> void:
	cells = PackedInt32Array(game_cells)
	res = PackedInt32Array(game_results)
	empties = PackedInt32Array()
	empties.resize(9)
	for big in 9:
		var count := 0
		for small in 9:
			if cells[big * 9 + small] == NONE:
				count += 1
		empties[big] = count
	forced = game_forced
	player = game_player
	result = NONE


## Elige la jugada para el jugador al que le toca. Devuelve Vector2i(big, small).
## `use_threads` solo ajusta el tiempo de pensar del nivel 5 (sin hilos piensa menos para no congelar la pantalla).
func choose(level: int, use_threads := true) -> Vector2i:
	var moves := _gen_moves()
	if moves.is_empty():
		return Vector2i(-1, -1)
	var picked: int
	match clampi(level, 1, 5):
		1:
			picked = moves[_rng.randi() % moves.size()]
		2:
			picked = _pick_tactical(moves)
		3:
			picked = _pick_searched(moves, 3, 0.25)
		4:
			picked = _pick_searched(moves, 5, 0.05)
		_:
			picked = _pick_master(moves, MASTER_TIME_MS if use_threads else MASTER_TIME_MS_NO_THREADS)
	return Vector2i(picked / 9, picked % 9)


# --- Niveles ---------------------------------------------------------------

## Nivel 2: mira cada jugada con reglas simples y a veces mete la pata a propósito.
func _pick_tactical(moves: PackedInt32Array) -> int:
	if _rng.randf() < 0.25:
		return moves[_rng.randi() % moves.size()]
	var best := moves[0]
	var best_score := -INF
	for move in moves:
		var score := _quick_score(move) + _rng.randf() * 10.0
		if score > best_score:
			best_score = score
			best = move
	return best


## Niveles 3 y 4: busca `depth` jugadas y, con probabilidad `slip`, elige la 2ª o 3ª mejor.
func _pick_searched(moves: PackedInt32Array, depth: int, slip: float) -> int:
	if _is_empty_board():
		return 4 * 9 + 4
	_deadline_ms = 0
	_aborted = false
	var ordered := _order(moves)
	var scores := _root_scores(ordered, depth)
	# Ordenar de mejor a peor.
	var idx: Array = range(ordered.size())
	idx.sort_custom(func(a: int, b: int) -> bool: return scores[a] > scores[b])
	last_depth = depth
	last_score = scores[idx[0]]
	var choice := 0
	if idx.size() > 1 and _rng.randf() < slip:
		choice = _rng.randi_range(1, mini(2, idx.size() - 1))
	return ordered[idx[choice]]


## Nivel 5: profundidad iterativa con límite de tiempo.
func _pick_master(moves: PackedInt32Array, time_ms: int) -> int:
	if _is_empty_board():
		return 4 * 9 + 4
	var ordered := _order(moves)
	var best_move := ordered[0]
	_deadline_ms = Time.get_ticks_msec() + time_ms
	_aborted = false
	_nodes = 0
	last_depth = 0
	for depth in range(1, MASTER_MAX_DEPTH + 1):
		var depth_best := -1
		var depth_best_score := -INF
		var alpha := -INF
		for move in ordered:
			var undo := _push(move)
			var score := -_search(depth - 1, -INF, -alpha, 1)
			_pop(move, undo)
			if _aborted or cancelled:
				break
			if score > depth_best_score:
				depth_best_score = score
				depth_best = move
				alpha = maxi(alpha, score)
		# Si se cortó a la mitad, vale lo ya encontrado solo si la jugada anterior fue la primera en revisarse.
		if depth_best != -1 and (not _aborted or depth_best_score > -INF):
			best_move = depth_best
			last_score = depth_best_score
			if not _aborted:
				last_depth = depth
			# La mejor jugada pasa al frente para revisarse primero en la próxima vuelta.
			var pos := ordered.find(depth_best)
			if pos > 0:
				ordered.remove_at(pos)
				ordered.insert(0, depth_best)
		if _aborted or cancelled:
			break
		if absi(depth_best_score) > WIN - 100:
			break  # ya hay victoria o derrota forzada a la vista
		if Time.get_ticks_msec() >= _deadline_ms:
			break
	return best_move


## Puntaje de cada jugada raíz. Las que quedan muy por debajo de la mejor se cortan (sirven solo como "malas").
func _root_scores(ordered: PackedInt32Array, depth: int) -> Array:
	var scores: Array = []
	var best := -INF
	for move in ordered:
		var undo := _push(move)
		var floor_alpha := -INF if best == -INF else best - 40
		var score := -_search(depth - 1, -INF, -floor_alpha, 1)
		_pop(move, undo)
		scores.append(score)
		best = maxi(best, score)
	return scores


# --- Búsqueda --------------------------------------------------------------

## Negamax con poda alfa-beta. El puntaje es desde el punto de vista de quien juega ahora.
func _search(depth: int, alpha: int, beta: int, ply: int) -> int:
	_nodes += 1
	if (_nodes & 255) == 0 and (cancelled or (_deadline_ms > 0 and Time.get_ticks_msec() > _deadline_ms)):
		_aborted = true
	if _aborted:
		return 0
	if result != NONE:
		return 0 if result == DRAW else -(WIN - ply)
	if depth <= 0:
		return _evaluate()
	var moves := _order(_gen_moves())
	var best := -INF
	for move in moves:
		var undo := _push(move)
		var score := -_search(depth - 1, -beta, -alpha, ply + 1)
		_pop(move, undo)
		if _aborted:
			return 0
		if score > best:
			best = score
			if score > alpha:
				alpha = score
				if alpha >= beta:
					break
	return best


## Valor del tablero para quien juega ahora (positivo = va ganando).
func _evaluate() -> int:
	var score := 0
	for big in 9:
		var owner := res[big]
		if owner == X:
			score += BOARD_WEIGHT[big]
		elif owner == O:
			score -= BOARD_WEIGHT[big]
		elif owner == NONE:
			score += _board_potential(big)
	for line in LINES:
		var x_count := 0
		var o_count := 0
		for big in line:
			if res[big] == X:
				x_count += 1
			elif res[big] == O:
				o_count += 1
			elif res[big] == DRAW:
				x_count += 10
				o_count += 10
		if o_count == 0 and x_count in [1, 2]:
			score += 12 if x_count == 1 else 70
		elif x_count == 0 and o_count in [1, 2]:
			score -= 12 if o_count == 1 else 70
	# Elegir tablero libre es una ventaja chica para quien mueve.
	if forced == -1:
		score += 8 if player == X else -8
	return score if player == X else -score


## Líneas abiertas dentro de un tablero todavía sin dueño.
func _board_potential(big: int) -> int:
	var base := big * 9
	var score := 0
	for line in LINES:
		var x_count := 0
		var o_count := 0
		for k in 3:
			var mark := cells[base + line[k]]
			if mark == X:
				x_count += 1
			elif mark == O:
				o_count += 1
		if o_count == 0 and x_count > 0:
			score += 2 if x_count == 1 else 9
		elif x_count == 0 and o_count > 0:
			score -= 2 if o_count == 1 else 9
	var center := cells[base + 4]
	if center == X:
		score += 2
	elif center == O:
		score -= 2
	return score


# --- Jugadas ---------------------------------------------------------------

func _is_empty_board() -> bool:
	for mark in cells:
		if mark != NONE:
			return false
	return true


## Jugadas legales como índices big * 9 + small.
func _gen_moves() -> PackedInt32Array:
	var moves := PackedInt32Array()
	if result != NONE:
		return moves
	if forced == -1:
		for i in 81:
			if cells[i] == NONE:
				moves.append(i)
	else:
		var base := forced * 9
		for small in 9:
			if cells[base + small] == NONE:
				moves.append(base + small)
	return moves


## Ordena las jugadas de más a menos prometedora (mejora mucho la poda).
func _order(moves: PackedInt32Array) -> PackedInt32Array:
	if moves.size() <= 1:
		return moves
	var keyed: Array = []
	for move in moves:
		keyed.append([_quick_score(move), move])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var ordered := PackedInt32Array()
	for pair in keyed:
		ordered.append(pair[1])
	return ordered


## Puntaje rápido de una jugada sin buscar: sirve para ordenar y para el nivel 2.
func _quick_score(move: int) -> float:
	var big := move / 9
	var small := move % 9
	var opponent := O if player == X else X
	var score := 0.0
	if res[big] == NONE:
		if _completes_line(big, small, player):
			score += 60.0
		elif _completes_line(big, small, opponent):
			score += 35.0
	# A dónde mando al rival.
	if empties[small] == 0:
		score -= 12.0  # le regalo elegir tablero libre
	elif res[small] == NONE and _can_win_board(small, opponent):
		score -= 45.0  # el rival gana ese tablero enseguida
	elif res[small] == NONE and _can_win_board(small, player):
		score += 6.0
	if small == 4:
		score += 3.0
	elif small in [0, 2, 6, 8]:
		score += 1.5
	if big == 4:
		score += 1.0
	return score


## ¿Poner `mark` en (big, small) cierra una línea de ese tablero?
func _completes_line(big: int, small: int, mark: int) -> bool:
	var base := big * 9
	for li in THROUGH[small]:
		var line: Array = LINES[li]
		var count := 0
		for k in 3:
			var cell: int = line[k]
			if cell != small and cells[base + cell] == mark:
				count += 1
		if count == 2:
			return true
	return false


func _can_win_board(big: int, mark: int) -> bool:
	for small in 9:
		if cells[big * 9 + small] == NONE and _completes_line(big, small, mark):
			return true
	return false


## Juega `move` para el jugador actual. Devuelve lo que hace falta para deshacerla (empaquetado en un entero).
func _push(move: int) -> int:
	var big := move / 9
	var small := move % 9
	var mark := player
	var prev_res := res[big]
	var prev_forced := forced
	cells[move] = mark
	empties[big] -= 1
	var changed := false
	if prev_res == NONE:
		var base := big * 9
		var won := false
		for li in THROUGH[small]:
			var line: Array = LINES[li]
			if cells[base + line[0]] == mark and cells[base + line[1]] == mark and cells[base + line[2]] == mark:
				won = true
				break
		if won:
			res[big] = mark
			changed = true
		elif empties[big] == 0:
			res[big] = DRAW
			changed = true
	if changed:
		if res[big] != DRAW:
			for li in THROUGH[big]:
				var line: Array = LINES[li]
				if res[line[0]] == mark and res[line[1]] == mark and res[line[2]] == mark:
					result = mark
					break
		if result == NONE:
			var open := false
			for r in res:
				if r == NONE:
					open = true
					break
			if not open:
				result = DRAW
	forced = -1 if empties[small] == 0 else small
	player = O if mark == X else X
	# prev_forced (-1..8) + 1, prev_res (0..3), si cambió el resultado global.
	return (prev_forced + 1) | (prev_res << 4) | ((1 if changed else 0) << 6)


func _pop(move: int, undo: int) -> void:
	var big := move / 9
	player = O if player == X else X
	cells[move] = NONE
	empties[big] += 1
	forced = (undo & 15) - 1
	res[big] = (undo >> 4) & 3
	result = NONE  # si la partida había terminado, esta jugada fue la que la cerró
