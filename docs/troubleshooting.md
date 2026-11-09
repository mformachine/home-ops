# Troubleshooting

Flux applies `main` on its own within ~1–2 minutes of a merge. Nothing needs to be run
on the server for normal changes. These commands are for checking and fixing.

## Is everything healthy?

```bash
flux get ks -A                          # all Kustomizations: READY True?
flux get sources git -A                 # latest commit fetched from GitHub?
flux events -A --types=Warning          # recent problems
flux logs --all-namespaces --level=error --since=1h
flux tree ks flux-system                # what Flux manages
```

**Normal after a merge:** `n8n` briefly shows `dependency 'flux-system/database' is not ready`.
The database re-checks itself on every new commit; n8n retries within ~30s.

## Apply a merged change right now

```bash
flux reconcile ks cluster-apps --with-source
```

## Preview a change before merging

Use `flux diff`, not `kubectl diff`. It is a server-side dry run as Flux itself, fills in
`${SECRET_*}` placeholders, and shows fields Flux would remove:

```bash
git fetch -q origin && git checkout -q origin/<pr-branch>
flux diff ks <kustomization> --path ./kubernetes/apps/<app>/app
git checkout -q main
```

Fields set by hand (`kubectl edit`, `kubectl rollout restart`, `kubectl set`) are not in git, so
Flux removes them on its next apply. That can restart a pod (this happened to n8n once).

## Never print secret values

Don't run `kubectl diff`, `kubectl get -o yaml/json` or `kubectl describe` on Secrets, and don't
`flux diff` a Kustomization that contains Secrets. See [secrets.md](secrets.md) for value-free checks.

## Pause Flux for one app

```bash
flux suspend ks <kustomization>   # Flux stops touching it; the cluster stays as it is
flux resume ks <kustomization>    # after fixing the repo
```

## After changing a secret

Pods read environment variables only at startup. Restart the app after Flux has applied the
new value, for example `kubectl rollout restart deployment/<name> -n <namespace>`.

## Traefik / certificates

Certificates live in `/data/acme.json` on a Longhorn volume, so restarts don't re-issue them.
Traefik uses the `Recreate` strategy: expect ~30s of downtime when it is updated or restarted.

```bash
# Issuer and issue date per site (no secrets printed)
D=$(sops -d --extract '["stringData"]["SECRET_DOMAIN"]' kubernetes/apps/cluster-secrets.sops.yaml)
for h in n8n grafana pdf archive longhorn; do printf '%-9s ' $h; echo | openssl s_client -connect 127.0.0.1:443 -servername $h.$D 2>/dev/null | openssl x509 -noout -issuer -startdate | tr '\n' ' '; echo; done; unset D
```

Validate Traefik values against the chart before a PR (k3s ships chart 39.x, which rejects some
old keys, e.g. `ports.web.redirectTo`): render with `helm template` using the chart version from
`kubectl get helmchart traefik -n kube-system -o jsonpath='{.spec.chart}'`.

## Flux controllers crash after (re)bootstrap

Symptoms: `flux bootstrap` hangs on "waiting for GitRepository"; controllers in `CrashLoopBackOff`;
logs say `the server has asked for the client to provide credentials`; the k3s log
(`sudo journalctl -u k3s | grep 'invalid bearer'`) says `serviceaccounts ... not found`.

Cause: an old `flux-system` Kustomization stuck mid-deletion (from an earlier `flux uninstall`)
is finishing its deletion and pruning Flux itself. Check before bootstrapping:

```bash
kubectl get kustomizations,gitrepositories -A -o custom-columns=NAME:.metadata.name,DELETING:.metadata.deletionTimestamp
```

Fix, **in this order**:

```bash
kubectl patch kustomization flux-system -n flux-system --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]'
flux bootstrap github --owner=mformachine --repository=home-ops --branch=main --path=kubernetes/flux/cluster --personal --private=false
kubectl delete pods -n flux-system --all
```

## Removing Flux

Only with `flux uninstall`. Flux manages its own files (`kubernetes/flux/cluster/flux-system`);
deleting them or the `flux-system` Kustomization makes Flux prune itself, CRDs included.
