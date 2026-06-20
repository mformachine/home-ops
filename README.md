# home-ops

Kubernetes manifests for a self-hosted homelab cluster running on k3s.

## Cluster

| Node | Role | IP | RAM | Storage |
|------|------|----|-----|---------|
| homelab-server | control-plane | 192.168.178.10 | 64 GB | 1 TB NVMe |
| homelab-worker1 | worker | 192.168.178.11 | 32 GB | 512 GB NVMe |
| homelab-worker2 | worker | 192.168.178.12 | 32 GB | 512 GB NVMe |
| homelab-worker3 | worker | 192.168.178.13 | 32 GB | 512 GB NVMe |

- **OS:** Ubuntu 24.04 LTS
- **K8s:** k3s v1.34.5
- **Ingress:** Traefik (k3s built-in) with Let's Encrypt wildcard via Cloudflare DNS-01
- **Storage:** Longhorn (replicated), local-path (legacy)
- **Domain:** `*.bizleadz.xyz` (Namecheap registrar, Cloudflare DNS)
- **Remote access:** Cloudflare Tunnel (SSH)

## Structure

```
kubernetes/
├── components/
│   └── traefik/                  # Ingress + TLS configuration
│       ├── traefik-config.yaml
│       └── traefik-cloudflare-secret.yaml
│
├── apps/
│   ├── database/                 # Shared data stores
│   │   ├── postgres.yaml         # PVC + Deployment + Service
│   │   └── redis.yaml            # PVC + Deployment + Service (CP-pinned)
│   │
│   ├── n8n-service/              # Workflow automation
│   │   ├── n8n-app.yaml
│   │   ├── n8n-worker.yaml
│   │   ├── n8n-secrets.yaml      # (not in git — see Secrets below)
│   │   ├── n8n-ingress.yaml      # n8n.bizleadz.xyz
│   │   ├── n8n-nodeport.yaml     # :30000
│   │   ├── storage.yaml          # n8n PVC
│   │   ├── poppler.yaml
│   │   ├── pdf2img-poppler.yaml
│   │   ├── pdf2img-goppler.yaml
│   │   └── gotenberg.yaml
│   │
│   ├── stirling-pdf/             # PDF toolkit
│   │   ├── stirling-pdf.yaml
│   │   ├── stirling-pdf-nodeport.yaml   # :30001
│   │   └── stirling-pdf-ingress.yaml    # pdf.bizleadz.xyz
│   │
│   ├── observability/            # Monitoring
│   │   ├── grafana.yaml
│   │   ├── grafana-nodeport.yaml        # :30002
│   │   └── grafana-ingress.yaml         # grafana.bizleadz.xyz
│   │
│   └── longhorn-service/         # Storage management
│       └── longhorn-ingress.yaml        # longhorn.bizleadz.xyz
```

## Deploying

Apply in dependency order:

```bash
cd ~/home-ops/kubernetes

# 1. Infrastructure
kubectl apply -f components/traefik/traefik-cloudflare-secret.yaml
kubectl apply -f components/traefik/traefik-config.yaml

# 2. Database layer
kubectl apply -f apps/database/postgres.yaml
kubectl apply -f apps/database/redis.yaml

# 3. n8n stack
kubectl apply -f apps/n8n-service/n8n-secrets.yaml
kubectl apply -f apps/n8n-service/storage.yaml
kubectl apply -f apps/n8n-service/n8n-app.yaml
kubectl apply -f apps/n8n-service/n8n-worker.yaml
kubectl apply -f apps/n8n-service/n8n-ingress.yaml
kubectl apply -f apps/n8n-service/poppler.yaml

# 4. Apps
kubectl apply -f apps/stirling-pdf/stirling-pdf.yaml
kubectl apply -f apps/stirling-pdf/stirling-pdf-ingress.yaml
kubectl apply -f apps/observability/grafana.yaml
kubectl apply -f apps/observability/grafana-ingress.yaml
kubectl apply -f apps/longhorn-service/longhorn-ingress.yaml
```

## Secrets

Secret files are excluded from Git via `.gitignore`. Template files (`.example.yaml`) show the expected structure with placeholder values.

To set up on a fresh cluster:

1. Copy each `.example.yaml` and remove the `.example` suffix
2. Replace `CHANGE_ME` values with real credentials
3. Apply with `kubectl apply -f`

## Principles

- `kubectl apply -f` only — never destructive scripts that cause downtime
- Version-pin all images — never use `:latest` in production
- One component per file — no monolithic manifests
- Never commit real secrets to Git — `.example.yaml` templates only
- Always review live cluster state before applying changes
