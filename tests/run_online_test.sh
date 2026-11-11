#!/usr/bin/env bash
# Levanta un servidor local con banco de 2s, corre el test online y lo apaga.
# Uso: GODOT=/ruta/a/godot tests/run_online_test.sh
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."

"$GODOT" --headless -s server/server_main.gd -- --port=9081 --initial=2000 --increment=0 --skip_refill=1000 --grace=1500 --intro=0 &
SERVER_PID=$!
sleep 2

timeout 60 "$GODOT" --headless -s tests/online_test.gd
STATUS=$?

kill "$SERVER_PID" 2>/dev/null
wait "$SERVER_PID" 2>/dev/null

# Servidor aparte con presentación de 1,5 s para probar que no deja jugar antes
"$GODOT" --headless -s server/server_main.gd -- --port=9082 --intro=1500 &
INTRO_PID=$!
sleep 2
timeout 30 "$GODOT" --headless -s tests/intro_online_test.gd
INTRO_STATUS=$?
kill "$INTRO_PID" 2>/dev/null
wait "$INTRO_PID" 2>/dev/null
if [ "$STATUS" -eq 0 ]; then STATUS=$INTRO_STATUS; fi

# Servidor aparte para cuentas (archivo temporal, sin Supabase)
rm -f /tmp/mtt_accounts.json
env -u SUPABASE_URL -u SUPABASE_KEY "$GODOT" --headless -s server/server_main.gd -- --port=9083 --accounts=/tmp/mtt_accounts.json &
ACC_PID=$!
sleep 2
timeout 30 "$GODOT" --headless -s tests/accounts_online_test.gd
ACC_STATUS=$?
kill "$ACC_PID" 2>/dev/null
wait "$ACC_PID" 2>/dev/null
rm -f /tmp/mtt_accounts.json
if [ "$STATUS" -eq 0 ]; then STATUS=$ACC_STATUS; fi
exit "$STATUS"
