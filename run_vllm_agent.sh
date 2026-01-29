#!/bin/bash
set -e

# VLLM Agent Launcher Script
# This script reads the MODEL environment variable from vars.env
# and executes the corresponding vllm serve command defined in models.yml

# Get the vllm serve command for the selected model from models.yml
COMMAND=$(python3 << 'PYTHON_EOF'
import yaml
import os
import sys

model_name = os.environ.get('MODEL', 'glm47-flash')
models_file = '/app/models.yml'

try:
    with open(models_file, 'r') as f:
        models = yaml.safe_load(f)

    if model_name not in models:
        print(f"Error: Model '{model_name}' not found in {models_file}", file=sys.stderr)
        print(f"Available models: {', '.join(sorted(models.keys()))}", file=sys.stderr)
        sys.exit(1)

    print(models[model_name].strip())
except FileNotFoundError:
    print(f"Error: Configuration file not found: {models_file}", file=sys.stderr)
    print("Make sure models.yml is mounted in the container", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"Error loading model configuration: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
)

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "VLLM Agent Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Model: $MODEL"
echo "Configuration File: /app/models.yml"
echo "Command: $COMMAND"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Execute the command, replacing the current shell process
exec $COMMAND
