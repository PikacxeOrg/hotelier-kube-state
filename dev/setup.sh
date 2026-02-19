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
echo "Waiting for databases to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/postgresql -n databases || true
kubectl wait --for=condition=available --timeout=120s deployment/mongodb -n databases || true
kubectl wait --for=condition=available --timeout=120s deployment/rabbitmq -n databases || true

echo ""
echo "Deploying Hotelier microservices..."
kubectl apply -f "$SCRIPT_DIR/hotelier-identity-service/identity-service.yaml"
kubectl apply -f "$SCRIPT_DIR/hotelier-accommodation-service/accommodation-service.yaml"
kubectl apply -f "$SCRIPT_DIR/hotelier-availability-service/availability-service.yaml"
kubectl apply -f "$SCRIPT_DIR/hotelier-reservation-service/reservation-service.yaml"
kubectl apply -f "$SCRIPT_DIR/hotelier-rating-service/rating-service.yaml"
kubectl apply -f "$SCRIPT_DIR/hotelier-search-service/search-service.yaml"
kubectl apply -f "$SCRIPT_DIR/hotelier-notification-service/notification-service.yaml"
kubectl apply -f "$SCRIPT_DIR/hotelier-cdn-service/cdn-service.yaml"

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