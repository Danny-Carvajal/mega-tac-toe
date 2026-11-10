extends SceneTree
## Smoke test de la pantalla: carga la escena, juega una jugada y revisa el estado.
##   godot --headless -s tests/ui_smoke.gd

var failures := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame  # deja que corra _ready()

	check(main.small_buttons.size() == 9, "se crean los 9 tableros grandes")
	check(main.small_buttons[0].size() == 9, "cada tablero tiene 9 casillas")

	main._on_small_pressed(4, 2)
	check(main.small_buttons[4][2].text == "X", "la casilla jugada muestra X")
	check(main.small_buttons[2][0].disabled == false, "el tablero forzado queda jugable")
	check(main.small_buttons[0][0].disabled == true, "los demás tableros se bloquean")
	check(main.status_label.text.begins_with("Turno de O"), "el estado muestra el turno de O")

	main._on_reset_pressed()
	check(main.small_buttons[4][2].text == "", "reiniciar limpia el tablero")

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
