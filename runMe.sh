#!/bin/bash

###############################################################################
# runMe.sh - Simplified vLLM Model Launcher
#
# Usage:
#   ./runMe.sh [MODEL_NAME] [VARIANT] [DOCKER_COMPOSE_ARGS...]
#
# Examples:
#   ./runMe.sh                              # List available models
#   ./runMe.sh glm47-flash                  # Launch legacy single-model
#   ./runMe.sh glm47-flash --build          # Launch with rebuild
#   ./runMe.sh qwen3-coder-next nvfp4       # Launch family + variant
#   ./runMe.sh qwen3-coder-next nvfp4 -d    # Launch family + variant, detached
#   ./runMe.sh step-3.5 hcsw --build        # Family + variant with rebuild
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

# Function to read optional model description from a model YAML file.
# For family files, reads the defaults.description field.
read_model_description() {
    local model_file="$1"
    local description=""

    description="$(
        awk '
            # For family files, match "  description:" under "defaults:"
            /^defaults:/ { in_defaults=1; next }
            in_defaults && /^[[:space:]]+description:[[:space:]]*/ {
                sub(/^[[:space:]]*description:[[:space:]]*/, "", $0)
                print; exit
            }
            # Stop scanning defaults block on a new top-level key
            in_defaults && /^[^[:space:]]/ { in_defaults=0 }
            # For flat files, match top-level "description:"
            !in_defaults && /^description:[[:space:]]*/ {
                sub(/^description:[[:space:]]*/, "", $0)
                print; exit
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

# List variants for a family model file (returns space-separated names)
list_variants_for_model() {
    local model_file="$1"
    python3 -c "
import yaml, sys
with open('$model_file') as f:
    d = yaml.safe_load(f)
print(' '.join(sorted((d.get('variants') or {}).keys())))
" 2>/dev/null || true
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
        # Skip legacy base-only files
        [[ "$model_name" == *-base ]] && continue
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

        # For family files, list available variants
        if grep -q '^variants:' "$model_file" 2>/dev/null; then
            local variants
            variants="$(list_variants_for_model "$model_file")"
            if [[ -n "$variants" ]]; then
                echo -e "    ${CYAN}Variants: ${variants}${NC}"
            fi
        fi
        echo ""
    done

    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo -e "  ./runMe.sh ${YELLOW}<model>${NC} [docker-compose-args...]"
    echo -e "  ./runMe.sh ${YELLOW}<family> <variant>${NC} [docker-compose-args...]"
    echo -e "  ./runMe.sh ${YELLOW}--tuning <model>${NC} [--batch-sizes \"1 2 3\"] [--tp N] [--dtype DTYPE]"
    echo -e "  ./runMe.sh ${YELLOW}--tuning default <model>${NC}"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  ./runMe.sh ${YELLOW}glm47-flash${NC}                               ${CYAN}# Launch model${NC}"
    echo -e "  ./runMe.sh ${YELLOW}glm47-flash${NC} --build                       ${CYAN}# Rebuild and start${NC}"
    echo -e "  ./runMe.sh ${YELLOW}qwen3-coder-next nvfp4${NC}                    ${CYAN}# Family + variant${NC}"
    echo -e "  ./runMe.sh ${YELLOW}qwen3-coder-next nvfp4${NC} -d                 ${CYAN}# Family + variant, detached${NC}"
    echo -e "  ./runMe.sh ${YELLOW}--tuning glm47-flash${NC}                      ${CYAN}# Real GPU benchmark tuner (recommended)${NC}"
    echo -e "  ./runMe.sh ${YELLOW}--tuning glm47-flash${NC} --batch-sizes \"1 2 4\" ${CYAN}# Custom batch sizes${NC}"
    echo -e "  ./runMe.sh ${YELLOW}--tuning default glm47-flash${NC}              ${CYAN}# Fast heuristic profiles (unpredictable quality)${NC}"
    echo ""
}

# Function to validate model and optional variant
validate_model() {
    local model="$1"
    local variant="$2"  # may be empty
    local model_file="${MODELS_DIR}/${model}.yml"

    if [[ ! -f "$model_file" ]]; then
        echo -e "${RED}Error: Model '${model}' not found${NC}" >&2
        echo ""
        list_models
        return 1
    fi

    # For family files, validate (or require) the variant
    if grep -q '^variants:' "$model_file" 2>/dev/null; then
        local available
        available="$(list_variants_for_model "$model_file")"

        if [[ -z "$variant" ]]; then
            local count
            count="$(echo "$available" | wc -w)"
            if [[ "$count" -gt 1 ]]; then
                echo -e "${RED}Error: '${model}' is a family model — specify a variant.${NC}" >&2
                echo -e "  Available variants: ${CYAN}${available}${NC}" >&2
                echo -e "  Usage: ./runMe.sh ${model} <variant>" >&2
                return 1
            fi
            # count == 1: resolver will auto-select, nothing to do here
        else
            if ! echo " $available " | grep -q " $variant "; then
                echo -e "${RED}Error: Variant '${variant}' not found in model '${model}'.${NC}" >&2
                echo -e "  Available variants: ${CYAN}${available}${NC}" >&2
                return 1
            fi
        fi
    fi

    return 0
}

# Function to check if running with sudo
check_sudo() {
    if [[ $EUID -eq 0 ]]; then
        echo -e "${YELLOW}Warning: Running as root. Make sure Docker permissions are configured correctly.${NC}"
    fi
}

# Run fast heuristic MoE profile generation (no GPU benchmarking).
# Profiles are generated from pre-set heuristics for common (E, N, dtype)
# combinations. Speed: seconds. Quality: unpredictable — can improve, be
# neutral, or slightly worsen throughput compared to vLLM defaults.
run_heuristic_tuning() {
    local model="$1"
    local output_dir="${SCRIPT_DIR}/moe_configs/${model}"

    echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${YELLOW}  ⚠  HEURISTIC MoE PROFILES — READ BEFORE CONTINUING${NC}"
    echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  These profiles are generated from ${BOLD}pre-set heuristics${NC}, NOT from"
    echo -e "  real GPU benchmarks. They are fast to produce (seconds vs. minutes),"
    echo -e "  but the quality is ${BOLD}unpredictable${NC}: they may improve throughput,"
    echo -e "  have no effect, or in rare cases make inference slightly slower."
    echo ""
    echo -e "  ${GREEN}Use this when:${NC}"
    echo -e "    • You want profiles immediately and will run the real tuner later"
    echo -e "    • You cannot spare GPU time for full benchmarking right now"
    echo ""
    echo -e "  ${CYAN}For benchmark-verified profiles (recommended):${NC}"
    echo -e "    ${YELLOW}./runMe.sh --tuning ${model}${NC}   (real GPU benchmarks, a few minutes)"
    echo ""
    echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Docker compose detection
    local -a compose_cmd
    if docker compose version &>/dev/null 2>&1; then
        compose_cmd=(docker compose)
    elif command -v docker-compose &>/dev/null; then
        compose_cmd=(docker-compose)
    else
        echo -e "${RED}Error: Neither 'docker compose' nor 'docker-compose' found.${NC}" >&2
        exit 1
    fi

    # Sudo detection
    local -a sudo_prefix=()
    if ! docker ps &>/dev/null 2>&1 && [[ $EUID -ne 0 ]]; then
        if sudo -n true &>/dev/null; then
            sudo_prefix=(sudo -n)
        elif [[ -t 0 && -t 1 ]]; then
            sudo_prefix=(sudo)
        else
            echo -e "${RED}Error: Docker requires sudo but no interactive terminal available.${NC}" >&2
            exit 1
        fi
    fi

    mkdir -p "${output_dir}"

    echo -e "${CYAN}Generating heuristic profiles for: ${BOLD}${model}${NC}"
    echo -e "${CYAN}Output: ${output_dir}/${NC}"
    echo ""

    "${sudo_prefix[@]+"${sudo_prefix[@]}"}" "${compose_cmd[@]}" \
        -f "${SCRIPT_DIR}/docker-compose.yml" \
        run --rm --no-deps \
        --volume "${output_dir}:/moe_output:rw" \
        --entrypoint bash \
        -e "MODEL=${model}" \
        vllm-node -c "python3 /app/scripts/generate_moe_configs.py /moe_output"

    echo ""
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}  Heuristic profiles saved!${NC}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    if ls "${output_dir}"/*.json &>/dev/null 2>&1; then
        ls -lh "${output_dir}"/*.json
    else
        echo -e "  ${YELLOW}(no .json files found — check output above for errors)${NC}"
    fi
    echo ""
    echo -e "  ${YELLOW}Remember:${NC} for benchmark-verified profiles run:"
    echo -e "    ${YELLOW}./runMe.sh --tuning ${model}${NC}"
    echo ""
}

# Main script logic
main() {
    # Check if model argument is provided
    if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        list_models
        exit 0
    fi

    # ── MoE tuning mode ──────────────────────────────────────────────────────
    # Real tuner:     ./runMe.sh --tuning <model> [--batch-sizes "1 2 3"] [--tp N] [--dtype DTYPE]
    # Heuristic fast: ./runMe.sh --tuning default <model>
    if [[ "$1" == "--tuning" ]]; then
        shift
        if [[ $# -eq 0 ]]; then
            echo -e "${RED}Error: --tuning requires a mode or model name.${NC}" >&2
            echo -e "  ${BOLD}Real GPU benchmarks:${NC}  ./runMe.sh --tuning <model>" >&2
            echo -e "  ${BOLD}Fast heuristic:${NC}       ./runMe.sh --tuning default <model>" >&2
            exit 1
        fi

        # Heuristic mode: --tuning default <model>
        if [[ "$1" == "default" ]]; then
            shift
            if [[ $# -eq 0 ]]; then
                echo -e "${RED}Error: --tuning default requires a model name.${NC}" >&2
                echo -e "  Usage: ./runMe.sh --tuning default <model>" >&2
                exit 1
            fi
            local heuristic_model="$1"

            # For family models, auto-select first variant
            local heuristic_variant=""
            local model_file="${MODELS_DIR}/${heuristic_model}.yml"
            if grep -q '^variants:' "$model_file" 2>/dev/null; then
                local available
                available="$(list_variants_for_model "$model_file")"
                heuristic_variant="$(echo "$available" | tr ' ' '\n' | head -n1)"
            fi

            validate_model "$heuristic_model" "$heuristic_variant" || exit 1
            run_heuristic_tuning "$heuristic_model"
            exit 0
        fi

        # Real GPU benchmarking mode: --tuning <model>
        local tuning_model="$1"
        shift

        # For family models, if no variant is specified, auto-select the first one
        local tuning_variant=""
        local model_file="${MODELS_DIR}/${tuning_model}.yml"
        if grep -q '^variants:' "$model_file" 2>/dev/null; then
            local available
            available="$(list_variants_for_model "$model_file")"
            if [[ $# -eq 0 ]] || [[ "$1" =~ ^-- ]]; then
                # No variant specified, use first available
                tuning_variant="$(echo "$available" | tr ' ' '\n' | head -n1)"
                echo -e "${BOLD}${CYAN}Family model detected — using variant: ${tuning_variant}${NC}"
                echo ""
            else
                # Variant provided as next argument
                tuning_variant="$1"
                shift
            fi
        fi

        # Validate model (with selected variant if applicable)
        validate_model "$tuning_model" "$tuning_variant" || exit 1

        echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}${CYAN}MoE Kernel Tuning: ${tuning_model}${NC}"
        [[ -n "$tuning_variant" ]] && echo -e "${BOLD}${CYAN}Variant: ${tuning_variant}${NC}"
        echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""

        # Delegate entirely to tune_moe.sh — it owns the docker compose run logic
        # Export variant for family models
        if [[ -n "$tuning_variant" ]]; then
            (export VARIANT="$tuning_variant"; exec "${SCRIPT_DIR}/scripts/tune_moe.sh" "$tuning_model" "$@")
        else
            exec "${SCRIPT_DIR}/scripts/tune_moe.sh" "$tuning_model" "$@"
        fi
    fi

    local model="$1"
    shift  # Remove model from arguments

    # Check if next positional arg is a variant (for family files)
    local variant=""
    if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
        local model_file="${MODELS_DIR}/${model}.yml"
        if grep -q '^variants:' "$model_file" 2>/dev/null; then
            variant="$1"
            shift
        fi
    fi

    # Validate model (and variant if provided)
    validate_model "$model" "$variant" || exit 1

    check_sudo

    if [[ -n "$variant" ]]; then
        echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}${GREEN}Launching vLLM: ${model} / ${variant}${NC}"
        echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    else
        echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}${GREEN}Launching vLLM with model: ${model}${NC}"
        echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi
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

    # Build the run command, passing MODEL and VARIANT as environment
    local -a run_cmd
    run_cmd=("${sudo_prefix[@]}" env "MODEL=$model" "VARIANT=$variant" \
        "${compose_cmd[@]}" -f "${SCRIPT_DIR}/docker-compose.yml" up)
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
