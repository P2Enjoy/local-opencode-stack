#!/bin/bash
set -e

# VLLM Agent Launcher Script
# This script:
# 1. Loads ALL environment variables from vars.env (global exports for every execution)
# 2. Generates LiteLLM config.yaml from template + global defaults + model-specific overrides
# 3. Reads the MODEL environment variable and corresponding configuration from models.yml
# 4. Applies model-specific environment variables on top of global vars
# 5. Executes the corresponding vllm serve command

# Source vars.env to load all environment variables globally
VARS_FILE="${VARS_FILE:-.env}"
if [ -f "$VARS_FILE" ]; then
    set -a
    source "$VARS_FILE"
    set +a
fi

# Generate LiteLLM config.yaml to shared volume
echo "Generating LiteLLM configuration..."
mkdir -p /app/generated_configs
python3 "$(dirname "$0")/generate_litellm_config.py" \
  --output-file /app/generated_configs/config.yaml || exit 1

# Get the vllm serve command and model-specific env vars for the selected model from models.yml
read -r COMMAND MODEL_ENV_JSON < <(python3 << 'PYTHON_EOF'
import yaml
import os
import sys
import json

model_name = os.environ.get('MODEL', 'glm47-flash')
models_file = '/app/models.yml'

try:
    with open(models_file, 'r') as f:
        models = yaml.safe_load(f)

    if model_name not in models:
        print(f"Error: Model '{model_name}' not found in {models_file}", file=sys.stderr)
        print(f"Available models: {', '.join(sorted(models.keys()))}", file=sys.stderr)
        sys.exit(1)

    model_config = models[model_name]
    command = model_config.get('command', '').strip()
    model_env = model_config.get('env', {})

    if not command:
        print(f"Error: Model '{model_name}' has no command defined", file=sys.stderr)
        sys.exit(1)

    print(command, json.dumps(model_env))
except FileNotFoundError:
    print(f"Error: Configuration file not found: {models_file}", file=sys.stderr)
    print("Make sure models.yml is mounted in the container", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"Error loading model configuration: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
)

# Parse and apply model-specific environment variables
MODEL_ENV_DICT=$(python3 -c "import json, sys; d = json.loads('$MODEL_ENV_JSON'); print(' '.join([f'{k}={v}' for k, v in d.items()]))")

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "VLLM Agent Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Model: $MODEL"
echo "Configuration File: /app/models.yml"
echo "Global Variables Exported: $(env | grep -E '^(HF_TOKEN|ANTHROPIC)' | cut -d= -f1 | tr '\n' ' ')"
echo "Model-Specific Variables: $MODEL_ENV_DICT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Export model-specific environment variables
for var_assignment in $MODEL_ENV_DICT; do
    export "$var_assignment"
done

# Execute the command, replacing the current shell process
exec bash -c "$COMMAND --api-key sk-FAKE --served-model-name vllm_agent --gpu-memory-utilization 0.85"
