#!/bin/bash
set -euo pipefail

# VLLM Agent Launcher Script
# This script:
# 1. Loads ALL environment variables from vars.env (global exports for every execution)
# 2. Generates LiteLLM config.yaml from template + global defaults + model-specific overrides
# 3. Reads the MODEL environment variable and corresponding configuration from models.yml
# 4. Applies model-specific environment variables on top of global vars
# 5. Executes the corresponding vllm serve command

# Source vars.env to load all environment variables globally
VARS_FILE="${VARS_FILE:-/app/vars.env}"
if [ -f "$VARS_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$VARS_FILE"
    set +a
fi

MODEL="${MODEL:-glm47-flash}"
GENERATED_MODELS_FILE="/app/generated_configs/models.yml"

# Build models.yml inside the container from model fragments.
# If MODEL is set, only that model fragment is included.
echo "Generating models.yml..."
mkdir -p /app/generated_configs
/app/scripts/gen_models_yml.sh \
  --model "${MODEL:-}" \
  || exit 1

# Generate LiteLLM config.yaml to shared volume
echo "Generating LiteLLM configuration..."
mkdir -p /app/generated_configs
python3 "$(dirname "$0")/generate_litellm_config.py" \
  --env-file "$VARS_FILE" \
  --models-file "$GENERATED_MODELS_FILE" \
  --template-file /app/litellm_config.template.yaml \
  --output-file /app/generated_configs/config.yaml || exit 1

# Get the vllm serve command and model-specific env vars for the selected model from models.yml
python3 > /tmp/model_config.json << 'PYTHON_EOF'
import yaml
import os
import sys
import json

model_name = os.environ.get('MODEL', 'glm47-flash')
models_file = '/app/generated_configs/models.yml'

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

    # Output command and env as a single JSON object to avoid shell parsing issues.
    print(json.dumps({"model_name": model_name, "command": command, "env": model_env}))
except FileNotFoundError:
    print(f"Error: Configuration file not found: {models_file}", file=sys.stderr)
    print("Make sure model fragments are mounted in /app/models and generation completed", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"Error loading model configuration: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Parse the JSON output
COMMAND=$(python3 -c "import json; c = json.load(open('/tmp/model_config.json')); print(c['command'])")
MODEL_ENV_KEYS=$(python3 -c "import json; c = json.load(open('/tmp/model_config.json')); print(' '.join(c.get('env', {}).keys()))")

# Export model-specific environment variables using shell-safe quoting.
python3 > /tmp/model_env.sh << 'PYTHON_EOF'
import json
import shlex

data = json.load(open('/tmp/model_config.json'))
for key, value in (data.get('env') or {}).items():
    print(f"export {key}={shlex.quote(str(value))}")
PYTHON_EOF

if [ -s /tmp/model_env.sh ]; then
    # shellcheck disable=SC1091
    source /tmp/model_env.sh
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "VLLM Agent Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Model: $MODEL"
echo "Configuration File: /app/generated_configs/models.yml"
echo "Global Variables Exported: $(env | grep -E '^(HF_TOKEN|ANTHROPIC)' | cut -d= -f1 | tr '\n' ' ' || true)"
echo "Model-Specific Variables: ${MODEL_ENV_KEYS:-<none>}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Execute the command, replacing the current shell process
FINAL_COMMAND="$COMMAND"

# Ensure required runtime arguments are present while preserving model-specific
# settings when already provided.
if ! printf '%s\n' "$FINAL_COMMAND" | grep -Eq '(^|[[:space:]])--port([[:space:]]|=)'; then
    FINAL_COMMAND="$FINAL_COMMAND --port 8000"
fi
if ! printf '%s\n' "$FINAL_COMMAND" | grep -Eq '(^|[[:space:]])--host([[:space:]]|=)'; then
    FINAL_COMMAND="$FINAL_COMMAND --host 0.0.0.0"
fi
if ! printf '%s\n' "$FINAL_COMMAND" | grep -Eq '(^|[[:space:]])--api-key([[:space:]]|=)'; then
    FINAL_COMMAND="$FINAL_COMMAND --api-key sk-FAKE"
fi
if ! printf '%s\n' "$FINAL_COMMAND" | grep -Eq '(^|[[:space:]])--served-model-name([[:space:]]|=)'; then
    FINAL_COMMAND="$FINAL_COMMAND --served-model-name vllm_agent"
fi

exec bash -c "$FINAL_COMMAND"
