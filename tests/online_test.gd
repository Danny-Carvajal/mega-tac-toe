extends SceneTree
## Test de punta a punta con 2 clientes contra un servidor real.
## Lo corre tests/run_online_test.sh (levanta el servidor y lo apaga al final).

const NetClient := preload("res://scripts/net_client.gd")
const URL := "ws://127.0.0.1:9081"

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

	# --- Partida rápida: se emparejan, se sortean los turnos ---
	var qa := {"t": "queue", "name": "Ana", "colors": {"x": "#ff0000", "o": "#00ff00"}}
	var qb := {"t": "queue", "name": "Beto", "colors": {"x": "#0000ff", "o": "#ffff00"}}
	a.client.send(qa)
	check((await _next(a, "waiting")).has("t"), "el primero queda esperando")
	b.client.send(qb)
	var sa := await _next(a, "start")
	var sb := await _next(b, "start")
	check(not sa.is_empty() and not sb.is_empty(), "los dos reciben start")
	check(sa.you != sb.you, "cada uno tiene un asiento distinto")
	check(sa.colors == sb.colors, "los dos ven los mismos colores")
	var first: Probe = a if sa.you == 1 else b
	var second: Probe = b if first == a else a

	# --- Turnos y reglas las valida el servidor ---
	second.client.send({"t": "move", "big": 4, "small": 4})
	check((await _next(second, "error")).has("msg"), "mover fuera de turno da error")
	first.client.send({"t": "move", "big": 4, "small": 2})
	var m1 := await _next(first, "move")
	var m2 := await _next(second, "move")
	check(m1.big == 4 and m2.small == 2, "los dos reciben la jugada")
	second.client.send({"t": "move", "big": 5, "small": 0})
	check((await _next(second, "error")).has("msg"), "jugar fuera del tablero forzado da error")
	second.client.send({"t": "move", "big": 2, "small": 0})
	check((await _next(first, "move")).player == 2, "jugada legal del segundo llega al primero")

	# --- Rendirse ---
	first.client.send({"t": "resign"})
	var over := await _next(second, "over")
	check(over.get("reason") == "resign", "rendirse termina la partida")
	check(over.get("winner") == 2, "gana el que no se rindió (el primero tenía el asiento 1)")
	await _next(first, "over")

	# --- Se acaba el tiempo (el servidor corre con banco de 2s) ---
	a.client.send(qa)
	b.client.send(qb)
	await _next(a, "start")
	await _next(b, "start")
	var slow := await _next(a, "over", 5.0)
	check(slow.get("reason") == "timeout", "si nadie mueve, vence el reloj")
	check(slow.get("winner") == 2, "pierde el jugador al que le tocaba (X)")
	await _next(b, "over")

	# --- Sala privada con código ---
	b.client.send({"t": "join_room", "code": "ZZZZ"})
	check((await _next(b, "error")).has("msg"), "un código que no existe da error")
	a.client.send({"t": "create_room", "name": "Ana"})
	var room := await _next(a, "room")
	check(str(room.get("code", "")).length() == 4, "la sala devuelve un código de 4 letras")
	b.client.send({"t": "join_room", "name": "Beto", "code": str(room.get("code", "")).to_lower()})
	check(not (await _next(a, "start")).is_empty(), "al unirse con el código arranca la partida")
	await _next(b, "start")
	a.client.send({"t": "resign"})
	await _next(b, "over")

	if failures == 0:
		print("OK: test online pasó")
	else:
		print("FALLARON %d checks" % failures)
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
