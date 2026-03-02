#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Simplified setup script for Hotelier using plain Kubernetes manifests

command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Creating namespaces..."
kubectl create namespace databases --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace hotelier --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Deploying databases..."
kubectl apply -f "$SCRIPT_DIR/postgres/postgres.yaml"
kubectl apply -f "$SCRIPT_DIR/mongo/mongo.yaml"
kubectl apply -f "$SCRIPT_DIR/rabbitmq/rabbitmq.yaml"

echo ""
echo "Deploying monitoring stack..."
kubectl apply -f "$SCRIPT_DIR/prometheus-stack/prometheus.yaml"

DASHBOARDS_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")/etc/grafana/dashboards"
kubectl create configmap grafana-dashboards \
  --from-file="$DASHBOARDS_DIR/services-overview.json" \
  --from-file="$DASHBOARDS_DIR/service-detail.json" \
  --from-file="$DASHBOARDS_DIR/logs-explorer.json" \
  --from-file="$DASHBOARDS_DIR/os-metrics.json" \
  --from-file="$DASHBOARDS_DIR/container-metrics.json" \
  --from-file="$DASHBOARDS_DIR/web-traffic.json" \
  --from-file="$DASHBOARDS_DIR/tracing.json" \
  -n observability --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "$SCRIPT_DIR/prometheus-stack/grafana.yaml"
kubectl apply -f "$SCRIPT_DIR/prometheus-stack/jaeger.yaml"
kubectl apply -f "$SCRIPT_DIR/prometheus-stack/node-exporter.yaml"

echo ""
echo "Deploying Loki and Promtail..."
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update grafana 2>/dev/null || true
helm upgrade --install loki grafana/loki -f "$SCRIPT_DIR/loki/values.yaml" -n observability
helm upgrade --install promtail grafana/promtail -f "$SCRIPT_DIR/promtail/values.yaml" -n observability

echo ""
echo "Installing ServiceMonitor CRD (required by Helm charts)..."
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.75.0/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml

echo ""
echo "Waiting for databases to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/postgresql -n databases || true
kubectl wait --for=condition=available --timeout=120s deployment/mongodb -n databases || true
kubectl wait --for=condition=available --timeout=120s deployment/rabbitmq -n databases || true

HELM_CHARTS_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")/helm-charts"
SECRETS_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")/etc/kubernetes/secrets"

echo ""
echo "Applying secrets..."
kubectl apply -f "$SECRETS_DIR/hotelier-secrets.yaml"

echo ""
echo "Deploying Hotelier microservices with Helm..."
helm upgrade --install identity-service      "$HELM_CHARTS_DIR/hotelier-identity-service"      -f "$SCRIPT_DIR/hotelier-identity-service/values.yaml"      -n hotelier
helm upgrade --install accommodation-service "$HELM_CHARTS_DIR/hotelier-accommodation-service" -f "$SCRIPT_DIR/hotelier-accommodation-service/values.yaml" -n hotelier
helm upgrade --install availability-service  "$HELM_CHARTS_DIR/hotelier-availability-service"  -f "$SCRIPT_DIR/hotelier-availability-service/values.yaml"  -n hotelier
helm upgrade --install reservation-service   "$HELM_CHARTS_DIR/hotelier-reservation-service"   -f "$SCRIPT_DIR/hotelier-reservation-service/values.yaml"   -n hotelier
helm upgrade --install rating-service        "$HELM_CHARTS_DIR/hotelier-rating-service"        -f "$SCRIPT_DIR/hotelier-rating-service/values.yaml"        -n hotelier
helm upgrade --install search-service        "$HELM_CHARTS_DIR/hotelier-search-service"        -f "$SCRIPT_DIR/hotelier-search-service/values.yaml"        -n hotelier
helm upgrade --install notification-service  "$HELM_CHARTS_DIR/hotelier-notification-service"  -f "$SCRIPT_DIR/hotelier-notification-service/values.yaml"  -n hotelier
helm upgrade --install cdn-service           "$HELM_CHARTS_DIR/hotelier-cdn-service"           -f "$SCRIPT_DIR/hotelier-cdn-service/values.yaml"           -n hotelier
helm upgrade --install frontend              "$HELM_CHARTS_DIR/hotelier-frontend"              -f "$SCRIPT_DIR/hotelier-frontend/values.yaml"              -n hotelier

echo ""
echo "Deploying ingress..."
kubectl apply -f "$SCRIPT_DIR/ingress.yaml"

echo ""
echo "============================================"
echo "Setup complete!"
echo "============================================"
echo ""
echo "Access the frontend:"
echo "  1. Add to /etc/hosts (first time only):"
echo "     sudo sh -c 'echo \"127.0.0.1 hotelier.local monitoring.local rabbitmq.local\" >> /etc/hosts'"
echo ""
echo "  2. Port-forward the ingress controller:"
echo "     kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80"
echo ""
echo "  3. Open http://hotelier.local:8080"
echo ""
echo "Other dashboards (via port-forward):"
echo "  Grafana:    kubectl port-forward -n observability svc/grafana 3000:3000"
echo "  Prometheus: kubectl port-forward -n observability svc/prometheus 9090:9090"
echo "  Jaeger:     kubectl port-forward -n observability svc/jaeger 16686:16686"
echo "  RabbitMQ:   kubectl port-forward -n databases svc/rabbitmq 15672:15672"
echo ""
echo "Check status:"
echo "  kubectl get pods -n hotelier"
echo "  kubectl get pods -n databases"
echo "  kubectl get pods -n observability"
echo ""