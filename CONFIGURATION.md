# VLLM Server Configuration System

This document describes the complete configuration architecture for your VLLM + LiteLLM setup.

> **📖 For detailed vLLM options and parameters, see [MODELS.md](MODELS.md)**

## Overview

The configuration system is designed with **separation of concerns**, where different aspects of the setup are managed in separate configuration files:

```
Configuration Files
├── models.yml                      ← VLLM model serving parameters (see MODELS.md)
├── litellm_config.template.yaml   ← LiteLLM proxy configuration template
├── generate_litellm_config.py     ← Generates LiteLLM config from template + models.yml
├── vars.env                       ← Runtime environment variables
├── docker-compose.yml             ← Service orchestration
└── run_vllm_agent.sh              ← Model launcher script (ties everything together)
```

## Configuration Files Explained

### 1. `vars.env` (Environment Variables)
**Purpose:** Central repository for all environment variables used by containers.

**Key Variables:**
- `MODEL="step-3.5-flash"` - Selects which model variant to run (glm47-flash or step-3.5-flash)
- `HF_TOKEN` - HuggingFace API token for model downloads
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` - Reduces telemetry when using Claude Code

**Optional Variables (commented out by default):**
- `VLLM_USE_V1=1` - Use vLLM V1 engine
- `VLLM_MLA_DISABLE=1` - Disable MLA (model-specific)
- Various other VLLM optimization flags (see MODELS.md for details)

**Used by:** docker-compose.yml (via `env_file`)

### 2. `models.yml` (VLLM Configuration)
**Purpose:** Centralized storage of VLLM serving commands and LiteLLM parameters for different model variants.

**Structure:**
Each entry contains three sections:

```yaml
model-name:
  command: |
    vllm serve HuggingFace/model-id \
      --max-model-len 16384 \
      [additional vllm parameters...]

  env:
    VLLM_SPECIFIC_VAR: "value"
    # Model-specific environment overrides

  litellm:
    temperature: 0.7
    max_tokens: 8192
    # LiteLLM inference parameters
```

**Current Models:**
- `glm47-flash` - GLM-4.7-Flash with AWQ quantization, FP8 KV cache (high throughput)
- `step-3.5-flash` - Step-3.5 with FP8 quantization, expert parallelism (reasoning tasks)

**Used by:**
- `run_vllm_agent.sh` - Launches vLLM with model-specific command + env
- `generate_litellm_config.py` - Generates LiteLLM config with model-specific parameters

> **📖 For all available vLLM parameters and their meanings, see [MODELS.md](MODELS.md)**

### 3. LiteLLM Configuration System

#### `litellm_config.template.yaml` (Template)
**Purpose:** Template for LiteLLM proxy configuration with placeholder variables.

**Key Configuration:**
```yaml
model_list:
  - model_name: "anthropic/*"                    # Accepts any model starting with "anthropic/"
    litellm_params:
      allowed_openai_params: ["reasoning_effort"]
      model: "hosted_vllm/vllm_agent"           # Points to VLLM service
      api_base: "http://vllm-node:8000/v1"      # Internal Docker network
      api_key: "sk-FAKE"
      max_tokens: {{ max_tokens }}               # Filled at runtime
      temperature: {{ temperature }}
      top_k: {{ top_k }}
      top_p: {{ top_p }}
      repetition_penalty: {{ repetition_penalty }}
```

#### `generate_litellm_config.py` (Config Generator)
**Purpose:** Generates final `config.yaml` by merging:
1. Global defaults from `vars.env` (LITELLM_* variables)
2. Model-specific overrides from `models.yml` (litellm section)
3. Template from `litellm_config.template.yaml`

**Priority:** Model overrides > Global defaults > Template defaults

**Features:**
- Routes requests to VLLM backend
- Supports OpenAI and Anthropic-compatible APIs
- Allows custom parameters like `reasoning_effort`
- Dynamic configuration based on selected model

**Used by:**
- `run_vllm_agent.sh` - Generates config before starting LiteLLM
- `litellm` container - Uses generated config.yaml

### 4. `docker-compose.yml` (Orchestration)
**Purpose:** Defines three services and how they interact.

**Services:**

#### vllm-node
- **Build:** Custom Dockerfile (based on vLLM base image)
- **Port:** 8000 (VLLM API)
- **GPU:** All available GPUs (`gpus: all`)
- **Execution:** Runs `run_vllm_agent.sh` which:
  1. Generates LiteLLM config from template + models.yml
  2. Launches vLLM with model-specific command + environment
- **Volumes:**
  - HuggingFace cache: `/home/you/.cache/huggingface` → `/root/.cache/huggingface`
  - Config files (read-only): `models.yml`, `vars.env`, scripts, templates
  - Shared volume: `litellm_config` (tmpfs) for generated config.yaml
- **Health Check:** Validates vLLM API is responding and model is loaded

#### litellm
- **Image:** `ghcr.io/berriai/litellm:main-stable`
- **Port:** 4000 (OpenAI/Anthropic-compatible API)
- **Config:** Uses generated `config.yaml` from shared volume
- **Dependencies:** Waits for vllm-node and db to be healthy
- **Health Check:** Validates proxy is responding

#### db
- **Image:** `postgres:16`
- **Purpose:** Stores LiteLLM logs and metrics
- **Volume:** Named volume `postgres_data` for persistence
- **Credentials:** Configured via environment variables
- **Health Check:** Validates PostgreSQL is ready

**Network:** Docker internal network allows container-to-container communication

### 5. `run_vllm_agent.sh` (Launcher Script)
**Purpose:** Orchestrates the complete startup process for both vLLM and LiteLLM.

**What it does:**
1. **Validate Environment**
   - Checks for required files (models.yml, vars.env, templates)
   - Reads `MODEL` environment variable
   - Validates Python and dependencies are available

2. **Generate LiteLLM Configuration**
   - Runs `generate_litellm_config.py` to create config.yaml
   - Merges global defaults + model-specific overrides
   - Writes to shared volume for LiteLLM container

3. **Parse Model Configuration**
   - Uses Python + YAML to parse `models.yml`
   - Extracts three sections: `command`, `env`, `litellm`
   - Exports model-specific environment variables

4. **Launch vLLM**
   - Prints configuration for debugging
   - Executes the `vllm serve` command with all parameters

**Error Handling:**
- Validates model exists in `models.yml` (lists available if not)
- Checks for missing configuration files
- Shows detailed error messages for troubleshooting

## Data Flow

### Container Startup
```
docker-compose up
    ↓
    ├─→ db service starts first
    │   └─ Initializes PostgreSQL database
    │   └─ Health check: ready
    │
    ├─→ vllm-node service starts
    │   ├─ Loads vars.env (MODEL="step-3.5-flash")
    │   ├─ Mounts models.yml, templates, scripts
    │   ├─ Runs run_vllm_agent.sh
    │   │   ├─ Generates config.yaml from template + models.yml
    │   │   ├─ Reads MODEL variable
    │   │   ├─ Parses models.yml (command, env, litellm sections)
    │   │   ├─ Exports model-specific environment variables
    │   │   └─ Executes: vllm serve stepfun-ai/Step-3.5-Flash-FP8 [args...]
    │   └─ Listens on http://localhost:8000
    │   └─ Health check: model loaded and responding
    │
    └─→ litellm service starts (waits for db + vllm-node health)
        ├─ Loads vars.env
        ├─ Loads config.yaml from shared volume
        └─ Listens on http://localhost:4000
        └─ Health check: proxy responding
```

### Request Flow
```
Client Application
    ↓
    └─→ http://localhost:4000 (LiteLLM proxy)
        ├─ Validates request format
        ├─ Transforms to VLLM format
        └─→ http://vllm-node:8000 (VLLM server)
            └─ Executes model inference
                └─ Returns result
```

## Switching Models at Runtime

To change which model variant runs:

```bash
# Edit vars.env
MODEL="glm47-flash"  # or "step-3.5-flash"

# Restart both services (config needs regeneration)
docker-compose restart
```

The `run_vllm_agent.sh` script will automatically:
1. Regenerate LiteLLM config with new model's parameters
2. Load the new model with its specific configuration

## Adding Custom Models

### Step 1: Add to models.yml
```yaml
my-model:
  command: |
    vllm serve MyOrg/my-model-name \
      --max-model-len 16384 \
      --max-num-seqs 256 \
      --gpu-memory-utilization 0.90 \
      --quantization awq \
      --kv-cache-dtype fp8 \
      --trust-remote-code

  env:
    VLLM_ATTENTION_BACKEND: "FLASH_ATTN"
    # Model-specific environment variables

  litellm:
    temperature: 0.7
    top_p: 0.9
    max_tokens: 8192
```

> **📖 For all available vLLM parameters, see [MODELS.md](MODELS.md)**

### Step 2: Update vars.env
```bash
MODEL="my-model"
```

### Step 3: Restart
```bash
docker-compose restart
```

## Configuration Best Practices

### Model Parameters
> **📖 For detailed guidance on tuning vLLM parameters, see [MODELS.md](MODELS.md)**

**Quick Guidelines:**
- **max_tokens in litellm section:** Set to 50-75% of max-model-len to leave room for input tokens
- **GPU Memory Utilization:** 0.85-0.90 for stability, 0.95 for maximum throughput
- **Quantization:** Use AWQ/FP8 for best performance, combine with FP8 KV cache
- **Load Format:** `fastsafetensors` for production, `auto` for compatibility

### Environment Variables
- Keep sensitive tokens in `vars.env`, never in YAML config
- Model-specific environment variables go in `models.yml` under `env` section
- Use `VLLM_*` prefix for vLLM-specific runtime variables

### Container Health
- All services include health checks (30s interval, 10 retries)
- vLLM healthcheck validates model is loaded and responding
- LiteLLM healthcheck validates proxy is operational
- PostgreSQL healthcheck ensures database is ready
- Start period allows time for model loading (150s for vLLM)

## Debugging Tips

### View available models
```bash
python3 -c "import yaml; print(list(yaml.safe_load(open('models.yml')).keys()))"
```

### Check container logs
```bash
docker logs vllm-container     # VLLM logs
docker logs litellm            # LiteLLM logs
docker logs litellm_db         # Database logs
```

### Validate YAML syntax
```bash
python3 -c "import yaml; yaml.safe_load(open('models.yml')); print('✓ Valid')"
```

### Test API endpoint
```bash
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-FAKE" \
  -d '{
    "model": "anthropic/claude-4.5",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

## Configuration Validation Checklist

Before deploying, verify:
- [ ] `vars.env` exists with `MODEL` variable set to valid model name
- [ ] `models.yml` contains the selected model with all three sections (command, env, litellm)
- [ ] `litellm_config.template.yaml` exists with correct placeholders
- [ ] `generate_litellm_config.py` is present and executable
- [ ] `run_vllm_agent.sh` is executable (`chmod +x`)
- [ ] `docker-compose.yml` mounts all required files and volumes
- [ ] HuggingFace token is valid (check with `huggingface-cli whoami`)
- [ ] GPU is available and visible to Docker (`docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi`)
- [ ] Ports 8000 and 4000 are available on host (`lsof -i :8000,4000`)
- [ ] Shared volume `litellm_config` is properly configured as tmpfs

## File Permissions

Make sure the launcher script is executable:
```bash
chmod +x run_vllm_agent.sh
```

Config files should be readable:
```bash
chmod 644 models.yml config.yaml vars.env
```

## Summary

Your configuration system provides:
✓ **Multi-layered configuration** - Global defaults + model-specific overrides
✓ **Centralized model management** - All models defined in `models.yml`
✓ **Dynamic LiteLLM config generation** - Template-based with runtime merging
✓ **Clear separation of concerns** - Each file has a specific purpose
✓ **Easy model switching** - Single `MODEL` variable changes everything
✓ **Health checks and dependencies** - Services start in correct order
✓ **Extensibility** - Add new models without code changes
✓ **Comprehensive documentation** - This guide + MODELS.md cover all options

## Related Documentation

- **[MODELS.md](MODELS.md)** - Complete vLLM command-line options, environment variables, quantization methods, performance tuning, and configuration patterns
- **[LAUNCHER_GUIDE.md](LAUNCHER_GUIDE.md)** - How to use launcher scripts (test.sh, local_claude.sh) with Claude Code

## Quick Start

```bash
# 1. Configure which model to use
echo 'MODEL="step-3.5-flash"' >> vars.env

# 2. Start all services
docker-compose up -d

# 3. Monitor startup
docker-compose logs -f vllm-node

# 4. Wait for "Application startup complete"

# 5. Test the API
curl -H "Authorization: Bearer sk-FAKE" http://localhost:8000/v1/models

# 6. Use with Claude Code (see LAUNCHER_GUIDE.md)
./launchers/local_claude.sh
```
