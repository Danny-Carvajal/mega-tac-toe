extends SceneTree
## Punto de entrada del servidor:
##   godot --headless -s server/server_main.gd -- --port=9080 --initial=30000 --increment=5000


func _initialize() -> void:
	root.add_child(preload("res://server/game_server.gd").new())
