# Mega Tac Toe

Ultimate Tic Tac Toe hecho en Godot 4, pensado para móvil y web, con partidas online.

## Reglas

- El tablero es un 3x3 de tableros 3x3.
- El primer jugador elige libre dónde empezar (el orden de turno se sortea en online).
- La casilla que jugás dentro de un mini tablero decide en cuál tablero grande juega el rival.
- Si ese tablero está lleno, el rival elige libre.
- Un tablero se gana con 3 en línea adentro (el primero en hacer línea se lo queda). Un tablero ganado
  **sigue jugable** en sus casillas libres; su marca se ve translúcida encima.
- La partida se gana con 3 tableros en línea.

## Turnos con reloj (estilo Polytopia "Live Game")

- Cada jugador arranca con un banco de 5 minutos. El reloj corre solo en su turno.
- Al jugar se le suman 45 s; lo que no gastó se acumula para los próximos turnos.
- Si se queda sin tiempo le **saltan el turno**: el rival deshace su última jugada y la vuelve a elegir,
  ya sabiendo que el otro no responde (así piensa en su propia ventaja). Al que saltaron se le repone un
  banco de 90 s. Con **3 saltos pierde** la partida.
- Todos los valores se cambian con argumentos del servidor: `--initial`, `--increment`, `--skip_refill` (en ms).

## Menú

- Página principal con nombre, partida rápida, salas y local. Arriba a la derecha, el botón **Servidor** abre una cascada para cambiar la URL (por defecto el server de Render).
- A la izquierda hay una página de **colores** (swipe a la derecha o flecha `< Colores`): selector grande y atajos para X y O.

## Estructura

- `scripts/ultimate_game.gd`: lógica pura del juego, sin UI ni red.
- `scripts/turn_clock.gd`: reloj con banco, incremento y saltos.
- `scripts/profile.gd`: nombre, colores (rojo X / azul O por defecto) y dirección del servidor.
- `scripts/net_client.gd`: cliente WebSocket.
- `scripts/app.gd`, `menu.gd`, `game_screen.gd`: pantallas.
- `server/`: servidor autoritativo (Godot headless por WebSocket). Reutiliza la misma lógica y reloj.
- `tests/`: tests de lógica, de pantallas y de punta a punta online.

## Probar en local

```
# servidor
godot --headless -s server/server_main.gd -- --port=9080
# juego: abrir el proyecto en Godot y correrlo (por defecto apunta a ws://127.0.0.1:9080)
```

## Tests

```
godot --headless -s tests/run_tests.gd
godot --headless --quit-after 600 -s tests/ui_smoke.gd
GODOT=godot tests/run_online_test.sh
```

## Desplegar el servidor gratis (Render)

El plan gratis de Render no pide tarjeta, soporta WebSocket y da TLS (`wss://`). Se duerme tras 15 min
sin tráfico y tarda cerca de 1 min en despertar.

1. En render.com: New > Blueprint, conectar este repo (usa `render.yaml` y el `Dockerfile`).
2. Cuando termine, copiar la URL (`https://mega-tac-toe-server.onrender.com`).
3. En el menú del juego, en "Servidor", poner `wss://mega-tac-toe-server.onrender.com`.

## Android

Cada push a `main` que toque el juego compila un APK en GitHub Actions y lo publica en
[Releases](https://github.com/Danny-Carvajal/mega-tac-toe/releases/latest) (un release nuevo por build, `build-N`).

1. Abrir ese link desde el cel y bajar `mega-tac-toe.apk`.
2. Abrirlo y permitir "instalar apps de orígenes desconocidos" cuando lo pida.
3. Para jugar online, poner la dirección del servidor en el campo "Servidor" del menú.

El APK está firmado con una llave de debug (`ci/debug.keystore`, pública a propósito), así que las
builds nuevas se instalan encima de las anteriores. Para publicar en Play Store hará falta una llave propia.

## Pendiente

- Exportar a web.
- Partidas de 24 h por turno (asíncronas), que necesitan guardar partidas en disco/base de datos.
- Reconexión si se cae la conexión a mitad de partida.
- Cuentas, ranking y notificaciones.

## Historial y repeticiones

Las partidas online terminadas se guardan en el dispositivo (`scripts/history.gd`, `user://history.json`, máx. 300).
Cada jugada ocupa 1 byte (`big * 9 + small`, 255 = salto de turno) y el registro completo va en base64, así una
partida pesa ~60 caracteres más los nombres. Se abre desde Estadísticas > "Historial de partidas": muestra la lista y,
al tocar una, la repetición (paso a paso, con Play en vivo, y con apuntes). Cuando haya cuentas, los mismos
registros se pueden subir al servidor.

## Práctica contra la IA

Debajo de JUGAR hay un botón chiquito "Práctica" con 5 niveles (`scripts/ai.gd`): 1 Novato (azar), 2 Aprendiz (ve jugadas de un paso),
3 Estratega (3 jugadas adelante), 4 Experto (5 jugadas adelante) y 5 Maestro (búsqueda alfa-beta por tiempo, ~1,5 s por jugada).
La persona es X y empieza. La IA piensa en un hilo aparte (en la web, sin hilos, piensa menos). Las partidas de práctica todavía no se guardan en estadísticas ni historial.

## Presentación de la partida online (VS + moneda)

Al emparejarse, el servidor da `intro_ms` (8,5 s por defecto, `--intro=` para cambiarlo) de presentación: VS con los dos jugadores,
moneda animada y la marca que le tocó a cada uno (X siempre empieza). El servidor ya sorteó el asiento; el cliente solo lo anima
(`scripts/intro_screen.gd`). En ese tiempo no se aceptan jugadas y el reloj de X todavía no corre. Un servidor viejo no manda `intro_ms`: sin presentación.

## Tienda, cajas y cosméticos

Botón "Tienda" (arriba a la izquierda del menú, con las monedas). Hay 3 tipos de cosméticos, todos dibujados por código (`scripts/cosmetics.gd`):
figuras (10 para la X y 10 para la O, `figure_view.gd`), banners (13, `banner_view.gd`) y fuentes del nombre (9). Rarezas: común, rara, épica y legendaria.
Una caja cuesta 300 monedas (60 % común, 28 % rara, 9 % épica, 3 % legendaria); si sale una repetida devuelve monedas según la rareza.
Monedas: online 100 por ganar, 50 por empatar y 25 por perder; en práctica ganar da de 5 a 25 según el nivel de la IA. Se empieza con 600.
Lo que tenés se guarda en el dispositivo (`scripts/collection.gd`, `user://collection.json`). Online, el servidor solo le pasa tus cosméticos al rival
(valida que los ids tengan forma válida; el cliente cae a los de inicio si no los conoce). El VS muestra banner, fuente y figuras de cada jugador.
