extends SceneTree
## Smoke test de las pantallas: menú, juego local y juego online simulado.
##   godot --headless --quit-after 600 -s tests/ui_smoke.gd

const GameScreen := preload("res://scripts/game_screen.gd")
const Profile := preload("res://scripts/profile.gd")

var failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	# --- La app arranca en el menú ---
	var app: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	check(app.menu != null and app.current == app.menu, "la app arranca en el menú")
	check(app.menu.color_x_button.color == Profile.DEFAULT_X, "X es rojo por defecto")
	check(app.menu.color_o_button.color == Profile.DEFAULT_O, "O es azul por defecto")

	app.menu.local_requested.emit()
	await process_frame
	check(app.game_screen != null, "jugar local abre la pantalla de juego")
	app.game_screen.exit_requested.emit()
	await process_frame
	check(app.game_screen == null and app.current == app.menu, "volver al menú")
	app.queue_free()

	# --- Juego local ---
	var local := GameScreen.new()
	local.setup_local(Profile.new())
	root.add_child(local)
	await process_frame
	check(local.small_buttons.size() == 9 and local.small_buttons[0].size() == 9, "9 tableros de 9 casillas")
	local._on_small_pressed(4, 2)
	check(local.small_buttons[4][2].text == "X", "la casilla jugada muestra X")
	check(not local.small_buttons[2][0].disabled, "el tablero forzado queda jugable")
	check(local.small_buttons[0][0].disabled, "los demás tableros se bloquean")
	check(local.status_label.text.begins_with("Turno de O"), "turno de O")
	local._on_new_game_pressed()
	check(local.small_buttons[4][2].text == "", "nueva partida limpia el tablero")
	local.queue_free()

	# --- Un tablero ganado sigue jugable y su marca es translúcida ---
	var won := GameScreen.new()
	won.setup_local(Profile.new())
	root.add_child(won)
	await process_frame
	won.game.cells[0] = 1
	won.game.cells[1] = 1
	won.game.play(0, 2)
	won.game.forced_board = -1
	won._refresh()
	check(won.result_labels[0].visible, "el tablero ganado muestra su marca grande")
	check(won.result_labels[0].get_theme_color("font_color").a < 0.5, "la marca grande es translúcida")
	check(not won.small_buttons[0][5].disabled, "las casillas libres del tablero ganado se pueden jugar")
	check(won.small_buttons[0][0].disabled, "las ocupadas no")
	won.queue_free()

	# --- Juego online (mensajes del servidor simulados) ---
	var start := {
		"t": "start", "you": 2, "names": ["Ana", "Beto"],
		"colors": ["#e5484d", "#e5484d"],  # mismo color: debe resolverse el choque
		"clocks": [30000, 30000],
	}
	var online := GameScreen.new()
	online.setup_online(start, Profile.new())
	root.add_child(online)
	await process_frame
	var sent: Array = []
	online.move_requested.connect(func(big: int, small: int) -> void: sent.append([big, small]))
	check(online.colors[1] != online.colors[2], "colores iguales: el rival se ve con otro color")
	check(online.status_label.text.begins_with("Turno de Ana"), "arranca X (Ana) y yo soy O")
	online._on_small_pressed(4, 4)
	check(sent.is_empty(), "no puedo jugar fuera de mi turno")
	online.apply_move({"big": 4, "small": 4, "player": 1, "clocks": [35000, 30000]})
	check(online.small_buttons[4][4].text == "X", "la jugada del servidor se dibuja")
	check(online.status_label.text.begins_with("Tu turno"), "ahora es mi turno")
	online._on_small_pressed(4, 0)
	check(sent == [[4, 0]], "mi jugada se pide al servidor")
	check(online.small_buttons[4][0].text == "", "no se dibuja hasta que el servidor confirme")
	check(online.clock_labels[1].text.contains("0:35"), "el reloj de Ana muestra el banco con incremento")
	# El servidor confirma mi jugada; después a Ana (X) se le acaba el tiempo.
	online.apply_move({"big": 4, "small": 0, "player": 2, "clocks": [35000, 35000]})
	check(online.game.current_player == 1, "tras mi jugada le toca a Ana")
	online.apply_skip({"player": 1, "skips": [1, 0], "clocks": [10000, 35000]})
	check(online.game.current_player == 2, "si le saltan el turno a Ana, me toca a mí")
	check(online.small_buttons[4][0].text == "", "mi última jugada se deshace para volver a elegirla")
	check(online.clock_labels[1].text.contains("Saltos 1/3"), "se muestra el contador de saltos")
	online.apply_over({"winner": 2, "reason": "skips", "clocks": [1000, 20000]})
	check(online.status_label.text.begins_with("Ganaste"), "mensaje de victoria")
	check(online.left_button.text == "Volver al menú", "al terminar se puede volver al menú")
	online.queue_free()

	if failures == 0:
		print("OK: smoke test de UI pasó")
	else:
		print("FALLARON %d checks" % failures)
	quit(1 if failures > 0 else 0)


func check(condition: bool, name: String) -> void:
	if condition:
		print("  ok   %s" % name)
	else:
		failures += 1
		print("  FAIL %s" % name)
