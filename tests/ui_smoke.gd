extends SceneTree

const Pal := preload("res://scripts/pal.gd")
## Smoke test de las pantallas: menú, juego local y juego online simulado.
##   godot --headless --quit-after 600 -s tests/ui_smoke.gd

const GameScreen := preload("res://scripts/game_screen.gd")
const Profile := preload("res://scripts/profile.gd")
const IntroScreen := preload("res://scripts/intro_screen.gd")
const ShopScreen := preload("res://scripts/shop_screen.gd")
const Collection := preload("res://scripts/collection.gd")
const Cosmetics := preload("res://scripts/cosmetics.gd")
const FigureView := preload("res://scripts/figure_view.gd")
const BannerView := preload("res://scripts/banner_view.gd")

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

	# Buscando rival: el botón Cancelar tiene que estar habilitado y volver al estado normal
	app.menu.set_busy(true)
	check(app.menu.cancel_button.visible and not app.menu.cancel_button.disabled, "buscando rival: Cancelar está habilitado")
	app.menu.set_searching(true)
	await create_timer(0.5).timeout
	check(app.menu.search_box.visible and not app.menu.status_label.visible and app.menu.search_dots.text.length() >= 1, "buscando rival: puntitos y tiempo visibles")
	check(app.menu.search_timer.text.strip_edges().begins_with("0:0"), "buscando rival: el tiempo en cola corre")
	app.menu.cancel_button.pressed.emit()
	check(not app.menu.cancel_button.visible and not app.menu._action_buttons[0].disabled and not app.menu.search_box.visible, "Cancelar vuelve el menú a la normalidad")

	# Restore: el cliente arma lo que sabe de la partida
	var rgs := GameScreen.new()
	rgs.setup_online({"you": 1, "names": ["Ana", "Beto"], "colors": ["#ff0000", "#0000ff"], "sid": "s1", "clocks": [60000, 60000]}, Profile.new())
	root.add_child(rgs)
	await process_frame
	rgs.apply_move({"big": 4, "small": 4, "clocks": [60000, 60000]})
	var payload := rgs.restore_payload("tok")
	check(payload["t"] == "restore" and payload["sid"] == "s1" and payload["log"] == [[4, 4]] and payload["seat"] == 1 and payload["token"] == "tok", "restore_payload lleva sid, registro y token")
	rgs.free()

	# Historial y repetición
	var HistoryClass := preload("res://scripts/history.gd")
	var record := HistoryClass.make_record(["Ana", "Beto"], ["#e5484d", "#3b82f6"], 1, 1, "line", [[4, 4], [4, 0], [0, 4], "s", [4, 8]])
	var rp := GameScreen.new()
	rp.setup_replay(record)
	root.add_child(rp)
	await process_frame
	check(rp.replay_index == 0 and rp.game.get_cell(4, 4) == 0, "la repetición arranca en el inicio")
	rp._on_replay_button("next")
	check(rp.replay_index == 1 and rp.game.get_cell(4, 4) == 1, "paso adelante: aparece la primera jugada")
	check(rp.status_label.text.contains("e5"), "se muestra la notación de la jugada (e5)")
	rp._on_replay_button("end")
	check(rp.replay_index == 5 and rp.status_label.text.contains("Ganó Ana"), "al final dice quién ganó")
	rp._on_replay_button("back")
	check(rp.replay_index == 4 and rp.status_label.text.contains("Salto"), "paso atrás: se ve el salto de turno")
	rp._on_small_pressed(0, 0)
	check(rp.game.get_cell(0, 0) == 0, "en la repetición el tablero no se toca")
	rp._on_replay_button("start")
	rp._on_replay_button("play")
	check(rp.replay_playing and rp.replay_play_button.text == "Pausa", "Play reproduce en vivo")
	rp._set_replay_playing(false)
	rp.free()
	var hs := preload("res://scripts/history_screen.gd").new()
	hs.history = HistoryClass.new()
	hs.history.add(record)
	root.add_child(hs)
	await process_frame
	check(hs.get_child_count() > 0, "la lista de historial se arma")
	hs.free()

	# Apretar botones varias veces no cambia su tamaño (sin zoom)
	var zoom_screen := GameScreen.new()
	zoom_screen.setup_local(Profile.new())
	root.add_child(zoom_screen)
	await process_frame
	for _i in 6:
		zoom_screen.notes_button.button_down.emit()
		zoom_screen.notes_button.button_up.emit()
	await create_timer(0.4).timeout
	check(zoom_screen.notes_button.scale == Vector2.ONE, "el botón de apuntes no hace zoom al apretarlo")
	zoom_screen.free()

	# Modo claro desde el pop up de ajustes
	app.menu.theme_button.pressed.emit()
	await create_timer(0.5).timeout
	check(app.profile.light_mode and Pal.light and app.menu.server_panel.visible, "modo claro: cambia la paleta y reabre ajustes")
	check(app.menu.theme_button.text == "Modo claro: sí", "el botón de tema refleja el estado")
	app.menu.theme_button.pressed.emit()
	await create_timer(0.5).timeout
	check(not app.profile.light_mode and not Pal.light, "modo claro: se puede volver a oscuro")
	app.menu.server_panel.visible = false

	# Estadísticas: nav, registro de resultados
	app.menu.apply_layout(false)
	app.menu.set_page(2, false)
	await process_frame
	check(app.menu.page == 2 and app.menu.stats_page.position.x == 0.0, "la pestaña de estadísticas abre la página 2")
	app.menu.set_page(1, false)
	app.stats.reset()
	app.stats.record("W")
	app.stats.record("W")
	app.stats.record("L")
	check(app.stats.total() == 3 and app.stats.streak == -1 and app.stats.best_streak == 2, "stats cuenta victorias, derrotas y rachas")
	check(is_equal_approx(app.stats.win_rate(), 66.6666667) or int(round(app.stats.win_rate())) == 67, "stats calcula el porcentaje")
	app.stats.reset()

	# Layout ancho (compu): las dos páginas lado a lado, sin barra de abajo
	app.menu.apply_layout(true)
	await process_frame
	check(not app.menu.nav.visible, "en compu no hay barra de pestañas")
	check(app.menu.main_page.position.x == 0.0 and app.menu.colors_page.position.x < 0.0 and app.menu.stats_page.position.x > 0.0, "en compu se ve una sola página, las otras a los costados")
	check(app.menu._edges[0].visible and app.menu._edges[1].visible and app.menu._edges[0].label == "Colores" and app.menu._edges[1].label == "Estadísticas", "en compu hay zonas de hover a los costados")
	app.menu.edge_tick(0.1, Vector2(1850, 500))
	check(app.menu._edges[1].progress > 0.0 and app.menu._edges[0].progress == 0.0, "el mouse encima resalta el botón del costado")
	check(app.menu.page == 1, "el hover solo resalta, no cambia de pantalla")
	_click_at(app, Vector2(1850, 500))
	await create_timer(0.5).timeout
	check(app.menu.page == 2 and app.menu.stats_page.position.x == 0.0 and not app.menu._edges[1].visible, "clic en el costado derecho abre estadísticas")
	_click_at(app, Vector2(40, 500))
	await create_timer(0.4).timeout
	check(app.menu.page == 1, "clic en el costado izquierdo vuelve al menú")
	_click_at(app, Vector2(1850, 40))
	check(app.menu.page == 1, "la esquina de arriba (engranaje) no cambia de pantalla")
	check(not app.menu.private_box.visible, "las opciones de sala privada están ocultas al inicio")
	app.menu._set_private_open(true)
	check(app.menu.private_box.visible, "Privado muestra crear sala y código")
	app.menu._set_private_open(false)
	check(app.menu.colors_page.position.x + app.menu.colors_page.size.x * app.menu.colors_page.scale.x <= app.menu.pager.size.x + 1.0, "la página de colores cabe en pantalla")
	app.menu.apply_layout(false)
	await process_frame
	check(app.menu.nav.visible and app.menu.colors_page.position.x == -width, "al volver a vertical vuelve la barra y las páginas con swipe")

	# --- Práctica contra la IA ---
	check(app.menu.practice_button != null and not app.menu.practice_box.visible, "hay botón de práctica y los niveles arrancan ocultos")
	app.menu._set_practice_open(true)
	check(app.menu.practice_box.visible and not app.menu.private_box.visible, "Práctica muestra los 5 niveles y cierra Privado")
	check(app.menu.practice_box.get_child_count() == 5, "hay 5 niveles de IA")
	app.menu.practice_box.get_child(2).pressed.emit()
	await process_frame
	check(app.game_screen != null and app.game_screen.vs_ai and app.game_screen.ai_level == 3, "tocar el nivel 3 abre la práctica contra la IA nivel 3")
	app.show_menu()
	await process_frame
	var practice := GameScreen.new()
	var practice_profile := Profile.new()
	practice_profile.player_name = "Danny"
	practice.setup_practice(practice_profile, 1)
	root.add_child(practice)
	await process_frame
	check(practice.status_label.text.begins_with("Tu turno"), "práctica: empieza la persona (X)")
	practice._on_small_pressed(4, 4)
	check(practice.cell_text(4, 4) == "X" and practice.game.current_player == 2, "práctica: mi jugada se dibuja y le toca a la IA")
	check(practice.status_label.text.contains("pensando"), "práctica: se avisa que la IA piensa")
	practice._on_small_pressed(4, 0)
	check(practice.cell_text(4, 0) == "", "práctica: no puedo jugar mientras la IA piensa")
	await create_timer(1.2).timeout
	check(practice.game.cells.count(2) == 1 and practice.game.current_player == 1, "práctica: la IA contestó con una jugada")
	check(practice.status_label.text.begins_with("Tu turno"), "práctica: vuelve mi turno")
	practice._on_new_game_pressed()
	check(practice.game.cells.count(0) == 81 and not practice._ai_busy, "práctica: nueva partida limpia el tablero")
	practice.queue_free()
	await process_frame

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
	local.apply_layout(true)
	check(local.turn_banner.get_parent() == local.side_box and local.buttons_row.vertical, "en compu el estado y los botones van a la derecha")
	local.apply_layout(false)
	check(local.turn_banner.get_parent() == local.root_box and not local.buttons_row.vertical, "en vertical todo vuelve a la columna")
	local._on_small_pressed(4, 2)
	check(local.cell_text(4, 2) == "X", "la casilla jugada muestra X")
	check(not local.small_buttons[2][0].disabled, "el tablero forzado queda jugable")
	check(local.small_buttons[0][0].disabled, "los demás tableros se bloquean")
	check(local.status_label.text.begins_with("Turno de O"), "turno de O")
	local._on_new_game_pressed()
	check(local.cell_text(4, 2) == "", "nueva partida limpia el tablero")
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
	check(won.result_figs[0].visible, "el tablero ganado muestra su marca grande")
	check(won.result_figs[0].color.a < 0.5, "la marca grande es translúcida")
	check(not won.small_buttons[0][5].disabled, "las casillas libres del tablero ganado se pueden jugar")
	check(won.small_buttons[0][0].disabled, "las ocupadas no")
	won.queue_free()

	# --- Resaltado de la última jugada, apuntes con flechas y confirmación de rendirse ---
	var fx := GameScreen.new()
	fx.setup_local(Profile.new())
	root.add_child(fx)
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	fx._on_small_pressed(4, 2)
	check(fx._highlighted == Vector2i(4, 2), "se resalta la última jugada")
	fx._on_small_pressed(2, 5)
	check(fx._highlighted == Vector2i(2, 5), "el resaltado sigue a la última jugada")
	var grid_before: Vector2 = fx.big_grid.size
	fx.notes_button.button_pressed = true
	await process_frame
	await process_frame
	check(fx.big_grid.size == grid_before, "activar apuntes no cambia el tamaño del tablero")
	check(fx.notes_mode and fx.clear_notes_button.visible, "el toggle de apuntes activa el modo y muestra Borrar")
	fx._toggle_arrow(Vector2i(0, 0), Vector2i(4, 4))
	check(fx.arrows.size() == 1, "se agrega una flecha")
	fx._toggle_arrow(Vector2i(0, 0), Vector2i(4, 4))
	check(fx.arrows.is_empty(), "dibujar la misma flecha otra vez la borra")
	var from_point: Vector2 = fx._cell_center(Vector2i(0, 0))
	var to_point: Vector2 = fx._cell_center(Vector2i(8, 8))
	await _drag(from_point, to_point)
	check(fx.arrows.size() == 1 and fx.arrows[0]["from"] == Vector2i(0, 0) and fx.arrows[0]["to"] == Vector2i(8, 8), "arrastrar dibuja una flecha")
	var middle := (from_point + to_point) / 2.0
	await _drag(middle, middle)
	check(fx.arrows.is_empty(), "tocar una flecha la borra")
	fx._toggle_arrow(Vector2i(1, 1), Vector2i(2, 2))
	fx.clear_notes_button.pressed.emit()
	check(fx.arrows.is_empty(), "Borrar limpia todas las flechas")
	fx.queue_free()

	var start2 := {
		"t": "start", "you": 2, "names": ["Ana", "Beto"], "rules": 2,
		"colors": ["#e5484d", "#3b82f6"], "clocks": [60000, 60000],
	}
	var online2 := GameScreen.new()
	online2.setup_online(start2, Profile.new())
	root.add_child(online2)
	await process_frame
	var resigned: Array = []
	online2.resign_requested.connect(func() -> void: resigned.append(1))
	online2.left_button.pressed.emit()
	check(online2.confirm_layer.visible and resigned.is_empty(), "rendirse pide confirmación")
	online2._confirm_resign()
	check(resigned.size() == 1 and not online2.confirm_layer.visible, "confirmar rinde y cierra el diálogo")
	online2.apply_move({"big": 4, "small": 2, "clocks": [60000, 60000]})
	check(online2._highlighted == Vector2i(4, 2), "online: se resalta la jugada del rival")
	online2.apply_move({"big": 2, "small": 5, "clocks": [60000, 60000]})
	check(online2._highlighted == Vector2i(-1, -1), "online: mi propia jugada no se resalta")
	online2.queue_free()

	# --- Reconexión: se cae el socket en plena partida y se reanuda con el token ---
	var app2: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(app2)
	await process_frame
	app2.profile.server_url = "ws://127.0.0.1:1"
	app2._on_net_message({"t": "start", "you": 2, "token": "tok123", "names": ["Ana", "Beto"],
		"colors": ["#e5484d", "#3b82f6"], "clocks": [60000, 60000], "rules": 2})
	await process_frame
	check(app2.game_screen != null and app2._token == "tok123", "start guarda el token")
	app2._on_net_disconnected()
	check(app2._reconnecting and app2.game_screen.status_label.text == "Reconectando...", "si se cae la conexión en plena partida se muestra Reconectando")
	check(not app2.game_screen.finished, "la partida no se da por terminada mientras se reconecta")
	app2._on_net_message({"t": "opponent", "connected": false, "grace_ms": 60000})
	check(app2.game_screen.status_label.text.begins_with("El rival perdió la conexión"), "se avisa si el rival se cayó")
	app2._on_net_message({"t": "resume_ok", "you": 2, "names": ["Ana", "Beto"], "colors": ["#e5484d", "#3b82f6"],
		"clocks": [50000, 40000], "skips": [0, 1], "opponent_connected": true,
		"log": [[4, 2], [2, 5], "s"]})
	var rg: Control = app2.game_screen
	check(not app2._reconnecting and not rg.finished, "al reanudar termina la reconexión")
	check(rg.game.get_cell(4, 2) == UltimateGame.X and rg.game.get_cell(2, 5) == UltimateGame.NONE, "las jugadas se reconstruyen (y el salto deshace la última)")
	check(rg.game.current_player == UltimateGame.O and rg.skips[2] == 1, "turno y saltos quedan como en el servidor")
	check(not rg.status_label.text.begins_with("Reconectando") and not rg.status_label.text.begins_with("El rival perdió"), "los avisos desaparecen al reanudar")
	app2._on_net_disconnected()
	app2._on_net_message({"t": "resume_failed"})
	check(rg.finished and rg.status_label.text == "Se cayó la conexión", "si la partida ya no existe, termina")
	app2.queue_free()

	# --- Tienda y cosméticos ---
	var shop_collection := Collection.new()
	shop_collection.path = "user://test_collection.json"
	shop_collection.coins = 650
	var shop := ShopScreen.new()
	shop.collection = shop_collection
	shop.profile = Profile.new()
	root.add_child(shop)
	await process_frame
	check(shop.coins_label.text == "650 monedas" and not shop.box_button.disabled, "la tienda muestra las monedas y deja abrir caja")
	check(shop.grid.get_child_count() == 10, "la pestaña de figuras de X lista las 10 figuras")
	shop._select_tab("banner")
	await process_frame
	check(shop.grid.get_child_count() == 13, "la pestaña de banners lista los 13 banners")
	shop._select_tab("font")
	await process_frame
	check(shop.grid.get_child_count() == 9, "la pestaña de fuentes lista las 9 fuentes")
	shop._on_box_pressed()
	await process_frame
	check(shop.overlay.visible and shop_collection.boxes_opened == 1 and shop_collection.coins >= 350, "abrir la caja muestra la animación y cobra")
	await create_timer(1.2).timeout
	check(shop.overlay.get_child_count() >= 2, "la caja se abre y muestra lo que salió")
	shop._close_overlay()
	check(not shop.overlay.visible, "se cierra el cartel de la caja")
	shop_collection.coins = 100
	shop._refresh()
	check(shop.box_button.disabled, "sin monedas no se puede abrir otra caja")
	shop_collection.owned["heart"] = true
	shop._select_tab("fx")
	shop._on_tile_pressed("heart")
	check(shop_collection.equipped["fx"] == "heart", "tocar una figura que tenés la equipa")
	shop._on_tile_pressed("bolt")
	check(shop_collection.equipped["fx"] == "heart", "tocar una bloqueada no hace nada")
	shop.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_collection.json"))
	# Todas las figuras y banners se dibujan sin errores
	var drawing_holder := Control.new()
	root.add_child(drawing_holder)
	for entry in Cosmetics.items_of_kind("fx") + Cosmetics.items_of_kind("fo"):
		var figure := FigureView.new()
		figure.custom_minimum_size = Vector2(120, 120)
		figure.size = Vector2(120, 120)
		figure.set_figure(entry["id"], Color.WHITE)
		drawing_holder.add_child(figure)
	for entry in Cosmetics.items_of_kind("banner"):
		var banner := BannerView.new()
		banner.size = Vector2(600, 200)
		banner.set_banner(entry["id"])
		drawing_holder.add_child(banner)
	await process_frame
	await process_frame
	check(drawing_holder.get_child_count() == 33, "se dibujan las 20 figuras y los 13 banners")
	drawing_holder.queue_free()
	# Figura elegida en el tablero (local): la X usa mi figura de X
	var cos_local := GameScreen.new()
	cos_local.setup_local(Profile.new(), {"fx": "star", "fo": "moon", "b": "banner_classic", "n": "font_classic"})
	root.add_child(cos_local)
	await process_frame
	cos_local._on_small_pressed(4, 4)
	check(cos_local._mark_figure(1) == "star" and cos_local._mark_figure(2) == "moon", "el tablero dibuja con las figuras elegidas")
	cos_local._on_small_pressed(4, 0)
	check(cos_local.cell_text(4, 4) == "X" and cos_local.cell_text(4, 0) == "O", "las marcas con figura se siguen leyendo como X y O")
	cos_local.queue_free()
	# Online: cada uno ve la figura del rival según su lado
	var cos_start := {"t": "start", "you": 1, "names": ["Ana", "Beto"], "colors": ["#e5484d", "#3b82f6"], "clocks": [30000, 30000], "rules": 2,
			"cosmetics": [{"fx": "heart", "fo": "sun", "b": "banner_gold", "n": "font_fire"}, {"fx": "bolt", "fo": "target", "b": "hack!", "n": "font_ice"}]}
	var cos_online := GameScreen.new()
	cos_online.setup_online(cos_start, Profile.new())
	check(cos_online._mark_figure(1) == "heart" and cos_online._mark_figure(2) == "target", "online: la X usa la figura de X de Ana y la O la figura de O de Beto")
	check(cos_online.seat_cos[2]["b"] == "banner_classic", "online: un banner raro del rival vuelve al de inicio")
	cos_online.free()

	# --- Presentación online: VS + moneda ---
	var intro_start := {"t": "start", "you": 2, "names": ["Ana", "Beto"], "colors": ["#e5484d", "#3b82f6"],
			"clocks": [30000, 30000], "intro_ms": 900, "rules": 2}
	var intro_game := GameScreen.new()
	intro_game.setup_online(intro_start, Profile.new())
	root.add_child(intro_game)
	await process_frame
	check(intro_game.intro_layer != null and intro_game._intro_active(), "online: arranca con la presentación VS")
	check(intro_game.intro_layer.cards.size() == 2 and intro_game.intro_layer.my_name == "Beto" and intro_game.intro_layer.opponent_name == "Ana", "el VS muestra a los dos jugadores (yo y el rival)")
	var intro_sent: Array = []
	intro_game.move_requested.connect(func(big: int, small: int) -> void: intro_sent.append([big, small]))
	intro_game.apply_move({"big": 4, "small": 4, "player": 1, "clocks": [30000, 30000]})
	intro_game._on_small_pressed(4, 0)
	check(intro_sent.is_empty(), "durante la presentación no se puede jugar")
	await create_timer(0.5).timeout
	check(intro_game.intro_layer.coin.modulate.a > 0.0, "la moneda aparece después del VS")
	await create_timer(0.7).timeout
	check(intro_game.intro_layer == null, "la presentación termina sola")
	check(intro_game.intro_layer == null and not intro_game._intro_active(), "después de la presentación se puede jugar")
	intro_game._on_small_pressed(4, 0)
	check(intro_sent == [[4, 0]], "terminada la presentación, mi jugada se pide al servidor")
	intro_game.queue_free()
	# La moneda siempre cae en la marca que le tocó a este jugador
	for seat in [1, 2]:
		var intro := IntroScreen.new()
		intro.my_seat = seat
		intro.duration_ms = 400
		root.add_child(intro)
		await create_timer(0.6).timeout
		check(intro.coin.face == seat, "la moneda cae en %s cuando me toca %s" % ["X" if seat == 1 else "O", "X" if seat == 1 else "O"])
		intro.queue_free()
	await process_frame

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
	check(online.cell_text(4, 4) == "X", "la jugada del servidor se dibuja")
	check(online.status_label.text.begins_with("Tu turno"), "ahora es mi turno")
	online._on_small_pressed(4, 0)
	check(sent == [[4, 0]], "mi jugada se pide al servidor")
	check(online.cell_text(4, 0) == "", "no se dibuja hasta que el servidor confirme")
	check(online.clock_labels[1].text.contains("0:35"), "el reloj de Ana muestra el banco con incremento")
	# El servidor confirma mi jugada; después a Ana (X) se le acaba el tiempo.
	online.apply_move({"big": 4, "small": 0, "player": 2, "clocks": [35000, 35000]})
	check(online.game.current_player == 1, "tras mi jugada le toca a Ana")
	online.apply_skip({"player": 1, "skips": [1, 0], "clocks": [10000, 35000]})
	check(online.game.current_player == 2, "si le saltan el turno a Ana, me toca a mí")
	check(online.cell_text(4, 0) == "", "mi última jugada se deshace para volver a elegirla")
	check(online.clock_labels[1].text.contains("Saltos 1/3"), "se muestra el contador de saltos")
	online.apply_over({"winner": 2, "reason": "skips", "clocks": [1000, 20000]})
	check(online.status_label.text.begins_with("Ganaste"), "mensaje de victoria")
	check(online.result_layer.visible and online._result_title == "¡GANASTE!", "al ganar sale el cartel grande")
	check(not online.confirm_layer.visible, "al terminar se cierra la confirmación de rendirse")
	online._on_small_pressed(0, 0)
	check(online.game.get_cell(0, 0) == 0, "con la partida terminada tocar el tablero no hace nada")
	online.notes_button.button_pressed = true
	var arrows_before: int = online.arrows.size()
	var ev_down := InputEventMouseButton.new()
	ev_down.button_index = MOUSE_BUTTON_LEFT
	ev_down.pressed = true
	ev_down.position = online.big_grid.get_global_rect().get_center()
	online._input(ev_down)
	check(online._drag_from.x < 0, "con el cartel de fin puesto, los apuntes no capturan el mouse")
	online.notes_button.button_pressed = false
	online._dismiss_result_overlay()
	check(not online.result_layer.visible and not online.notes_button.disabled, "Ver tablero cierra el cartel y los apuntes andan normal")
	check(online.left_button.text == "Volver al menú", "al terminar se puede volver al menú")
	online.queue_free()

	if failures == 0:
		print("OK: smoke test de UI pasó")
	else:
		print("FALLARON %d checks" % failures)
	quit(1 if failures > 0 else 0)


func _drag(from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	root.push_input(press, true)
	var move := InputEventMouseMotion.new()
	move.position = to
	root.push_input(move, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	root.push_input(release, true)
	await process_frame


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


func _click_at(app: Control, point: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = point
	app.menu._input(ev)
