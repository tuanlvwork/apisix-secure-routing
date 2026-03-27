# APISIX Secure Routing

A production-pattern microservices stack demonstrating **dual-network routing** and **zero-trust security** with Apache APISIX as the API gateway, NestJS microservices, and Kubernetes (Minikube/GKE) managed through Kustomize.

---

## Architecture

```
                          ┌─────────────────────────────────────────────┐
                          │               Kubernetes Cluster             │
                          │                                              │
  Public Internet         │  ┌──────────── gateway ns ───────────────┐  │
  ─────────────           │  │                                        │  │
  curl :9080  ────────────┼──▶  APISIX :9080  (External / Public)    │  │
                          │  │     │  /external/*  →  no auth        │  │
  Internal Network        │  │     │                                  │  │
  ─────────────           │  │  APISIX :9081  (Internal / Private)   │  │
  curl :9081  ────────────┼──▶     │  /internal/* →  X-API-KEY       │  │
  + X-API-KEY             │  │     │  401 silently rewritten → 404   │  │
                          │  │     │                                  │  │
                          │  │  etcd :2379  (APISIX config store)    │  │
                          │  └──────────────────┬─────────────────────┘  │
                          │                     │ proxy (ClusterIP)      │
                          │  ┌──────── services ─▼─────────────────────┐  │
                          │  │  product-service :3000                  │  │
                          │  │    GET /api/products        (public)    │  │
                          │  │    GET /api/products/admin  (internal)  │  │
                          │  │    GET /api/products/admin/stats        │  │
                          │  └─────────────────────────────────────────┘  │
                          └─────────────────────────────────────────────┘
```

### Port Map

| Port | Listener | Purpose |
|------|----------|---------|
| `9080` | External | Public routes (`/external/*`) — no authentication |
| `9081` | Internal | Private routes (`/internal/*`) — `X-API-KEY` required |
| `9180` | Admin | APISIX Admin API — used by the config Job |
| `3000` | Internal | NestJS ClusterIP — never exposed externally |

**Minikube NodePorts:** `30080` (ext) · `30081` (int) · `31800` (admin)

---

## Stack

| Layer | Technology |
|-------|-----------|
| API Gateway | [Apache APISIX 3.9](https://apisix.apache.org/) |
| Config Store | [etcd 3.5](https://etcd.io/) |
| Backend | [NestJS 10](https://nestjs.com/) (TypeScript) |
| Orchestration | [Kubernetes](https://kubernetes.io/) via [Kustomize](https://kustomize.io/) |
| Local Cluster | [Minikube](https://minikube.sigs.k8s.io/) |
| APISIX Config | Kubernetes `Job` + shell script calling Admin API |

---

## Project Structure

```
apisix-secure-routing/
├── services/
│   └── product-service/            # NestJS microservice
│       ├── src/
│       │   ├── main.ts             # globalPrefix = "api"
│       │   ├── app.module.ts
│       │   └── products/
│       │       ├── products.controller.ts
│       │       ├── products.service.ts
│       │       └── products.module.ts
│       ├── Dockerfile              # Multi-stage, non-root user
│       └── package.json
│
├── k8s/
│   ├── base/                       # Environment-agnostic manifests
│   │   ├── namespaces.yaml         # gateway + services namespaces
│   │   ├── etcd/                   # etcd deployment + service
│   │   ├── apisix/                 # APISIX deployment, configmap, service
│   │   ├── product-service/        # Deployment + ClusterIP service
│   │   ├── apisix-config-job/      # Secret, script ConfigMap, Job
│   │   └── kustomization.yaml
│   │
│   └── overlays/
│       └── local/                  # Minikube overrides
│           ├── patches/
│           │   └── apisix-service-nodeport.yaml
│           └── kustomization.yaml
│
└── scripts/
    └── bootstrap.sh                # One-shot cold-start
```

---

## Architectural Rules

### 1 · Network Separation
Routes are **port-bound** using APISIX's `vars` expression on the built-in `server_port` Nginx variable:

```json
"vars": [["server_port", "==", "9080"]]  // external only
"vars": [["server_port", "==", "9081"]]  // internal only
```

This means an internal route **cannot be reached** from the external port, even with a valid API key.

### 2 · Path Rewriting
APISIX strips the network prefix before forwarding to NestJS:

```
/external/products  ──proxy-rewrite──▶  /api/products
/internal/products  ──proxy-rewrite──▶  /api/products
```

NestJS knows nothing about the gateway prefixes — clean separation of concerns.

### 3 · Security — Hiding Internal Routes (401 → 404)

Unauthorized access to an internal route **must not reveal its existence**.  
We use the `serverless-post-function` plugin in the `header_filter` phase:

```lua
-- Runs AFTER key-auth rejects in the access phase
if ngx.status == 401 then
  ngx.status = 404   -- route is invisible to unauthorized callers
end
```

| Scenario | Expected response |
|----------|-------------------|
| Valid key on `:9081/internal/*` | `200 OK` |
| Missing/wrong key on `:9081/internal/*` | `404 Not Found` ← (not 401) |
| Any request on `:9080/internal/*` | `404 Not Found` (wrong port, no route) |

### 4 · APISIX Configuration — No CRDs
All APISIX routes, upstreams, and consumers are provisioned via a **Kubernetes `Job`** that runs a shell script calling the APISIX Admin REST API. This avoids CRD dependency and works identically in Minikube and GKE.

---

## Quick Start

### Prerequisites

```bash
# Required tools
minikube  >= 1.32
kubectl   >= 1.29
kustomize >= 5.0
docker    >= 24.0
```

### Cold Start (one command)

```bash
git clone <this-repo>
cd apisix-secure-routing
bash scripts/bootstrap.sh
```

The script will:
1. Start Minikube (4 CPU, 4 GB RAM)
2. Build `product-service:latest` inside Minikube's Docker daemon
3. Apply `k8s/overlays/local` via Kustomize
4. Wait for all deployments and the config Job to complete
5. Print verification commands

---

## Verification

```bash
NODE_IP=$(minikube ip)

# ✅ Public endpoint — no auth needed
curl http://${NODE_IP}:30080/external/products

# ✅ Internal endpoint — API key required
curl -H "X-API-KEY: internal-secret-key-CHANGE-IN-PRODUCTION" \
     http://${NODE_IP}:30081/internal/products/admin

# ✅ Admin stats (internal)
curl -H "X-API-KEY: internal-secret-key-CHANGE-IN-PRODUCTION" \
     http://${NODE_IP}:30081/internal/products/admin/stats

# 🔒 Security test — MUST return 404, not 401
curl -sv http://${NODE_IP}:30081/internal/products/admin 2>&1 | grep "< HTTP"
# Expected: < HTTP/1.1 404 Not Found

# 🔒 Port isolation — internal route unreachable on external port
curl -sv http://${NODE_IP}:30080/internal/products/admin 2>&1 | grep "< HTTP"
# Expected: < HTTP/1.1 404 Not Found
```

---

## NestJS Endpoints

| Method | Path | Visibility | Description |
|--------|------|------------|-------------|
| `GET` | `/api/products` | Public | In-stock products only |
| `GET` | `/api/products/admin` | Internal | All products (incl. out-of-stock) |
| `GET` | `/api/products/admin/stats` | Internal | Aggregate stats |
| `GET` | `/api/products/health` | Internal | K8s liveness/readiness probe |

> **Note:** NestJS has no authentication itself. Auth is enforced entirely at the APISIX layer.

---

## Adding a New Service

### 1 · NestJS Controller

```typescript
// apps/my-service/src/orders/orders.controller.ts
@Controller('orders')
export class OrdersController {
  @Get()          // → /api/orders  (public)
  findAll() { ... }

  @Get('admin')   // → /api/orders/admin  (internal)
  findAllAdmin() { ... }
}
```

### 2 · K8s Manifests

```bash
# Create the folder structure (mirror product-service/)
cp -r k8s/base/product-service k8s/base/my-service
# Edit deployment.yaml, service.yaml — update name + namespace
# Add to k8s/base/kustomization.yaml:  - my-service/
```

### 3 · APISIX Config Job

Add to `k8s/base/apisix-config-job/configmap.yaml`:

```bash
# Upstream
apisix_put "upstreams/my-service" '{
  "id": "my-service",
  "type": "roundrobin",
  "nodes": { "my-service.services.svc.cluster.local:3000": 1 }
}'

# External route (port 9080)
apisix_put "routes/orders-external" '{
  "uri": "/external/orders*",
  "vars": [["server_port", "==", "9080"]],
  "methods": ["GET"],
  "plugins": {
    "proxy-rewrite": { "regex_uri": ["/external/(.*)", "/api/$1"] }
  },
  "upstream_id": "my-service"
}'

# Internal route (port 9081) — with 401→404 security
apisix_put "routes/orders-internal" '{
  "uri": "/internal/orders*",
  "vars": [["server_port", "==", "9081"]],
  "plugins": {
    "key-auth": { "header": "X-API-KEY" },
    "proxy-rewrite": { "regex_uri": ["/internal/(.*)", "/api/$1"] },
    "serverless-post-function": {
      "phase": "header_filter",
      "functions": ["return function(conf, ctx)\n  if ngx.status == 401 then\n    ngx.status = 404\n  end\nend"]
    }
  },
  "upstream_id": "my-service"
}'
```

---

## Secrets Management

> ⚠️ The default keys in `secret.yaml` are **for local development only**.

In production (GKE), replace the Kubernetes Secret with values from **Google Secret Manager** or **Vault**, and seal them with **Sealed Secrets** or **External Secrets Operator**.

| Secret key | Purpose | Default (dev) |
|---|---|---|
| `admin-key` | APISIX Admin API auth | `supersecretadminkey` |
| `internal-api-key` | Consumer API key for internal callers | `internal-secret-key-CHANGE-IN-PRODUCTION` |

---

## Useful Commands

```bash
# View APISIX logs
kubectl logs -n gateway deployment/apisix -f

# View config Job logs
kubectl logs -n gateway job/apisix-config-job

# Rerun config Job (after a route change)
kubectl delete job apisix-config-job -n gateway
kubectl apply -k k8s/overlays/local

# List all APISIX routes (from host)
NODE_IP=$(minikube ip)
curl -H "X-API-KEY: supersecretadminkey" \
     http://${NODE_IP}:31800/apisix/admin/routes | jq .

# Tear down
minikube delete
```

---

## License

MIT
