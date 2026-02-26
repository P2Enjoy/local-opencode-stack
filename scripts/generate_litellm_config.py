#!/usr/bin/env python3
"""
Generate LiteLLM config.yaml at runtime from:
1. Global defaults in vars.env
2. Per-model overrides in models.yml
3. Template in litellm_config.template.yaml
"""

import yaml
import os
import sys
import argparse
from pathlib import Path
from jinja2 import Environment, StrictUndefined, UndefinedError


def load_env_file(env_file):
    """Load environment variables from a file."""
    env_vars = {}
    if not os.path.exists(env_file):
        print(f"Warning: {env_file} not found", file=sys.stderr)
        return env_vars

    with open(env_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue

            if '=' in line:
                key, value = line.split('=', 1)
                # Remove quotes if present
                if value.startswith('"') and value.endswith('"'):
                    value = value[1:-1]
                elif value.startswith("'") and value.endswith("'"):
                    value = value[1:-1]
                env_vars[key.strip()] = value.strip()

    return env_vars


def extract_litellm_params(env_vars):
    """Extract LiteLLM parameters from environment variables."""
    litellm_params = {}
    litellm_vars = {
        'LITELLM_TEMPERATURE': 'temperature',
        'LITELLM_TOP_P': 'top_p',
        'LITELLM_TOP_K': 'top_k',
        'LITELLM_REPETITION_PENALTY': 'repetition_penalty',
        'LITELLM_MAX_TOKENS': 'max_tokens',
        'LITELLM_TIMEOUT': 'timeout',
        'LITELLM_MAX_PARALLEL_REQUESTS': 'max_parallel_requests',
    }

    for env_key, param_key in litellm_vars.items():
        if env_key in env_vars:
            value = env_vars[env_key]
            # Convert to appropriate type
            try:
                if param_key in ['temperature', 'top_p', 'repetition_penalty', 'timeout']:
                    litellm_params[param_key] = float(value)
                else:  # top_k, max_tokens, max_parallel_requests
                    litellm_params[param_key] = int(value)
            except ValueError:
                print(f"Warning: Could not convert {env_key}={value} to appropriate type", file=sys.stderr)
                litellm_params[param_key] = value

    return litellm_params


def generate_config(
    env_file='vars.env',
    models_file='models.yml',
    template_file='litellm_config.template.yaml',
    output_file='config.yaml'
):
    """Generate config.yaml by merging defaults, model-specific overrides, and template."""

    # Load environment variables (global defaults)
    env_vars = load_env_file(env_file)
    global_litellm_params = extract_litellm_params(env_vars)

    # Get selected model (required)
    model_name = os.environ.get('MODEL')
    if not model_name:
        print("Error: MODEL environment variable is required", file=sys.stderr)
        sys.exit(1)

    # Load models.yml and get model-specific overrides
    try:
        with open(models_file, 'r') as f:
            models = yaml.safe_load(f)
    except FileNotFoundError:
        print(f"Error: {models_file} not found", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error loading {models_file}: {e}", file=sys.stderr)
        sys.exit(1)

    if model_name not in models:
        print(f"Error: Model '{model_name}' not found in {models_file}", file=sys.stderr)
        print(f"Available models: {', '.join(sorted(models.keys()))}", file=sys.stderr)
        sys.exit(1)

    # Get model-specific LiteLLM overrides
    model_config = models[model_name]
    model_litellm_overrides = model_config.get('litellm', {})

    # Merge: global defaults + model-specific overrides
    final_litellm_params = {**global_litellm_params, **model_litellm_overrides}

    # Load template
    try:
        with open(template_file, 'r') as f:
            template_content = f.read()
    except FileNotFoundError:
        print(f"Error: {template_file} not found", file=sys.stderr)
        sys.exit(1)

    # Render template using Jinja2 (handles both {{ var }} and {% if %} blocks)
    jinja_env = Environment(
        trim_blocks=True,    # drop the newline after a block tag
        lstrip_blocks=True,  # strip leading whitespace before block tags
        undefined=StrictUndefined,
    )
    try:
        rendered_config = jinja_env.from_string(template_content).render(**final_litellm_params)
    except UndefinedError as e:
        print(f"Error: template variable not set: {e}", file=sys.stderr)
        print(f"  Defined params: {list(final_litellm_params.keys())}", file=sys.stderr)
        sys.exit(1)

    # Write config.yaml
    try:
        with open(output_file, 'w') as f:
            f.write(rendered_config)

        print(f"✓ Generated {output_file}")
        print(f"  Model: {model_name}")
        print(f"  LiteLLM Parameters:")
        for key, value in final_litellm_params.items():
            override_marker = " (model override)" if key in model_litellm_overrides else " (global default)"
            print(f"    - {key}: {value}{override_marker}")

        return True
    except Exception as e:
        print(f"Error writing {output_file}: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Generate LiteLLM config from template and environment'
    )
    parser.add_argument(
        '--env-file',
        default='vars.env',
        help='Path to vars.env file (default: vars.env)'
    )
    parser.add_argument(
        '--models-file',
        default='models.yml',
        help='Path to models.yml file (default: models.yml)'
    )
    parser.add_argument(
        '--template-file',
        default='litellm_config.template.yaml',
        help='Path to template file (default: litellm_config.template.yaml)'
    )
    parser.add_argument(
        '--output-file',
        default='config.yaml',
        help='Path to output config file (default: config.yaml)'
    )

    args = parser.parse_args()
    generate_config(
        env_file=args.env_file,
        models_file=args.models_file,
        template_file=args.template_file,
        output_file=args.output_file
    )
