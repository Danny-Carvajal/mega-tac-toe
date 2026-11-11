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

- Cada jugador arranca con un banco de 30 s. El reloj corre solo en su turno.
- Al jugar se le suman 5 s; lo que no gastó se acumula para los próximos turnos.
- Si se queda sin tiempo le **saltan el turno**: el rival deshace su última jugada y la vuelve a elegir,
  ya sabiendo que el otro no responde (así piensa en su propia ventaja). Al que saltaron se le repone un
  banco de 10 s. Con **3 saltos pierde** la partida.
- Todos los valores se cambian con argumentos del servidor: `--initial`, `--increment`, `--skip_refill` (en ms).

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
[Releases](https://github.com/Danny-Carvajal/mega-tac-toe/releases/tag/latest) (etiqueta `latest`).

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
