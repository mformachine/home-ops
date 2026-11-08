# Secrets (SOPS + age)

Every Kubernetes Secret in this repo is encrypted with [SOPS](https://github.com/getsops/sops)
using the age public key in [`.sops.yaml`](../.sops.yaml). Flux decrypts them in the cluster
with the private key stored in the `sops-age` Secret in `flux-system`.

## Rules

- Only files named `*.sops.yaml` may contain secrets, and every value must be `ENC[...]` before `git add`.
- Pipe plaintext straight into `sops`; never write it to a file.
- Never commit the age private key (`AGE-SECRET-KEY-...`). Keep a copy in a password manager.
- **Never print secret values.** Don't run `kubectl diff`, `kubectl get -o yaml/json` or
  `kubectl describe` on Secrets: Secrets created with `kubectl apply` keep a plaintext copy in the
  `kubectl.kubernetes.io/last-applied-configuration` annotation, and those commands print it.
  Check key names only (see below).
- Every Secret file carries `kustomize.toolkit.fluxcd.io/prune: disabled`, so removing a file from
  git never deletes the live Secret.

## Secrets in this repo

| File | Secret | Used by |
|---|---|---|
| `kubernetes/apps/cluster-secrets.sops.yaml` | `flux-system/cluster-secrets` | Flux `postBuild` substitution (domain, emails) |
| `kubernetes/apps/database/app/n8n-credentials.sops.yaml` | `n8n-prod/n8n-credentials` | Postgres, Redis, n8n, n8n-worker |
| `kubernetes/apps/traefik/app/cloudflare-api-token.sops.yaml` | `kube-system/cloudflare-api-token` | Traefik (Let's Encrypt DNS-01) |

`N8N_ENCRYPTION_KEY` must never change: a different value makes every credential stored in n8n unreadable.

## One-time setup

```bash
brew install sops age
```

Viewing or editing needs the age private key at sops's default location
(`~/.config/sops/age/keys.txt` on Linux, `~/Library/Application Support/sops/age/keys.txt` on macOS).
Encrypting a new file needs only the public key in `.sops.yaml`.

The cluster gets the key once, before bootstrap:

```bash
kubectl create secret generic sops-age -n flux-system --from-file=age.agekey=<path-to-age-key>
```

## cluster-secrets (domain and email placeholders)

The repo is public, so the domain and email addresses aren't written in the manifests.
They appear as `${SECRET_DOMAIN}`, `${SECRET_ACME_EMAIL}` and `${SECRET_SMTP_SENDER}`, and
each app's Flux Kustomization fills them in through `postBuild.substituteFrom`.

- **Add a variable:** add it under `stringData` with `sops`, then use `${SECRET_NAME}` in a manifest.
  The app's `ks.yaml` must have the `postBuild.substituteFrom` block.
- To write a literal `${...}` in a manifest that Flux substitutes, escape it as `$${...}`.

## Changing or rotating a value

```bash
sops kubernetes/apps/database/app/n8n-credentials.sops.yaml   # opens decrypted in $EDITOR, re-encrypts on save
```

Commit, open a PR, merge. Flux updates the live Secret. Pods read env vars from Secrets only at
startup, so restart the app afterwards (for example `kubectl rollout restart deploy/<name> -n <ns>`;
for a Flux-managed Deployment, prefer bumping an annotation in git).

## Adding a new Secret

Write it with `stringData`, the prune annotation, and pipe it straight into sops. `read -rs` keeps the
value out of the screen and shell history:

```bash
read -rsp "value: " V && printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: NAME\n  namespace: NS\n  annotations:\n    kustomize.toolkit.fluxcd.io/prune: disabled\ntype: Opaque\nstringData:\n  KEY: "%s"\n' "$V" | sops --encrypt --input-type yaml --output-type yaml --filename-override kubernetes/apps/APP/app/NAME.sops.yaml /dev/stdin > kubernetes/apps/APP/app/NAME.sops.yaml; unset V
```

Then add it to that app's `kustomization.yaml`.

## Checking a Secret without printing it

```bash
# Every data value in the file is encrypted (prints the count of plain values; must be 0)
awk '/^(data|stringData):/{s=1;next} /^[a-z]/{s=0} s && /^  [^ ]/ && !/ENC\[/' FILE.sops.yaml | wc -l

# Key names on the cluster
kubectl get secret NAME -n NS -o go-template='{{range $k, $v := .data}}{{$k}}{{"\n"}}{{end}}'

# Whether the file's values equal the live ones, comparing fingerprints only (for files using `data:`)
diff <(sops -d --output-type json FILE.sops.yaml | python3 -c 'import sys,json,hashlib; d=json.load(sys.stdin)["data"]; [print(k, hashlib.sha256(x.encode()).hexdigest()[:12]) for k,x in sorted(d.items())]') \
     <(kubectl get secret NAME -n NS -o json | python3 -c 'import sys,json,hashlib; d=json.load(sys.stdin)["data"]; [print(k, hashlib.sha256(x.encode()).hexdigest()[:12]) for k,x in sorted(d.items())]') && echo identical
```
