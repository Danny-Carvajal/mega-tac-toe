# Mega Tic Toe

Ultimate Tic Tac Toe hecho en Godot 4, pensado primero para móvil y web, y a futuro multijugador cross platform.

## Reglas (base)

- El tablero es un 3x3 de tableros 3x3.
- El primer jugador elige libre dónde empezar.
- La casilla que jugás dentro de un mini tablero decide en cuál tablero grande juega el rival.
- Si ese tablero ya está ganado o lleno, el rival elige libre.
- Un tablero se gana con 3 en línea adentro. La partida se gana con 3 tableros en línea.

## Estructura

- `scripts/ultimate_game.gd`: lógica pura del juego, sin UI ni red.
- `scripts/main.gd` y `scenes/main.tscn`: pantalla jugable (el tablero se arma por código).
- `tests/run_tests.gd`: tests de la lógica.
- `tests/ui_smoke.gd`: smoke test de la pantalla.
- `project.godot`: configuración (renderer Compatibility para que exporte a web).

## Tests

```
godot --headless -s tests/run_tests.gd
godot --headless --quit-after 300 -s tests/ui_smoke.gd
```

## Ideas pendientes

- Multijugador online
- Variantes de reglas propias
