#!/usr/bin/env bash
#
# load-app-secrets.sh — generic env/secret loader for gcp-gce-server.
#
# Inputs (cloud-init):
#   /app/env.manifest           KEY=VALUE
#   /app/secrets.manifest       KEY=<gsm_secret_id>          # IDs only, never values
#   /app/secret-files.manifest  <file name>=<gsm_secret_id>  # secrets written as files
#
# Output (tmpfs, RAM only):
#   /run/app-secrets/app.env            env + resolved secrets
#   /run/app-secrets/<file name>        each secret-file (e.g. SSH host keys)
#
# Uses the metadata access token + Secret Manager REST API via curl
# (no gcloud, no docker). Atomic and fail-closed: assembles on tmpfs and
# publishes app.env only after every secret resolves.

set -euo pipefail

SECRETS_MOUNT="/run/app-secrets"
ENV_MANIFEST="/app/env.manifest"
SECRETS_MANIFEST="/app/secrets.manifest"
SECRET_FILES_MANIFEST="/app/secret-files.manifest"
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

# Fetch the metadata access token once if any secret needs resolving.
need_token=0
{ [ -f "${SECRETS_MANIFEST}" ] && [ -s "${SECRETS_MANIFEST}" ]; } && need_token=1
{ [ -f "${SECRET_FILES_MANIFEST}" ] && [ -s "${SECRET_FILES_MANIFEST}" ]; } && need_token=1

if [ "${need_token}" -eq 1 ]; then
  project="$(curl -sf -H 'Metadata-Flavor: Google' "${METADATA}/project/project-id")"
  token="$(curl -sf -H 'Metadata-Flavor: Google' \
    "${METADATA}/instance/service-accounts/default/token" \
    | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"
  if [ -z "${token}" ]; then
    echo "load-app-secrets: failed to obtain access token" >&2
    exit 1
  fi
fi

sm_url() { echo "https://secretmanager.googleapis.com/v1/projects/${project}/secrets/$1/versions/latest:access"; }

# 2) Secrets -> KEY=VALUE lines in app.env.
if [ -f "${SECRETS_MANIFEST}" ] && [ -s "${SECRETS_MANIFEST}" ]; then
  while IFS='=' read -r key secret_id || [ -n "${key}" ]; do
    [ -z "${key}" ] && continue
    data="$(curl -sf -H "Authorization: Bearer ${token}" "$(sm_url "${secret_id}")" \
      | sed -n 's/.*"data"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    if [ -z "${data}" ]; then
      echo "load-app-secrets: failed to fetch secret ${secret_id}" >&2
      exit 1
    fi
    printf '%s=%s\n' "${key}" "$(printf '%s' "${data}" | base64 -d)" >> "${tmp}"
  done < "${SECRETS_MANIFEST}"
fi

# 3) Secret files -> files on tmpfs (preserve exact bytes incl. trailing newlines).
if [ -f "${SECRET_FILES_MANIFEST}" ] && [ -s "${SECRET_FILES_MANIFEST}" ]; then
  while IFS='=' read -r fname secret_id || [ -n "${fname}" ]; do
    [ -z "${fname}" ] && continue
    ftmp="$(mktemp "${SECRETS_MOUNT}/.${fname}.XXXXXX")"
    if ! curl -sf -H "Authorization: Bearer ${token}" "$(sm_url "${secret_id}")" \
      | sed -n 's/.*"data"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      | base64 -d > "${ftmp}" || [ ! -s "${ftmp}" ]; then
      echo "load-app-secrets: failed to fetch secret file ${fname} (${secret_id})" >&2
      rm -f "${ftmp}"
      exit 1
    fi
    chmod 644 "${ftmp}"
    mv "${ftmp}" "${SECRETS_MOUNT}/${fname}"
  done < "${SECRET_FILES_MANIFEST}"
fi

# 4) Publish app.env atomically within tmpfs.
mv "${tmp}" "${SECRETS_MOUNT}/app.env"
trap - EXIT

echo "load-app-secrets: ok"
