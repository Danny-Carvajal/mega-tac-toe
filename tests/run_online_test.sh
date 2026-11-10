#!/usr/bin/env bash
# Levanta un servidor local con banco de 2s, corre el test online y lo apaga.
# Uso: GODOT=/ruta/a/godot tests/run_online_test.sh
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."

"$GODOT" --headless -s server/server_main.gd -- --port=9081 --initial=2000 --increment=0 --skip_refill=1000 &
SERVER_PID=$!
sleep 2

timeout 60 "$GODOT" --headless -s tests/online_test.gd
STATUS=$?

kill "$SERVER_PID" 2>/dev/null
wait "$SERVER_PID" 2>/dev/null
exit "$STATUS"
