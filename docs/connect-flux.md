# Connecting Flux to the live cluster (zero-change)

Goal: Flux takes over what is already running **without changing any workload**.
Image tags, resources and settings in this repo mirror the live server, so each
app's first reconcile should only add Flux labels. Nothing restarts.

## Before you start

- An earlier bootstrap attempt may have left Flux CRDs, a `flux-system` namespace and its
  deploy-key secret behind, with no controllers running. Re-running bootstrap reuses and
  overwrites these leftovers; no cleanup is needed.
- Only apps that actually exist on the cluster are listed in this repo, so the first sync
  should only add Flux labels and the prune-protection annotations.

> ⚠️ **Merge this layout to `main` before bootstrapping.** The old `main` lists every app,
> including ones that don't exist on the cluster. The only thing stopping Flux from
> applying all of it today is the missing `sops-age` secret.

Run everything on the k3s server (or any machine with its kubeconfig).
On the server, `kubectl` is `sudo k3s kubectl` unless `KUBECONFIG=/etc/rancher/k3s/k3s.yaml` is set.

## 0. Tools

```bash
curl -s https://fluxcd.io/install.sh | sudo FLUX_VERSION=2.9.2 bash   # match gotk-components.yaml
flux --version
```

Also: `sops` and `age` (only needed once you add encrypted secrets).

## 1. Get this layout onto `main`

Flux syncs `main` at `kubernetes/flux/cluster`. Merge this branch through a PR first.
Do **not** merge the open Renovate PRs yet. They would start changing versions the moment Flux is live.

## 2. Pre-flight (read-only)

```bash
flux check --pre
```

Back up before anything else:

```bash
kubectl exec -n n8n-prod deploy/postgres -- sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' > n8n-$(date +%F).sql
```

Plus a Longhorn snapshot of each volume (Longhorn UI → Volumes → Take Snapshot).

Compare every app with what's live. `kubectl diff` only does a dry run; it changes nothing:

```bash
cd home-ops   # a checkout of main
for a in stirling-pdf filebrowser observability longhorn-service traefik database n8n-service; do
  echo "===== $a"; kubectl diff -k kubernetes/apps/$a/app
done
kubectl diff -f kubernetes/apps/namespace.yaml
```

Expected differences, all harmless:

- the `kustomize.toolkit.fluxcd.io/prune: disabled` annotation on the namespace and the 4 PVCs
- `kubectl.kubernetes.io/last-applied-configuration` annotation noise

Anything else (an image, a resource limit, an env var) means the repo and the cluster disagree.
Fix the repo to match the cluster and diff again before going on.
If Traefik shows any difference, k3s will redeploy Traefik when Flux applies it, so get that diff empty.

## 3. SOPS key (needed before bootstrap)

Several Flux Kustomizations reference the `sops-age` secret. Create it even before any secret is encrypted.
Use the age private key whose public key is in `.sops.yaml`:

```bash
kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic sops-age -n flux-system --from-file=age.agekey=<path-to-age-key>
```

Also save a copy of the key in a password manager. If the server's disk dies, it's the only
way to decrypt the secrets in git. Never commit it.

## 4. Bootstrap

You'll need a GitHub token with `repo` scope. Export it in your own shell; it's used once to add a read-only deploy key.

```bash
export GITHUB_TOKEN=<your token>
flux bootstrap github --owner=mformachine --repository=home-ops --branch=main \
  --path=kubernetes/flux/cluster --personal
```

At this point `kubernetes/apps/kustomization.yaml` only enables `namespace.yaml`, so Flux
manages the Flux controllers and the `n8n-prod` namespace and nothing else.

```bash
flux get sources git -A
flux get ks -A                      # flux-system and cluster-apps: Ready=True
kubectl get pods -n n8n-prod        # ages and restart counts unchanged
```

## 5. Hand over apps one at a time

One PR per app: uncomment its line in `kubernetes/apps/kustomization.yaml`, merge, then run:

```bash
flux reconcile ks cluster-apps --with-source
flux get ks <app>
kubectl get pods -n n8n-prod        # nothing restarted
```

Order (least to most risky): stirling-pdf → filebrowser → observability → longhorn-service → traefik → database → n8n-service.

`database` and `n8n-service` don't need their secrets in git yet. Flux leaves the existing
`n8n-credentials` secret alone because it didn't create it. Encrypt it later with [secrets.md](secrets.md).

## If something goes wrong

```bash
flux suspend ks <app>       # stop Flux touching that app; the cluster stays as it is
flux resume ks <app>        # after fixing the repo
```

`flux uninstall` removes Flux but leaves every workload it was managing in place.

## After it's connected

- `main` is now the source of truth. `kubectl apply` / `kubectl edit` changes are reverted on the next reconcile (≤30 min). Change things by PR.
- Any manual checkout used for `kubectl apply` is no longer how things get deployed.
- Next steps, each as its own PR: encrypt secrets, CI checks on PRs, branch protection, then let Renovate PRs in.
