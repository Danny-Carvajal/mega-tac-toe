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
	check(app.menu.color_x == Profile.DEFAULT_X, "X es rojo por defecto")
	check(app.menu.color_o == Profile.DEFAULT_O, "O es azul por defecto")

	# Servidor: cascada cerrada y Render por defecto
	check(not app.menu.server_panel.visible, "la cascada del servidor arranca cerrada")
	check(app.menu.url_edit.text == Profile.DEFAULT_SERVER_URL, "el servidor por defecto es Render")
	app.menu._toggle_server_panel()
	check(app.menu.server_panel.visible, "el botón abre la cascada")
	check(app.menu.handle_back(), "atrás cierra la cascada primero")
	check(not app.menu.server_panel.visible, "la cascada quedó cerrada")

	# Página de colores a la izquierda (flecha)
	var width: float = app.menu.pager.size.x
	check(app.menu.main_page.position.x == 0.0 and app.menu.colors_page.position.x == -width, "colores empieza fuera, a la izquierda")
	app.menu.set_colors_open(true, false)
	check(app.menu.colors_page.position.x == 0.0 and app.menu.main_page.position.x == width, "la flecha abre los colores")
	app.menu._select_mark("O")
	app.menu._set_selected_color(Color("22c55e"))
	check(app.menu.color_o == Color("22c55e") and app.menu.color_x == Profile.DEFAULT_X, "el atajo cambia solo el color elegido")
	check(app.menu.handle_back() and not app.menu.colors_open, "atrás vuelve a la página principal")
	await create_timer(0.5).timeout
	check(app.menu.main_page.position.x == 0.0, "la animación termina en la página principal")

	# Swipe hacia la derecha abre colores; hacia la izquierda los cierra
	await _swipe(Vector2(200, 900), Vector2(width * 0.8, 900))
	await create_timer(0.5).timeout
	check(app.menu.colors_open, "swipe a la derecha abre los colores")
	await _swipe(Vector2(width * 0.8, 1700), Vector2(100, 1700))
	await create_timer(0.5).timeout
	check(not app.menu.colors_open, "swipe a la izquierda vuelve")
	app.menu.color_o = Profile.DEFAULT_O

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
	# Servidor viejo (sin "rules") y errores del servidor: se avisa en pantalla
	check(online.status_label.text.begins_with("El servidor tiene otras reglas"), "un servidor con reglas viejas se avisa")
	online.show_notice("Jugada ilegal", 100000)
	check(online.status_label.text == "Jugada ilegal", "los errores del servidor se muestran")
	online._notice = ""
	online._refresh_status()
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


func _swipe(from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	root.push_input(press)
	for i in 6:
		var move := InputEventMouseMotion.new()
		move.position = from.lerp(to, (i + 1) / 6.0)
		root.push_input(move)
		await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	root.push_input(release)
	await process_frame


func check(condition: bool, name: String) -> void:
	if condition:
		print("  ok   %s" % name)
	else:
		failures += 1
		print("  FAIL %s" % name)
