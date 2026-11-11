extends Node
## Servidor autoritativo de Mega Tac Toe. Habla JSON por WebSocket (sin TLS: en
## producción va detrás de un proxy que ponga wss://). Reutiliza la misma lógica
## de juego y el mismo reloj que el cliente, así hay una sola fuente de verdad.
##
## Mensajes cliente -> servidor:
##   {t:"queue", name, colors:{x,o}}        partida rápida
##   {t:"create_room", name, colors}        sala privada (responde {t:"room", code})
##   {t:"join_room", code, name, colors}
##   {t:"move", big, small}
##   {t:"resign"}
##   {t:"leave"}                            salir de la cola/sala de espera
##   {t:"restore", sid, token, seat, names, colors, log, skips, clocks}  devolver una partida que el servidor perdió al reiniciarse
##   {t:"resume", token}                   volver a una partida en curso tras perder la conexión
## Mensajes servidor -> cliente:
##   {t:"waiting"}, {t:"room", code}
##   {t:"start", you, token, names, colors, initial_ms, increment_ms, clocks}
##   {t:"move", big, small, player, clocks}
##   {t:"skip", player, skips:[x,o], clocks}   se le acabó el tiempo: le saltan el turno y
##       el rival deshace su última jugada y la vuelve a elegir (UltimateGame.skip_turn)
##   {t:"over", winner (0 = empate), reason, clocks}
##       reason: line | draw | skips (3 saltos) | resign | disconnect
##   {t:"error", msg}
##   {t:"resume_ok", you, names, colors, clocks, skips, log, ...}  estado completo para reanudar;
##       `log` son las jugadas [big,small] y "s" por cada salto, en orden
##   {t:"restore_wait"}                     falta que el rival también devuelva la partida
##   {t:"resume_failed"}                    esa partida ya no existe
##   {t:"opponent", connected, grace_ms}    el rival perdió / recuperó la conexión

const UltimateGame := preload("res://scripts/ultimate_game.gd")
const TurnClock := preload("res://scripts/turn_clock.gd")

const ROOM_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const DEFAULT_COLORS := {"x": "#e5484d", "o": "#3b82f6"}

const MAX_SKIPS := 3
## Si no llega ningún mensaje en este tiempo, la conexión se da por muerta (el cliente manda ping cada 25 s).
const IDLE_MS := 70000
## Cuánto se guarda el resultado de una partida para quien estaba desconectado.
const RESULT_KEEP_MS := 300000

var port := 9080
var initial_ms := 300000
var increment_ms := 45000
## Banco que se le repone a quien se pasó de tiempo y le saltaron el turno.
var skip_refill_ms := 90000
## Tiempo que se espera a que un jugador desconectado vuelva antes de darle la derrota.
var grace_ms := 60000

var _tcp := TCPServer.new()
var _conns: Array[Conn] = []
var _queue: Array[Conn] = []
var _rooms := {}  # código -> Conn que espera
var _finished := {}  # token -> {msg, until}: resultado para quien no estaba conectado al terminar
var _sessions: Array[Session] = []
var _restoring := {}  # sid -> {seats: {1: {conn, msg}, 2: ...}, since}
var _rng := RandomNumberGenerator.new()
var _color_regex := RegEx.create_from_string("^#[0-9a-fA-F]{6}$")


class Conn:
	extends RefCounted
	var ws: WebSocketPeer
	var player_name := "Jugador"
	var colors := DEFAULT_COLORS.duplicate()
	var session: Session = null
	var seat := 0
	var last_seen_ms := 0


class Session:
	extends RefCounted
	var game := UltimateGame.new()
	var clock: TurnClock
	var seats: Array = [null, null, null]  # índice 1 y 2
	var skips: Array = [0, 0, 0]
	var over := false
	var tokens: Array = ["", "", ""]
	var sid := ""
	var names: Array = []
	var colors: Array = []
	## Jugadas en orden: [big, small] o "s" (salto). Sirve para reconstruir la partida al reanudar.
	var log: Array = []
	## Desde cuándo está desconectado cada asiento (0 = conectado).
	var gone_since: Array = [0, 0, 0]


func _ready() -> void:
	_rng.randomize()
	# Render (y otros) le pasan el puerto por variable de entorno.
	var env_port := OS.get_environment("PORT")
	if not env_port.is_empty():
		port = int(env_port)
	_parse_args()
	var err := _tcp.listen(port)
	if err != OK:
		push_error("No pude abrir el puerto %d (error %d)" % [port, err])
		get_tree().quit(1)
		return
	print("Mega Tac Toe server escuchando en el puerto %d (banco %dms, +%dms)" % [port, initial_ms, increment_ms])


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--initial="):
			initial_ms = int(arg.get_slice("=", 1))
		elif arg.begins_with("--increment="):
			increment_ms = int(arg.get_slice("=", 1))
		elif arg.begins_with("--skip_refill="):
			skip_refill_ms = int(arg.get_slice("=", 1))
		elif arg.begins_with("--grace="):
			grace_ms = int(arg.get_slice("=", 1))


func _process(_delta: float) -> void:
	while _tcp.is_connection_available():
		var conn := Conn.new()
		conn.ws = WebSocketPeer.new()
		conn.ws.accept_stream(_tcp.take_connection())
		conn.last_seen_ms = Time.get_ticks_msec()
		_conns.append(conn)

	for conn in _conns.duplicate():
		conn.ws.poll()
		match conn.ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while conn.ws.get_available_packet_count() > 0:
					_on_message(conn, conn.ws.get_packet().get_string_from_utf8())
			WebSocketPeer.STATE_CLOSED:
				_drop(conn)

	var now := Time.get_ticks_msec()
	# Conexiones que dejaron de contestar (por ejemplo, un cel que se durmió sin cerrar el socket).
	for conn in _conns.duplicate():
		if now - conn.last_seen_ms > IDLE_MS:
			conn.ws.close()
			_drop(conn)
	for session in _sessions.duplicate():
		if session.over:
			continue
		for seat in [1, 2]:
			if session.gone_since[seat] > 0 and now - session.gone_since[seat] >= grace_ms:
				_finish(session, 3 - seat, "disconnect")
				break
		if not session.over and session.clock.is_expired(now):
			_handle_timeout(session, now)
	for sid in _restoring.keys():
		if now - int(_restoring[sid]["since"]) > grace_ms * 2:
			_restoring.erase(sid)
	for token in _finished.keys():
		if now > int(_finished[token]["until"]):
			_finished.erase(token)


# --- Mensajes -------------------------------------------------------------

func _on_message(conn: Conn, text: String) -> void:
	conn.last_seen_ms = Time.get_ticks_msec()
	var msg = JSON.parse_string(text)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	match str(msg.get("t", "")):
		"queue":
			_read_profile(conn, msg)
			_enqueue(conn)
		"create_room":
			_read_profile(conn, msg)
			_create_room(conn)
		"join_room":
			_read_profile(conn, msg)
			_join_room(conn, str(msg.get("code", "")).to_upper())
		"move":
			_on_move(conn, int(msg.get("big", -1)), int(msg.get("small", -1)))
		"resign":
			if conn.session != null and not conn.session.over:
				_finish(conn.session, 3 - conn.seat, "resign")
		"leave":
			_leave_waiting(conn)
		"resume":
			_resume(conn, str(msg.get("token", "")))
		"restore":
			_restore(conn, msg)
		"ping":
			_send(conn, {"t": "pong"})


func _read_profile(conn: Conn, msg: Dictionary) -> void:
	conn.player_name = str(msg.get("name", "Jugador")).strip_edges().left(16)
	if conn.player_name.is_empty():
		conn.player_name = "Jugador"
	var colors = msg.get("colors", {})
	if typeof(colors) == TYPE_DICTIONARY:
		for key in ["x", "o"]:
			var hex := str(colors.get(key, ""))
			if _color_regex.search(hex) != null:
				conn.colors[key] = hex


func _enqueue(conn: Conn) -> void:
	if conn.session != null:
		return
	_leave_waiting(conn)
	while not _queue.is_empty():
		var other: Conn = _queue.pop_front()
		if other.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_start_session(other, conn)
			return
	_queue.append(conn)
	_send(conn, {"t": "waiting"})


func _create_room(conn: Conn) -> void:
	if conn.session != null:
		return
	_leave_waiting(conn)
	var code := ""
	while code.is_empty() or _rooms.has(code):
		code = ""
		for i in 4:
			code += ROOM_CHARS[_rng.randi() % ROOM_CHARS.length()]
	_rooms[code] = conn
	_send(conn, {"t": "room", "code": code})


func _join_room(conn: Conn, code: String) -> void:
	if conn.session != null:
		return
	var host: Conn = _rooms.get(code)
	if host == null or host == conn:
		_send(conn, {"t": "error", "msg": "No existe esa sala"})
		return
	_rooms.erase(code)
	_start_session(host, conn)


func _leave_waiting(conn: Conn) -> void:
	_queue.erase(conn)
	for code in _rooms.keys():
		if _rooms[code] == conn:
			_rooms.erase(code)


func _start_session(a: Conn, b: Conn) -> void:
	# El orden de turno se sortea, como en Polytopia.
	if _rng.randi() % 2 == 0:
		var tmp := a
		a = b
		b = tmp
	var session := Session.new()
	session.clock = TurnClock.new(initial_ms, increment_ms)
	session.seats[1] = a
	session.seats[2] = b
	session.names = [a.player_name, b.player_name]
	session.colors = [a.colors["x"], b.colors["o"]]
	var crypto := Crypto.new()
	session.sid = crypto.generate_random_bytes(8).hex_encode()
	session.tokens[1] = crypto.generate_random_bytes(12).hex_encode()
	session.tokens[2] = crypto.generate_random_bytes(12).hex_encode()
	a.session = session
	a.seat = 1
	b.session = session
	b.seat = 2
	_sessions.append(session)
	var now := Time.get_ticks_msec()
	session.clock.start(1, now)

	var names := [a.player_name, b.player_name]
	var colors := [a.colors["x"], b.colors["o"]]
	for conn in [a, b]:
		_send(conn, {
			"t": "start",
			"you": conn.seat,
			"token": session.tokens[conn.seat],
			"sid": session.sid,
			"names": names,
			"colors": colors,
			"initial_ms": initial_ms,
			"increment_ms": increment_ms,
			"max_skips": MAX_SKIPS,
			"rules": UltimateGame.RULES_VERSION,
			"clocks": session.clock.snapshot(now),
		})


func _on_move(conn: Conn, big: int, small: int) -> void:
	var session := conn.session
	if session == null or session.over:
		_send(conn, {"t": "error", "msg": "No estás en una partida"})
		return
	if session.game.current_player != conn.seat:
		_send(conn, {"t": "error", "msg": "No es tu turno"})
		return
	var now := Time.get_ticks_msec()
	if session.clock.is_expired(now):
		# La jugada llegó tarde: ya le tocaba el salto.
		_handle_timeout(session, now)
		_send(conn, {"t": "error", "msg": "Se te acabó el tiempo"})
		return
	if not session.game.play(big, small):
		_send(conn, {"t": "error", "msg": "Jugada ilegal"})
		return
	session.log.append([big, small])

	if session.game.is_over():
		session.clock.stop(now)
	else:
		session.clock.pass_turn(session.game.current_player, now)

	_broadcast(session, {
		"t": "move",
		"big": big,
		"small": small,
		"player": conn.seat,
		"clocks": session.clock.snapshot(now),
	})
	if session.game.is_over():
		var winner := 0 if session.game.result == UltimateGame.DRAW else session.game.result
		_finish(session, winner, "line" if winner != 0 else "draw")


## Se le acabó el tiempo al jugador de turno: le saltan el turno (estilo Polytopia)
## y con MAX_SKIPS saltos pierde la partida.
func _handle_timeout(session: Session, now: int) -> void:
	var loser: int = session.game.current_player
	session.skips[loser] += 1
	if session.skips[loser] >= MAX_SKIPS:
		_finish(session, 3 - loser, "skips")
		return
	session.game.skip_turn()
	session.log.append("s")
	session.clock.skip_turn(session.game.current_player, now, skip_refill_ms)
	_broadcast(session, {
		"t": "skip",
		"player": loser,
		"skips": [session.skips[1], session.skips[2]],
		"clocks": session.clock.snapshot(now),
	})


func _finish(session: Session, winner: int, reason: String) -> void:
	if session.over:
		return
	session.over = true
	var now := Time.get_ticks_msec()
	session.clock.stop(now)
	var over_message := {
		"t": "over",
		"winner": winner,
		"reason": reason,
		"clocks": session.clock.snapshot(now),
	}
	_broadcast(session, over_message)
	for seat in [1, 2]:
		var conn: Conn = session.seats[seat]
		if conn != null:
			conn.session = null
			conn.seat = 0
		else:
			# Estaba desconectado: cuando vuelva con su token se entera de cómo terminó.
			_finished[session.tokens[seat]] = {"msg": over_message, "until": now + RESULT_KEEP_MS}
	_sessions.erase(session)


func _drop(conn: Conn) -> void:
	_conns.erase(conn)
	for sid in _restoring.keys():
		for seat in _restoring[sid]["seats"].keys():
			if _restoring[sid]["seats"][seat]["conn"] == conn:
				_restoring[sid]["seats"].erase(seat)
	_leave_waiting(conn)
	var session := conn.session
	if session != null and not session.over:
		# No se pierde de inmediato: se guarda el asiento un rato por si vuelve (reanudar).
		session.seats[conn.seat] = null
		session.gone_since[conn.seat] = Time.get_ticks_msec()
		_broadcast(session, {"t": "opponent", "connected": false, "grace_ms": grace_ms})
	conn.session = null
	conn.seat = 0


## Un cliente que perdió la conexión vuelve con su token y retoma la partida.
func _resume(conn: Conn, token: String) -> void:
	if conn.session != null:
		return
	if _finished.has(token):
		_send(conn, _finished[token]["msg"])
		_finished.erase(token)
		return
	var now := Time.get_ticks_msec()
	if not token.is_empty():
		for session in _sessions:
			for seat in [1, 2]:
				if session.over or session.tokens[seat] != token:
					continue
				var old: Conn = session.seats[seat]
				if old != null and old != conn:
					# La conexión vieja seguía "viva" pero muerta: se reemplaza.
					old.session = null
					old.seat = 0
					_conns.erase(old)
					old.ws.close()
				session.seats[seat] = conn
				session.gone_since[seat] = 0
				conn.session = session
				conn.seat = seat
				var other: Conn = session.seats[3 - seat]
				_send(conn, {
					"t": "resume_ok",
					"you": seat,
					"names": session.names,
					"colors": session.colors,
					"max_skips": MAX_SKIPS,
					"rules": UltimateGame.RULES_VERSION,
					"clocks": session.clock.snapshot(now),
					"skips": [session.skips[1], session.skips[2]],
					"log": session.log,
					"opponent_connected": other != null,
				})
				if other != null:
					_send(other, {"t": "opponent", "connected": true})
				return
	_send(conn, {"t": "resume_failed"})


## Repite la partida a partir de su registro. Devuelve null si el registro no es válido o ya terminó.
func _replay(log: Array) -> UltimateGame:
	var game := UltimateGame.new()
	for entry in log:
		if entry is Array and entry.size() == 2:
			if not game.play(int(entry[0]), int(entry[1])):
				return null
		elif str(entry) == "s":
			game.skip_turn()
		else:
			return null
	return null if game.is_over() else game


## El servidor se reinició y perdió las partidas: cada jugador manda lo que sabe y, cuando llegan
## los dos con la misma partida (mismo `sid`), se reconstruye y sigue donde estaba.
func _restore(conn: Conn, msg: Dictionary) -> void:
	if conn.session != null:
		return
	var sid := str(msg.get("sid", ""))
	var seat := int(msg.get("seat", 0))
	var token := str(msg.get("token", ""))
	var log = msg.get("log", [])
	if sid.is_empty() or token.is_empty() or (seat != 1 and seat != 2) or typeof(log) != TYPE_ARRAY or _replay(log) == null:
		_send(conn, {"t": "resume_failed"})
		return
	for session in _sessions:
		if session.sid == sid:  # esa partida sí existe: que reanude normal
			_send(conn, {"t": "resume_failed"})
			return
	var entry: Dictionary = _restoring.get(sid, {"seats": {}, "since": Time.get_ticks_msec()})
	entry["seats"][seat] = {"conn": conn, "msg": msg}
	_restoring[sid] = entry
	var seats: Dictionary = entry["seats"]
	if not (seats.has(1) and seats.has(2)):
		_send(conn, {"t": "restore_wait"})
		return
	_restoring.erase(sid)
	var msg1: Dictionary = seats[1]["msg"]
	var msg2: Dictionary = seats[2]["msg"]
	# Si uno se perdió el último mensaje, vale el registro más largo (si el otro es prefijo suyo).
	var log1: Array = msg1["log"]
	var log2: Array = msg2["log"]
	var best: Array = log1 if log1.size() >= log2.size() else log2
	var short: Array = log2 if log1.size() >= log2.size() else log1
	if JSON.stringify(best.slice(0, short.size())) != JSON.stringify(short):
		for seat_key in [1, 2]:
			_send(seats[seat_key]["conn"], {"t": "resume_failed"})
		return
	var session := Session.new()
	session.sid = sid
	session.game = _replay(best)
	session.log = best.duplicate()
	var now := Time.get_ticks_msec()
	session.clock = TurnClock.new(initial_ms, increment_ms)
	var names: Array = msg1.get("names", ["X", "O"])
	session.names = [str(names[0]).left(16), str(names[1]).left(16)] if names.size() == 2 else ["X", "O"]
	var colors: Array = msg1.get("colors", [])
	session.colors = [DEFAULT_COLORS["x"], DEFAULT_COLORS["o"]]
	if colors.size() == 2:
		for i in 2:
			if _color_regex.search(str(colors[i])) != null:
				session.colors[i] = str(colors[i])
	for seat_key in [1, 2]:
		var m: Dictionary = seats[seat_key]["msg"]
		var c: Conn = seats[seat_key]["conn"]
		session.tokens[seat_key] = str(m["token"])
		session.seats[seat_key] = c
		c.session = session
		c.seat = seat_key
		var their_skips: Array = m.get("skips", [0, 0])
		var their_clocks: Array = m.get("clocks", [initial_ms, initial_ms])
		for i in 2:
			if their_skips.size() == 2:
				session.skips[i + 1] = maxi(session.skips[i + 1], clampi(int(their_skips[i]), 0, MAX_SKIPS - 1))
		for i in 2:
			if their_clocks.size() == 2:
				var ms := clampi(int(their_clocks[i]), 1000, initial_ms + increment_ms * 100)
				# Se toma el menor de los dos reportes: ninguno puede inventarse más tiempo.
				session.clock.banks[i + 1] = ms if seat_key == 1 else mini(int(session.clock.banks[i + 1]), ms)
	_sessions.append(session)
	session.clock.start(session.game.current_player, now)
	for seat_key in [1, 2]:
		_send(session.seats[seat_key], {
			"t": "resume_ok",
			"you": seat_key,
			"names": session.names,
			"colors": session.colors,
			"max_skips": MAX_SKIPS,
			"rules": UltimateGame.RULES_VERSION,
			"clocks": session.clock.snapshot(now),
			"skips": [session.skips[1], session.skips[2]],
			"log": session.log,
			"opponent_connected": true,
		})


func _broadcast(session: Session, data: Dictionary) -> void:
	for seat in [1, 2]:
		var conn: Conn = session.seats[seat]
		if conn != null:
			_send(conn, data)


func _send(conn: Conn, data: Dictionary) -> void:
	if conn.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		conn.ws.send_text(JSON.stringify(data))
