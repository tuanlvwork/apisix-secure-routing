---
description: Re-run the APISIX config job after config changes
---

Use this workflow to re-apply APISIX routes/consumers/upstreams after editing
`k8s/base/apisix-config-job/configmap.yaml`.

## Steps

1. Edit the config script as needed:
   ```
   k8s/base/apisix-config-job/configmap.yaml
   ```

// turbo
2. Run the rollout script with live logs:
   ```bash
   bash scripts/rollout-config-job.sh --logs
   ```

3. Verify routes were registered:
   ```bash
   kubectl port-forward -n gateway svc/apisix-admin 9180:9180 &
   curl -s -H "X-API-KEY: supersecretadminkey" \
     http://localhost:9180/apisix/admin/routes | python3 -m json.tool
   ```

4. Quick smoke test (optional):
   ```bash
   MINIKUBE_IP=$(minikube -p apisix-secure-routing ip)
   # External — no auth required
   curl -s "http://${MINIKUBE_IP}:30080/external/products"
   # Internal — auth required
   curl -s -H "X-API-KEY: internal-secret-key-CHANGE-IN-PRODUCTION" \
     "http://${MINIKUBE_IP}:30081/internal/products"
   # Security test — must return 404, NOT 401
   curl -sv "http://${MINIKUBE_IP}:30081/internal/products" 2>&1 | grep "< HTTP"
   ```
