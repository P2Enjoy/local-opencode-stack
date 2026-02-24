#!/bin/bash

# Load env vars from secret files in a directory.
# Secret file naming convention:
#   <DIR>/<ENV_VAR_NAME>
# Existing non-empty env vars are preserved by default.

is_valid_secret_key() {
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

load_secrets_dir() {
    local secrets_dir="${1:-}"
    local overwrite_existing="${2:-false}"

    [ -n "$secrets_dir" ] || return 0
    [ -d "$secrets_dir" ] || return 0

    local loaded=0
    local skipped=0

    while IFS= read -r -d '' secret_file; do
        local secret_name
        local secret_value

        secret_name="$(basename "$secret_file")"
        if ! is_valid_secret_key "$secret_name"; then
            continue
        fi

        if [ "$overwrite_existing" != "true" ] && [ -n "${!secret_name:-}" ]; then
            skipped=$((skipped + 1))
            continue
        fi

        secret_value="$(cat "$secret_file")"
        secret_value="${secret_value%$'\r'}"
        export "$secret_name=$secret_value"
        loaded=$((loaded + 1))
    done < <(find "$secrets_dir" -mindepth 1 -maxdepth 1 -type f -print0)

    echo "[INFO] Secrets loaded from ${secrets_dir}: loaded=${loaded} skipped=${skipped}"
}
