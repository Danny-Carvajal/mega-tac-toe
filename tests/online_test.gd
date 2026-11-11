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

	# --- Se acaba el tiempo: salto de turno, y con 3 saltos se pierde ---
	# (el servidor corre con banco de 2s y repone 1s tras cada salto)
	a.client.send(qa)
	b.client.send(qb)
	await _next(a, "start")
	await _next(b, "start")
	var skip := await _next(a, "skip", 4.0)
	check(int(skip.get("player", 0)) == 1, "se le acaba el tiempo a X y le saltan el turno")
	check(int(skip.get("skips", [0, 0])[0]) == 1, "queda con 1 salto")
	var skip_b := await _next(b, "skip", 2.0)
	check(not skip_b.is_empty(), "el rival también se entera del salto")
	var lost := await _next(a, "over", 12.0)
	check(lost.get("reason") == "skips", "con 3 saltos por tiempo se pierde")
	check(lost.get("winner") == 2, "pierde el que acumuló los saltos (X)")
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

	# --- Perder la conexión y reanudar con el token ---
	a.client.send(qa)
	b.client.send(qb)
	var ga := await _next(a, "start")
	var gb := await _next(b, "start")
	var mover: Probe = a if ga.you == 1 else b
	var dropper: Probe = b if mover == a else a
	var dropper_start: Dictionary = gb if dropper == b else ga
	check(str(dropper_start.get("token", "")).length() > 10, "el start trae un token para reanudar")
	mover.client.send({"t": "move", "big": 4, "small": 2})
	await _next(mover, "move")
	await _next(dropper, "move")
	dropper.client.close()
	var gone := await _next(mover, "opponent")
	check(gone.get("connected") == false, "el rival se entera de que se cayó la conexión")
	var back := _probe("Beto", "#000000", "#000000")
	check(await _wait_open(back), "se vuelve a conectar")
	back.client.send({"t": "resume", "token": dropper_start.get("token", "")})
	var resumed := await _next(back, "resume_ok")
	var log: Array = resumed.get("log", [])
	check(log.size() >= 1 and int(log[0][0]) == 4 and int(log[0][1]) == 2, "reanudar devuelve las jugadas hechas")
	check(int(resumed.get("you", 0)) == int(dropper_start.get("you", -1)), "vuelve al mismo asiento")
	check((await _next(mover, "opponent")).get("connected") == true, "el rival se entera de que volvió")
	var stranger := _probe("Zeta", "#000000", "#000000")
	check(await _wait_open(stranger), "otro cliente conectado")
	stranger.client.send({"t": "resume", "token": "inventado"})
	check(not (await _next(stranger, "resume_failed")).is_empty(), "un token inventado no sirve")

	# Si no vuelve dentro de la gracia, pierde; al volver tarde se entera del resultado.
	back.client.close()
	check((await _next(mover, "opponent")).get("connected") == false, "se cae otra vez")
	var forfeit := await _next(mover, "over", 6.0)
	check(forfeit.get("reason") == "disconnect", "pasada la gracia gana el que se quedó")
	check(int(forfeit.get("winner", 0)) == int(ga.you if mover == a else gb.you), "gana el que no se desconectó")
	var late := _probe("Beto", "#000000", "#000000")
	check(await _wait_open(late), "vuelve tarde")
	late.client.send({"t": "resume", "token": dropper_start.get("token", "")})
	check((await _next(late, "over")).get("reason") == "disconnect", "al volver tarde se entera de cómo terminó")

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
