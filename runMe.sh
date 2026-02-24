#!/bin/bash

###############################################################################
# runMe.sh - Simplified vLLM Model Launcher
#
# Usage:
#   ./runMe.sh [MODEL_NAME] [DOCKER_COMPOSE_ARGS...]
#
# Examples:
#   ./runMe.sh                          # List available models
#   ./runMe.sh step-3.5-flash           # Launch with step-3.5-flash model
#   ./runMe.sh glm47-flash --build      # Launch with rebuild
#   ./runMe.sh qwen3-next-coder -d      # Launch in detached mode
#
###############################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${SCRIPT_DIR}/models"

# Function to read optional model description from a model YAML file
read_model_description() {
    local model_file="$1"
    local description=""

    description="$(
        awk '
            /^[[:space:]]*description:[[:space:]]*/ {
                sub(/^[[:space:]]*description:[[:space:]]*/, "", $0)
                print
                exit
            }
        ' "$model_file"
    )"

    # Strip optional surrounding single/double quotes.
    description="${description#\"}"
    description="${description%\"}"
    description="${description#\'}"
    description="${description%\'}"

    if [[ -n "$description" ]]; then
        echo "$description"
    else
        echo "No description available"
    fi
}

# Function to list available models
list_models() {
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}Available Models${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if [[ ! -d "$MODELS_DIR" ]]; then
        echo -e "${RED}Error: Models directory not found: $MODELS_DIR${NC}"
        exit 1
    fi

    local models=()
    while IFS= read -r file; do
        local model_name="${file%.yml}"
        models+=("$model_name")
    done < <(find "$MODELS_DIR" -maxdepth 1 -type f -name "*.yml" ! -name "README.md" -printf "%f\n" | sort)

    if [[ ${#models[@]} -eq 0 ]]; then
        echo -e "${RED}No model configurations found in $MODELS_DIR${NC}"
        exit 1
    fi

    for model in "${models[@]}"; do
        local model_file="${MODELS_DIR}/${model}.yml"
        local desc
        desc="$(read_model_description "$model_file")"
        echo -e "  ${GREEN}●${NC} ${BOLD}${model}${NC}"
        echo -e "    ${desc}"
        echo ""
    done

    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo -e "  ./runMe.sh ${YELLOW}<model_name>${NC} [docker-compose-args...]"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  ./runMe.sh ${YELLOW}step-3.5-flash${NC}           ${CYAN}# Start with step-3.5-flash${NC}"
    echo -e "  ./runMe.sh ${YELLOW}glm47-flash${NC} --build      ${CYAN}# Rebuild and start${NC}"
    echo -e "  ./runMe.sh ${YELLOW}qwen3-next-coder${NC} -d      ${CYAN}# Start in detached mode${NC}"
    echo ""
}

# Function to validate model exists
validate_model() {
    local model="$1"
    local model_file="${MODELS_DIR}/${model}.yml"

    if [[ ! -f "$model_file" ]]; then
        echo -e "${RED}Error: Model '${model}' not found${NC}" >&2
        echo ""
        list_models
        return 1
    fi
    return 0
}

# Function to check if running with sudo
check_sudo() {
    if [[ $EUID -eq 0 ]]; then
        echo -e "${YELLOW}Warning: Running as root. Make sure Docker permissions are configured correctly.${NC}"
    fi
}

# Main script logic
main() {
    # Check if model argument is provided
    if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        list_models
        exit 0
    fi

    local model="$1"
    shift  # Remove model from arguments

    # Validate model exists
    validate_model "$model" || exit 1

    check_sudo

    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}Launching vLLM with model: ${model}${NC}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Check if docker compose or docker-compose command exists
    local -a compose_cmd
    if command -v docker &> /dev/null && docker compose version &> /dev/null 2>&1; then
        compose_cmd=(docker compose)
    elif command -v docker-compose &> /dev/null; then
        compose_cmd=(docker-compose)
    else
        echo -e "${RED}Error: Neither 'docker compose' nor 'docker-compose' command found${NC}" >&2
        echo -e "${YELLOW}Please install Docker Compose: https://docs.docker.com/compose/install/${NC}" >&2
        exit 1
    fi

    # Check if we need sudo
    local -a sudo_prefix=()
    if ! docker ps &> /dev/null 2>&1 && [[ $EUID -ne 0 ]]; then
        if ! command -v sudo &> /dev/null; then
            echo -e "${RED}Error: Docker requires elevated permissions but 'sudo' is not available.${NC}" >&2
            exit 1
        fi

        # Prefer non-interactive sudo when credentials are already cached.
        if sudo -n true &> /dev/null; then
            echo -e "${YELLOW}Docker requires sudo. Using cached sudo credentials...${NC}"
            sudo_prefix=(sudo -n)
        # Fall back to interactive sudo when a TTY is available.
        elif [[ -t 0 && -t 1 ]]; then
            echo -e "${YELLOW}Docker requires sudo. Prompting for sudo password...${NC}"
            sudo_prefix=(sudo)
        else
            echo -e "${RED}Error: Docker requires sudo, but this shell is non-interactive and sudo needs a password.${NC}" >&2
            echo -e "${YELLOW}Run this command in an interactive terminal, add your user to the docker group, or configure passwordless sudo for docker commands.${NC}" >&2
            exit 1
        fi
    fi

    # Run docker compose with the model
    local -a run_cmd
    run_cmd=("${sudo_prefix[@]}" env "MODEL=$model" "${compose_cmd[@]}" -f "${SCRIPT_DIR}/docker-compose.yml" up)
    run_cmd+=("$@")

    echo -e "${CYAN}Running:${NC}"
    printf '  %q' "${run_cmd[@]}"
    echo ""
    echo ""
    cd "$SCRIPT_DIR"
    "${run_cmd[@]}"
}

# Run main function
main "$@"
