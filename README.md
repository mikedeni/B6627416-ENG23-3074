# K8S Infrastructure MVP: Nginx + Postgres + Jenkins + Monitoring

A production-ready Kubernetes infrastructure boilerplate running on **Kind** (Kubernetes in Docker). This project includes a web server, database, automated CI/CD pipeline, and full observability — all accessible via `.local` domains.

---

## System Architecture

- **Frontend/Proxy**: Nginx (3 Replicas) with Ingress Controller — `my-nginx.local`
- **Database**: PostgreSQL with Persistent Volume (PV) and Secrets management.
- **CI/CD**: Jenkins Pipeline (`Jenkinsfile`) — `jenkins.local`
- **Observability**: Prometheus (Data collection) & Grafana (Visualization) — `grafana.local`

---

## Quick Start (Kind Cluster)

### 1. Create Cluster with Ingress Support

Run this command to create a Kind cluster with ports 80 and 443 exposed to the host:

```bash
cat <<EOF | kind create cluster --name mycluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
```

### 2. Install Nginx Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
```

### 3. Add `.local` Domains to `/etc/hosts`

```bash
echo "127.0.0.1  my-nginx.local jenkins.local grafana.local" | sudo tee -a /etc/hosts
```

### 4. Deploy Everything

```bash
# Deploy Postgres & Nginx
kubectl apply -f postgresql/
kubectl apply -f nginx/deployment/
kubectl apply -f nginx/service/
kubectl apply -f nginx/ingress/

# Deploy Jenkins
kubectl apply -f jenkins/

# Deploy Monitoring (Prometheus + Grafana)
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f monitoring/
```

### 5. Verify All Pods Are Running

```bash
kubectl get pods -A
kubectl get ingress -A
```

---

## Accessing the Services

All services are accessible via Ingress through `.local` domains. If your cluster was created **without** `extraPortMappings` (port 80 not exposed), use the [Port-Forward fallback](#port-forward-fallback-existing-cluster) below.

### Web Application — `my-nginx.local`

Visit: **http://my-nginx.local**

### Jenkins CI/CD — `jenkins.local`

Visit: **http://jenkins.local**

> First-time setup: retrieve the admin password with:
> ```bash
> kubectl exec -it $(kubectl get pod -l app=jenkins -o jsonpath='{.items[0].metadata.name}') -- cat /var/jenkins_home/secrets/initialAdminPassword
> ```

![Jenkins Dashboard](images/jenkins.jpeg)

![Jenkins Nodes](images/jenkins-nodes.png)

### Grafana Monitoring — `grafana.local`

Visit: **http://grafana.local**

Default credentials: `admin` / `admin`

> Prometheus data source URL (add in Grafana): `http://prometheus-service.monitoring.svc.cluster.local`

![Grafana Dashboard](images/grafana.jpeg)

---

## Port-Forward Fallback (Existing Cluster)

If your cluster does **not** have port 80 mapped to the host (i.e. created without `extraPortMappings`), forward the Ingress controller instead:

```bash
# Forward all ingress traffic to localhost:8080
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80 &
```

Then add this to `/etc/hosts`:

```
127.0.0.1  my-nginx.local jenkins.local grafana.local
```

Access services on port 8080:
- **http://my-nginx.local:8080**
- **http://jenkins.local:8080**
- **http://grafana.local:8080**

---

## Directory Structure

```text
├── nginx/
│   ├── deployment/   # Nginx Deployment (3 replicas, unprivileged)
│   ├── service/      # ClusterIP Service
│   └── ingress/      # Ingress rule -> my-nginx.local
├── postgresql/       # PV, PVC, Secret, Deployment, Service, NetworkPolicy
├── jenkins/
│   ├── jenkins.yaml  # Deployment + Service
│   ├── jenkins-pvc.yaml
│   └── ingress.yaml  # Ingress rule -> jenkins.local
├── monitoring/
│   ├── prometheus.yaml        # Prometheus Deployment + Service + ConfigMap
│   ├── grafana.yaml           # Grafana Deployment + Service
│   └── grafana-ingress.yaml   # Ingress rule -> grafana.local
└── Jenkinsfile       # CI/CD pipeline definition
```

---

## Maintenance & Verification

```bash
# Check all resources
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A

# Watch pod status
kubectl get pods -w

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
```

---

## Ingress Summary

| Domain | Service | Namespace |
|--------|---------|-----------|
| `my-nginx.local` | `nginx-service:80` | default |
| `jenkins.local` | `jenkins-service:8080` | default |
| `grafana.local` | `grafana-service:80` | monitoring |
