#!/bin/bash

###############################################################################
# OpenCode.ai Launcher - Routes OpenCode through LiteLLM Proxy
#
# This script sets up Anthropic environment variables to use a local
# LiteLLM proxy and launches OpenCode.ai with local model support.
#
# Usage:
#   open_code.sh [OPTIONS] [OPENCODE_ARGS]
#
# Examples:
#   open_code.sh                    # Launch OpenCode normally
#   open_code.sh --help             # Show this help
#   open_code.sh --verbose          # Show environment variables
#   open_code.sh --no-check         # Skip health check
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
║       OpenCode.ai - LiteLLM Proxy Support                      ║
╚════════════════════════════════════════════════════════════════╝

DESCRIPTION:
  Routes OpenCode.ai through a local LiteLLM proxy that connects
  to a local vLLM backend. This allows OpenCode to use models
  running on your local hardware via the Anthropic API format.

  OpenCode is an AI coding agent available as:
  - Terminal interface
  - IDE extensions (VS Code, JetBrains, etc)
  - Desktop application

USAGE:
  open_code.sh [OPTIONS] [OPENCODE_ARGS]

OPTIONS:
  --help              Show this help message
  --verbose           Display environment variables and configuration
  --no-check          Skip health check of the proxy
  --host HOST         Override litellm proxy host (default: localhost)
  --port PORT         Override litellm proxy port (default: 4000)
  --token TOKEN       Override API token (default: sk-FAKE)
  --dry-run           Show environment variables and exit without launching
  --install           Install/update OpenCode if not found

EXAMPLES:
  # Launch OpenCode with local proxy
  open_code.sh

  # Launch with verbose output
  open_code.sh --verbose

  # Launch with custom proxy host
  open_code.sh --host 192.168.1.100 --port 8080

  # Show what would be set without launching
  open_code.sh --dry-run

  # Pass arguments to OpenCode
  open_code.sh -- --help
  open_code.sh -- --model anthropic/glm47-flash

SETUP:
  1. Install OpenCode (if not already installed):
     curl -fsSL https://opencode.ai/install | bash

  2. Start the services:
     docker compose -f /home/p2enjoy/jupyterlab/vllm-server/docker-compose.yml up -d

  3. Test the connection:
     /home/p2enjoy/jupyterlab/vllm-server/launchers/test.sh

  4. Launch OpenCode:
     open_code.sh

  5. Add to your PATH (optional):
     export PATH="/home/p2enjoy/jupyterlab/vllm-server/launchers:$PATH"

  6. Then use from anywhere:
     open_code.sh

ENVIRONMENT VARIABLES:
  These are set automatically based on vars.env:
  - ANTHROPIC_BASE_URL       LiteLLM proxy URL
  - ANTHROPIC_AUTH_TOKEN     API authentication token
  - CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
                              Disable non-essential network traffic

OPENCODE FEATURES:
  - Works in your terminal
  - IDE integration (VS Code, JetBrains, Vim, Emacs)
  - Desktop application
  - Supports 75+ LLM providers
  - Privacy-first (no code storage)

WORKFLOW:
  1. Start services: docker compose up -d
  2. Launch: open_code.sh
  3. Use commands like:
     - code [filename]      Generate/edit code
     - test [filename]      Generate tests
     - explain [filename]   Explain code
     - review [filename]    Review code

DOCUMENTATION:
  - OpenCode.ai: https://opencode.ai/
  - GitHub: https://github.com/opencode-ai/opencode

TROUBLESHOOTING:
  OpenCode command not found:
    1. Install: curl -fsSL https://opencode.ai/install | bash
    2. Or use: open_code.sh --install
    3. Verify: which opencode

  Can't connect to proxy:
    1. Check proxy health: open_code.sh --verbose
    2. Start services: docker compose -f /home/p2enjoy/jupyterlab/vllm-server/docker-compose.yml up -d
    3. Test connection: /home/p2enjoy/jupyterlab/vllm-server/launchers/test.sh

  Environment variables not set:
    1. Check configuration: open_code.sh --dry-run
    2. Verify vars.env: cat /home/p2enjoy/jupyterlab/vllm-server/vars.env

EOF
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
        log_info "To skip this check in the future, use: open_code.sh --no-check"
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

check_opencode_installed() {
    if command -v opencode &> /dev/null; then
        log_success "OpenCode is installed"
        return 0
    fi

    log_warning "OpenCode CLI not found in PATH"
    log_info ""
    log_info "To install OpenCode, run:"
    log_info "  curl -fsSL https://opencode.ai/install | bash"
    log_info ""
    log_info "Or use this launcher with --install flag:"
    log_info "  open_code.sh --install"
    return 1
}

install_opencode() {
    log_info "Installing OpenCode..."
    echo ""

    if curl -fsSL https://opencode.ai/install | bash; then
        log_success "OpenCode installed successfully"
        echo ""
        return 0
    else
        log_error "Failed to install OpenCode"
        log_info "Try installing manually: curl -fsSL https://opencode.ai/install | bash"
        return 1
    fi
}

###############################################################################
# Parse Command Line Arguments
###############################################################################

OPENCODE_ARGS=()
INSTALL_FLAG=false
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
        --install)
            INSTALL_FLAG=true
            shift
            ;;
        --)
            # Stop parsing options, rest are opencode args
            shift
            OPENCODE_ARGS=("$@")
            break
            ;;
        *)
            # Any other argument is passed to opencode
            OPENCODE_ARGS+=("$1")
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
    echo -e "${CYAN}║      OpenCode.ai - LiteLLM Proxy Launcher                      ║${NC}"
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
        log_info "Dry run mode - environment variables set but OpenCode not launched"
        return 0
    fi

    # Check if OpenCode is installed, optionally install
    echo ""
    if ! check_opencode_installed; then
        if [ "$INSTALL_FLAG" = true ]; then
            if ! install_opencode; then
                return 1
            fi
        else
            log_warning "Use --install flag to automatically install OpenCode"
            return 1
        fi
    fi

    # Launch OpenCode with the environment variables
    echo ""
    log_info "Launching OpenCode.ai..."
    log_info "Proxy: ${ANTHROPIC_BASE_URL}"
    echo ""

    # Launch OpenCode with collected arguments and environment variables
    exec env \
        ANTHROPIC_BASE_URL="$ANTHROPIC_BASE_URL" \
        ANTHROPIC_AUTH_TOKEN="$ANTHROPIC_AUTH_TOKEN" \
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" \
        opencode "${OPENCODE_ARGS[@]}"
}

# Run main function
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
