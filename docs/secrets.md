# Secrets (SOPS + age)

Every Kubernetes Secret in this repo is encrypted with [SOPS](https://github.com/getsops/sops)
using the age public key in [`.sops.yaml`](../.sops.yaml). Flux decrypts them in the cluster
with the private key stored in the `sops-age` Secret in `flux-system`.

**Rules**

- Only files named `*.sops.yaml` may contain secrets, and they must be encrypted before `git add`.
- The commands below pipe plaintext straight into `sops`, so it never lands on disk.
- Never commit the age private key (`AGE-SECRET-KEY-...`). Keep it in a password manager.
- Values must match what is live on the cluster. In particular `N8N_ENCRYPTION_KEY`:
  a different value makes every credential stored in n8n unreadable.

## One-time setup

```bash
brew install sops age jq
```

Put the age private key at `~/Library/Application Support/sops/age/keys.txt`
(the default location sops looks in on macOS), then load it into the cluster:

```bash
kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic sops-age -n flux-system \
  --from-file=age.agekey="$HOME/Library/Application Support/sops/age/keys.txt"
```

## Encrypting an existing plaintext Secret file

If you already have a plaintext Secret manifest (kept outside git), encrypt it into the repo
without copying it in first:

```bash
OUT=kubernetes/apps/database/app/n8n-credentials.sops.yaml
sops --encrypt --filename-override "$OUT" <path-to-plaintext-secret.yaml> > "$OUT"
```

Then run the checks below, and delete the plaintext file once the encrypted copy is verified.

Alternatively, export straight from the cluster as shown in the next sections.

## n8n-credentials (used by Postgres, Redis, n8n, n8n-worker)

Export the live Secret and encrypt it in one step:

```bash
OUT=kubernetes/apps/database/app/n8n-credentials.sops.yaml
kubectl get secret n8n-credentials -n n8n-prod -o json \
  | jq '{apiVersion, kind, type, metadata: {name: .metadata.name, namespace: .metadata.namespace}, data}' \
  | sops --encrypt --input-type json --output-type yaml --filename-override "$OUT" /dev/stdin > "$OUT"
```

Check it, then add `- ./n8n-credentials.sops.yaml` to
`kubernetes/apps/database/app/kustomization.yaml`:

```bash
grep -q '^sops:' "$OUT" && ! grep -qE '^\s+[A-Z_]+: [^E]' "$OUT" && echo encrypted   # every value must be ENC[...]
sops --decrypt "$OUT" | kubectl diff -f -                  # should print nothing
```

## cloudflare-api-token (Traefik DNS-01)

```bash
OUT=kubernetes/apps/traefik/app/cloudflare-api-token.sops.yaml
kubectl get secret cloudflare-api-token -n kube-system -o json \
  | jq '{apiVersion, kind, type, metadata: {name: .metadata.name, namespace: .metadata.namespace}, data}' \
  | sops --encrypt --input-type json --output-type yaml --filename-override "$OUT" /dev/stdin > "$OUT"
```

If that Secret doesn't exist under this name, find the one Traefik actually uses
(`kubectl get secrets -n kube-system`) and make `traefik-config.yaml` and this file agree.
Then add `- ./cloudflare-api-token.sops.yaml` to `kubernetes/apps/traefik/app/kustomization.yaml`.

## Editing an existing secret

```bash
sops kubernetes/apps/database/app/n8n-credentials.sops.yaml   # opens decrypted in $EDITOR, re-encrypts on save
```
