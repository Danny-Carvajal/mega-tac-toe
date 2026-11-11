class_name UltimateGame
extends RefCounted
## Lógica pura del Ultimate Tic Tac Toe. No sabe nada de pantallas ni de red,
## así la misma clase sirve para el juego local, la IA y el multijugador.
##
## Coordenadas: `big` es el tablero grande (0-8) y `small` la casilla dentro
## de ese tablero (0-8). Ambos van de izquierda a derecha, de arriba a abajo:
##
##   0 | 1 | 2
##   --+---+--
##   3 | 4 | 5
##   --+---+--
##   6 | 7 | 8

const NONE := 0
const X := 1
const O := 2
const DRAW := 3

## Versión de las reglas. Cliente y servidor tienen que coincidir (1 = tablero ganado se bloquea,
## 2 = tablero ganado sigue jugable). Subirla cada vez que cambie la lógica.
const RULES_VERSION := 2

const LINES := [
	[0, 1, 2], [3, 4, 5], [6, 7, 8],
	[0, 3, 6], [1, 4, 7], [2, 5, 8],
	[0, 4, 8], [2, 4, 6],
]

## 81 casillas: índice = big * 9 + small. Valores: NONE, X u O.
var cells: Array[int] = []
## Resultado de cada tablero grande: NONE, X, O o DRAW.
var board_results: Array[int] = []
var current_player: int = X
## Tablero grande donde se debe jugar. -1 significa "elegí el que quieras".
var forced_board: int = -1
## Resultado de la partida: NONE mientras siga, X, O o DRAW.
var result: int = NONE
## Estado antes de cada jugada ({player, forced_before, cells, results}), para poder deshacer la última.
var _history: Array[Dictionary] = []


func _init() -> void:
	reset()


func reset() -> void:
	cells.resize(81)
	cells.fill(NONE)
	board_results.resize(9)
	board_results.fill(NONE)
	current_player = X
	forced_board = -1
	result = NONE
	_history.clear()


func is_over() -> bool:
	return result != NONE


func get_cell(big: int, small: int) -> int:
	return cells[big * 9 + small]


func is_legal(big: int, small: int) -> bool:
	if is_over():
		return false
	if big < 0 or big > 8 or small < 0 or small > 8:
		return false
	# Un tablero ganado sigue siendo jugable en sus casillas libres.
	if forced_board != -1 and forced_board != big:
		return false
	return cells[big * 9 + small] == NONE


## Todas las jugadas posibles ahora mismo, como Vector2i(big, small).
func legal_moves() -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	for big in 9:
		for small in 9:
			if is_legal(big, small):
				moves.append(Vector2i(big, small))
	return moves


## Juega una casilla. Devuelve false si la jugada no es legal.
func play(big: int, small: int) -> bool:
	if not is_legal(big, small):
		return false

	# Foto del estado anterior, para poder deshacer la jugada si le saltan el turno al rival.
	_history.append({
		"player": current_player,
		"forced_before": forced_board,
		"cells": cells.duplicate(),
		"results": board_results.duplicate(),
	})
	cells[big * 9 + small] = current_player

	# El primero en hacer línea se queda con el tablero, aunque después se siga jugando ahí.
	if board_results[big] == NONE:
		var local := _line_winner(cells.slice(big * 9, big * 9 + 9))
		if local != NONE:
			board_results[big] = local
		elif _board_is_full(big):
			board_results[big] = DRAW

	var global := _line_winner(board_results)
	if global != NONE:
		result = global
	elif not board_results.has(NONE):
		result = DRAW

	# La casilla que jugué decide el tablero del rival; solo si ese tablero
	# está lleno el rival elige libre.
	forced_board = -1 if _board_is_full(small) else small

	if not is_over():
		current_player = O if current_player == X else X
	return true


## Salta el turno del jugador actual (por ejemplo cuando se le acaba el tiempo).
## El rival deshace su última jugada y la vuelve a elegir, ya sabiendo que el otro
## no va a responder: así puede pensar en su propia ventaja y no en lo que podía
## hacer el rival. Si todavía no había jugadas que deshacer, solo pasa el turno.
func skip_turn() -> bool:
	if is_over():
		return false
	if _history.is_empty():
		current_player = O if current_player == X else X
	else:
		_undo_last_move()
	return true


func _undo_last_move() -> void:
	var last: Dictionary = _history.pop_back()
	cells.assign(last["cells"])
	board_results.assign(last["results"])
	result = NONE
	forced_board = int(last["forced_before"])
	current_player = int(last["player"])


func _board_is_full(big: int) -> bool:
	for small in 9:
		if cells[big * 9 + small] == NONE:
			return false
	return true


## Los tres índices de la línea que tiene `who` completa, o [] si no hay.
static func winning_line(marks: Array, who: int) -> Array:
	for line in LINES:
		if marks[line[0]] == who and marks[line[1]] == who and marks[line[2]] == who:
			return line
	return []


## Gana quien tenga 3 en línea. DRAW (3) nunca cuenta como línea.
static func _line_winner(marks: Array) -> int:
	for line in LINES:
		var mark: int = marks[line[0]]
		if (mark == X or mark == O) and marks[line[1]] == mark and marks[line[2]] == mark:
			return mark
	return NONE
