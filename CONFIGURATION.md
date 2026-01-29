# VLLM Server Configuration System

This document describes the complete configuration architecture for your VLLM + LiteLLM Anthropic emulator setup.

## Overview

The configuration system is designed with **separation of concerns**, where different aspects of the setup are managed in separate configuration files:

```
Configuration Files
├── models.yml              ← VLLM model serving parameters
├── config.yaml            ← LiteLLM proxy configuration
├── vars.env               ← Runtime environment variables
├── docker-compose.yml     ← Service orchestration
└── run_vllm_agent.sh      ← Model launcher script (ties everything together)
```

## Configuration Files Explained

### 1. `vars.env` (Environment Variables)
**Purpose:** Central repository for all environment variables used by containers.

**Key Variables:**
- `MODEL="glm47-flash"` - Selects which model variant to run
- `HF_TOKEN` - HuggingFace API token for model downloads
- `VLLM_MLA_DISABLE=1` - VLLM optimization flag
- `ANTHROPIC_AUTH_TOKEN` - Fake token for Anthropic API emulation
- `ANTHROPIC_BASE_URL` - Points to LiteLLM proxy

**Used by:** docker-compose.yml (via `env_file`)

### 2. `models.yml` (VLLM Configuration)
**Purpose:** Centralized storage of VLLM serving commands for different model variants.

**Structure:**
Each entry is a model name mapped to a complete `vllm serve` command:

```yaml
model-variant-name: >
  vllm serve HuggingFace/model-id
  --port 8000
  --host 0.0.0.0
  [additional parameters...]
```

**Current Models:**
- `glm47-flash` - AWQ quantized (default, high throughput)
- `glm47-flash-int4` - INT4 quantized (aggressive compression)
- `glm47-flash-int8` - INT8 quantized (maximum compression)
- `glm47-flash-fp8` - FP8 quantized (precision-optimized)

**Used by:** run_vllm_agent.sh (mounted into vllm-node container)

### 3. `config.yaml` (LiteLLM Configuration)
**Purpose:** Configure the LiteLLM proxy as an OpenAI-compatible gateway.

**Key Configuration:**
```yaml
model_list:
  - model_name: "anthropic/*"        # Accepts any model starting with "anthropic/"
    litellm_params:
      model: "hosted_vllm/vllm_agent"  # Points to VLLM service
      api_base: "http://vllm-node:8000/v1"  # Internal Docker network
```

**Features:**
- Routes requests to VLLM backend
- Supports OpenAI-compatible API
- Allows custom parameters like `reasoning_effort`

**Used by:** litellm container (mounted as config file)

### 4. `docker-compose.yml` (Orchestration)
**Purpose:** Defines three services and how they interact.

**Services:**

#### vllm-node
- **Image:** `scitrera/dgx-spark-vllm:0.14.0-t5`
- **Port:** 8000 (VLLM API)
- **GPU:** All available GPUs
- **Execution:** Runs `run_vllm_agent.sh` which launches the model based on MODEL env var
- **Volumes:**
  - HuggingFace cache directory
  - `models.yml` (read-only) - Model configurations
  - `run_vllm_agent.sh` (read-only) - Launcher script

#### litellm
- **Image:** `ghcr.io/berriai/litellm:main-stable`
- **Port:** 4000 (OpenAI-compatible API)
- **Config:** Mounts `config.yaml`
- **Dependencies:** Waits for vllm-node and db services

#### db
- **Image:** `postgres:16`
- **Purpose:** Stores LiteLLM logs and metrics
- **Volume:** Named volume `postgres_data` for persistence

**Network:** Docker internal network allows container-to-container communication

### 5. `run_vllm_agent.sh` (Launcher Script)
**Purpose:** Bridges the gap between environment configuration and VLLM execution.

**What it does:**
1. Reads `MODEL` environment variable from `vars.env`
2. Uses Python + YAML to parse `models.yml`
3. Extracts the corresponding `vllm serve` command
4. Validates that the selected model exists
5. Prints configuration for debugging
6. Executes the command

**Error Handling:**
- Checks if model exists in `models.yml`
- Lists available models if selection fails
- Shows helpful error messages if files are missing

## Data Flow

### Container Startup
```
docker-compose up
    ↓
    ├─→ vllm-node service starts
    │   ├─ Loads vars.env (MODEL="glm47-flash")
    │   ├─ Mounts models.yml
    │   ├─ Runs run_vllm_agent.sh
    │   │   ├─ Reads MODEL variable
    │   │   ├─ Parses models.yml
    │   │   └─ Executes: vllm serve QuantTrio/GLM-4.7-Flash-AWQ [args...]
    │   └─ Listens on http://localhost:8000
    │
    ├─→ litellm service starts
    │   ├─ Loads vars.env
    │   ├─ Loads config.yaml
    │   └─ Listens on http://localhost:4000
    │
    └─→ db service starts
        └─ Initializes PostgreSQL database
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
MODEL="glm47-flash-int4"

# Restart only the vllm-node service
docker-compose up -d vllm-node
```

The `run_vllm_agent.sh` script will automatically detect the change and load the new model.

## Adding Custom Models

### Step 1: Add to models.yml
```yaml
my-model: >
  vllm serve MyOrg/my-model-name
  --port 8000
  --host 0.0.0.0
  --api-key sk-FAKE
  --gpu-memory-utilization 0.90
  [additional parameters as needed]
```

### Step 2: Update vars.env
```bash
MODEL="my-model"
```

### Step 3: Restart
```bash
docker-compose up -d vllm-node
```

## Configuration Best Practices

### Model Parameters
- **GPU Memory Utilization:** Start at 0.85-0.92 depending on memory availability
- **Max Model Length:** Should not exceed your GPU VRAM limits
- **Batch Size:** Higher values improve throughput, lower values improve latency
- **Load Format:** Use `fastsafetensors` for fastest loading, `auto` for compatibility

### Environment Variables
- Keep sensitive tokens in `vars.env`, never in YAML config
- Separate development (`.vscode/settings.json`) from production (`vars.env`)
- Use descriptive variable names

### Container Health
- LiteLLM includes health checks (every 30s, 3 retries)
- VLLM logs show when model is fully loaded
- PostgreSQL health checks ensure database is ready

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
- [ ] `vars.env` exists with `MODEL` variable set
- [ ] `models.yml` contains the selected model
- [ ] `config.yaml` points to correct VLLM endpoint
- [ ] `run_vllm_agent.sh` is executable
- [ ] `docker-compose.yml` mounts all config files
- [ ] HuggingFace token is valid
- [ ] GPU is available and visible to Docker
- [ ] Port 8000 and 4000 are available on host

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
✓ **Centralized model management** via `models.yml`
✓ **Clear separation of concerns** across files
✓ **Easy model switching** via single `MODEL` variable
✓ **Container orchestration** with defined dependencies
✓ **Environment isolation** between development and production
✓ **Extensibility** for adding new models without code changes
