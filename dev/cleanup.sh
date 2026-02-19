#!/usr/bin/env bash
set -euo pipefail

echo "Cleaning up Hotelier deployment..."

echo "Deleting microservices..."
kubectl delete namespace hotelier --ignore-not-found=true

echo "Deleting databases..."
kubectl delete namespace databases --ignore-not-found=true

echo "Deleting monitoring..."
kubectl delete namespace observability --ignore-not-found=true

echo ""
echo "Cleanup complete!"
