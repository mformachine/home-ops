#!/usr/bin/env bash
# Builds every kustomization the way Flux will and validates the result against
# Kubernetes + CRD schemas. Runs in CI on every PR; run locally with:
#   ./scripts/validate-manifests.sh
# Needs: kubectl (for `kubectl kustomize`), kubeconform, envsubst.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

fail=0
err() { echo "::error::$*"; fail=1; }

SECRETS_FILE=kubernetes/apps/cluster-secrets.sops.yaml

# 1. Every ${SECRET_*} placeholder used in manifests must exist as a key in
#    cluster-secrets (key names are plaintext in SOPS files; values are not).
keys=$(awk '/^(data|stringData):/{s=1;next} /^[^ ]/{s=0} s && /^  [A-Z_]+:/{sub(":","",$1); print $1}' "$SECRETS_FILE" | sort -u)
used=$(git grep -hoE '\$\{SECRET_[A-Z0-9_]+\}' -- 'kubernetes/' | tr -d '${}' | sort -u)
for v in $used; do
  echo "$keys" | grep -qx "$v" || err "placeholder \${$v} is used but missing from $SECRETS_FILE"
done

# Dummy values so the rendered YAML is valid (real values never leave the cluster)
subst_vars=""
for v in $used; do
  export "$v=ci-placeholder.example.com"
  subst_vars="$subst_vars \${$v}"
done

# 2. Build + validate every kustomization Flux applies
SCHEMAS=(
  -schema-location default
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
)
# Secret: SOPS adds a top-level `sops:` field that strict validation rejects; secrets
#         are covered by check-secrets.sh instead.
# HelmChartConfig (k3s, helm.cattle.io): no public schema available.
# CustomResourceDefinition: Flux's generated CRDs (gotk-components.yaml); no schema
#   for CRD objects themselves, and they're produced by `flux install`, not hand-written.
SKIP="Secret,HelmChartConfig,CustomResourceDefinition"

dirs=$( { echo kubernetes/flux/cluster; echo kubernetes/apps; \
          find kubernetes/apps -mindepth 2 -maxdepth 2 -type d -name app; } | sort )
for d in $dirs; do
  out=$(kubectl kustomize "$d" 2>&1) || { err "$d: kustomize build failed: $out"; continue; }
  # Same substitution Flux postBuild does, restricted to our variables only
  rendered=$(printf '%s\n' "$out" | envsubst "$subst_vars")
  if printf '%s\n' "$rendered" | grep -qE '\$\{SECRET_[A-Z0-9_]+\}'; then
    err "$d: unfilled \${SECRET_*} placeholder after substitution"
  fi
  if res=$(printf '%s\n' "$rendered" | kubeconform -strict -summary -output text -skip "$SKIP" "${SCHEMAS[@]}" - 2>&1); then
    echo "✔ $d  ($(echo "$res" | tail -1))"
  else
    err "$d: schema validation failed"
    echo "$res" | grep -vE '^Summary' | sed 's/^/    /'
  fi
done

[[ $fail -eq 0 ]] && echo "✔ all manifests valid" || echo "✖ manifest validation failed"
exit $fail
