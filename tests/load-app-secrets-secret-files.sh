#!/usr/bin/env bash
# Offline checks for secret-files.manifest handling in load-app-secrets.sh.
# Does not call GCP; verifies fail-closed behavior when the file-fetch path runs
# without a metadata token / GSM (expected exit non-zero).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOADER="${ROOT}/load-app-secrets.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

mkdir -p "${WORKDIR}/app" "${WORKDIR}/run"
python3 - "${LOADER}" "${WORKDIR}/load-app-secrets.sh" "${WORKDIR}" <<'PY'
import pathlib, sys
src, dst, work = map(pathlib.Path, sys.argv[1:4])
text = src.read_text()
replacements = {
    'SECRETS_MOUNT="/run/app-secrets"': f'SECRETS_MOUNT="{work}/run/app-secrets"',
    'ENV_MANIFEST="/app/env.manifest"': f'ENV_MANIFEST="{work}/app/env.manifest"',
    'SECRETS_MANIFEST="/app/secrets.manifest"': f'SECRETS_MANIFEST="{work}/app/secrets.manifest"',
    'SECRET_FILES_MANIFEST="/app/secret-files.manifest"': f'SECRET_FILES_MANIFEST="{work}/app/secret-files.manifest"',
    'grep -q "${SECRETS_MOUNT}" /proc/mounts || mount -t tmpfs -o size=1m tmpfs "${SECRETS_MOUNT}"': "true",
}
for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f"pattern not found in loader: {old}")
    text = text.replace(old, new)
dst.write_text(text)
dst.chmod(0o755)
PY

# 1) Empty manifests -> success, app.env published.
: > "${WORKDIR}/app/env.manifest"
: > "${WORKDIR}/app/secrets.manifest"
: > "${WORKDIR}/app/secret-files.manifest"
if ! "${WORKDIR}/load-app-secrets.sh"; then
  echo "FAIL: empty manifests should succeed" >&2
  exit 1
fi
test -f "${WORKDIR}/run/app-secrets/app.env"
echo "OK: empty manifests publish app.env"

# 2) Non-empty secret-files without GSM -> fail closed (no token / fetch).
rm -f "${WORKDIR}/run/app-secrets/app.env"
printf 'id_ed25519=fake-secret-id\n' > "${WORKDIR}/app/secret-files.manifest"
if "${WORKDIR}/load-app-secrets.sh"; then
  echo "FAIL: missing GSM should fail closed" >&2
  exit 1
fi
if [ -f "${WORKDIR}/run/app-secrets/app.env" ]; then
  echo "FAIL: app.env must not be published on secret-file failure" >&2
  exit 1
fi
echo "OK: secret-files fail closed without GSM"

echo "All load-app-secrets secret-files checks passed."
