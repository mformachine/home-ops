#!/usr/bin/env bash
# Fails if anything secret could be committed in plaintext.
# Runs in CI on every PR and can be run locally: ./scripts/check-secrets.sh
# Prints file names and line numbers only, never the offending values.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

fail=0
err() { echo "::error::$*"; fail=1; }

# Every tracked file (respects .gitignore, just like what would be pushed).
# A while-read loop instead of mapfile keeps this working with macOS's bash 3.2.
count=0
while IFS= read -r f; do
  count=$((count + 1))
  [[ -f "$f" ]] || continue
  case "$f" in
    .sops.yaml) continue ;;
    *.sops.yaml|*.sops.yml)
      # 1. Must be a real SOPS file with an integrity check
      grep -q '^sops:' "$f" || err "$f: missing 'sops:' block (not encrypted)"
      grep -qE '^    mac: ENC\[|^  mac: ENC\[' "$f" || err "$f: missing SOPS mac"
      # 2. Every value under data/stringData must be ENC[...]
      plain=$(awk '/^(data|stringData):/{s=1;next} /^[^ ]/{s=0} s && /^  [^ #]/ && !/: ENC\[/ {print NR}' "$f")
      [[ -z "$plain" ]] || err "$f: unencrypted value(s) on line(s): $(echo $plain)"
      ;;
    *.example.yaml|*.example.yml) ;;
    kubernetes/*.yaml|kubernetes/*.yml)
      # 3. Plain manifests must not contain Secrets (those belong in *.sops.yaml)
      if grep -qE '^kind:[[:space:]]*Secret[[:space:]]*$' "$f"; then
        err "$f: contains 'kind: Secret' but is not a *.sops.yaml file"
      fi
      ;;
  esac

  # 4. Files that .gitignore says must never be committed
  case "$f" in
    *-secret.yaml|*-secrets.yaml|*.agekey|*.pem|*.key|.env|*.env|kubeconfig*)
      [[ "$f" == *.example.yaml ]] || err "$f: this file type must never be committed" ;;
  esac
done < <(git ls-files)

# 5. Known secret formats anywhere in tracked text files (names/lines only)
patterns='AGE-SECRET-KEY-1[0-9A-Z]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40,}|SG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}|cfut_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[abpr]-[A-Za-z0-9-]{10,}|\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{50,}'
while IFS=: read -r file line; do
  err "$file:$line: looks like a credential (value not shown)"
done < <(git grep -nIE -o "$patterns" -- . ':!scripts/check-secrets.sh' | cut -d: -f1,2 | sort -u || true)

if [[ $fail -eq 0 ]]; then
  echo "✔ secret check passed ($count tracked files)"
else
  echo "✖ secret check failed"
fi
exit $fail
