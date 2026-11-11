extends SceneTree
## Presentación (VS + moneda): el servidor no acepta jugadas hasta que termina.
## Lo corre tests/run_online_test.sh con un servidor aparte que usa --intro=1500.

const NetClient := preload("res://scripts/net_client.gd")
const URL := "ws://127.0.0.1:9082"

var failures := 0


class Probe:
	extends RefCounted
	var client: Node
	var inbox: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var a := _probe("Ana", "#ff0000", "#00ff00")
	var b := _probe("Beto", "#0000ff", "#ffff00")
	for p in [a, b]:
		check(await _wait_open(p), "cliente conectado")
	a.client.send({"t": "queue", "name": "Ana", "colors": {"x": "#ff0000", "o": "#00ff00"}})
	await _next(a, "waiting")
	b.client.send({"t": "queue", "name": "Beto", "colors": {"x": "#0000ff", "o": "#ffff00"}})
	var sa := await _next(a, "start")
	var sb := await _next(b, "start")
	check(sa.get("intro_ms") == 1500 and sb.get("intro_ms") == 1500, "el servidor avisa cuánto dura la presentación")
	check(sa.get("clocks") == [sa.get("clocks")[0], sa.get("clocks")[0]], "los relojes arrancan iguales (el de X no corre en la presentación)")
	var first: Probe = a if sa.you == 1 else b
	first.client.send({"t": "move", "big": 4, "small": 4})
	check((await _next(first, "error")).get("msg", "").begins_with("Todavía no empieza"), "durante la presentación el servidor rechaza jugadas")
	await create_timer(1.6).timeout
	first.client.send({"t": "move", "big": 4, "small": 4})
	check((await _next(first, "move")).get("big") == 4, "terminada la presentación la jugada pasa")
	if failures == 0:
		print("OK: test de presentación pasó")
	else:
		print("FALLARON %d tests" % failures)
	quit(1 if failures > 0 else 0)


func _probe(_name: String, _cx: String, _co: String) -> Probe:
	var p := Probe.new()
	p.client = NetClient.new()
	root.add_child(p.client)
	p.client.message.connect(func(data: Dictionary) -> void: p.inbox.append(data))
	p.client.connect_to_server(URL)
	return p


func _wait_open(p: Probe, timeout := 3.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < deadline:
		if p.client.is_open():
			return true
		await process_frame
	return false


func _next(p: Probe, type: String, timeout := 3.0) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < deadline:
		while not p.inbox.is_empty():
			var msg: Dictionary = p.inbox.pop_front()
			if msg.get("t") == type:
				return msg
		await process_frame
	print("  (timeout esperando '%s')" % type)
	return {}


func check(condition: bool, name: String) -> void:
	if condition:
		print("  ok   %s" % name)
	else:
		failures += 1
		print("  FAIL %s" % name)
