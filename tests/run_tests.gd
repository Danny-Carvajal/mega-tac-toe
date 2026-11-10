extends SceneTree
## Tests de la lógica. Correr con:
##   godot --headless -s tests/run_tests.gd

const UltimateGame := preload("res://scripts/ultimate_game.gd")

var failures := 0


func _init() -> void:
	test_first_move_is_free()
	test_move_forces_next_board()
	test_wrong_board_is_illegal()
	test_occupied_cell_is_illegal()
	test_local_win()
	test_forced_to_decided_board_gives_free_choice()
	test_local_draw()
	test_global_win()

	if failures == 0:
		print("OK: todos los tests pasaron")
	else:
		print("FALLARON %d tests" % failures)
	quit(1 if failures > 0 else 0)


func check(condition: bool, name: String) -> void:
	if condition:
		print("  ok   %s" % name)
	else:
		failures += 1
		print("  FAIL %s" % name)


func test_first_move_is_free() -> void:
	var g := UltimateGame.new()
	check(g.legal_moves().size() == 81, "primer turno: las 81 casillas son legales")


func test_move_forces_next_board() -> void:
	var g := UltimateGame.new()
	g.play(4, 2)
	check(g.forced_board == 2, "jugar en la casilla 2 manda al tablero 2")
	check(g.current_player == UltimateGame.O, "cambia el turno a O")
	for move in g.legal_moves():
		check(move.x == 2, "jugada legal solo en tablero 2")
		break
	check(g.legal_moves().size() == 9, "9 jugadas legales en el tablero forzado")


func test_wrong_board_is_illegal() -> void:
	var g := UltimateGame.new()
	g.play(4, 2)
	check(not g.play(5, 0), "no se puede jugar fuera del tablero forzado")
	check(g.current_player == UltimateGame.O, "una jugada ilegal no cambia el turno")


func test_occupied_cell_is_illegal() -> void:
	var g := UltimateGame.new()
	g.play(0, 0)  # X en (0,0), manda a O al tablero 0
	check(not g.play(0, 0), "no se puede jugar en casilla ocupada")


func test_local_win() -> void:
	var g := UltimateGame.new()
	g.cells[0] = UltimateGame.X
	g.cells[1] = UltimateGame.X
	g.play(0, 2)
	check(g.board_results[0] == UltimateGame.X, "X gana el tablero 0 con 3 en línea")
	check(not g.is_legal(0, 5), "no se puede jugar en un tablero ya ganado")


func test_forced_to_decided_board_gives_free_choice() -> void:
	var g := UltimateGame.new()
	g.board_results[4] = UltimateGame.X
	g.play(0, 4)
	check(g.forced_board == -1, "si mandan a un tablero decidido, elige libre")
	check(g.legal_moves().size() > 9, "con elección libre hay más de 9 jugadas")


func test_local_draw() -> void:
	var g := UltimateGame.new()
	# X O X / X O O / O X _  -> sin ganador, falta la casilla 8
	var marks := [1, 2, 1, 1, 2, 2, 2, 1]
	for i in marks.size():
		g.cells[i] = marks[i]
	g.play(0, 8)
	check(g.board_results[0] == UltimateGame.DRAW, "tablero lleno sin línea queda empatado")


func test_global_win() -> void:
	var g := UltimateGame.new()
	g.board_results[0] = UltimateGame.X
	g.board_results[1] = UltimateGame.X
	g.cells[18] = UltimateGame.X
	g.cells[19] = UltimateGame.X
	g.play(2, 2)
	check(g.result == UltimateGame.X, "X gana la partida con 3 tableros en línea")
	check(g.is_over(), "la partida termina")
	check(not g.play(5, 5), "no se puede jugar después de terminar")
