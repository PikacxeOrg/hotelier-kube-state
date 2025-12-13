#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

echo "Deploying monitoring stack into 'observability' namespace"
MON_NS="observability"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo add grafana https://grafana.github.io/helm-charts || true
helm repo update

helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack -n "$MON_NS" --create-namespace --version 66.7.1 --values kube-state/prometheus-stack/values.yaml

# Install Loki stack
helm upgrade --install loki grafana/loki-stack -n "$MON_NS" --create-namespace --set grafana.enabled=false --set prometheus.enabled=false --values kube-state/loki/values.yaml || true
helm upgrade --install promtail grafana/promtail -n "$MON_NS" --set loki.serviceName=loki --values kube-state/promtail/values.yaml || true

kubectl -n "$MON_NS" wait --for=condition=available --timeout=300s deployment -l app.kubernetes.io/name=grafana || true

# Add databases
echo "Deploying databases into 'databases' namespace"
DB_NS="databases"

# Add DB Helm repos and install databases (dev-friendly defaults in values files)
helm repo add bitnami https://charts.bitnami.com/bitnami || true
helm repo update

helm upgrade --install postgresql bitnami/postgresql -n "$DB_NS" --create-namespace --values kube-state/postgres/values.yaml || true
helm upgrade --install mongodb bitnami/mongodb -n "$DB_NS" --create-namespace --values kube-state/mongo/values.yaml || true
helm upgrade --install rabbitmq bitnami/rabbitmq -n "$DB_NS" --create-namespace --values kube-state/rabbitmq/values.yaml || true

# Wait for core DB workloads to become ready (best-effort)
kubectl -n "$DB_NS" wait --for=condition=available --timeout=300s deployment -l app.kubernetes.io/name=postgresql || true
kubectl -n "$DB_NS" wait --for=condition=ready --timeout=300s statefulset -l app.kubernetes.io/instance=mongodb || true
kubectl -n "$DB_NS" wait --for=condition=ready --timeout=300s statefulset -l app.kubernetes.io/instance=rabbitmq || true


# Install/upgrade script for Hotelier Helm charts

command -v helm >/dev/null 2>&1 || { echo "helm is required but not installed" >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed" >&2; exit 1; }

HELM_CHARTS_DIR="helm-charts/"
NS="hotelier"

echo "Deploying Hotelier services to namespace: $NS"

declare -a services=(
	"accommodation-service:hotelier-accommodation-service"
	"availability-service:hotelier-availability-service"
	"cdn-service:hotelier-cdn-service"
	"identity-service:hotelier-identity-service"
	"notification-service:hotelier-notification-service"
	"rating-service:hotelier-rating-service"
	"reservation-service:hotelier-reservation-service"
	"search-service:hotelier-search-service"
)

for entry in "${services[@]}"; do
	release="${entry%%:*}"
	chartname="${entry#*:}"
	chartpath="$HELM_CHARTS_DIR/$chartname"
	valuesfile="$chartname/values.yaml"

	if [ ! -d "$chartpath" ]; then
		echo "Warning: chart path not found: $chartpath — attempting to continue (chart may be a repo/chart)"
	fi

	if [ ! -f "$valuesfile" ]; then
		echo "Note: values file not found: $valuesfile — deploying with chart defaults"
		helm upgrade --install "$release" "$chartpath" -n "$NS" --create-namespace
	else
		helm upgrade --install "$release" "$chartpath" -n "$NS" --create-namespace --values kube-state/"$valuesfile"
	fi
done

echo "Setup complete"