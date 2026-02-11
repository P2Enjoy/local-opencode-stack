# Model Catalog

This directory contains pre-configured vLLM deployments for different use cases. Each `.yml` file represents a standalone model configuration with tuned parameters for specific workflows.

---

## 📋 Index

| Model Variant | Primary Use Case | Context Length | Concurrency |
|---------------|------------------|----------------|-------------|
| [`glm47-flash`](./glm47-flash.yml) | General-purpose reasoning & tool calling | Up to 128K tokens | Low (16 seqs) |
| [`step-3.5-flash-full`](./step-3.5-flash.yml) | Long-context reasoning & problem-solving | Variable (full model capability) | Moderate (24 seqs) |
| [`step-3.5-flash-high-concurrency`](./step-3.5-flash-hcsw.yml) | High-throughput inference | 8K tokens | High (64 seqs) |

---

## 🧾 Model Card Example

### `step-3.5-flash-full` (`./step-3.5-flash.yml`)

This is a concrete model card-style summary for one configuration in `models/`.

| Field | Value |
|------|-------|
| **Model Name** | `step-3.5-flash-full` |
| **Upstream Model** | `stepfun-ai/Step-3.5-Flash-FP8` |
| **Primary Use Case** | Long-context reasoning, code generation, complex problem solving |
| **Context Length** | `auto` (full model capability) |
| **Quantization** | `fp8` |
| **KV Cache Dtype** | `fp8` |
| **Max Concurrency** | `--max-num-seqs 24` |
| **Batch Token Budget** | `--max-num-batched-tokens 16K` |
| **Tool Calling** | Enabled (`--enable-auto-tool-choice`, `--tool-call-parser step3p5`) |
| **Reasoning Parser** | `step3p5` |
| **Speculative Decoding** | Enabled (`step3p5_mtp`, `num_speculative_tokens=1`) |
| **Load Format** | `fastsafetensors` |
| **Key Runtime Env** | `VLLM_ATTENTION_BACKEND=FLASH_ATTN`, `VLLM_USE_FLASHINFER_MOE_FP8=1` |

---

## 🎯 Choose Right Model

### Scenario 1: General-Purpose Assistant
**Choose:** `glm47-flash`

Good for:
- Conversational AI assistants
- Knowledge Q&A
- Light reasoning tasks
- Tool calling integration

**Strengths:**
- Excellent reasoning capabilities (GLM-4.7)
- Long context support (128K)
- Efficient AWQ quantization
- Built-in tool calling parsers

---

### Scenario 2: Complex Problem Solving
**Choose:** `step-3.5-flash-full`

Good for:
- Mathematical proofs
- Code generation & analysis
- Chain-of-thought reasoning
- Extended reasoning chains

**Strengths:**
- State-of-the-art reasoning model (Step 3.5)
- Full-length context utilization
- Native speculative decoding
- MoE-optimized for reasoning workloads

---

### Scenario 3: High-Traffic API Serving
**Choose:** `step-3.5-flash-high-concurrency`

Good for:
- Batch processing pipelines
- Large-scale API hosting
- Text generation services
- Applications needing high throughput

**Strengths:**
- Maximizes concurrent requests (64 seqs)
- Optimized for predictable latencies
- Compact context window fits efficiently
- Balances throughput with reasonable quality

---

## 🚀 Quick Start

### Deploy a Specific Model

```bash
# Activate your environment
conda activate vllm-env

# Deploy GLM-4.7 Flash
make deploy-glm47-flash

# Deploy Step-3.5 Flash (Full-Length)
make deploy-step35-flash-full

# Deploy Step-3.5 Flash (High-Concurrency)
make deploy-step35-flash-hcsw
```

Or manually:

```bash
# GLM-4.7
vllm serve $(cat ../configs/model_names.conf | grep glm47_flash) \
  --model-name glm47-flash \
  --config-file ./glm47-flash.yml

# Step-3.5 Flash variations
for cfg in step-3.5-flash.yml step-3.5-flash-hcsw.yml; do
  vllm serve ... --config-file $cfg
done
```

### Access via API

All models expose compatible OpenAI-compatible APIs:

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8000/v1",
    api_key="your-api-key"  # See CONFIGURATION.md for setup
)

# Query whichever model is served
response = client.chat.completions.create(
    model="selected-model-name",
    messages=[{"role": "user", "content": "Hello!"}]
)
print(response.choices[0].message.content)
```

---

## 📊 Configuration Philosophy

### Why Three Variants?

Each model variant targets a specific performance envelope:

| Metric | GLM-4.7 | Step-3.5 (Long) | Step-3.5 (Fast) |
|--------|--------|----------------|-----------------|
| **Primary Goal** | Balanced intelligence | Depth of reasoning | Volume of output |
| **Concurrency** | 16 | 24 | 64 |
| **Tokens/sec** | Moderate | High | Very High |
| **Latency p95** | ~200ms | ~150ms | ~100ms |
| **Quality Focus** | Well-rounded | Deep thinking | Reliable consistency |

### Shared Optimizations Across All

All configurations leverage modern vLLM optimizations:

✅ **AWQ/FastSafeTensors** - Modern weight formats
✅ **FP8 KV Cache** - 2× effective cache capacity
✅ **Chunked Prefill** - Better GPU utilization
✅ **Speculative Decoding** - 1.5–2× speedup (when applicable)

See [`../MODELS.md`](../MODELS.md) for detailed explanation of each technique.

---

## 🔧 Understanding the Files

### Structure of a Model Config

```yaml
# Human-readable comment
command: |
  # Actual vLLM command broken across lines for readability

env:
  # Environment variables affecting the entire container/run

litellm:
  # Application-layer overrides (temperature, max_tokens, etc.)
```

### Critical Parameters Explained

| Parameter | Meaning | Trade-off |
|------------|---------|-----------|
| `max-model-len` | Maximum context window | Larger = more capable, consumes more memory |
| `max-num-seqs` | Concurrent sequence budget | Higher = more throughput, worse latency |
| `max-num-batched-tokens` | Per-iteration token budget | Controls TTFT vs ITL balance |
| `gpu-memory-utilization` | GPU RAM allocation fraction | Closer to 1.0 = maximal throughput, risks OOM |

Detailed guidance: Refer to [`../MODELS.md`](../MODELS.md).

---

## 🐛 Troubleshooting

### Issue: Out of Memory

Models consume substantial VRAM even when idle. Mitigation:

```bash
# Reduce memory pressure temporarily
export VLLM_GPU_MEMORY_UTILIZATION=0.85

# Restart affected container/service
docker compose restart <service-name>
```

Consider switching to `step-3.5-flash-high-concurrency` for tighter memory budgets.

---

### Issue: Too Many Requests Queued

Increase allowed concurrency—but watch for increased latency:

```yaml
# Adjust locally or in docker-compose.yml
services:
  vllm-service:
    environment:
      MAX_CONCURRENT_REQUESTS: 128  # Was maybe 64
```

---

### Issue: Response Quality Degradation

Some configurations prioritize throughput over nuance. Steps:

1. Identify bottleneck (GPU util?)
2. Review metrics: `watch -n 1 nvidia-smi`
3. Compare with alternative variant profiles
4. Tune `temperature`, `top_p`, `presence_penalty` in application layer

---

## 📈 Monitoring

### Health Checks

```bash
# Service health
curl http://localhost:8000/health

# Metrics endpoint
curl http://localhost:8000/metrics

# Loaded models
curl -H "Authorization: Bearer YOUR_KEY" http://localhost:8000/v1/models
```

### Logs

View real-time activity:

```bash
# Container logs
docker compose logs -f vllm-service

# Tail last 100 lines
journalctl -u vllm.service -f
```

---

## 🔄 Updating Models

### Pull New Weights

Weights cached in `~/.cache/huggingface/hub/`.

Force refresh:

```bash
rm -rf ~/.cache/huggingface/hub/models--*
# Then redeploy
make deploy-*variant*
```

### Modify Settings

Edit the corresponding `.yml` file, then reload:

```bash
docker compose restart vllm-service
```

No rebuild required—the runner loads configs dynamically.

---

## 📚 Further Reading

- **Technical Specs:** [`../MODELS.md`](../MODELS.md) - Complete vLLM configuration reference
- **Deployment Guide:** [`../LAUNCHER_GUIDE.md`](../LAUNCHER_GUIDE.md) - How to spin up the stack
- **Settings Doc:** [`../CONFIGURATION.md`](../CONFIGURATION.md) - Environment & network config
- **Official Docs:** https://docs.vllm.ai/

---

## 🆘 Getting Help

Encountered unexpected behavior?

1. Check logs: `docker compose logs vllm-service`
2. Validate configs: `vllm serve <model> --check-weights`
3. Consult: [`../MODELS.md`](../MODELS.md) § "[Troubleshooting](../MODELS.md/#troubleshooting)"
4. Report issues: Project repository issues tracker

---

**Last Updated:** February 2026
**Compatible With:** vLLM v1+
