#!/usr/bin/env bash
# Simulates the "catalog agent" of the video: twelve requests at once, then the status of each one
# asked every two seconds, until all of them are finished. Like Open WebUI, it sends the studio
# token and the identity header.
# Prerequisites, in another terminal: kubectl -n studio3d port-forward svc/studio 8000:8000
# and the token in the environment: export STUDIO_TOKEN=…
set -euo pipefail
URL=${STUDIO_URL:-http://127.0.0.1:8000}
AGENT=${AGENT:-catalog-agent@example.com}
COUNT=${COUNT:-12}
: "${STUDIO_TOKEN:?STUDIO_TOKEN missing}"
SCENE='import bpy\nbpy.ops.mesh.primitive_plane_add(size=6); bpy.context.object.name = \"Decor floor\"\nbpy.ops.mesh.primitive_cylinder_add(radius=0.5, depth=1, location=(0, 0, 0.5))'

tool() { # $1: tool name, $2: JSON arguments
  curl -s "$URL/mcp" -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -H "Authorization: Bearer $STUDIO_TOKEN" -H "X-User-Email: $AGENT" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}" \
    | sed -n 's/^data: //p'   # JSON-RPC answer; the tool result is an escaped JSON text
}

numbers=()
for i in $(seq 1 "$COUNT"); do
  n=$(tool submit_render "{\"title\":\"Item $i\",\"code\":\"$SCENE\"}" | grep -o 'number[\\"]*: *[0-9]*' | head -1 | grep -o '[0-9]*$')
  numbers+=("$n")
done
echo "Requests sent: ${numbers[*]}"

# Polling in a loop: exactly what not to do, and what the dashboard reveals.
while :; do
  remaining=0
  for n in "${numbers[@]}"; do
    status=$(tool render_status "{\"number\":$n}" | grep -o 'status[\\"]*: *[\\"]*[a-z_]*' | head -1 | grep -o '[a-z_]*$')
    case "$status" in done|error) ;; *) remaining=$((remaining + 1)) ;; esac
  done
  echo "$(date +%T): $remaining request(s) in progress · queue: $(curl -s "$URL/health")"
  [ "$remaining" -eq 0 ] && break
  sleep 2
done
