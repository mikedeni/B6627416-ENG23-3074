# =============================================================================
# Makefile — K8S Infrastructure MVP
# Kind + Nginx + PostgreSQL + Jenkins + Prometheus + Grafana
# =============================================================================
# Usage: make <target>
# Run `make` or `make help` to see all available targets.

# -----------------------------------------------------------------------------
# Configuration (override with: make <target> CLUSTER_NAME=myname)
# -----------------------------------------------------------------------------
CLUSTER_NAME  ?= mycluster
KUBECTL       ?= kubectl
KIND          ?= kind
NAMESPACE_MON ?= monitoring

# Colors (ANSI)
RESET  := \033[0m
BOLD   := \033[1m
GREEN  := \033[32m
YELLOW := \033[33m
CYAN   := \033[36m
RED    := \033[31m

# -----------------------------------------------------------------------------
# Default target — show help
# -----------------------------------------------------------------------------
.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help message
	@printf "$(BOLD)Usage:$(RESET) make $(CYAN)<target>$(RESET)\n\n"
	@printf "$(BOLD)Variables (override with make <target> VAR=value):$(RESET)\n"
	@printf "  CLUSTER_NAME  = $(CLUSTER_NAME)\n"
	@printf "  KUBECTL       = $(KUBECTL)\n"
	@printf "  KIND          = $(KIND)\n\n"
	@printf "$(BOLD)Targets:$(RESET)\n"
	@awk 'BEGIN {FS = ":.*##"} \
		/^[a-zA-Z_-]+:.*?##/ { printf "  $(CYAN)%-22s$(RESET) %s\n", $$1, $$2 } \
		/^##@/ { printf "\n$(BOLD)%s$(RESET)\n", substr($$0,5) }' $(MAKEFILE_LIST)

# =============================================================================
##@ Cluster
# =============================================================================

.PHONY: cluster-create
cluster-create: ## Create Kind cluster with port 80/443 exposed (uses kind-config.yaml)
	@printf "$(GREEN)Creating Kind cluster: $(CLUSTER_NAME)...$(RESET)\n"
	$(KIND) create cluster --name $(CLUSTER_NAME) --config=kind-config.yaml

.PHONY: cluster-delete
cluster-delete: ## Delete Kind cluster (DESTRUCTIVE — prompts for confirmation)
	@printf "$(RED)This will DELETE cluster '$(CLUSTER_NAME)' and all its data.$(RESET)\n"
	@printf "Press Ctrl-C to cancel, or Enter to continue..."; read _
	$(KIND) delete cluster --name $(CLUSTER_NAME)

.PHONY: cluster-status
cluster-status: ## Show cluster info and node status
	@printf "$(CYAN)--- Cluster Info ---$(RESET)\n"
	$(KUBECTL) cluster-info
	@printf "\n$(CYAN)--- Nodes ---$(RESET)\n"
	$(KUBECTL) get nodes -o wide

.PHONY: cluster-start
cluster-start: ## Start existing Kind cluster (start stopped Docker containers)
	@printf "$(GREEN)Starting Kind cluster containers...$(RESET)\n"
	docker start $$(docker ps -aq --filter "name=$(CLUSTER_NAME)")

.PHONY: cluster-stop
cluster-stop: ## Stop Kind cluster (pause Docker containers, preserves data)
	@printf "$(YELLOW)Stopping Kind cluster containers...$(RESET)\n"
	docker stop $$(docker ps -q --filter "name=$(CLUSTER_NAME)")

# =============================================================================
##@ Setup (run once after cluster-create)
# =============================================================================

.PHONY: ingress-install
ingress-install: ## Install Nginx Ingress Controller and wait for ready
	@printf "$(GREEN)Installing Nginx Ingress Controller...$(RESET)\n"
	$(KUBECTL) apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
	$(KUBECTL) wait --namespace ingress-nginx \
		--for=condition=ready pod \
		--selector=app.kubernetes.io/component=controller \
		--timeout=120s

.PHONY: hosts-setup
hosts-setup: ## Add .local domains to /etc/hosts (requires sudo)
	@printf "$(GREEN)Adding .local domains to /etc/hosts...$(RESET)\n"
	@grep -q "my-nginx.local" /etc/hosts \
		&& printf "$(YELLOW)Entries already exist in /etc/hosts — skipping.$(RESET)\n" \
		|| (echo "127.0.0.1  my-nginx.local jenkins.local grafana.local" | sudo tee -a /etc/hosts \
			&& printf "$(GREEN)Done.$(RESET)\n")

.PHONY: namespace-create
namespace-create: ## Create required namespaces
	$(KUBECTL) create namespace $(NAMESPACE_MON) --dry-run=client -o yaml | $(KUBECTL) apply -f -

.PHONY: setup
setup: ingress-install hosts-setup namespace-create ## Run all one-time setup steps (ingress + hosts + namespaces)
	@printf "$(GREEN)Setup complete.$(RESET)\n"

# =============================================================================
##@ Deploy
# =============================================================================

.PHONY: deploy-postgres
deploy-postgres: ## Deploy PostgreSQL (PV, PVC, Secret, Deployment, Service, NetworkPolicy)
	@printf "$(GREEN)Deploying PostgreSQL...$(RESET)\n"
	$(KUBECTL) apply -f postgresql/

.PHONY: _wait-ingress-webhook
_wait-ingress-webhook:
	@printf "$(YELLOW)Waiting for ingress-nginx admission webhook...$(RESET)\n"
	@$(KUBECTL) wait --namespace ingress-nginx \
		--for=condition=ready pod \
		--selector=app.kubernetes.io/component=controller \
		--timeout=60s 2>/dev/null || true

.PHONY: deploy-nginx
deploy-nginx: _wait-ingress-webhook ## Deploy Nginx (Deployment, Service, Ingress)
	@printf "$(GREEN)Deploying Nginx...$(RESET)\n"
	$(KUBECTL) apply -f nginx/deployment/
	$(KUBECTL) apply -f nginx/service/
	$(KUBECTL) apply -f nginx/ingress/

.PHONY: deploy-jenkins
deploy-jenkins: ## Deploy Jenkins (PVC, Deployment, Service, Ingress)
	@printf "$(GREEN)Deploying Jenkins...$(RESET)\n"
	$(KUBECTL) apply -f jenkins/

.PHONY: deploy-monitoring
deploy-monitoring: ## Deploy Prometheus + Grafana
	@printf "$(GREEN)Deploying monitoring stack...$(RESET)\n"
	$(KUBECTL) apply -f monitoring/

.PHONY: deploy-all
deploy-all: deploy-postgres deploy-nginx deploy-jenkins deploy-monitoring ## Deploy all services
	@printf "$(GREEN)All services deployed.$(RESET)\n"

.PHONY: undeploy-all
undeploy-all: ## Remove all deployed resources (keeps cluster running)
	@printf "$(YELLOW)Removing all deployed resources...$(RESET)\n"
	$(KUBECTL) delete -f monitoring/   --ignore-not-found
	$(KUBECTL) delete -f jenkins/      --ignore-not-found
	$(KUBECTL) delete -f nginx/ingress/ --ignore-not-found
	$(KUBECTL) delete -f nginx/service/ --ignore-not-found
	$(KUBECTL) delete -f nginx/deployment/ --ignore-not-found
	$(KUBECTL) delete -f postgresql/   --ignore-not-found

# =============================================================================
##@ Status & Verification
# =============================================================================

.PHONY: status
status: ## Show status of all pods, services, and ingresses
	@printf "$(CYAN)--- Pods (all namespaces) ---$(RESET)\n"
	$(KUBECTL) get pods -A
	@printf "\n$(CYAN)--- Services (all namespaces) ---$(RESET)\n"
	$(KUBECTL) get svc -A
	@printf "\n$(CYAN)--- Ingresses ---$(RESET)\n"
	$(KUBECTL) get ingress -A

.PHONY: watch
watch: ## Watch pod status live
	$(KUBECTL) get pods -A -w

.PHONY: events
events: ## Show recent Kubernetes events (warnings first)
	$(KUBECTL) get events -A --sort-by='.lastTimestamp'

# =============================================================================
##@ Logs
# =============================================================================

.PHONY: logs-nginx
logs-nginx: ## Tail logs from Nginx pods
	$(KUBECTL) logs -l app=my-nginx --tail=100 -f

.PHONY: logs-jenkins
logs-jenkins: ## Tail logs from Jenkins pod
	$(KUBECTL) logs -l app=jenkins --tail=100 -f

.PHONY: logs-postgres
logs-postgres: ## Tail logs from PostgreSQL pod
	$(KUBECTL) logs -l app=postgres --tail=100 -f

.PHONY: logs-grafana
logs-grafana: ## Tail logs from Grafana pod
	$(KUBECTL) logs -n $(NAMESPACE_MON) -l app=grafana --tail=100 -f

.PHONY: logs-prometheus
logs-prometheus: ## Tail logs from Prometheus pod
	$(KUBECTL) logs -n $(NAMESPACE_MON) -l app=prometheus --tail=100 -f

.PHONY: logs-ingress
logs-ingress: ## Tail logs from Nginx Ingress Controller
	$(KUBECTL) logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=100 -f

# =============================================================================
##@ Access & Utilities
# =============================================================================

.PHONY: jenkins-password
jenkins-password: ## Print Jenkins initial admin password
	@printf "$(CYAN)Jenkins initial admin password:$(RESET)\n"
	$(KUBECTL) exec -it \
		$$($(KUBECTL) get pod -l app=jenkins -o jsonpath='{.items[0].metadata.name}') \
		-- cat /var/jenkins_home/secrets/initialAdminPassword

.PHONY: port-forward
port-forward: ## Start port-forward fallback on localhost:8080 (for clusters without extraPortMappings)
	@printf "$(YELLOW)Forwarding ingress-nginx to localhost:8080 — access services on port 8080$(RESET)\n"
	$(KUBECTL) port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80

.PHONY: shell-postgres
shell-postgres: ## Open psql shell inside PostgreSQL pod (user read from Secret)
	$(KUBECTL) exec -it \
		$$($(KUBECTL) get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}') \
		-- psql -U $$($(KUBECTL) get secret postgres-secret \
			-o jsonpath='{.data.POSTGRES_USER}' | base64 -d)

.PHONY: describe-ingress
describe-ingress: ## Describe all ingress resources
	$(KUBECTL) describe ingress -A

# =============================================================================
##@ Full Lifecycle
# =============================================================================

.PHONY: up
up: cluster-create setup deploy-all ## Full bring-up: create cluster + setup + deploy everything
	@printf "\n$(GREEN)$(BOLD)Infrastructure is up!$(RESET)\n"
	@printf "  Nginx:   http://my-nginx.local\n"
	@printf "  Jenkins: http://jenkins.local\n"
	@printf "  Grafana: http://grafana.local  (admin/admin)\n"

.PHONY: down
down: cluster-delete ## Full teardown: delete cluster (DESTRUCTIVE)

.PHONY: restart
restart: undeploy-all deploy-all ## Re-deploy all services without recreating cluster
	@printf "$(GREEN)All services restarted.$(RESET)\n"
