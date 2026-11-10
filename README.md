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
- `tests/run_tests.gd`: tests de la lógica.
- `project.godot`: configuración (renderer Compatibility para que exporte a web).

## Tests

```
godot --headless -s tests/run_tests.gd
```

## Ideas pendientes

- Multijugador online
- Variantes de reglas propias
