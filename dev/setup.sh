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
kubectl apply -f "$SCRIPT_DIR/prometheus-stack/grafana.yaml"

echo ""
echo "Installing ServiceMonitor CRD (required by Helm charts)..."
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.75.0/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml

echo ""
echo "Waiting for databases to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/postgresql -n databases || true
kubectl wait --for=condition=available --timeout=120s deployment/mongodb -n databases || true
kubectl wait --for=condition=available --timeout=120s deployment/rabbitmq -n databases || true

HELM_CHARTS_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")/helm-charts"

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

echo ""
echo "Deploying ingress..."
kubectl apply -f "$SCRIPT_DIR/ingress.yaml"

echo ""
echo "============================================"
echo "Setup complete!"
echo "============================================"
echo ""
echo "Access services:"
echo "  - Hotelier API: http://hotelier.local/{service}"
echo "  - Grafana: http://monitoring.local/grafana (admin/admin)"
echo "  - Prometheus: http://monitoring.local/prometheus"
echo "  - RabbitMQ: http://rabbitmq.local (guest/guest)"
echo ""
echo "Add to /etc/hosts:"
echo "  127.0.0.1 hotelier.local monitoring.local rabbitmq.local"
echo ""
echo "Check status:"
echo "  kubectl get pods -n hotelier"
echo "  kubectl get pods -n databases"
echo "  kubectl get pods -n observability"
echo ""