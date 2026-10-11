#!/usr/bin/env bash
# Simule l'« agent catalogue » de la vidéo : douze demandes d'un coup, puis l'état de chacune
# demandé toutes les deux secondes, jusqu'à ce que toutes soient finies. Comme Open WebUI, il
# passe le jeton du studio et l'en-tête d'identité.
# Prérequis, dans un autre terminal : kubectl -n studio3d port-forward svc/studio 8000:8000
# et le jeton dans l'environnement : export STUDIO_JETON=…
set -euo pipefail
URL=${STUDIO_URL:-http://127.0.0.1:8000}
AGENT=${AGENT:-agent-catalogue@example.com}
NOMBRE=${NOMBRE:-12}
: "${STUDIO_JETON:?STUDIO_JETON manquant}"
SCENE='import bpy\nbpy.ops.mesh.primitive_plane_add(size=6); bpy.context.object.name = \"Decor sol\"\nbpy.ops.mesh.primitive_cylinder_add(radius=0.5, depth=1, location=(0, 0, 0.5))'

outil() { # $1 : nom de l'outil, $2 : arguments JSON
  curl -s "$URL/mcp" -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -H "Authorization: Bearer $STUDIO_JETON" -H "X-Utilisateur-Email: $AGENT" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}" \
    | sed -n 's/^data: //p'   # réponse JSON-RPC ; le résultat de l'outil est un texte JSON échappé
}

numeros=()
for i in $(seq 1 "$NOMBRE"); do
  n=$(outil soumettre_rendu "{\"titre\":\"Article $i\",\"code\":\"$SCENE\"}" | grep -o 'numero[\\"]*: *[0-9]*' | head -1 | grep -o '[0-9]*$')
  numeros+=("$n")
done
echo "Demandes envoyées : ${numeros[*]}"

# Interrogation en boucle : exactement ce qu'il ne faut pas faire, et ce que le tableau de bord révèle.
while :; do
  restantes=0
  for n in "${numeros[@]}"; do
    statut=$(outil etat_rendu "{\"numero\":$n}" | grep -o 'statut[\\"]*: *[\\"]*[a-z_]*' | head -1 | grep -o '[a-z_]*$')
    case "$statut" in termine|erreur) ;; *) restantes=$((restantes + 1)) ;; esac
  done
  echo "$(date +%T) : $restantes demande(s) en cours · file : $(curl -s "$URL/sante")"
  [ "$restantes" -eq 0 ] && break
  sleep 2
done
