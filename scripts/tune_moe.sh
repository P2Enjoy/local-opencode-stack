#!/bin/bash
set -euo pipefail

# tune_moe.sh - Real vLLM MoE kernel tuner launcher
#
# Runs `python3 -m vllm.model_executor.layers.fused_moe.tune` inside the Docker
# container to produce BENCHMARK-VERIFIED kernel profiles for your specific GPU.
# Profiles are saved to ./moe_configs/<model_config_name>/ and automatically
# mounted into the vLLM container when that model is started.
#
# Usage:
#   ./tune_moe.sh <model_config_name> [OPTIONS]
#
# Examples:
#   ./tune_moe.sh qwen3-next-coder
#   ./tune_moe.sh glm47-flash --batch-sizes "1 2 4 8 16"
#   ./tune_moe.sh step-3.5-flash --dtype fp8 --tp 1

# This script lives in scripts/ — climb one level to reach the project root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS_DIR="${SCRIPT_DIR}/models"
MOE_CONFIG_DIR="${SCRIPT_DIR}/moe_configs"

# Defaults (auto-detected from model YAML unless overridden)
BATCH_SIZES="1 2 3 4 5"
TP=""
DTYPE=""

# ─── Usage ───────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") <model_config_name> [OPTIONS]

Runs the real vLLM MoE kernel tuner (actual GPU benchmarks) for interactive
small-batch inference. Profiles are saved to ./moe_configs/<model_config_name>/
and mounted automatically when that model is started via docker compose.

Arguments:
  model_config_name   Model config name (filename in ./models/ without .yml)

Options:
  --tp N                    Tensor parallel size (default: auto from model config)
  --dtype DTYPE             fp8 | float16 | bfloat16 (default: auto from config)
  --batch-sizes "1 2 3..."  Batch sizes to benchmark (default: "$BATCH_SIZES")
  -h, --help                Show this help

Available models:
EOF
    for f in "${MODELS_DIR}"/*.yml; do
        [[ -f "$f" ]] || continue
        name=$(basename "$f" .yml)
        hf_id=$(python3 -c "
import yaml, re
with open('$f') as fh:
    m = yaml.safe_load(fh)
cmd = m.get('command', '')
match = re.search(r'vllm serve\s+(\S+)', cmd)
print(match.group(1) if match else '?')
" 2>/dev/null || echo "?")
        tuned_marker=""
        [[ -d "${MOE_CONFIG_DIR}/${name}" ]] && \
            [[ -n "$(ls "${MOE_CONFIG_DIR}/${name}"/*.json 2>/dev/null)" ]] && \
            tuned_marker=" [tuned]"
        printf "  %-32s -> %s%s\n" "$name" "$hf_id" "$tuned_marker"
    done
    echo ""
    echo "Profiles directory: ${MOE_CONFIG_DIR}/"
    exit 0
}

# ─── Argument parsing ─────────────────────────────────────────────────────────

MODEL_NAME=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        --tp)          TP="$2";           shift 2 ;;
        --dtype)       DTYPE="$2";        shift 2 ;;
        --batch-sizes) BATCH_SIZES="$2";  shift 2 ;;
        -*)
            echo "Unknown option: $1"
            echo ""
            usage
            ;;
        *)
            if [[ -z "$MODEL_NAME" ]]; then
                MODEL_NAME="$1"
            else
                echo "Unexpected argument: $1"
                echo ""
                usage
            fi
            shift
            ;;
    esac
done

if [[ -z "$MODEL_NAME" ]]; then
    echo "Error: model_config_name is required."
    echo ""
    usage
fi

# ─── Resolve model config ─────────────────────────────────────────────────────

MODEL_CONFIG_FILE="${MODELS_DIR}/${MODEL_NAME}.yml"
if [[ ! -f "$MODEL_CONFIG_FILE" ]]; then
    echo "Error: Model config not found: ${MODEL_CONFIG_FILE}"
    echo ""
    echo "Available models:"
    for f in "${MODELS_DIR}"/*.yml; do
        [[ -f "$f" ]] || continue
        echo "  $(basename "$f" .yml)"
    done
    exit 1
fi

# Parse model YAML to extract HF model ID, TP, and dtype
# Handles both flat model configs and family configs with variants
PARSE_RESULT=$(python3 - <<PYTHON_EOF
import yaml, re, os, sys

with open("${MODEL_CONFIG_FILE}") as f:
    model = yaml.safe_load(f)

# Determine which variant/command to use
command = ""
is_family = "variants" in model

if is_family:
    # Family file: get variant from ENV or use first alphabetically
    variant_name = os.environ.get("VARIANT", "")
    variants = model.get("variants", {})

    if variant_name and variant_name not in variants:
        print(f"Error: Variant '{variant_name}' not found in model config", file=sys.stderr)
        print(f"Available: {' '.join(sorted(variants.keys()))}", file=sys.stderr)
        sys.exit(1)

    if not variant_name:
        # Use first variant alphabetically
        variant_name = sorted(variants.keys())[0]

    variant_cmd = variants[variant_name].get("command", "")
    if not variant_cmd:
        print(f"Error: Variant '{variant_name}' has no command defined", file=sys.stderr)
        sys.exit(1)
    command = variant_cmd
else:
    # Flat config: use top-level command
    command = model.get("command", "")

if not command:
    print("Error: No command found in model config", file=sys.stderr)
    sys.exit(1)

# HF model ID: first argument after 'vllm serve'
match = re.search(r"vllm serve\s+(\S+)", command)
hf_id = match.group(1) if match else ""

# Tensor parallel size
tp_match = re.search(r"--tensor-parallel-size\s+(\d+)", command)
tp = tp_match.group(1) if tp_match else "1"

# Dtype: prefer --quantization, fall back to --kv-cache-dtype
dtype = "fp8"  # safe default for fp8 models
quant_match = re.search(r"--quantization\s+(\S+)", command)
kv_match = re.search(r"--kv-cache-dtype\s+(\S+)", command)
if quant_match:
    dtype = quant_match.group(1)
elif kv_match:
    dtype = kv_match.group(1)

print(f"{hf_id}|{tp}|{dtype}")
PYTHON_EOF
)

MODEL_HF_ID=$(echo "$PARSE_RESULT" | cut -d'|' -f1)
[[ -z "$TP"    ]] && TP=$(echo "$PARSE_RESULT"    | cut -d'|' -f2)
[[ -z "$DTYPE" ]] && DTYPE=$(echo "$PARSE_RESULT" | cut -d'|' -f3)

if [[ -z "$MODEL_HF_ID" ]]; then
    echo "Error: Could not extract HuggingFace model ID from ${MODEL_CONFIG_FILE}"
    echo "       Make sure the config has a 'vllm serve <model_id>' command."
    exit 1
fi

# ─── Docker detection ─────────────────────────────────────────────────────────

if docker ps &>/dev/null; then
    DOCKER=("docker")
elif sudo docker ps &>/dev/null; then
    DOCKER=("sudo" "docker")
    echo "Note: Using sudo for Docker commands"
else
    echo "Error: Cannot access Docker. Make sure Docker is running."
    exit 1
fi

DOCKER_COMPOSE=("${DOCKER[@]}" "compose" "-f" "${SCRIPT_DIR}/docker-compose.yml")

# ─── GPU contention check ─────────────────────────────────────────────────────

if "${DOCKER[@]}" ps --format '{{.Names}}' 2>/dev/null | grep -q '^vllm-container$'; then
    echo "WARNING: vllm-container is running and using the GPU."
    echo "         Tuning benchmarks will compete for GPU resources."
    echo "         Stop it first for accurate profiles:"
    echo "           docker compose stop vllm-node"
    echo ""
    read -rp "Continue anyway? [y/N] " CONFIRM
    [[ "$CONFIRM" =~ ^[yY]$ ]] || { echo "Aborted."; exit 0; }
fi

# ─── Load HF token from secrets ───────────────────────────────────────────────

HF_TOKEN=""
if [[ -f "${SCRIPT_DIR}/secrets/HF_TOKEN" ]]; then
    HF_TOKEN=$(tr -d '[:space:]' < "${SCRIPT_DIR}/secrets/HF_TOKEN")
fi

# ─── Prepare output directory ─────────────────────────────────────────────────

MODEL_MOE_DIR="${MOE_CONFIG_DIR}/${MODEL_NAME}"
mkdir -p "${MODEL_MOE_DIR}"

echo ""
echo "========================================================================"
echo "  vLLM MoE Real Kernel Tuner"
echo "========================================================================"
echo "  Model config  : ${MODEL_NAME}"
echo "  HF model ID   : ${MODEL_HF_ID}"
echo "  Tensor parallel: ${TP}"
echo "  Dtype          : ${DTYPE}"
echo "  Batch sizes    : ${BATCH_SIZES}"
echo "  Profiles out   : ${MODEL_MOE_DIR}/"
echo "========================================================================"
echo ""
echo "  This runs ACTUAL Triton kernel benchmarks on your GPU."
echo "  The tuner will try all kernel configurations and keep the fastest."
echo "  Expect several minutes per batch size."
echo ""

# ─── Build the tune command ───────────────────────────────────────────────────

TUNE_CMD="python3 -m vllm.model_executor.layers.fused_moe.tune \
    --model ${MODEL_HF_ID} \
    --tp ${TP} \
    --dtype ${DTYPE} \
    --d ${BATCH_SIZES} \
    --save-path /moe_output"

echo "  Command: ${TUNE_CMD}"
echo ""

# ─── Run tuner in container ───────────────────────────────────────────────────
# Uses `docker compose run` to pick up the correct vLLM image and environment.
# - Overrides entrypoint to bypass run_vllm_agent.sh
# - Mounts MODEL_MOE_DIR as rw at /moe_output (tuner writes here)
# - The existing ro moe_configs mount in compose is ignored by the tuner
# - Passes HF_TOKEN for gated model downloads

RUN_ARGS=(
    run --rm --no-deps
    --volume "${MODEL_MOE_DIR}:/moe_output:rw"
    --entrypoint bash
)

if [[ -n "$HF_TOKEN" ]]; then
    RUN_ARGS+=(-e "HF_TOKEN=${HF_TOKEN}")
    RUN_ARGS+=(-e "HUGGING_FACE_HUB_TOKEN=${HF_TOKEN}")
fi

"${DOCKER_COMPOSE[@]}" "${RUN_ARGS[@]}" vllm-node -c "cd /tmp/vllm_moe_tune/ && ${TUNE_CMD}"

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "========================================================================"
echo "  Tuning complete!"
echo "========================================================================"
echo ""
echo "  Profiles saved to: ${MODEL_MOE_DIR}/"
echo ""

if ls "${MODEL_MOE_DIR}"/*.json &>/dev/null; then
    ls -lh "${MODEL_MOE_DIR}"/*.json
else
    echo "  (no .json files found — check tuner output above for errors)"
fi

echo ""
echo "  Start the server with optimized profiles:"
echo "    MODEL=${MODEL_NAME} docker compose up vllm-node"
echo ""
