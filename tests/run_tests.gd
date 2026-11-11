extends SceneTree
## Tests de la lógica. Correr con:
##   godot --headless -s tests/run_tests.gd

const UltimateGame := preload("res://scripts/ultimate_game.gd")
const TurnClock := preload("res://scripts/turn_clock.gd")
const History := preload("res://scripts/history.gd")
const UltimateAI := preload("res://scripts/ai.gd")

var failures := 0


func _init() -> void:
	test_history_encoding()
	test_first_move_is_free()
	test_move_forces_next_board()
	test_wrong_board_is_illegal()
	test_occupied_cell_is_illegal()
	test_local_win()
	test_forced_to_full_board_gives_free_choice()
	test_forced_to_won_board_still_forces()
	test_won_board_keeps_first_winner()
	test_local_draw()
	test_global_win()
	test_clock_runs_only_for_active_player()
	test_clock_increment_and_rollover()
	test_clock_expiry()
	test_skip_turn()
	test_clock_skip_refill()
	test_ai_mirrors_the_game()
	test_ai_moves_are_legal()
	test_ai_finds_the_winning_move()
	test_ai_levels_get_stronger()

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
	g.forced_board = -1
	check(g.is_legal(0, 5), "un tablero ganado sigue jugable en sus casillas libres")
	check(not g.is_legal(0, 0), "pero no en las casillas ocupadas")


func test_forced_to_full_board_gives_free_choice() -> void:
	var g := UltimateGame.new()
	# Tablero 4 lleno y sin línea: X O X / X O O / O X X
	var marks := [1, 2, 1, 1, 2, 2, 2, 1, 1]
	for i in 9:
		g.cells[36 + i] = marks[i]
	g.board_results[4] = UltimateGame.DRAW
	g.play(0, 4)
	check(g.forced_board == -1, "si mandan a un tablero lleno, elige libre")
	check(g.legal_moves().size() > 9, "con elección libre hay más de 9 jugadas")


func test_forced_to_won_board_still_forces() -> void:
	var g := UltimateGame.new()
	g.cells[0] = UltimateGame.X
	g.cells[1] = UltimateGame.X
	g.play(0, 2)  # X gana el tablero 0 y manda a O al tablero 2
	g.play(2, 0)  # O manda a X de vuelta al tablero 0, que está ganado pero con espacio
	check(g.forced_board == 0, "mandan a un tablero ganado con casillas libres: se juega ahí")
	check(g.legal_moves().size() == 6, "las 6 casillas libres del tablero ganado son jugables")


func test_won_board_keeps_first_winner() -> void:
	var g := UltimateGame.new()
	for i in 3:
		g.cells[i] = UltimateGame.X
	g.board_results[0] = UltimateGame.X
	g.cells[3] = UltimateGame.O
	g.cells[4] = UltimateGame.O
	g.current_player = UltimateGame.O
	g.play(0, 5)  # O hace línea en el mismo tablero
	check(g.board_results[0] == UltimateGame.X, "el primero en hacer línea se queda el tablero")


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


func test_clock_runs_only_for_active_player() -> void:
	var c := TurnClock.new(30000, 5000)
	c.start(1, 0)
	check(c.remaining_ms(1, 10000) == 20000, "el reloj de X corre en su turno")
	check(c.remaining_ms(2, 10000) == 30000, "el reloj de O no corre en el turno de X")


func test_clock_increment_and_rollover() -> void:
	var c := TurnClock.new(30000, 5000)
	c.start(1, 0)
	c.pass_turn(2, 10000)  # X gastó 10s y movió
	check(c.banks[1] == 25000, "X: 30 - 10 + 5 de incremento")
	check(c.active == 2, "ahora corre el reloj de O")
	c.pass_turn(1, 10000 + 2000)  # O movió rápido
	check(c.banks[2] == 33000, "O guarda el tiempo que le sobró: 30 - 2 + 5")


func test_skip_turn() -> void:
	var g := UltimateGame.new()
	g.play(4, 2)  # X manda a O al tablero 2
	check(g.skip_turn(), "se puede saltar el turno")
	check(g.current_player == UltimateGame.X, "tras saltar a O, X vuelve a jugar")
	check(g.get_cell(4, 2) == UltimateGame.NONE, "la jugada anterior de X se deshace")
	check(g.forced_board == -1, "X recupera la elección que tenía en ese turno")
	check(g.play(4, 6) and g.forced_board == 6, "X puede elegir otra jugada")

	var h := UltimateGame.new()
	check(h.skip_turn() and h.current_player == UltimateGame.O, "sin jugadas que deshacer solo pasa el turno")
	check(h.cells.count(UltimateGame.NONE) == 81, "saltar no pone marcas")

	var w := UltimateGame.new()
	w.cells[0] = UltimateGame.X
	w.cells[1] = UltimateGame.X
	w.play(0, 2)
	check(w.board_results[0] == UltimateGame.X, "X gana el tablero 0")
	w.skip_turn()
	check(w.board_results[0] == UltimateGame.NONE, "al deshacer se pierde también ese tablero ganado")
	check(w.current_player == UltimateGame.X, "X puede volver a jugar ahí")

	var s := UltimateGame.new()
	s.play(0, 0)
	s.play(0, 1)
	s.skip_turn()  # le saltan a X: O deshace su jugada
	check(s.current_player == UltimateGame.O and s.forced_board == 0, "O vuelve a su turno con el tablero que tenía")
	s.skip_turn()  # le saltan a O: X deshace la suya
	check(s.current_player == UltimateGame.X and s.forced_board == -1, "X vuelve a su turno original")

	var done := UltimateGame.new()
	done.board_results[0] = UltimateGame.X
	done.result = UltimateGame.X
	check(not done.skip_turn(), "no se puede saltar con la partida terminada")


func test_clock_skip_refill() -> void:
	var c := TurnClock.new(30000, 5000)
	c.start(1, 0)
	c.skip_turn(2, 30000, 10000)
	check(c.banks[1] == 10000, "al saltar, el banco se repone")
	check(c.active == 2, "corre el reloj del rival")
	check(c.remaining_ms(2, 31000) == 29000, "el rival conserva su banco")


func test_clock_expiry() -> void:
	var c := TurnClock.new(30000, 5000)
	c.start(1, 0)
	check(not c.is_expired(29999), "todavía no se acaba el tiempo")
	check(c.is_expired(30000), "se acaba el tiempo exacto")
	c.stop(30000)
	check(not c.is_expired(99999), "con el reloj detenido no vence")


func test_history_encoding() -> void:
	check(History.cell_name(6, 6) == "a1" and History.cell_name(6, 0) == "a3" and History.cell_name(2, 2) == "i9" and History.cell_name(4, 4) == "e5" and History.cell_name(0, 0) == "a9" and History.cell_name(8, 8) == "i1", "notación a1-i9 (a1 abajo a la izquierda)")
	var log: Array = [[4, 4], [4, 0], [0, 8], "s", [8, 8]]
	var text := History.encode(log)
	check(History.decode(text) == log, "el historial guarda y recupera las jugadas (incluye saltos)")
	var long_log: Array = []
	for i in 40:
		long_log.append([i % 9, (i * 4) % 9])
	check(History.encode(long_log).length() <= 60, "una partida de 40 jugadas ocupa ~60 caracteres")
	check(History.decode("") == [], "historial vacío")
	var record := History.make_record(["Ana", "Beto"], ["#ff0000", "#0000ff"], 1, 1, "line", log)
	check(record["n"] == ["Ana", "Beto"] and record["w"] == 1 and History.decode(record["m"]) == log, "el registro lleva nombres, ganador y jugadas")


# --- IA (modo práctica) -----------------------------------------------------

func test_ai_mirrors_the_game() -> void:
	# La copia compacta de la IA tiene que coincidir con UltimateGame en partidas al azar.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var mismatches := 0
	for g in 60:
		var game := UltimateGame.new()
		var ai := UltimateAI.new()
		ai.load_state(game.cells, game.board_results, game.forced_board, game.current_player)
		while not game.is_over():
			var moves := game.legal_moves()
			if ai._gen_moves().size() != moves.size():
				mismatches += 1
				break
			var move: Vector2i = moves[rng.randi() % moves.size()]
			game.play(move.x, move.y)
			ai._push(move.x * 9 + move.y)
			if ai.result != game.result or ai.res != PackedInt32Array(game.board_results):
				mismatches += 1
				break
	check(mismatches == 0, "la IA entiende las reglas igual que el juego (60 partidas al azar)")


func test_ai_moves_are_legal() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var illegal := 0
	for level in [1, 2, 3, 4]:
		var game := UltimateGame.new()
		for i in 14:
			var ai := UltimateAI.new()
			ai.load_state(game.cells, game.board_results, game.forced_board, game.current_player)
			var move := ai.choose(level)
			if not game.play(move.x, move.y):
				illegal += 1
				break
	check(illegal == 0, "los niveles 1 a 4 siempre juegan jugadas legales")
	var game5 := UltimateGame.new()
	game5.play(4, 4)
	var ai5 := UltimateAI.new()
	ai5.load_state(game5.cells, game5.board_results, game5.forced_board, game5.current_player)
	var reply := ai5.choose(5)
	check(game5.is_legal(reply.x, reply.y) and reply.x == 4, "el nivel 5 juega legal y en el tablero que le tocaba")


func test_ai_finds_the_winning_move() -> void:
	# X ya tiene los tableros 0 y 1; en el tablero 2 tiene dos en línea: jugar (2, 2) gana la partida.
	var game := UltimateGame.new()
	game.cells[18] = UltimateGame.X
	game.cells[19] = UltimateGame.X
	game.cells[22] = UltimateGame.O
	game.cells[23] = UltimateGame.O
	game.board_results[0] = UltimateGame.X
	game.board_results[1] = UltimateGame.X
	var ai := UltimateAI.new()
	ai.load_state(game.cells, game.board_results, 2, UltimateGame.X)
	check(ai.choose(5) == Vector2i(2, 2), "el nivel 5 gana la partida cuando puede")
	# Lo mismo jugando de O.
	var game_o := UltimateGame.new()
	game_o.cells[18] = UltimateGame.O
	game_o.cells[19] = UltimateGame.O
	game_o.board_results[0] = UltimateGame.O
	game_o.board_results[1] = UltimateGame.O
	var ai_o := UltimateAI.new()
	ai_o.load_state(game_o.cells, game_o.board_results, 2, UltimateGame.O)
	check(ai_o.choose(5) == Vector2i(2, 2), "el nivel 5 también gana jugando de O")


func test_ai_levels_get_stronger() -> void:
	# Cada nivel le gana al anterior (jugando de los dos lados, pocas partidas para que sea rápido).
	var pairs := [[2, 1, 6], [4, 2, 4]]
	for pair in pairs:
		var strong: int = pair[0]
		var weak: int = pair[1]
		var strong_wins := 0
		var weak_wins := 0
		for gi in int(pair[2]):
			var game := UltimateGame.new()
			var strong_seat := 1 if gi % 2 == 0 else 2
			while not game.is_over():
				var ai := UltimateAI.new()
				ai.load_state(game.cells, game.board_results, game.forced_board, game.current_player)
				var move := ai.choose(strong if game.current_player == strong_seat else weak)
				game.play(move.x, move.y)
			if game.result == strong_seat:
				strong_wins += 1
			elif game.result != UltimateGame.DRAW:
				weak_wins += 1
		check(strong_wins > weak_wins, "el nivel %d le gana al nivel %d (%d-%d)" % [strong, weak, strong_wins, weak_wins])
