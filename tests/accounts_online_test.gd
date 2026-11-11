extends SceneTree
## Cuentas contra un servidor real (puerto 9083, archivo de cuentas temporal).

const NetClient := preload("res://scripts/net_client.gd")
const Account := preload("res://scripts/account.gd")
const Profile := preload("res://scripts/profile.gd")
const Stats := preload("res://scripts/stats.gd")
const History := preload("res://scripts/history.gd")
const Collection := preload("res://scripts/collection.gd")
const URL := "ws://127.0.0.1:9083"

var failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var a := await _connect()
	check(a != null, "conecta")
	if a == null:
		quit(1)
		return
	var inbox: Array = a[1]
	var c: Node = a[0]

	c.send({"t": "register", "user": "ab", "pass": "123456"})
	check((await _next(inbox, "auth_error")).has("msg"), "usuario muy corto se rechaza")
	c.send({"t": "register", "user": "Karmish", "pass": "123"})
	check((await _next(inbox, "auth_error")).has("msg"), "contraseña corta se rechaza")
	c.send({"t": "register", "user": "Karmish", "pass": "secreto1", "data": {"coins": 700}})
	var reg := await _next(inbox, "auth")
	check(reg.get("user") == "Karmish" and reg.get("created") == true and int(reg["data"]["coins"]) == 700, "registro crea la cuenta con los datos locales")
	var token: String = reg.get("token", "")
	check(token.length() > 20, "devuelve un token")
	c.send({"t": "register", "user": "karmish", "pass": "otra123"})
	check((await _next(inbox, "auth_error")).get("msg", "").contains("existe"), "no se repite el usuario (sin importar mayúsculas)")
	c.send({"t": "save", "data": {"coins": 900, "owned": {"star": true}}})
	check((await _next(inbox, "saved")).get("ok") == true, "guarda los datos")

	var b := await _connect()
	var inbox2: Array = b[1]
	var c2: Node = b[0]
	c2.send({"t": "login", "user": "KARMISH", "pass": "mala"})
	check(not (await _next(inbox2, "auth_error")).is_empty(), "contraseña mala no entra")
	c2.send({"t": "save", "data": {"coins": 1}})
	check((await _next(inbox2, "saved", 0.6)).is_empty(), "sin sesión no se puede guardar")
	c2.send({"t": "login", "user": "KARMISH", "pass": "secreto1"})
	var lg := await _next(inbox2, "auth")
	check(lg.get("user") == "Karmish" and int(lg["data"]["coins"]) == 900 and lg.get("created") == false, "login trae lo guardado")
	c2.send({"t": "logout"})
	c2.send({"t": "save", "data": {"coins": 5}})
	check((await _next(inbox2, "saved", 0.6)).is_empty(), "después de salir no se guarda")

	var d := await _connect()
	var inbox3: Array = d[1]
	d[0].send({"t": "auth", "token": token})
	var au := await _next(inbox3, "auth")
	check(au.get("user") == "Karmish" and int(au["data"]["coins"]) == 900, "el token vuelve a entrar sin contraseña")
	d[0].send({"t": "auth", "token": "karmish.falso"})
	check(_next_expired(await _next(inbox3, "auth_error")), "un token falso no sirve")

	await _client_flow()
	print("FAIL: %d" % failures if failures > 0 else "OK: cuentas")
	quit(1 if failures > 0 else 0)


func _make_account(file: String) -> Account:
	var acc := Account.new()
	acc.profile = Profile.new()
	acc.profile.server_url = URL
	acc.stats = Stats.new()
	acc.history = History.new()
	acc.collection = Collection.new()
	acc.path = file
	root.add_child(acc)
	return acc


func _wait(cond: Callable, timeout := 4.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await process_frame
	return false


func _client_flow() -> void:
	var f1 := "/tmp/mtt_acc_a.json"
	var f2 := "/tmp/mtt_acc_b.json"
	var one := _make_account(f1)
	one.collection.coins = 777
	one.stats.record("W")
	one.profile.player_name = "Zeta"
	one.register("Cliente1", "clave123")
	check(await _wait(func() -> bool: return one.is_logged_in()), "cliente: crea la cuenta")
	one.collection.add_coins(50)
	one.stats.record("L")
	check(await _wait(func() -> bool: return one.status == "Guardado en tu cuenta.", 8.0), "cliente: sube los cambios solo")
	var two := _make_account(f2)
	two.login("cliente1", "clave123")
	check(await _wait(func() -> bool: return two.is_logged_in() and two.collection.coins == 827), "cliente: otro dispositivo baja las monedas")
	check(two.stats.wins == 1 and two.stats.losses == 1 and two.profile.player_name == "Zeta", "cliente: baja stats y perfil")
	var three := _make_account(f1)
	three.start()
	check(await _wait(func() -> bool: return three.is_logged_in() and three.status.begins_with("Sesión iniciada")), "cliente: retoma la sesión guardada al abrir la app")
	three.logout()
	check(not three.is_logged_in(), "cliente: cerrar sesión")
	for file in [f1, f2]:
		DirAccess.remove_absolute(file)
	# apply_data guardó en las rutas reales de usuario: se limpian para no ensuciar otros tests
	for local in [Profile.PATH, Stats.PATH, History.PATH, "user://collection.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(local))


func _next_expired(msg: Dictionary) -> bool:
	return msg.get("expired") == true


func _connect() -> Array:
	var client := NetClient.new()
	root.add_child(client)
	var inbox: Array = []
	client.message.connect(func(data: Dictionary) -> void: inbox.append(data))
	client.connect_to_server(URL)
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		if client.is_open():
			return [client, inbox]
		await process_frame
	return []


func _next(inbox: Array, type: String, timeout := 3.0) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < deadline:
		while not inbox.is_empty():
			var msg: Dictionary = inbox.pop_front()
			if msg.get("t") == type:
				return msg
		await process_frame
	return {}


func check(condition: bool, name: String) -> void:
	if condition:
		print("  ok   %s" % name)
	else:
		failures += 1
		print("  FAIL %s" % name)
