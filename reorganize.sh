#!/bin/bash
# Reorganizes flat n8n-k8s-deployment into home-ops/kubernetes structure.
# Uses cp (not mv) — original files remain until you verify and delete them.

set -e

OLD="$HOME/n8n-k8s-deployment"
NEW="$HOME/home-ops/kubernetes"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Creating directory structure...${NC}"
mkdir -p "$NEW/components/traefik"
mkdir -p "$NEW/apps/database"
mkdir -p "$NEW/apps/n8n-service"
mkdir -p "$NEW/apps/stirling-pdf"
mkdir -p "$NEW/apps/observability"
mkdir -p "$NEW/apps/longhorn-service"
mkdir -p "$NEW/apps/immich-service"
mkdir -p "$NEW/apps/system-upgrade"
mkdir -p "$NEW/apps/cert-manager"
mkdir -p "$NEW/apps/network"

# --- Traefik (infrastructure) ---
echo -e "${GREEN}Copying traefik files...${NC}"
cp "$OLD/traefik-config.yaml" "$NEW/components/traefik/"
cp "$OLD/traefik-cloudflare-secret.yaml" "$NEW/components/traefik/"

# --- n8n service ---
echo -e "${GREEN}Copying n8n service files...${NC}"
cp "$OLD/n8n-app.yaml" "$NEW/apps/n8n-service/"
cp "$OLD/n8n-worker.yaml" "$NEW/apps/n8n-service/"
cp "$OLD/n8n-secrets.yaml" "$NEW/apps/n8n-service/"
cp "$OLD/n8n-ingress.yaml" "$NEW/apps/n8n-service/"
cp "$OLD/n8n-nodeport.yaml" "$NEW/apps/n8n-service/"
cp "$OLD/poppler.yaml" "$NEW/apps/n8n-service/"
cp "$OLD/pdf2img-poppler.yaml" "$NEW/apps/n8n-service/"
cp "$OLD/pdf2img-goppler.yaml" "$NEW/apps/n8n-service/"
cp "$OLD/gotenberg.yaml" "$NEW/apps/n8n-service/"

# --- Stirling PDF ---
echo -e "${GREEN}Copying stirling-pdf files...${NC}"
cp "$OLD/stirling-pdf.yaml" "$NEW/apps/stirling-pdf/"
cp "$OLD/stirling-pdf-nodeport.yaml" "$NEW/apps/stirling-pdf/"
cp "$OLD/stirling-pdf-ingress.yaml" "$NEW/apps/stirling-pdf/"

# --- Observability ---
echo -e "${GREEN}Copying observability files...${NC}"
cp "$OLD/grafana.yaml" "$NEW/apps/observability/"
cp "$OLD/grafana-nodeport.yaml" "$NEW/apps/observability/"
cp "$OLD/grafana-ingress.yaml" "$NEW/apps/observability/"

# --- Longhorn ---
echo -e "${GREEN}Copying longhorn files...${NC}"
cp "$OLD/longhorn-ingress.yaml" "$NEW/apps/longhorn-service/"

echo ""
echo -e "${YELLOW}Skipped (handled separately):${NC}"
echo "  backend.yaml  → replaced by apps/database/postgres.yaml + redis.yaml"
echo "  storage.yaml   → replaced by per-service PVCs in postgres.yaml, redis.yaml, n8n-service/storage.yaml"
echo "  deploy.sh      → dropped (uses destructive delete-before-apply pattern)"
echo ""
echo -e "${GREEN}✅ Done. Original files in $OLD are untouched.${NC}"
echo ""
echo "Next steps:"
echo "  1. SCP the new files (postgres.yaml, redis.yaml, storage.yaml, .gitignore, README.md, etc.)"
echo "  2. Verify the new structure: tree $NEW"
echo "  3. Test: kubectl apply -f $NEW/apps/database/redis.yaml"
echo "  4. Once verified, remove the old directory: rm -rf $OLD"
