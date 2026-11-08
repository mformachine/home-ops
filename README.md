# home-ops

Kubernetes manifests for a self-hosted homelab cluster running on k3s.

## Cluster

| Node | Role | IP | RAM | Storage |
|------|------|----|-----|---------|
| homelab-server | control-plane | 192.xxx.xxx.10 | 64 GB | 1 TB NVMe |
| homelab-worker1 | worker | 192.xxx.xxx.11 | 32 GB | 512 GB NVMe |
| homelab-worker2 | worker | 192.xxx.xxx.12 | 32 GB | 512 GB NVMe |
| homelab-worker3 | worker | 192.xxx.xxx.13 | 32 GB | 512 GB NVMe |

- **OS:** Ubuntu 24.04 LTS
- **K8s:** k3s v1.34.5
- **Ingress:** Traefik (k3s built-in) with Let's Encrypt wildcard via Cloudflare DNS-01
- **Storage:** Longhorn (replicated), local-path (legacy)
- **Domain:** `*.homelab.xyz` (Your registrar, Your DNS)

## Structure

```
kubernetes/
├── flux/cluster/                 # Flux entry point (bootstrap points here)
│   ├── flux-system/              # Flux components + GitRepository (generated)
│   └── ks.yaml                   # cluster-apps -> kubernetes/apps
│
└── apps/                         # One Flux Kustomization (ks.yaml) per app
    ├── namespace.yaml            # n8n-prod (prune disabled)
    ├── traefik/                  # HelmChartConfig: Let's Encrypt via Cloudflare DNS-01
    ├── database/                 # Postgres + Redis (+ n8n-credentials.sops.yaml)
    ├── n8n-service/              # n8n main + worker, poppler  (n8n.*)
    ├── stirling-pdf/             # PDF toolkit  (pdf.*, NodePort 30001)
    ├── observability/            # Grafana      (grafana.*, NodePort 30002)
    ├── filebrowser/              # File archive (archive.*)
    └── longhorn-service/         # Longhorn UI ingress  (longhorn.*)
```

Each app folder holds a `ks.yaml` (the Flux Kustomization) and an `app/` folder with the manifests.

## Secrets

Secrets are encrypted with SOPS + age and decrypted by Flux in the cluster.
See [docs/secrets.md](docs/secrets.md). Never commit an unencrypted secret.
The domain and email addresses are kept in the encrypted `kubernetes/apps/cluster-secrets.sops.yaml`
and filled in by Flux (`${SECRET_DOMAIN}` etc. in the manifests).
