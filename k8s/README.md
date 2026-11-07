# k8s manifests

| File | What it is |
|---|---|
| `namespace.yaml` | Creates the `orders` namespace.<br>Everything else in this folder goes into it. |
| `deployment.yaml` | Runs 2 replicas of the app on port 8000, as non-root (uid 65534) with a read-only filesystem.<br>Probes hit `/healthz`; CPU and memory requests/limits are set. |
| `service.yaml` | ClusterIP Service `orders` on port 8080.<br>Forwards to the pods' container port 8000. |

> Orders are kept in memory, so each of the 2 replicas has its own separate list.
> A `GET` may not see an order that a `POST` created on the other pod.

## Setting the image

`deployment.yaml` uses the placeholder `ORDERS_IMAGE`. CI should replace it before applying, for example:

```bash
IMAGE=ghcr.io/you/orders:abc123
sed "s|ORDERS_IMAGE|$IMAGE|" k8s/deployment.yaml | kubectl apply -f -
# or, after applying:
kubectl -n orders set image deployment/orders orders=$IMAGE
```

## Validate

```bash
kubectl apply --dry-run=client -f k8s/
```

This creates nothing, but kubectl still contacts the cluster in your current context to look up resource types, so it needs a reachable cluster.
Check which one first with `kubectl config current-context`, and point it at your local kind cluster (`kubectl config use-context kind-orders`).

With no cluster at all, check the files against the Kubernetes schemas instead:

```bash
docker run --rm -v "$PWD/k8s:/k8s:ro" ghcr.io/yannh/kubeconform:v0.6.7 -strict -summary /k8s/namespace.yaml /k8s/deployment.yaml /k8s/service.yaml
```

## Apply (to a kind cluster)

```bash
kind create cluster --name orders
docker build -t orders:0.1.0 .
kind load docker-image orders:0.1.0 --name orders
kubectl apply -f k8s/namespace.yaml
sed "s|ORDERS_IMAGE|orders:0.1.0|" k8s/deployment.yaml | kubectl apply -f -
kubectl apply -f k8s/service.yaml
kubectl -n orders port-forward svc/orders 8080:8080   # then: curl localhost:8080/healthz
```
