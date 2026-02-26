# Agent Guide: Contributing to vLLM Server

## Overview

This document explains how to contribute to the vLLM Server project as an AI assistant (agent). Following these guidelines ensures you make effective, safe contributions without breaking the deployment system.

---

## Important: Scripts Run Inside Docker

**🛑 NEVER run `runMe.sh`, `run_vllm_agent.sh`, or launch scripts from the host machine.**

These scripts are designed to run **INSIDE** the Docker container where:
- The correct Python/VirtualEnv environment is activated
- Model files are mounted at `/app/models`
- Configuration is generated dynamically
- Environment variables are properly loaded

### Why Not From Host?

| Issue | From Host | From Docker |
|-------|-----------|-------------|
| Python packages | May not be installed | Already in container |
| Model files | Not accessible | Mounted at `/app/models` |
| Environment | Missing vars.env | Loaded automatically |
| Permissions | Host user | Container root/app user |
| State | Confusing mixed | Clean container state |

### How to Correctly Test

To test changes, launch the model through Docker:

```bash
# Option 1: Use runMe.sh (recommended)
./runMe.sh step-3.5-flash

# Option 2: Direct docker compose
MODEL=step-3.5-flash docker compose up

# Then exec into container to run scripts manually if needed
docker exec -it vllm-container bash
# Now you're inside the container, scripts work correctly
```

---

## Project Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         Your Client                          │
└───────────────────────┬─────────────────────────────────────┘
                        │ REST/OpenAI API
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                      LiteLLM Service                         │
│                    Port: 4000 (container)                    │
│  - Rate limiting                                             │
│  - Request routing                                           │
│  - Usage tracking                                            │
└──────────┬──────────────────────────────────────────────────┘
           │ (network)
           ▼
┌─────────────────────────────────────────────────────────────┐
│                      vLLM Service                            │
│                    Port: 8000 (container)                    │
│  - Model inference                                           │
│  - Tokenization                                              │
│  - GPU management                                            │
└─────────────────────────────────────────────────────────────┘
```

### Key Services

| Service | Container Name | Port | Purpose |
|---------|---------------|------|---------|
| vLLM | vllm-container | 8000 | Actual model inference |
| LiteLLM | litellm | 4000 | API proxy + rate limiting |
| DB | litellm_db | 5432 | PostgreSQL for LiteLLM |

### Docker Volumes

- `postgres_data`: Persistent database storage
- `litellm_config`: **tmpfs** - config is regenerated each run
- Model configs mounted from `./models/` host directory
- Secrets mounted from `./secrets/` host directory

---

## Model Configuration System

### Files That Define a Model

Each model has a YAML file in `models/`:

```
models/
├── glm47-flash.yml
├── step-3.5-flash.yml
├── qwen3-next-coder.yml
└── ...
```

### Model File Structure

```yaml
# Comment: Description of what this model is
description: Code generation and analysis

# The vLLM command to run this model
command: |
  vllm serve organization/model-name \
    --flag1 value1 \
    --flag2 value2

# Environment variables for optimization
env:
  VLLM_USE_FLASHINFER_MOE_FP8: "1"
  VLLM_ATTENTION_BACKEND: "FLASH_ATTN"

# LiteLLM API parameters
litellm:
  temperature: 0.7
  top_p: 0.9
  timeout: 45
```

### Model Selection Flow

1. **Launch**: User runs `./runMe.sh model-name` or `MODEL=model-name docker compose up`
2. **Environment**: `MODEL=model-name` is set in container
3. **Generation**: `run_vllm_agent.sh` calls `gen_models_yml.sh`
4. **Collection**: `gen_models_yml.sh` finds `models/model-name.yml`
5. **Config Generation**: `generate_litellm_config.py` merges:
   - Global defaults from `vars.env`
   - Model overrides from `models/model-name.yml`
   - Template from `litellm_config.template.yaml`
6. **Result**: `config.yaml` written to shared volume

---

## Adding a New Model

### 1. Create the Model File

Copy an existing model file as template:

```bash
cp models/qwen3-next-coder.yml models/my-new-model.yml
```

Edit the new file:

```yaml
description: [Describe what this model is/use case]

command: |
  vllm serve <HUGGINGFACE_REPO_ID> \
    --tokenizer-mode auto \
    --enable-auto-tool-choice \
    --tool-call-parser <parser-name> \
    --load-format fastsafetensors \
    --attention-backend flashinfer \
    --enable-prefix-caching \
    --kv-cache-dtype fp8

env:
  SAFETENSORS_FAST_GPU: "1"
  VLLM_ALLOW_LONG_MAX_MODEL_LEN: "1"
  # Add any model-specific optimizations

litellm:
  temperature: 0.95
  top_p: 0.95
  top_k: 40
  repetition_penalty: 1.1
  max_tokens: 128K
  timeout: 45  # Adjust based on model speed
```

### 2. Test the Configuration

**DO NOT** try to run scripts from host. Instead:

```bash
# Build and start the model in Docker
./runMe.sh my-new-model --build

# Check logs
sudo docker compose logs -f vllm-node

# Test the API once healthy
curl http://localhost:4000/v1/models \
  -H "Authorization: Bearer sk-FAKE"
```

### 3. Add to Documentation

Update `README.md`:
- Add model to the table
- Add model card in `models/README.md`

---

## Using YAML Anchors for Model Variants

When you have multiple similar models (variants), use YAML anchors:

### Step 1: Create Base Configuration

```yaml
# models/qwen3-next-coder-base.yml
# This file defines common settings for all Qwen3-Coder-Next variants
# It's excluded from model selection (named *-base.yml)

&qwen3_coder_variant_anchor
description: Code generation and analysis (Qwen3-Coder-Next family)
command: |
  vllm serve <TO_BE_OVERRIDDEN> \
    --tokenizer-mode auto \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_xml \
    --load-format fastsafetensors \
    --attention-backend flashinfer \
    --enable-prefix-caching \
    --kv-cache-dtype fp8
env:
  SAFETENSORS_FAST_GPU: "1"
  VLLM_ALLOW_LONG_MAX_MODEL_LEN: "1"
  VLLM_USE_FLASHINFER_MOE_FP8: "1"
  VLLM_FLASHINFER_MOE_BACKEND: "latency"
  VLLM_USE_DEEP_GEMM: "0"
  VLLM_USE_TRTLLM_ATTENTION: "0"
litellm:
  temperature: 0.95
  top_p: 0.95
  top_k: 40
  repetition_penalty: 1.1
  max_tokens: 128K
  timeout: 45
```

### Step 2: Create Variants

```yaml
# models/qwen3-next-coder.yml (Official FP8)
&qwen3_coder_variant_anchor
command: |
  vllm serve unsloth/Qwen3-Coder-Next-FP8-Dynamic \
    --tokenizer-mode auto \
    --enable-auto-tool-choice \
    ...
# All other settings inherited from base

---

# models/qwen3-next-coder-nvfp4.yml (NVFP4 variant)
&qwen3_coder_variant_anchor
command: |
  vllm serve txn545/Qwen3-Coder-Next-NVFP4 \
    --tokenizer-mode auto \
    --enable-auto-tool-choice \
    ...
# All other settings inherited from base
```

### How It Works

1. `gen_models_yml.sh` collects all `*.yml` files EXCEPT `*-base.yml`
2. All files are merged into a single `models.yml` document
3. YAML anchors defined in one file can be referenced by others
4. The `<<: *anchor` merge key copies all settings from the base

---

## Common Modifications

### Changing Model Flags

Edit the `command:` section in the model's `.yml` file:

```yaml
command: |
  vllm serve model/repo \
    --max-num-seqs 16      # Change from 24 to 16
    --max-num-batched-tokens 8K  # Add this line
```

### Updating LiteLLM Settings

Edit the `litellm:` section:

```yaml
litellm:
  temperature: 0.8      # Change default temperature
  timeout: 60           # Increase timeout for slower models
  max_tokens: 64K       # Restrict max output
```

### Adjusting Concurrency

Edit `vars.env` or the model's `.yml`:

```bash
# In vars.env
LITELLM_MAX_PARALLEL_REQUESTS=5
LITELLM_TIMEOUT=30
```

Or per-model:

```yaml
env:
  LITELLM_TIMEOUT: 90
  LITELLM_MAX_PARALLEL_REQUESTS: 3
```

---

## Debugging

### Check Container Logs

```bash
# See what's happening in the container
sudo docker compose logs -f vllm-node

# Follow logs from container start
sudo docker compose logs --tail=200 vllm-node

# Check LiteLLM health
curl http://localhost:4000/health/liveliness
```

### Exec Into Container

```bash
# Get container ID
sudo docker compose ps

# Enter container
sudo docker exec -it vllm-container bash

# Now you're inside, can run scripts and check files
ls /app/models/
cat /app/generated_configs/config.yaml
```

### Verify Config Generation

Inside the container:

```bash
# Check what model is selected
echo $MODEL

# View generated config
cat /app/generated_configs/config.yaml

# Regenerate config (for testing changes)
python3 /app/generate_litellm_config.py
```

---

## Important Constraints

### 1. Environment Variable Passing

When using `sudo`, environment variables are NOT preserved by default:

```bash
# ❌ WRONG - sudo drops MODEL variable
sudo MODEL=step-3.5-flash docker compose up

# ✅ CORRECT - put MODEL before sudo
MODEL=step-3.5-flash sudo docker compose up

# ✅ ALSO CORRECT - use runMe.sh (handles this automatically)
./runMe.sh step-3.5-flash
```

### 2. Volume Mounts Are Read-Only

Model configs are mounted as read-only:

```yaml
volumes:
  - ./models:/app/models:ro  # Note the :ro (read-only)
```

You cannot modify model files from inside the container. Always edit on the host and restart.

### 3. Config is Regenerated Each Boot

The `generated_configs` volume is recreated on every startup:

```yaml
litellm_config:
  driver: tmpfs  # Clear on every restart
```

Any manual edits to `config.yaml` are lost on restart.

---

## Testing Best Practices

### 1. Start Small

First test with a minimal model to verify infrastructure works:

```bash
./runMe.sh glm47-flash  # Smallest model, fastest to start
```

### 2. Check Health Progressively

```bash
# 1. Check container started
sudo docker compose ps

# 2. Check vLLM endpoint
curl http://localhost:8000/v1/models

# 3. Check LiteLLM endpoint
curl http://localhost:4000/health/liveliness

# 4. Test actual generation
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-FAKE" \
  -d '{"model":"vllm_agent","messages":[{"role":"user","content":"hi"}]}'
```

### 3. Monitor Resources

```bash
# Watch GPU usage
watch -n 1 nvidia-smi

# Check container resource usage
sudo docker stats
```

---

## Common Pitfalls

| Symptom | Cause | Solution |
|---------|-------|----------|
| Model defaults to glm47-flash | `sudo` dropping env var | Use `MODEL=x sudo docker compose up` or `runMe.sh` |
| Container keeps restarting | Wrong command syntax | Check YAML `command:` indentation |
| Out of memory crash | Model too big for GPU | Reduce `--max-num-seqs` or switch to smaller model |
| Port already in use | Previous instance still running | `sudo docker compose down` first |
| Config changes don't apply | Forgot to rebuild | Use `--build` flag |
| Cross-file anchor fails | Anchor in different file | Put anchor in main model file, not base |

---

## Performance Tuning

### Reducing Latency

```yaml
env:
  VLLM_USE_FLASHINFER_MOE_FP8: "1"   # Faster MoE
  VLLM_ATTENTION_BACKEND: "FLASH_ATTN"  # Optimized attention
  VLLM_USE_DEEP_GEMM: "0"              # Use FlashInfer instead
```

### Increasing Throughput

```yaml
command: |
  vllm serve ... \
    --max-num-seqs 64 \              # More concurrent sequences
    --max-num-batched-tokens 16K \   # Larger batches
    --chunked-prefill \              # Chunk large prompts
    --enable-prefix-caching          # Cache repeated prefixes
```

### Reducing Memory Usage

```yaml
command: |
  vllm serve ... \
    --gpu-memory-utilization 0.7 \   # Less VRAM
    --max-num-seqs 8                 # Fewer concurrent requests
```

---

## Release Checklist

Before declaring a model ready:

- [ ] Model file created in `models/`
- [ ] `command:` uses correct HuggingFace repo ID
- [ ] `env:` has optimization flags
- [ ] `litellm:` has appropriate parameters
- [ ] Tested with `./runMe.sh model-name --build`
- [ ] Logs show successful startup
- [ ] API responds with completions
- [ ] GPU memory stable under load
- [ ] Documentation updated in `README.md`
- [ ] Model card added to `models/README.md`

---

## Additional Resources

- **Main README**: [README.md](./README.md) - User-facing documentation
- **Model Specs**: [models/README.md](./models/README.md) - Model-specific details
- **vLLM Docs**: https://docs.vllm.ai/
- **LiteLLM Docs**: https://docs.litellm.ai/

---

**Remember**: When in doubt, start from a known-working model and make incremental changes. Test each change by rebuilding and restarting the container.
