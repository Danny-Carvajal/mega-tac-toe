extends Node
## Cliente WebSocket para hablar con el servidor. Sirve igual en Android, iOS,
## PC y web. Los mensajes llegan como Dictionary por la señal `message`.

signal connected
signal disconnected
signal message(data: Dictionary)

var _ws := WebSocketPeer.new()
var _active := false
var _was_open := false


func connect_to_server(url: String) -> int:
	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url(url)
	_active = err == OK
	_was_open = false
	return err


func is_open() -> bool:
	return _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func send(data: Dictionary) -> void:
	if is_open():
		_ws.send_text(JSON.stringify(data))


func close() -> void:
	_ws.close()


func _process(_delta: float) -> void:
	if not _active:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				connected.emit()
			while _ws.get_available_packet_count() > 0:
				var data = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
				if typeof(data) == TYPE_DICTIONARY:
					message.emit(data)
		WebSocketPeer.STATE_CLOSED:
			_active = false
			_was_open = false
			disconnected.emit()
