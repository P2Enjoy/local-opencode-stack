# VLLM Model Configuration Reference

This document describes the available models and how to use them with the configuration system.

## Model Selection

Models are defined in `models.yml` and can be selected via the `MODEL` environment variable in `vars.env`.

**Current Setting in `vars.env`:**
```bash
MODEL="glm47-flash"
```

## Available Models

### 1. **glm47-flash** (Default)
- **Quantization:** AWQ (4-bit)
- **KV Cache:** FP8
- **Max Context:** 65,536 tokens
- **GPU Memory:** 92% utilization
- **Max Batch Size:** 16,384 tokens / 128 sequences
- **Load Format:** fastsafetensors
- **Use Case:** Balanced performance and memory efficiency. Best for production with high throughput.
- **HuggingFace Model:** `QuantTrio/GLM-4.7-Flash-AWQ`

### 2. **glm47-flash-int4**
- **Quantization:** INT4
- **KV Cache:** Default (FP32/FP16)
- **Max Context:** 65,536 tokens
- **GPU Memory:** 85% utilization
- **Max Batch Size:** 12,288 tokens / 96 sequences
- **Load Format:** auto
- **Use Case:** More aggressive quantization for reduced memory footprint.
- **HuggingFace Model:** `QuantTrio/GLM-4.7-Flash-int4`

### 3. **glm47-flash-int8**
- **Quantization:** INT8
- **KV Cache:** Default (FP32/FP16)
- **Max Context:** 32,768 tokens (reduced)
- **GPU Memory:** 78% utilization
- **Max Batch Size:** 8,192 tokens / 64 sequences
- **Load Format:** auto
- **Use Case:** Maximum memory conservation; smaller context window.
- **HuggingFace Model:** `QuantTrio/GLM-4.7-Flash-int8`

### 4. **glm47-flash-fp8**
- **Quantization:** FP8 (floating-point 8-bit)
- **KV Cache:** FP8
- **Max Context:** 65,536 tokens
- **GPU Memory:** 88% utilization
- **Max Batch Size:** 16,384 tokens / 120 sequences
- **Load Format:** safetensors
- **Use Case:** Good balance between quantization and precision.
- **HuggingFace Model:** `QuantTrio/GLM-4.7-Flash-FP8`

## Switching Models

To switch to a different model, simply change the `MODEL` variable in `vars.env`:

```bash
MODEL="glm47-flash-int4"  # Change this
```

Then restart the VLLM container:
```bash
docker-compose up -d vllm-node
```

The `run_vllm_agent.sh` script will automatically:
1. Read the MODEL environment variable
2. Parse `models.yml` using Python
3. Extract the corresponding `vllm serve` command
4. Execute it with all the configured parameters

## Configuration System Architecture

```
vars.env
  ↓
  └─→ MODEL="glm47-flash"
      ↓
docker-compose.yml (mounts vars.env)
  ↓
  └─→ vllm-node container
      ├─ Reads MODEL environment variable
      ├─ Mounts models.yml
      ├─ Runs run_vllm_agent.sh
      │
      └─→ run_vllm_agent.sh
          ├─ Reads MODEL from environment
          ├─ Parses models.yml (using Python + YAML)
          ├─ Extracts vllm serve command
          └─→ Executes: vllm serve [model] [args...]
```

## Adding New Models

To add a new model variant:

1. **Add an entry to `models.yml`:**
   ```yaml
   my-custom-model: >
     vllm serve HuggingFace/model-id
     --port 8000
     --host 0.0.0.0
     --api-key sk-FAKE
     [additional vllm parameters...]
   ```

2. **Update `vars.env` to use it:**
   ```bash
   MODEL="my-custom-model"
   ```

3. **Restart the container:**
   ```bash
   docker-compose up -d vllm-node
   ```

## Debugging

If a model fails to load, check the vllm-node container logs:
```bash
docker logs vllm-container
```

Common issues:
- **Model not found in models.yml:** The MODEL variable doesn't match any key in models.yml
- **HuggingFace model not found:** The model ID is incorrect or not publicly available
- **GPU out of memory:** Reduce `--gpu-memory-utilization` or switch to a more aggressive quantization

## LiteLLM Configuration

The LiteLLM proxy (`config.yaml`) connects to the VLLM service and exposes it as an OpenAI-compatible API:
- **API Base:** `http://localhost:4000`
- **Model Name:** `hosted_vllm/glm47-flash` (defined in config.yaml)
- **Served Model Name:** `vllm_agent` (from VLLM)

All VLLM models are served as `vllm_agent` regardless of which variant is running.
