# APISIX Secure Routing

A production-pattern microservices stack demonstrating **dual-network routing** and **zero-trust security** with Apache APISIX as the API gateway, NestJS microservices, and Kubernetes (Minikube/GKE) managed through Kustomize.

---

## Architecture

```
                          ┌─────────────────────────────────────────────────────────────┐
                          │                    Kubernetes Cluster                        │
                          │                                                              │
  Public Internet         │  ┌──────────────────── gateway ns ──────────────────────┐  │
  ─────────────           │  │                                                      │  │
  curl :9080  ────────────┼──▶  apisix (data plane)  :9080  Public routes           │  │
                          │  │  role: data_plane       :9081  Internal routes        │  │
  Internal Network        │  │                                                      │  │
  ─────────────           │  │  apisix-admin (control) :9180  Admin API + Admin UI  │  │
  curl :9081  ────────────┼──▶  role: control_plane           http://<ip>:9180/ui   │  │
  + X-API-KEY             │  │                                                      │  │
                          │  │     ↕ both read/write shared etcd :2379              │  │
                          │  └────────────────────┬─────────────────────────────────┘  │
                          │                       │ proxy (ClusterIP)                   │
                          │  ┌──────── services ──▼──────────────────────────────────┐ │
                          │  │  product-service :3000                                │ │
                          │  │    GET /api/public/products   (public routes)         │ │
                          │  │    GET /api/internal/products (internal routes)       │ │
                          │  │    GET /api/internal/products/stats                   │ │
                          │  │    GET /api/health            (K8s probe)             │ │
                          │  └───────────────────────────────────────────────────────┘ │
                          └─────────────────────────────────────────────────────────────┘
```

### Port Map

| Port | Pod | Purpose |
|------|-----|---------|
| `9080` | `apisix` (data plane) | Public routes (`/external/*`) — no authentication |
| `9081` | `apisix` (data plane) | Private routes (`/internal/*`) — `X-API-KEY` required |
| `9180` | `apisix-admin` (control plane) | Admin REST API + Admin UI (`/ui`) |
| `3000` | `product-service` | NestJS ClusterIP — never exposed externally |

**Minikube NodePorts:** `30080` (ext) · `30081` (int) · `31800` (admin UI at `:31800/ui`)

---

## Stack

| Layer | Technology |
|-------|-----------|
| API Gateway | [Apache APISIX 3.15](https://apisix.apache.org/) (split-plane: data + control) |
| Config Store | [etcd 3.5](https://etcd.io/) |
| Backend | [NestJS 10](https://nestjs.com/) (TypeScript) |
| Orchestration | [Kubernetes](https://kubernetes.io/) via [Kustomize](https://kustomize.io/) |
| Local Cluster | [Minikube](https://minikube.sigs.k8s.io/) |
| APISIX Config | Kubernetes `Job` + shell script calling Admin API |

---

## Project Structure

```
apisix-secure-routing/
├── apps/
│   └── product-service/            # NestJS microservice
│       ├── src/
│       │   ├── main.ts             # globalPrefix = "api"
│       │   ├── app.module.ts
│       │   └── products/
│       │       ├── products.controller.ts  # PublicProductsController
│       │       │                           # InternalProductsController
│       │       │                           # HealthController
│       │       ├── products.service.ts
│       │       └── products.module.ts
│       ├── Dockerfile              # Multi-stage, non-root user
│       └── package.json
│
├── k8s/
│   ├── base/                       # Environment-agnostic manifests
│   │   ├── namespaces.yaml         # gateway + services namespaces
│   │   ├── etcd/                   # etcd deployment + service
│   │   ├── apisix/                 # Data plane  (role: data_plane)
│   │   │                           #   ports 9080 + 9081, enable_admin: false
│   │   ├── apisix-admin/           # Control plane (role: control_plane)
│   │   │                           #   port 9180, Admin API + Admin UI (/ui)
│   │   ├── product-service/        # Deployment + ClusterIP service
│   │   ├── apisix-config-job/      # Secret, script ConfigMap, Job
│   │   └── kustomization.yaml
│   │
│   └── overlays/
│       └── local/                  # Minikube overrides
│           ├── patches/
│           │   ├── apisix-service-nodeport.yaml    # 30080/30081
│           │   └── apisix-admin-nodeport.yaml      # 31800
│           └── kustomization.yaml
│
└── scripts/
    ├── bootstrap.sh                # One-shot cold-start
    └── rollout-config-job.sh       # Re-apply APISIX routes after changes
```

---

## Security Architecture

### Route Flow Diagram

```
┌─────────────────────────── EXTERNAL (Public) ── NodePort 30080 ─────────────────────────────────────┐
│                                                                                                     │
│  Client          apisix :9080                  proxy-rewrite         product-service:3000           │
│  curl :30080     route: product-external        /external/(.*)        /api/public/*                 │
│                  vars: server_port==9080     →  /api/public/$1                                      │
│                                                                                                     │
│  ──GET /external/*──▶  [ match port 9080 ] ──▶ [ rewrite path ] ──▶  GET /api/public/products.      |
│    (no auth)                                                           GET /api/public/products/:id |
│                                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────── INTERNAL (Private) ── NodePort 30081 ───────────────────────────────────────────┐
│                                                                                                            │
│  Service         apisix :9081                  key-auth              proxy-rewrite                         │
│  curl :30081     route: product-internal        X-API-KEY header      /internal/(.*)                       │
│                  vars: server_port==9081        (consumer: internal_client)  /api/internal/$1              │
│                                                                                                            │
│                                                  ┌── missing/bad key                                       │
│  ──GET /internal/*──▶  [ match port 9081 ] ──▶  ─┤                                                         │
│    X-API-KEY: <key>                              │    serverless-post-function                             │
│                                                  │    401 ──────────────────▶ 404                          │
│                                                  │    (route existence hidden)                             │
│                                                  │                                                         │
│                                                  └── valid key                                             │
│                                                     [ rewrite path ] ──▶  GET /api/internal/products.      |
│                                                     [ rewrite path ] ──▶  GET /api/internal/products/stats |
│                                                                                                            │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

                     ▼ both lanes proxy to the same upstream ▼

            ┌──────────────────────────────────────────────────┐
            │  product-service.services.svc.cluster.local:3000 │
            │  active healthcheck: GET /api/health             │
            └──────────────────────────────────────────────────┘
```

> **Namespace isolation guarantee:** `proxy-rewrite` maps each port to a *disjoint* NestJS path prefix.
> A request on `:9080/external/internal/products` rewrites to `/api/public/internal/products` — the `/api/internal/*` namespace is unreachable from the public port by construction.

### 1 · Network Separation (Port Binding)

Routes are **port-bound** using APISIX's `vars` expression on the built-in `server_port` Nginx variable:

```json
"vars": [["server_port", "==", "9080"]]  // external only
"vars": [["server_port", "==", "9081"]]  // internal only
```

An internal route **cannot be reached** from the external port, even with a valid API key.

### 2 · Namespace Isolation (proxy-rewrite)

APISIX routes each port to a **separate NestJS path namespace**:

```
Port 9080:  /external/*  ──proxy-rewrite──▶  /api/public/*
Port 9081:  /internal/*  ──proxy-rewrite──▶  /api/internal/*
```

The two namespaces are **disjoint** — they can never overlap.

**Why wildcards are safe:** even if an attacker on port 9080 tries to guess an internal path:

```
GET :9080/external/internal/products
  → proxy-rewrite → /api/public/internal/products   ← wrong namespace → 404
```

NestJS never sees a request for `/api/internal/*` from the external port. This means you can add unlimited endpoints to either namespace **without touching APISIX config** — the wildcard covers everything automatically.

### 3 · Key Authentication (port 9081)

All requests on port 9081 must carry a valid `X-API-KEY` header, validated by APISIX's `key-auth` plugin before the request reaches NestJS.

### 4 · Route Stealth (401 → 404)

Unauthorized access to an internal route must not reveal its existence. The `serverless-post-function` plugin rewrites `401` to `404` in the `header_filter` phase:

```lua
if ngx.status == 401 then
  ngx.status = 404   -- route is invisible to unauthorized callers
end
```

| Scenario | Response |
|----------|----------|
| Valid key on `:9081/internal/*` | `200 OK` |
| Missing/wrong key on `:9081/internal/*` | `404 Not Found` ← (not 401) |
| Any request on `:9080` for an unmapped path | `404 Not Found` |

### 5 · APISIX Configuration — No CRDs

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

# ✅ Internal endpoint — full inventory (API key required)
curl -H "X-API-KEY: internal-secret-key-CHANGE-IN-PRODUCTION" \
     http://${NODE_IP}:30081/internal/products

# ✅ Internal stats endpoint
curl -H "X-API-KEY: internal-secret-key-CHANGE-IN-PRODUCTION" \
     http://${NODE_IP}:30081/internal/products/stats

# 🔒 Security test — no key → MUST return 404, not 401
curl -sv http://${NODE_IP}:30081/internal/products 2>&1 | grep "< HTTP"
# Expected: < HTTP/1.1 404 Not Found

# 🔒 Namespace isolation — hacker guesses /internal path via public port
curl -sv http://${NODE_IP}:30080/external/internal/products 2>&1 | grep "< HTTP"
# Expected: < HTTP/1.1 404 Not Found  (different namespace, never reaches NestJS)

# 🔒 Port isolation — internal port returns 404 with no route match
curl -sv http://${NODE_IP}:30080/internal/products 2>&1 | grep "< HTTP"
# Expected: < HTTP/1.1 404 Not Found  (no route bound to port 9080 for /internal/*)
```

---

## NestJS Endpoints

NestJS uses a global prefix `/api`. Controllers are split by namespace:

| Controller | NestJS Path | Gateway Path | Visibility |
|------------|-------------|--------------|------------|
| `PublicProductsController` | `GET /api/public/products` | `:9080/external/products` | Public — in-stock products only |
| `InternalProductsController` | `GET /api/internal/products` | `:9081/internal/products` | Internal — full inventory |
| `InternalProductsController` | `GET /api/internal/products/stats` | `:9081/internal/products/stats` | Internal — aggregate stats |
| `HealthController` | `GET /api/health` | Not exposed via APISIX | K8s liveness/readiness probe |

> **Note:** NestJS has no authentication itself. Auth is enforced entirely at the APISIX layer before NestJS is ever called.

---

## Adding a New Service

The namespace convention scales to unlimited services with **zero changes to APISIX config**.

### 1 · NestJS Controllers (follow the namespace convention)

```typescript
// apps/my-service/src/orders/orders.controller.ts

@Controller('public/orders')         // → /api/public/orders
export class PublicOrdersController {
  @Get()                             // GET /api/public/orders
  findAll() { ... }
}

@Controller('internal/orders')       // → /api/internal/orders
export class InternalOrdersController {
  @Get()                             // GET /api/internal/orders    (full list)
  findAll() { ... }

  @Get('stats')                      // GET /api/internal/orders/stats
  getStats() { ... }
}
```

Because the APISIX external route already matches `/external/*` → `/api/public/*` and internal matches `/internal/*` → `/api/internal/*`, **these endpoints are live the moment NestJS deploys** — no APISIX update required.

### 2 · K8s Manifests

```bash
# Mirror the product-service structure
cp -r k8s/base/product-service k8s/base/my-service
# Edit deployment.yaml, service.yaml — update name, namespace, image
# Add to k8s/base/kustomization.yaml:  - my-service/
```

### 3 · APISIX Upstream (only needed for a new upstream, not new endpoints)

Add to `k8s/base/apisix-config-job/configmap.yaml`:

```bash
# New upstream only — no new routes needed!
apisix_put "upstreams/my-service" '{
  "id": "my-service",
  "type": "roundrobin",
  "nodes": { "my-service.services.svc.cluster.local:3000": 1 }
}'

# Route external (port 9080) to the new upstream
apisix_put "routes/orders-external" '{
  "uri": "/external/orders*",
  "vars": [["server_port", "==", "9080"]],
  "methods": ["GET", "OPTIONS"],
  "plugins": {
    "proxy-rewrite": { "regex_uri": ["/external/(.*)", "/api/public/$1"] }
  },
  "upstream_id": "my-service"
}'

# Route internal (port 9081) to the new upstream, with 401→404 stealth
apisix_put "routes/orders-internal" '{
  "uri": "/internal/orders*",
  "vars": [["server_port", "==", "9081"]],
  "plugins": {
    "key-auth": { "header": "X-API-KEY" },
    "proxy-rewrite": { "regex_uri": ["/internal/(.*)", "/api/internal/$1"] },
    "serverless-post-function": {
      "phase": "header_filter",
      "functions": ["return function(conf, ctx)\n  if ngx.status == 401 then\n    ngx.status = 404\n  end\nend"]
    }
  },
  "upstream_id": "my-service"
}'
```

> Upstream routes are per-service, but **path-based sub-routes within a service are free** — they are automatically covered by the upstream wildcard and routed by NestJS internally.

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
# View data-plane logs (traffic)
kubectl logs -n gateway deployment/apisix -f

# View control-plane logs (Admin API)
kubectl logs -n gateway deployment/apisix-admin -f

# View config Job logs
kubectl logs -n gateway job/apisix-config-job

# Re-apply APISIX routes after a config change
bash scripts/rollout-config-job.sh

# Open Admin UI in browser (control-plane — port 31800)
open http://$(minikube ip):31800/ui

# List all APISIX routes via Admin API
NODE_IP=$(minikube ip)
curl -H "X-API-KEY: supersecretadminkey" \
     http://${NODE_IP}:31800/apisix/admin/routes | jq .

# Port-forward Admin API to localhost (alternative to NodePort)
kubectl port-forward -n gateway svc/apisix-admin 9180:9180 &
curl -H "X-API-KEY: supersecretadminkey" http://localhost:9180/apisix/admin/routes | jq .

# Tear down
minikube delete
```

---

## License

MIT
