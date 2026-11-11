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
## Mensajes servidor -> cliente:
##   {t:"waiting"}, {t:"room", code}
##   {t:"start", you, names, colors, initial_ms, increment_ms, clocks}
##   {t:"move", big, small, player, clocks}
##   {t:"skip", player, skips:[x,o], clocks}   se le acabó el tiempo: le saltan el turno y
##       el rival deshace su última jugada y la vuelve a elegir (UltimateGame.skip_turn)
##   {t:"over", winner (0 = empate), reason, clocks}
##       reason: line | draw | skips (3 saltos) | resign | disconnect
##   {t:"error", msg}

const UltimateGame := preload("res://scripts/ultimate_game.gd")
const TurnClock := preload("res://scripts/turn_clock.gd")

const ROOM_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const DEFAULT_COLORS := {"x": "#e5484d", "o": "#3b82f6"}

const MAX_SKIPS := 3

var port := 9080
var initial_ms := 90000
var increment_ms := 20000
## Banco que se le repone a quien se pasó de tiempo y le saltaron el turno.
var skip_refill_ms := 45000

var _tcp := TCPServer.new()
var _conns: Array[Conn] = []
var _queue: Array[Conn] = []
var _rooms := {}  # código -> Conn que espera
var _sessions: Array[Session] = []
var _rng := RandomNumberGenerator.new()
var _color_regex := RegEx.create_from_string("^#[0-9a-fA-F]{6}$")


class Conn:
	extends RefCounted
	var ws: WebSocketPeer
	var player_name := "Jugador"
	var colors := DEFAULT_COLORS.duplicate()
	var session: Session = null
	var seat := 0


class Session:
	extends RefCounted
	var game := UltimateGame.new()
	var clock: TurnClock
	var seats: Array = [null, null, null]  # índice 1 y 2
	var skips: Array = [0, 0, 0]
	var over := false


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


func _process(_delta: float) -> void:
	while _tcp.is_connection_available():
		var conn := Conn.new()
		conn.ws = WebSocketPeer.new()
		conn.ws.accept_stream(_tcp.take_connection())
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
	for session in _sessions.duplicate():
		if not session.over and session.clock.is_expired(now):
			_handle_timeout(session, now)


# --- Mensajes -------------------------------------------------------------

func _on_message(conn: Conn, text: String) -> void:
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
			"names": names,
			"colors": colors,
			"initial_ms": initial_ms,
			"increment_ms": increment_ms,
			"max_skips": MAX_SKIPS,
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
	_broadcast(session, {
		"t": "over",
		"winner": winner,
		"reason": reason,
		"clocks": session.clock.snapshot(now),
	})
	for seat in [1, 2]:
		var conn: Conn = session.seats[seat]
		if conn != null:
			conn.session = null
			conn.seat = 0
	_sessions.erase(session)


func _drop(conn: Conn) -> void:
	_conns.erase(conn)
	_leave_waiting(conn)
	if conn.session != null and not conn.session.over:
		_finish(conn.session, 3 - conn.seat, "disconnect")


func _broadcast(session: Session, data: Dictionary) -> void:
	for seat in [1, 2]:
		var conn: Conn = session.seats[seat]
		if conn != null:
			_send(conn, data)


func _send(conn: Conn, data: Dictionary) -> void:
	if conn.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		conn.ws.send_text(JSON.stringify(data))
