#!/usr/bin/env bash
#
# load-app-secrets.sh — generic env/secret loader for gcp-gce-server.
#
# Inputs (cloud-init):
#   /etc/app/env.manifest      KEY=VALUE
#   /etc/app/secrets.manifest  KEY=<gsm_secret_id>   # IDs only, never values
#
# Output (tmpfs, RAM only):
#   /run/app-secrets/app.env
#
# Uses the metadata access token + Secret Manager REST API via curl
# (no gcloud, no docker). Atomic and fail-closed: assembles on tmpfs and
# renames to app.env only after every secret resolves.

set -euo pipefail

SECRETS_MOUNT="/run/app-secrets"
ENV_MANIFEST="/etc/app/env.manifest"
SECRETS_MANIFEST="/etc/app/secrets.manifest"
METADATA="http://metadata.google.internal/computeMetadata/v1"

mkdir -p "${SECRETS_MOUNT}"
grep -q "${SECRETS_MOUNT}" /proc/mounts || mount -t tmpfs -o size=1m tmpfs "${SECRETS_MOUNT}"

umask 077
tmp="$(mktemp "${SECRETS_MOUNT}/.app.env.XXXXXX")"
trap 'rm -f "${tmp}"' EXIT

# 1) Non-sensitive env (manifest lines already include trailing newlines).
if [ -f "${ENV_MANIFEST}" ]; then
  cat "${ENV_MANIFEST}" >> "${tmp}"
fi

# 2) Resolve each KEY=<secret_id> from Secret Manager.
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

# 3) Publish atomically within tmpfs.
mv "${tmp}" "${SECRETS_MOUNT}/app.env"
trap - EXIT

echo "load-app-secrets: ok"
