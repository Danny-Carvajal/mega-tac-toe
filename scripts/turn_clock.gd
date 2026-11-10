extends RefCounted
## Reloj de turnos estilo "Live Game" de Polytopia (como un reloj de ajedrez Fischer):
## cada jugador arranca con un banco de tiempo, el reloj solo corre en su turno,
## y al mover se le suma un incremento. Lo que no gastó se acumula para el próximo turno.
##
## Todo recibe `now_ms` por parámetro, así se puede testear sin esperar tiempo real.

var initial_ms: int
var increment_ms: int
## Banco de cada jugador. Índice 1 = X, 2 = O (el 0 no se usa).
var banks: Array = [0, 0, 0]
## Jugador cuyo reloj corre ahora. 0 = reloj detenido.
var active := 0
var _turn_started_ms := 0


func _init(p_initial_ms: int = 30000, p_increment_ms: int = 5000) -> void:
	initial_ms = p_initial_ms
	increment_ms = p_increment_ms
	banks = [0, initial_ms, initial_ms]


func start(player: int, now_ms: int) -> void:
	active = player
	_turn_started_ms = now_ms


func remaining_ms(player: int, now_ms: int) -> int:
	if player == active:
		return maxi(0, banks[player] - (now_ms - _turn_started_ms))
	return banks[player]


func is_expired(now_ms: int) -> bool:
	return active != 0 and remaining_ms(active, now_ms) <= 0


## El jugador activo movió: se le descuenta lo gastado, se le suma el incremento
## y empieza a correr el reloj del siguiente.
func pass_turn(next_player: int, now_ms: int) -> void:
	if active != 0:
		banks[active] = remaining_ms(active, now_ms) + increment_ms
	start(next_player, now_ms)


## Al jugador activo se le acabó el tiempo y le saltan el turno: su banco se
## repone con `refill_ms` y empieza a correr el reloj del siguiente.
func skip_turn(next_player: int, now_ms: int, refill_ms: int) -> void:
	if active != 0:
		banks[active] = refill_ms
	start(next_player, now_ms)


func stop(now_ms: int) -> void:
	if active != 0:
		banks[active] = remaining_ms(active, now_ms)
	active = 0


## [tiempo de X, tiempo de O] en milisegundos.
func snapshot(now_ms: int) -> Array:
	return [remaining_ms(1, now_ms), remaining_ms(2, now_ms)]
