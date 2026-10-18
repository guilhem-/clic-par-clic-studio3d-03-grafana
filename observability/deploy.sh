#!/usr/bin/env bash
# Deploys the studio observability (module 3): Prometheus and Grafana, provisioned from files.
# The versioned files become ConfigMaps; nothing is set up with the mouse in Grafana.
#   GRAFANA_ADMIN=… ./observability/deploy.sh [en-US|fr-FR|de-DE]
set -euo pipefail
cd "$(dirname "$0")"
LANGUAGE=${1:-en-US}
: "${GRAFANA_ADMIN:?GRAFANA_ADMIN missing: password of the Grafana admin account}"
apply() { kubectl apply -f -; }
configmap() { kubectl -n observability create configmap "$@" --dry-run=client -o yaml | apply; }

kubectl create namespace observability --dry-run=client -o yaml | apply
kubectl -n observability create secret generic grafana-admin \
  --from-literal=password="$GRAFANA_ADMIN" --dry-run=client -o yaml | apply

# Prometheus configuration, data source, dashboard provider, alert, dashboard
configmap prometheus --from-file=prometheus.yml
configmap grafana-sources --from-file=grafana/sources.yaml
configmap grafana-dashboards --from-file=grafana/dashboards.yaml
configmap grafana-alerts --from-file=grafana/alerts.yaml
case "$LANGUAGE" in fr-FR) D=studio3d.fr.json ;; de-DE) D=studio3d.de.json ;; *) D=studio3d.json ;; esac
configmap grafana-dashboard-studio3d --from-file=studio3d.json="dashboards/$D"
configmap grafana-language --from-literal=language="$LANGUAGE"

# The two deployments, restarted to read the files again
kubectl apply -f k8s.yaml
kubectl -n observability rollout restart deployment/prometheus deployment/grafana
kubectl -n observability rollout status deployment/prometheus --timeout=180s
kubectl -n observability rollout status deployment/grafana --timeout=180s
echo "Dashboard: http://grafana.localhost:8080/d/studio3d"
