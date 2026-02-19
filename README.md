# Hotelier Kubernetes Setup (Simplified MVP)

This directory contains simplified Kubernetes manifests for deploying the Hotelier microservices platform. This setup is designed for university projects and local development - it uses plain Kubernetes YAML files without external Helm charts.

**⚠️ IMPORTANT**: This setup works WITHOUT requiring implemented microservices. Health checks have been removed to allow pods to start even with stub/empty services.

## Prerequisites

- Kubernetes cluster (minikube, kind, k3s, or Docker Desktop)
- kubectl CLI tool
- Ingress controller (nginx-ingress recommended)

## Quick Start

### 1. Enable Ingress (for minikube)

```bash
minikube addons enable ingress
```

For other Kubernetes distributions, install nginx-ingress:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
```

### 2. Build and Load Docker Images

Build all service images:

```bash
cd /home/x/Projects/hotelier

# Build each service
for service in accommodation availability cdn identity notification rating reservation search; do
  docker build -t hotelier-${service}-service:latest services/${service}-service/
done
```

Load images into minikube (if using minikube):

```bash
for service in accommodation availability cdn identity notification rating reservation search; do
  minikube image load hotelier-${service}-service:latest
done
```

### 3. Deploy Everything

```bash
cd kube-state/dev
chmod +x setup.sh
./setup.sh
```

### 4. Configure Local DNS

Add these entries to your `/etc/hosts` (or `C:\Windows\System32\drivers\etc\hosts` on Windows):

```
127.0.0.1 hotelier.local monitoring.local rabbitmq.local
```

If using minikube, get the IP first:

```bash
minikube ip
```

Then use that IP instead of 127.0.0.1.

### 5. Access Services

- **Hotelier APIs**: 
  - http://hotelier.local/identity/health
  - http://hotelier.local/accommodation/health
  - http://hotelier.local/availability/health
  - http://hotelier.local/reservation/health
  - http://hotelier.local/rating/health
  - http://hotelier.local/search/health
  - http://hotelier.local/notification/health
  - http://hotelier.local/cdn/health

- **Monitoring**:
  - Grafana: http://monitoring.local/grafana (admin/admin)
  - Prometheus: http://monitoring.local/prometheus

- **Message Queue**:
  - RabbitMQ Management: http://rabbitmq.local (guest/guest)

## Architecture

### Namespaces

- `hotelier` - Microservices
- `databases` - PostgreSQL, MongoDB, RabbitMQ
- `observability` - Prometheus, Grafana

### Services

All microservices run with:
- 1 replica
- **NO health checks** (works without implemented `/health` endpoints)
- Prometheus metrics annotations (optional - doesn't break if metrics not available)
- Resource limits: 1 CPU, 1GB RAM
- Resource requests: 250m CPU, 256MB RAM

### Databases

**PostgreSQL**:
- Creates separate databases for each service
- User: `hotelier` / Password: `hotelier`
- Port: 5432

**MongoDB**:
- No authentication (dev mode)
- Port: 27017

**RabbitMQ**:
- User: `guest` / Password: `guest`
- AMQP Port: 5672
- Management UI: 15672

## Useful Commands

### Check Status

```bash
# All pods
kubectl get pods --all-namespaces

# Specific namespace
kubectl get pods -n hotelier
kubectl get pods -n databases
kubectl get pods -n observability

# Services
kubectl get svc -n hotelier
kubectl get ingress -n hotelier
```

### View Logs

```bash
# Service logs
kubectl logs -n hotelier deployment/identity-service -f

# Database logs
kubectl logs -n databases deployment/postgresql -f
kubectl logs -n databases deployment/rabbitmq -f
```

### Debug Pod

```bash
# Exec into a pod
kubectl exec -it -n hotelier deployment/identity-service -- /bin/sh

# Check connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -n hotelier -- sh
# Then inside: wget -O- http://postgresql.databases:5432
```

### Port Forwarding (Alternative Access)

If ingress is not working, use port forwarding:

```bash
# Forward service
kubectl port-forward -n hotelier svc/identity-service 8080:80

# Forward Grafana
kubectl port-forward -n observability svc/grafana 3000:3000

# Forward RabbitMQ
kubectl port-forward -n databases svc/rabbitmq 15672:15672
```

## Cleanup

Remove all resources:

```bash
chmod +x cleanup.sh
./cleanup.sh
```

Or manually:

```bash
kubectl delete namespace hotelier databases observability
```

## Troubleshooting

### Pods not starting

Check events:
```bash
kubectl describe pod <pod-name> -n <namespace>
```

### Image pull errors

If using minikube, make sure images are loaded:
```bash
minikube image ls | grep hotelier
```

### Database connection issues

Check if databases are running:
```bash
kubectl get pods -n databases
kubectl logs -n databases deployment/postgresql
```

Test connectivity from a service pod:
```bash
kubectl exec -it -n hotelier deployment/identity-service -- /bin/sh
# Try: ping postgresql.databases.svc.cluster.local
```

### Ingress not working

Check ingress controller:
```bash
kubectl get pods -n ingress-nginx
```

Check ingress resources:
```bash
kubectl get ingress -n hotelier
kubectl describe ingress hotelier-ingress -n hotelier
```

## Customization

To modify configurations:

1. **Resources**: Edit the `resources` section in each service YAML
2. **Environment**: Add/modify `env` variables in deployment specs
3. **Replicas**: Change `replicas: 1` to scale services
4. **Ingress paths**: Edit `ingress.yaml`
