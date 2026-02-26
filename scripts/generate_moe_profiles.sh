#!/bin/bash
set -euo pipefail

# One-time MoE Profile Generator
# Run this script once to generate MoE optimization profiles for your GPU.
# The profiles will be saved to ./moe_configs/ and mounted into the container.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOE_CONFIG_DIR="${SCRIPT_DIR}/moe_configs"

# Detect if we need sudo for docker
DOCKER_CMD="docker"
if ! docker ps &>/dev/null; then
    if sudo docker ps &>/dev/null; then
        DOCKER_CMD="sudo docker"
        echo "Note: Using sudo for Docker commands"
    else
        echo "Error: Cannot access Docker. Please ensure Docker is running and you have permissions."
        exit 1
    fi
fi

DOCKER_COMPOSE_CMD="docker compose"
if ! docker compose version &>/dev/null; then
    if sudo docker compose version &>/dev/null; then
        DOCKER_COMPOSE_CMD="sudo docker compose"
    fi
fi

echo "========================================================================"
echo "vLLM MoE Profile Generator"
echo "========================================================================"
echo ""
echo "This script will generate optimized MoE kernel configurations for your GPU."
echo "These profiles will be saved to: ${MOE_CONFIG_DIR}"
echo ""

# Create the directory if it doesn't exist
mkdir -p "${MOE_CONFIG_DIR}"

# Check if container is running
if ${DOCKER_CMD} ps --format '{{.Names}}' | grep -q '^vllm-container$'; then
    echo "✓ Using running vllm-container..."
    echo ""
    ${DOCKER_CMD} exec vllm-container python3 /app/scripts/generate_moe_configs.py /tmp/moe_configs
    ${DOCKER_CMD} cp vllm-container:/tmp/moe_configs/. "${MOE_CONFIG_DIR}/"
else
    # Build the image if needed and start a temporary container
    echo "Container not running. Starting temporary container for profile generation..."
    echo ""

    # Run the profile generation in a temporary container
    ${DOCKER_COMPOSE_CMD} run --rm --no-deps \
        --entrypoint /bin/bash \
        vllm-node -c "python3 /app/scripts/generate_moe_configs.py /tmp/moe_configs && cp -r /tmp/moe_configs/* /app/moe_configs/" || {
        echo ""
        echo "Error: Failed to generate profiles in container."
        echo "Try starting the vllm-container first with: docker compose up -d vllm-node"
        exit 1
    }

    echo "✓ Profiles generated in temporary container"
fi

echo ""
echo "========================================================================"
echo "Profile Generation Complete!"
echo "========================================================================"
echo ""
echo "Generated profiles are in: ${MOE_CONFIG_DIR}"
echo ""
echo "Next steps:"
echo "1. Review the generated profiles in ${MOE_CONFIG_DIR}"
echo "2. The docker-compose.yml should be updated to mount these profiles"
echo "3. Restart your vLLM container to use the optimized profiles"
echo ""
