#!/usr/bin/env bash
# Déploie l'observabilité du studio (module 3) : Prometheus et Grafana, provisionnés par fichiers.
# Les fichiers versionnés deviennent des ConfigMaps ; rien ne se règle à la souris dans Grafana.
#   GRAFANA_ADMIN=… ./observabilite/deployer.sh [fr-FR|en-US|de-DE]
set -euo pipefail
cd "$(dirname "$0")"
LANGUE=${1:-fr-FR}
: "${GRAFANA_ADMIN:?GRAFANA_ADMIN manquant : mot de passe du compte admin de Grafana}"
appliquer() { kubectl apply -f -; }
configmap() { kubectl -n observabilite create configmap "$@" --dry-run=client -o yaml | appliquer; }

kubectl create namespace observabilite --dry-run=client -o yaml | appliquer
kubectl -n observabilite create secret generic grafana-admin \
  --from-literal=mot-de-passe="$GRAFANA_ADMIN" --dry-run=client -o yaml | appliquer

# Configuration de Prometheus, source de données, fournisseur de tableaux, alerte, tableau de bord
configmap prometheus --from-file=prometheus.yml
configmap grafana-sources --from-file=grafana/sources.yaml
configmap grafana-tableaux --from-file=grafana/tableaux.yaml
configmap grafana-alertes --from-file=grafana/alertes.yaml
case "$LANGUE" in en-US) T=studio3d.en.json ;; de-DE) T=studio3d.de.json ;; *) T=studio3d.json ;; esac
configmap grafana-tableau-studio3d --from-file=studio3d.json="tableaux/$T"
configmap grafana-langue --from-literal=langue="$LANGUE"

# Les deux déploiements, redémarrés pour relire les fichiers
kubectl apply -f k8s.yaml
kubectl -n observabilite rollout restart deployment/prometheus deployment/grafana
kubectl -n observabilite rollout status deployment/prometheus --timeout=180s
kubectl -n observabilite rollout status deployment/grafana --timeout=180s
echo "Tableau de bord : http://grafana.localhost:8080/d/studio3d"
