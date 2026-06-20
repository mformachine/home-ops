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
- **Domain:** `*.homelab.xyz` (Your registrar, Cloudflare DNS)
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
│   │   └── redis.yaml            # PVC + Deployment + Service
│   │
│   ├── n8n-service/              # Workflow automation
│   │   ├── n8n-app.yaml
│   │   ├── n8n-worker.yaml
│   │   ├── n8n-secrets.yaml      
│   │   ├── n8n-ingress.yaml      # n8n.homelab.xyz
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
│   │   └── stirling-pdf-ingress.yaml    # pdf.homelab.xyz
│   │
│   ├── observability/            # Monitoring
│   │   ├── grafana.yaml
│   │   ├── grafana-nodeport.yaml        # :30002
│   │   └── grafana-ingress.yaml         # grafana.homelab.xyz
│   │
│   └── longhorn-service/         # Storage management
│       └── longhorn-ingress.yaml        # longhorn.homelab.xyz
```
