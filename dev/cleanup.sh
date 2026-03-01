#!/usr/bin/env bash
set -euo pipefail

echo "Cleaning up Hotelier deployment..."

echo "Uninstalling Helm releases..."
for svc in identity-service accommodation-service availability-service reservation-service rating-service search-service notification-service cdn-service frontend; do
    helm uninstall "$svc" -n hotelier 2>/dev/null || true
done
helm uninstall loki -n observability 2>/dev/null || true
helm uninstall promtail -n observability 2>/dev/null || true

echo "Deleting microservices..."
kubectl delete namespace hotelier --ignore-not-found=true

echo "Deleting databases..."
kubectl delete namespace databases --ignore-not-found=true

echo "Deleting monitoring..."
kubectl delete namespace observability --ignore-not-found=true

echo ""
echo "Cleanup complete!"
