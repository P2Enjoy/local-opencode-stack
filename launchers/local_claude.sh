#!/bin/bash

###############################################################################
# Local Claude Launcher - Routes Claude Code through LiteLLM Proxy
#
# This script sets up Anthropic environment variables to use a local
# LiteLLM proxy and launches Claude Code (the CLI tool).
#
# Usage:
#   local_claude.sh [OPTIONS] [CLAUDE_ARGS]
#
# Examples:
#   local_claude.sh                    # Launch Claude Code normally
#   local_claude.sh --no-check         # Skip health check
#   local_claude.sh --verbose          # Show environment variables
#   local_claude.sh --help             # Show this help
#
# You can add this to your PATH:
#   export PATH="/home/p2enjoy/jupyterlab/vllm-server/launchers:$PATH"
#
###############################################################################

set -euo pipefail

# Get the directory where this script is located (works from any path)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# vars.env is in the parent directory (vllm-server root)
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VARS_FILE="${PROJECT_DIR}/vars.env"
SECRETS_DIR="${SECRETS_DIR:-${PROJECT_DIR}/secrets}"
SECRETS_HELPER="${PROJECT_DIR}/scripts/load_secrets_env.sh"

# Default configuration
LITELLM_HOST="${LITELLM_HOST:-localhost}"
LITELLM_PORT="${LITELLM_PORT:-4000}"
PROXY_URL="http://${LITELLM_HOST}:${LITELLM_PORT}"
CHECK_HEALTH=true
VERBOSE=false
SHOW_HELP=false
DRY_RUN=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

###############################################################################
# Helper Functions
###############################################################################

log_info() {
    echo -e "${BLUE}ℹ  $1${NC}" >&2
}

log_success() {
    echo -e "${GREEN}✓  $1${NC}" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠  $1${NC}" >&2
}

log_error() {
    echo -e "${RED}✗  $1${NC}" >&2
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
            ANTHROPIC_*|CLAUDE_CODE_*|HF_TOKEN|MODEL)
                export "$key=$value"
                ;;
        esac
    done < "$file"
}

print_help() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║           Local Claude Launcher for LiteLLM Proxy              ║
╚════════════════════════════════════════════════════════════════╝

DESCRIPTION:
  Routes Claude Code through a local LiteLLM proxy that connects
  to a local vLLM backend. This allows Claude Code to use models
  running on your local hardware via the Anthropic API format.

USAGE:
  local_claude.sh [OPTIONS] [CLAUDE_ARGS]

OPTIONS:
  --help              Show this help message
  --verbose           Display environment variables and configuration
  --no-check          Skip health check of the proxy
  --host HOST         Override litellm proxy host (default: localhost)
  --port PORT         Override litellm proxy port (default: 4000)
  --token TOKEN       Override API token (default: sk-FAKE)
  --dry-run           Show environment variables and exit without launching

EXAMPLES:
  # Launch Claude Code with local proxy
  local_claude.sh

  # Launch with verbose output
  local_claude.sh --verbose

  # Launch with custom proxy host
  local_claude.sh --host 192.168.1.100 --port 8080

  # Show what would be set without launching
  local_claude.sh --dry-run

  # Pass arguments to Claude Code
  local_claude.sh -- /path/to/project
  local_claude.sh --verbose -- /path/to/project

SETUP:
  1. Start the services:
     docker compose -f /home/p2enjoy/jupyterlab/vllm-server/docker-compose.yml up -d

  2. Test the connection:
     /home/p2enjoy/jupyterlab/vllm-server/launchers/test.sh

  3. Add to your PATH (optional):
     export PATH="/home/p2enjoy/jupyterlab/vllm-server:$PATH"

  4. Then use from anywhere:
     local_claude.sh

ENVIRONMENT VARIABLES:
  These are set automatically based on vars.env:
  - ANTHROPIC_BASE_URL       LiteLLM proxy URL
  - ANTHROPIC_AUTH_TOKEN     API authentication token
  - CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
                              Disable non-essential network traffic

TROUBLESHOOTING:
  If Claude Code doesn't connect:

  1. Check if services are running:
     docker compose -f /home/p2enjoy/jupyterlab/vllm-server/docker-compose.yml ps

  2. Test the proxy manually:
     /home/p2enjoy/jupyterlab/vllm-server/launchers/test.sh

  3. Check logs:
     docker compose -f /home/p2enjoy/jupyterlab/vllm-server/docker-compose.yml logs litellm

  4. Try with verbose mode:
     local_claude.sh --verbose

EOF
}

ensure_claude_code_installed() {
    # Check if claude-code or claude is already installed
    if command -v claude-code &> /dev/null || command -v claude &> /dev/null; then
        log_success "Claude Code is installed"
        return 0
    fi

    log_warning "Claude Code CLI not found. Installing..."
    echo ""

    # Check if npm is available
    if ! command -v npm &> /dev/null; then
        log_error "npm is not installed. Cannot install Claude Code."
        log_info "Please install Node.js and npm first, then run this script again."
        return 1
    fi

    # Install Claude Code globally
    log_info "Installing @anthropic-ai/claude-code..."
    if sudo npm install -g @anthropic-ai/claude-code; then
        log_success "Claude Code installed successfully"
        echo ""
        return 0
    else
        log_error "Failed to install Claude Code"
        log_info "Try installing manually with: sudo npm install -g @anthropic-ai/claude-code"
        return 1
    fi
}

check_health() {
    log_info "Checking LiteLLM proxy at ${PROXY_URL}..."

    if ! timeout 5 curl -fsS "${PROXY_URL}/health/liveliness" > /dev/null 2>&1; then
        log_error "LiteLLM proxy is not responding at ${PROXY_URL}"
        log_info ""
        log_info "To start the services, run:"
        log_info "  cd ${PROJECT_DIR}"
        log_info "  docker compose up -d"
        log_info ""
        log_info "To skip this check in the future, use: local_claude.sh --no-check"
        return 1
    fi

    log_success "LiteLLM proxy is healthy"
    return 0
}

load_environment() {
    # Check if vars.env exists
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

    # Override with environment-specific settings
    export ANTHROPIC_BASE_URL="${PROXY_URL}"
    export ANTHROPIC_AUTH_TOKEN="${ANTHROPIC_AUTH_TOKEN:-sk-FAKE}"
    export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

    return 0
}

show_environment() {
    log_info "Environment Configuration:"
    echo "  ANTHROPIC_BASE_URL: ${ANTHROPIC_BASE_URL}"
    echo "  ANTHROPIC_AUTH_TOKEN: ${ANTHROPIC_AUTH_TOKEN:0:10}..."
    echo "  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: ${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC}"
    if [ -n "${MODEL:-}" ]; then
        echo "  MODEL: ${MODEL}"
    fi
    if [ -n "${HF_TOKEN:-}" ]; then
        echo "  HF_TOKEN: ${HF_TOKEN:0:10}..."
    fi
    echo ""
}

###############################################################################
# Parse Command Line Arguments
###############################################################################

CLAUDE_ARGS=()
parse_args=true

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
            shift 2
            ;;
        --port)
            require_arg "--port" "${2:-}"
            LITELLM_PORT="$2"
            PROXY_URL="http://${LITELLM_HOST}:${LITELLM_PORT}"
            shift 2
            ;;
        --token)
            require_arg "--token" "${2:-}"
            ANTHROPIC_AUTH_TOKEN="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            CHECK_HEALTH=false
            VERBOSE=true
            shift
            ;;
        --)
            # Stop parsing options, rest are claude args
            shift
            CLAUDE_ARGS=("$@")
            break
            ;;
        *)
            # Any other argument is passed to claude
            CLAUDE_ARGS+=("$1")
            shift
            ;;
    esac
done

###############################################################################
# Main Execution
###############################################################################

main() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          Local Claude - LiteLLM Proxy Launcher                 ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Show help if requested
    if [ "$SHOW_HELP" = true ]; then
        print_help
        return 0
    fi

    # Load environment variables
    if ! load_environment; then
        log_error "Failed to load environment configuration"
        return 1
    fi

    # Update proxy URL if custom host/port was provided
    export ANTHROPIC_BASE_URL="${PROXY_URL}"

    # Show configuration if verbose
    if [ "$VERBOSE" = true ]; then
        show_environment
    fi

    # Check proxy health
    if [ "$CHECK_HEALTH" = true ]; then
        echo ""
        if ! check_health; then
            return 1
        fi
    fi

    # Dry run mode - just show environment and exit
    if [ "$DRY_RUN" = true ]; then
        log_info "Dry run mode - environment variables set but claude-code not launched"
        return 0
    fi

    # Ensure Claude Code is installed
    echo ""
    if ! ensure_claude_code_installed; then
        return 1
    fi

    # Launch Claude Code with the environment variables
    echo ""
    log_info "Launching Claude Code..."
    log_info "Proxy: ${ANTHROPIC_BASE_URL}"
    echo ""

    # Determine which command to use
    if command -v claude-code &> /dev/null; then
        CLAUDE_CMD="claude-code"
    elif command -v claude &> /dev/null; then
        CLAUDE_CMD="claude"
    else
        log_error "Claude Code CLI could not be found after installation attempt"
        return 1
    fi

    # Launch Claude Code with collected arguments
    exec "$CLAUDE_CMD" "${CLAUDE_ARGS[@]}"
}

# Run main function
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
