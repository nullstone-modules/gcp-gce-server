#!/usr/bin/env bash
#
# load-app-secrets.sh
#
# Generic boot-time env/secret loader for gcp-gce-server.
#
# Reads two manifests dropped into the instance via cloud-init:
#   /etc/app/env.manifest      KEY=VALUE            (non-sensitive env vars)
#   /etc/app/secrets.manifest  KEY=<gsm_secret_id>  (secrets to resolve)
#
# Each secret is resolved from Google Secret Manager using the VM's own service
# account -- obtained from the metadata server -- and the combined result is
# written to a tmpfs mount (RAM only, never on the boot disk):
#   /run/app-secrets/app.env
#
# Fetching uses the metadata access token + the Secret Manager REST API via
# curl (no gcloud, no docker), so the loader works on any GCE image
# (Ubuntu, Container-Optimized OS, ...).
#
# Fail-closed and atomic: the file is assembled in a temp file ON THE TMPFS
# MOUNT and only renamed to app.env after every secret resolves. Any failure
# aborts (set -euo pipefail) and leaves no app.env, so the application never
# starts with partial or blank credentials, and no secret value ever touches
# the boot disk.

set -euo pipefail

SECRETS_MOUNT="/run/app-secrets"
ENV_MANIFEST="/etc/app/env.manifest"
SECRETS_MANIFEST="/etc/app/secrets.manifest"
METADATA="http://metadata.google.internal/computeMetadata/v1"

# Back the secrets directory with tmpfs so nothing lands on the boot disk.
mkdir -p "${SECRETS_MOUNT}"
grep -q "${SECRETS_MOUNT}" /proc/mounts || mount -t tmpfs -o size=1m tmpfs "${SECRETS_MOUNT}"

umask 077
# Assemble inside the tmpfs mount so secret values are never written to disk.
tmp="$(mktemp "${SECRETS_MOUNT}/.app.env.XXXXXX")"
trap 'rm -f "${tmp}"' EXIT

# 1) Non-sensitive env vars (manifest lines already carry trailing newlines).
if [ -f "${ENV_MANIFEST}" ]; then
  cat "${ENV_MANIFEST}" >> "${tmp}"
fi

# 2) Secrets: resolve each KEY=<secret_id> to KEY=<value> from Secret Manager.
if [ -f "${SECRETS_MANIFEST}" ] && [ -s "${SECRETS_MANIFEST}" ]; then
  project="$(curl -sf -H 'Metadata-Flavor: Google' "${METADATA}/project/project-id")"
  token="$(curl -sf -H 'Metadata-Flavor: Google' \
    "${METADATA}/instance/service-accounts/default/token" \
    | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"
  if [ -z "${token}" ]; then
    echo "load-app-secrets: failed to obtain access token" >&2
    exit 1
  fi

  while IFS='=' read -r key secret_id || [ -n "${key}" ]; do
    [ -z "${key}" ] && continue
    data="$(curl -sf -H "Authorization: Bearer ${token}" \
      "https://secretmanager.googleapis.com/v1/projects/${project}/secrets/${secret_id}/versions/latest:access" \
      | sed -n 's/.*"data"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    if [ -z "${data}" ]; then
      echo "load-app-secrets: failed to fetch secret ${secret_id}" >&2
      exit 1
    fi
    printf '%s=%s\n' "${key}" "$(printf '%s' "${data}" | base64 -d)" >> "${tmp}"
  done < "${SECRETS_MANIFEST}"
fi

# 3) Publish atomically (rename within tmpfs): app.env exists only on full success.
mv "${tmp}" "${SECRETS_MOUNT}/app.env"
trap - EXIT

echo "load-app-secrets: ok"
