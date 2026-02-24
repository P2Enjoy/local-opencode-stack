#!/bin/bash

###############################################################################
# Local Codex Launcher - Routes Codex CLI through LiteLLM Proxy
#
# This script sets OpenAI-compatible environment variables for Codex CLI to use
# a local LiteLLM endpoint backed by vLLM.
#
# Usage:
#   local_codex.sh [OPTIONS] [CODEX_ARGS]
#
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VARS_FILE="${PROJECT_DIR}/vars.env"
SECRETS_DIR="${SECRETS_DIR:-${PROJECT_DIR}/secrets}"
SECRETS_HELPER="${PROJECT_DIR}/scripts/load_secrets_env.sh"

# Defaults
LITELLM_HOST="${LITELLM_HOST:-localhost}"
LITELLM_PORT="${LITELLM_PORT:-4000}"
PROXY_URL="http://${LITELLM_HOST}:${LITELLM_PORT}"
OPENAI_BASE_URL_DEFAULT="${PROXY_URL}/v1"
CHECK_HEALTH=true
VERBOSE=false
SHOW_HELP=false
DRY_RUN=false

# Loaded later from vars.env (fallback if missing)
MODEL_NAME="${MODEL:-glm47-flash}"
CODEX_MODEL=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO] $1${NC}" >&2
}

log_success() {
    echo -e "${GREEN}[OK]   $1${NC}" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARN] $1${NC}" >&2
}

log_error() {
    echo -e "${RED}[ERR]  $1${NC}" >&2
}

require_arg() {
    local flag="$1"
    local value="${2:-}"
    if [ -z "$value" ] || [[ "$value" == --* ]]; then
        log_error "Missing value for ${flag}"
        exit 1
    fi
}

load_selected_vars() {
    local file="$1"
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line#"${line%%[![:space:]]*}"}"
        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue
        [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue

        local key="${BASH_REMATCH[1]}"
        local value="${BASH_REMATCH[2]}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        if [[ "$value" =~ ^\".*\"$ ]] || [[ "$value" =~ ^\'.*\'$ ]]; then
            value="${value:1:-1}"
        fi

        case "$key" in
            MODEL|OPENAI_*|ANTHROPIC_*)
                export "$key=$value"
                ;;
        esac
    done < "$file"
}

print_help() {
    cat << 'EOF'
Local Codex Launcher for LiteLLM Proxy

USAGE:
  local_codex.sh [OPTIONS] [CODEX_ARGS]

OPTIONS:
  --help              Show this help message
  --verbose           Show resolved environment and launch command
  --no-check          Skip LiteLLM health check
  --host HOST         LiteLLM host (default: localhost)
  --port PORT         LiteLLM port (default: 4000)
  --token TOKEN       API token for OPENAI_API_KEY (default: sk-FAKE)
  --model MODEL       Model for Codex (default: anthropic/<MODEL from vars.env>)
  --dry-run           Show config and exit without launching
  --                  Pass all following args directly to codex

EXAMPLES:
  local_codex.sh
  local_codex.sh --verbose
  local_codex.sh --model anthropic/step-3.5-flash
  local_codex.sh -- --help
  local_codex.sh -- -C /path/to/repo
EOF
}

check_health() {
    log_info "Checking LiteLLM health at ${PROXY_URL}/health/liveliness..."
    if ! timeout 5 curl -fsS "${PROXY_URL}/health/liveliness" >/dev/null 2>&1; then
        log_error "LiteLLM proxy is not responding at ${PROXY_URL}"
        log_info "Start services with:"
        log_info "  cd ${PROJECT_DIR}"
        log_info "  docker compose up -d"
        return 1
    fi
    log_success "LiteLLM proxy is healthy"
    return 0
}

load_environment() {
    if [ ! -f "$VARS_FILE" ]; then
        log_error "Configuration file not found: $VARS_FILE"
        return 1
    fi

    # Load selected vars from vars.env without eval.
    load_selected_vars "$VARS_FILE"
    if [ -f "$SECRETS_HELPER" ]; then
        # shellcheck disable=SC1090
        source "$SECRETS_HELPER"
        load_secrets_dir "$SECRETS_DIR" >/dev/null
    fi

    MODEL_NAME="${MODEL:-$MODEL_NAME}"
    CODEX_MODEL="${CODEX_MODEL:-anthropic/${MODEL_NAME}}"
    OPENAI_BASE_URL="${OPENAI_BASE_URL:-$OPENAI_BASE_URL_DEFAULT}"
    OPENAI_API_KEY="${OPENAI_API_KEY:-${ANTHROPIC_AUTH_TOKEN:-sk-FAKE}}"

    export OPENAI_BASE_URL
    export OPENAI_API_KEY
    return 0
}

show_environment() {
    log_info "Launcher configuration:"
    echo "  PROXY_URL:        ${PROXY_URL}"
    echo "  OPENAI_BASE_URL:  ${OPENAI_BASE_URL}"
    echo "  OPENAI_API_KEY:   ${OPENAI_API_KEY:0:10}..."
    echo "  MODEL (vars.env): ${MODEL_NAME}"
    echo "  CODEX_MODEL:      ${CODEX_MODEL}"
    echo ""
}

ensure_codex_installed() {
    if command -v codex >/dev/null 2>&1; then
        log_success "codex CLI found"
        return 0
    fi
    log_error "codex CLI not found in PATH"
    log_info "Install Codex CLI and retry."
    return 1
}

codex_args_include_model() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            -m|--model|--model=*|-c|--config)
                return 0
                ;;
        esac
    done
    return 1
}

CODEX_ARGS=()
TOKEN_OVERRIDE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --help)
            SHOW_HELP=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --no-check)
            CHECK_HEALTH=false
            shift
            ;;
        --host)
            require_arg "--host" "${2:-}"
            LITELLM_HOST="$2"
            PROXY_URL="http://${LITELLM_HOST}:${LITELLM_PORT}"
            OPENAI_BASE_URL_DEFAULT="${PROXY_URL}/v1"
            shift 2
            ;;
        --port)
            require_arg "--port" "${2:-}"
            LITELLM_PORT="$2"
            PROXY_URL="http://${LITELLM_HOST}:${LITELLM_PORT}"
            OPENAI_BASE_URL_DEFAULT="${PROXY_URL}/v1"
            shift 2
            ;;
        --token)
            require_arg "--token" "${2:-}"
            TOKEN_OVERRIDE="$2"
            shift 2
            ;;
        --model)
            require_arg "--model" "${2:-}"
            CODEX_MODEL="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            CHECK_HEALTH=false
            VERBOSE=true
            shift
            ;;
        --)
            shift
            CODEX_ARGS=("$@")
            break
            ;;
        *)
            CODEX_ARGS+=("$1")
            shift
            ;;
    esac
done

main() {
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}            Local Codex - LiteLLM Launcher                 ${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""

    if [ "$SHOW_HELP" = true ]; then
        print_help
        return 0
    fi

    if ! load_environment; then
        return 1
    fi

    if [ -n "$TOKEN_OVERRIDE" ]; then
        OPENAI_API_KEY="$TOKEN_OVERRIDE"
        export OPENAI_API_KEY
    fi

    if [ "$VERBOSE" = true ]; then
        show_environment
    fi

    if [ "$CHECK_HEALTH" = true ]; then
        if ! check_health; then
            return 1
        fi
        echo ""
    fi

    if [ "$DRY_RUN" = true ]; then
        log_info "Dry run mode enabled; not launching codex."
        return 0
    fi

    if ! ensure_codex_installed; then
        return 1
    fi

    log_info "Launching codex..."
    log_info "Endpoint: ${OPENAI_BASE_URL}"

    if codex_args_include_model "${CODEX_ARGS[@]}"; then
        exec env \
            OPENAI_BASE_URL="$OPENAI_BASE_URL" \
            OPENAI_API_KEY="$OPENAI_API_KEY" \
            codex "${CODEX_ARGS[@]}"
    fi

    exec env \
        OPENAI_BASE_URL="$OPENAI_BASE_URL" \
        OPENAI_API_KEY="$OPENAI_API_KEY" \
        codex -m "$CODEX_MODEL" "${CODEX_ARGS[@]}"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
