# vLLM Model Configuration Guide

Complete reference for configuring vLLM models in `models.yml`. This guide covers all available command-line options, environment variables, and best practices for vLLM v1 (2025/2026).

---

## Table of Contents

1. [Getting Help](#getting-help)
2. [Basic Server Options](#basic-server-options)
3. [Model Loading and Memory](#model-loading-and-memory)
4. [Performance Tuning](#performance-tuning)
5. [Quantization](#quantization)
6. [Tool Calling and Reasoning](#tool-calling-and-reasoning)
7. [Batching and Concurrency](#batching-and-concurrency)
8. [KV Cache Configuration](#kv-cache-configuration)
9. [Environment Variables](#environment-variables)
10. [Distributed Inference](#distributed-inference)
11. [Advanced Features](#advanced-features)
12. [Configuration Patterns](#configuration-patterns)
13. [Troubleshooting](#troubleshooting)

---

## Getting Help

```bash
vllm serve --help                    # View all options
vllm serve --help=listgroup          # List all argument groups
vllm serve --help=ModelConfig        # View specific argument group
vllm serve --help=max-num-seqs       # View single argument
vllm serve --help=max                # Search by keyword
vllm serve --help=page               # View full help with pager
```

### Configuration File Support

vLLM accepts arguments from a YAML config file. Priority order: **command line > config file > defaults**

---

## Basic Server Options

### Server Configuration

| Flag | Description | Default |
|------|-------------|---------|
| `--host` | Host name for the server | localhost |
| `--port` | Port number | 8000 |
| `--uvicorn-log-level` | Uvicorn log level (debug, info, warning, error, critical, trace) | info |
| `--api-key` | API key for authentication (HTTP bearer token) | None |
| `--served-model-name` | Model name(s) used in API responses | Same as model arg |
| `--response-role` | Role for responses in chat completions | assistant |
| `--ssl-keyfile` | SSL key file path | None |
| `--ssl-certfile` | SSL certificate file path | None |
| `--ssl-ca-certs` | SSL CA certificates file path | None |
| `--ssl-cert-reqs` | SSL certificate requirements | 0 |

### CORS Configuration

| Flag | Description | Default |
|------|-------------|---------|
| `--allow-credentials` | Allow credentials in CORS | False |
| `--allowed-origins` | Allowed origins for CORS | ["*"] |
| `--allowed-methods` | Allowed HTTP methods | ["*"] |
| `--allowed-headers` | Allowed headers | ["*"] |

**Example:**
```yaml
command: |
  vllm serve model \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key sk-your-secret-key \
    --allowed-origins '["https://example.com"]'
```

---

## Model Loading and Memory

### Model Configuration

| Flag | Description | Default |
|------|-------------|---------|
| `--model` | Name or path of HuggingFace model | **Required** |
| `--tokenizer` | Tokenizer name or path | Same as model |
| `--tokenizer-mode` | Tokenizer mode | auto |
| `--trust-remote-code` | Trust remote code from HuggingFace | False |
| `--revision` | Model revision (branch, tag, or commit ID) | default |
| `--download-dir` | Directory to download and load weights | ~/.cache/huggingface |
| `--load-format` | Format for loading weights | auto |
| `--config-format` | Model config format | auto |

**Tokenizer Modes:**
- `auto` - Uses fast tokenizer if available, falls back to slow
- `slow` - Always use slow tokenizer
- `mistral` - Use Mistral tokenizer (required for Mistral models)

**Load Format Options:**
| Format | Description | Use Case |
|--------|-------------|----------|
| `auto` | Automatically detect format | General purpose |
| `safetensors` | SafeTensors format | Standard PyTorch models |
| `fastsafetensors` | Fast loading of safetensors | **Recommended for production** |
| `pt` | PyTorch pickle format | Legacy models |
| `bitsandbytes` | BitsAndBytes quantization | 4-bit/8-bit quantized models |
| `sharded_state` | Pre-sharded checkpoint files | Multi-GPU models |
| `gguf` | GGUF format files | Cross-platform quantized models |
| `mistral` | Mistral consolidated safetensors | Mistral-specific format |

**Example:**
```yaml
glm47-flash:
  command: |
    vllm serve QuantTrio/GLM-4.7-Flash-AWQ \
      --trust-remote-code \
      --load-format fastsafetensors \
      --revision main
```

### Memory Management

| Flag | Description | Default | Typical Range |
|------|-------------|---------|---------------|
| `--gpu-memory-utilization` | Fraction of GPU memory to use (0-1) | 0.9 | 0.7-0.95 |
| `--max-model-len` | Maximum model context length | Auto from config | 2048-131072 |
| `--max-num-seqs` | Maximum sequences per batch | 1024 (V1) | 16-4096 |
| `--max-num-batched-tokens` | Maximum batched tokens per iteration | 2048 | 2048-32768 |
| `--swap-space` | CPU swap space per GPU (GiB) | 4 | 2-16 |
| `--cpu-offload-gb` | CPU offload space per GPU (GiB) | 0 | 0-32 |
| `--kv-cache-memory-bytes` | KV cache size per GPU in bytes | None (auto) | Calculate based on needs |

**Key Insights:**

#### gpu-memory-utilization
- **Default:** 0.9 (90%)
- **High throughput:** 0.95 (risky but maximizes capacity)
- **Stable production:** 0.85-0.9 (recommended)
- **Memory constrained:** 0.7-0.8 (safer, room for spikes)
- Lower values reduce OOM risk but underutilize GPU

#### max-model-len
- Defines maximum context window
- Default: Uses model's `max_position_embeddings` from config
- **Important:** Cannot exceed model's trained context length without RoPE scaling
- Set to `auto` to use model's maximum
- Lower values save memory and increase throughput

**Memory Calculation:**
```
KV Cache Memory = max-num-seqs × max-model-len × hidden_size × num_layers × 2 (K + V) × bytes_per_element
```

#### max-num-seqs
- Higher = more concurrency, better throughput
- Lower = better per-request latency
- **High throughput:** 1024-4096
- **Balanced:** 256-512
- **Low latency:** 16-128

#### max-num-batched-tokens
- Tokens processed per forward pass
- Works with `--enable-chunked-prefill` for optimal scheduling
- **High throughput:** 8192-32768
- **Balanced:** 4096-8192
- **Low latency:** 2048-4096

#### cpu-offload-gb
- Virtual GPU memory increase
- Example: 24GB GPU + 10GB offload = effectively 34GB
- Slower than GPU memory but prevents OOM
- **New in 2026:** Native CPU KV cache offloading

**Example Configuration:**
```yaml
# High-throughput configuration
command: |
  vllm serve model \
    --gpu-memory-utilization 0.95 \
    --max-model-len 16384 \
    --max-num-seqs 1024 \
    --max-num-batched-tokens 16384

# Low-latency configuration
command: |
  vllm serve model \
    --gpu-memory-utilization 0.85 \
    --max-model-len 8192 \
    --max-num-seqs 128 \
    --max-num-batched-tokens 4096

# Memory-constrained configuration
command: |
  vllm serve model \
    --gpu-memory-utilization 0.75 \
    --max-model-len 8192 \
    --max-num-seqs 64 \
    --cpu-offload-gb 10
```

---

## Performance Tuning

### Batching and Scheduling

| Flag | Description | Default | Recommendation |
|------|-------------|---------|----------------|
| `--enable-chunked-prefill` | Enable chunked prefill for better GPU utilization | True (V1) | Enable for throughput |
| `--enable-prefix-caching` | Enable automatic prefix caching (APC) | True | Enable for RAG/chatbots |
| `--max-concurrency` | Maximum concurrent requests | None | Set for rate limiting |
| `--scheduler-delay-factor` | Delay factor for scheduling next prompt | 0.0 | 0-0.1 for latency tuning |
| `--num-scheduler-steps` | Multi-step scheduling (max forward steps) | 1 | 1-10 for throughput |
| `--preemption-mode` | Preemption mode (recompute, swap) | recompute | recompute for speed |

#### enable-chunked-prefill

**What it does:** Mixes prefill (compute-bound) and decode (memory-bound) requests in the same batch.

**Benefits:**
- Better GPU utilization
- Reduced queue waiting time
- Higher overall throughput

**Tuning with max-num-batched-tokens:**
- **Lower (2048-4096):** Better inter-token latency (ITL)
- **Higher (8192+):** Better time-to-first-token (TTFT) and throughput

**When to use:**
- ✅ High-throughput production servers
- ✅ Mixed workload (short + long requests)
- ❌ Ultra-low latency requirements (disable it)

#### enable-prefix-caching

**What it does:** Reuses KV cache blocks from previous requests with the same prefix.

**Benefits:**
- Faster processing for requests with shared prefixes
- Lower latency for RAG and chatbot applications
- Reduced memory usage for repeated prompts

**Use cases:**
- ✅ RAG systems (shared system prompts)
- ✅ Chatbots (shared context/history)
- ✅ Few-shot learning (shared examples)
- ✅ Multi-turn conversations

**Example:**
```python
# First request with system prompt (computed normally)
"System: You are a helpful assistant.\nUser: Hello"

# Second request (system prompt KV cache reused!)
"System: You are a helpful assistant.\nUser: How are you?"
```

#### num-scheduler-steps

**What it does:** Number of forward steps scheduled together (multi-step scheduling).

**Benefits:**
- Reduces scheduling overhead
- Better batch formation
- Higher throughput

**Recommendations:**
- **Default:** 1 (single-step)
- **High throughput:** 5-10
- **Trade-off:** Slightly higher latency, much better throughput

### Execution Mode

| Flag | Description | Default | Use Case |
|------|-------------|---------|----------|
| `--enforce-eager` | Always use eager-mode PyTorch | False | Debugging, CUDA graph issues |
| `--disable-log-stats` | Disable statistics logging | False | Marginal CPU overhead reduction |
| `--disable-log-requests` | Disable request logging | False | Privacy, performance |

**When to use enforce-eager:**
- 🔧 Debugging model issues
- 🔧 CUDA graph compilation errors
- 🔧 Custom operators not supporting graphs
- ⚠️ **Warning:** Significantly reduces performance

### Attention Backend

| Flag | Description | Options | Best For |
|------|-------------|---------|----------|
| `--attention-backend` | Attention implementation | auto, FLASH_ATTN, FLASHINFER, XFORMERS, TORCH_SDPA | auto (recommended) |
| `--disable-sliding-window` | Disable sliding window attention | False | Models without sliding window |

**Attention Backend Comparison:**

| Backend | Speed | Memory | Compatibility | Notes |
|---------|-------|--------|---------------|-------|
| `FLASH_ATTN` | ⚡⚡⚡ | 💾💾 | Ampere+ GPUs | Default for H100/A100 |
| `FLASHINFER` | ⚡⚡⚡ | 💾💾💾 | Ampere+ GPUs | Best for long context |
| `XFORMERS` | ⚡⚡ | 💾💾 | Most GPUs | Good compatibility |
| `TORCH_SDPA` | ⚡ | 💾 | All GPUs | Fallback option |

**Set via environment variable:**
```yaml
env:
  VLLM_ATTENTION_BACKEND: FLASH_ATTN
```

### Block and Cache Configuration

| Flag | Description | Default | Recommendation |
|------|-------------|---------|----------------|
| `--block-size` | Token block size for contiguous chunks | 16 | 8-32 (power of 2) |
| `--kv-cache-dtype` | KV cache data type | auto | fp8 for memory savings |
| `--calculate-kv-scales` | Calculate KV cache scales | False | True for FP8 |
| `--kv-sharing-fast-prefill` | Enable KV sharing during prefill | False | True for FP8 |

**Example:**
```yaml
command: |
  vllm serve model \
    --enable-chunked-prefill \
    --enable-prefix-caching \
    --num-scheduler-steps 5 \
    --kv-cache-dtype fp8 \
    --calculate-kv-scales \
    --kv-sharing-fast-prefill
```

---

## Quantization

### Supported Quantization Methods (2026)

| Method | Memory | Speed | Quality | Best For |
|--------|--------|-------|---------|----------|
| **AWQ** | 4-bit | ⚡⚡⚡ | ⭐⭐⭐⭐ | Best balance with Marlin kernel |
| **GPTQ** | 4-bit | ⚡⚡⚡ | ⭐⭐⭐⭐ | High throughput with Marlin |
| **FP8** | 8-bit | ⚡⚡⚡⚡ | ⭐⭐⭐⭐⭐ | H100, MI300x native support |
| **BitsAndBytes** | 4/8-bit | ⚡⚡ | ⭐⭐⭐ | Memory-constrained, flexible |
| **INT4/INT8** | 4/8-bit | ⚡⚡ | ⭐⭐⭐ | Edge devices, CPU inference |
| **GGUF** | Variable | ⚡⚡ | ⭐⭐⭐ | Cross-platform portability |
| **GPTQModel** | 4-bit | ⚡⚡⚡ | ⭐⭐⭐⭐ | Enhanced GPTQ, A100+ |

### Performance Benchmarks

| Method | Throughput (tok/s) | Pass@1 Quality | Memory | Notes |
|--------|-------------------|----------------|---------|-------|
| **Baseline FP16** | 461 | 55.4% | 100% | Reference |
| **Marlin-AWQ** | 741 | 51.8% | 25% | ⭐ Best throughput (1.6x FP16) |
| **Marlin-GPTQ** | 712 | ~52% | 25% | 1.5x FP16 |
| **FP8** | 800+ | 54.8% | 50% | ⭐ H100 native, best quality |
| **AWQ (no Marlin)** | 67 | 51.8% | 25% | Slow without kernel |

**Key Insights:**
- All 4-bit methods keep perplexity within ~6% of baseline
- Marlin kernels provide **10.9x speedup** over non-optimized AWQ
- FP8 on H100 provides best quality/speed balance

### Quantization Flags

| Flag | Description | Options |
|------|-------------|---------|
| `--quantization` | Quantization method | awq, gptq, fp8, bitsandbytes, int4, int8, gptqmodel, squeezellm, marlin, deepspeedfp, torchao |
| `--quantization-param-path` | Path to quantization parameters | File path |

### Method-Specific Configuration

#### AWQ (Activation-Aware Weight Quantization)

**Best for:** Quality preservation + speed with Marlin kernel

```yaml
command: |
  vllm serve TheBloke/Llama-2-7B-AWQ \
    --quantization awq \
    --kv-cache-dtype fp8
```

**When to use:**
- ✅ Pre-quantized AWQ models
- ✅ Need high throughput (Marlin kernel auto-enabled)
- ✅ NVIDIA GPUs with Ampere+ architecture

#### GPTQ

**Best for:** High throughput with Marlin kernel

```yaml
command: |
  vllm serve TheBloke/Llama-2-7B-GPTQ \
    --quantization gptq
```

**When to use:**
- ✅ Pre-quantized GPTQ models
- ✅ High throughput requirements
- ✅ NVIDIA Ampere+ GPUs

#### FP8 (8-bit Floating Point)

**Best for:** H100, MI300x GPUs with native FP8 support

```yaml
command: |
  vllm serve stepfun-ai/Step-3.5-Flash-FP8 \
    --quantization fp8 \
    --kv-cache-dtype fp8 \
    --calculate-kv-scales
```

**When to use:**
- ✅ H100 or MI300x GPUs (native FP8 tensor cores)
- ✅ Best quality/speed/memory balance
- ✅ Dynamic quantization (can quantize any model)

**FP8 Formats:**
- `e4m3` (E4M3): 4-bit exponent, 3-bit mantissa (more common)
- `e5m2` (E5M2): 5-bit exponent, 2-bit mantissa (wider range)

#### BitsAndBytes

**Best for:** Memory-constrained scenarios, flexible quantization

```yaml
command: |
  vllm serve model \
    --quantization bitsandbytes \
    --load-format bitsandbytes
```

**Options:**
- `nf4` - 4-bit NormalFloat (recommended)
- `fp4` - 4-bit floating point
- `int8` - 8-bit integer

**When to use:**
- ✅ Limited GPU memory
- ✅ Dynamic quantization of any model
- ✅ Research and experimentation

#### GGUF

**Best for:** Cross-platform portability, CPU inference

```yaml
command: |
  vllm serve model.gguf \
    --load-format gguf
```

**When to use:**
- ✅ Models from llama.cpp ecosystem
- ✅ CPU inference
- ✅ Multi-platform deployment

### Recommendation Matrix

| GPU | Memory | Priority | Recommendation |
|-----|--------|----------|----------------|
| **H100** | >40GB | Quality | FP8 W8A8 |
| **H100** | <40GB | Memory | FP8 W8A16 + FP8 KV cache |
| **A100** | >40GB | Speed | Marlin-AWQ or Marlin-GPTQ |
| **A100** | <40GB | Memory | AWQ/GPTQ + FP8 KV cache |
| **RTX 4090** | 24GB | Balanced | AWQ + FP8 KV cache |
| **RTX 3090** | 24GB | Memory | BitsAndBytes NF4 |
| **CPU** | Any | Portability | GGUF |

**Example Multi-Optimization:**
```yaml
command: |
  vllm serve model \
    --quantization fp8 \
    --kv-cache-dtype fp8 \
    --calculate-kv-scales \
    --kv-sharing-fast-prefill \
    --gpu-memory-utilization 0.95
```

---

## Tool Calling and Reasoning

### Tool Calling Configuration

| Flag | Description | Default |
|------|-------------|---------|
| `--enable-auto-tool-choice` | Enable autonomous tool call generation | False |
| `--tool-call-parser` | Tool parser to use | None |
| `--chat-template` | Custom chat template (Jinja2 file) | Model default |

### Reasoning Configuration

| Flag | Description | Default |
|------|-------------|---------|
| `--reasoning-parser` | Reasoning parser for o1-like models | None |
| `--reasoning-effort` | Default reasoning effort (low, medium, high) | medium |

### Supported Tool Call Parsers (2026)

| Parser | Model Family | Example |
|--------|--------------|---------|
| `hermes` | Hermes models | NousResearch/Hermes-2-Pro-Llama-3-8B |
| `mistral` | Mistral models | mistralai/Mistral-7B-Instruct-v0.3 |
| `llama3_json` | Llama 3.x models | meta-llama/Meta-Llama-3.1-8B-Instruct |
| `granite` | IBM Granite | ibm-granite/granite-20b-code-instruct |
| `internlm` | InternLM models | internlm/internlm2_5-7b-chat |
| `jamba` | Jamba models | ai21labs/Jamba-v0.1 |
| `xlam` | xLAM models | Salesforce/xLAM-1b-fc-r |
| `qwen` | Qwen models | Qwen/Qwen2.5-7B-Instruct |
| `minimax_m1` | MiniMax models | MiniMaxAI/MiniMax-01 |
| `deepseek_v3` | DeepSeek V3 | deepseek-ai/DeepSeek-V3 |
| `deepseek_v31` | DeepSeek V3.1 | deepseek-ai/DeepSeek-V3.1 |
| `kimi_k2` | Kimi K2 | Moonshot-AI/Kimi-K2 |
| `hunyuan_a13b` | Hunyuan A13B | Tencent/Hunyuan-A13B |
| `glm45` | GLM 4.5 | THUDM/glm-4-9b-chat |
| `glm47` | GLM 4.7 | THUDM/GLM-4.7-Flash |
| `step3p5` | Step 3.5 | stepfun-ai/Step-3.5-Flash |
| `olmo3` | Olmo 3 | allenai/Olmo3-7B-Instruct |
| `gigachat3` | Gigachat 3 | GigaChat/GigaChat3 |
| `pythonic` | Pythonic tool calls | Generic models with Python-style calls |

### Tool Choice Options

**Via API:**
```python
completion = client.chat.completions.create(
    model="model",
    messages=[...],
    tools=[...],
    tool_choice="auto"  # auto, required, none, or {"type": "function", "function": {"name": "func_name"}}
)
```

**Options:**
- `auto` - Model decides when to use tools
- `required` - Model must generate tool call(s)
- `none` - No tool calls, text response only
- Named function - Specify particular function: `{"type": "function", "function": {"name": "get_weather"}}`

### Example Configuration

```yaml
glm47-flash:
  command: |
    vllm serve QuantTrio/GLM-4.7-Flash-AWQ \
      --enable-auto-tool-choice \
      --tool-call-parser glm47 \
      --reasoning-parser glm45 \
      --trust-remote-code

step-3.5-flash:
  command: |
    vllm serve stepfun-ai/Step-3.5-Flash-FP8 \
      --enable-auto-tool-choice \
      --tool-call-parser step3p5 \
      --reasoning-parser step3p5
```

### Reasoning Effort

For o1-like reasoning models:

```python
completion = client.chat.completions.create(
    model="model",
    messages=[...],
    reasoning_effort="high"  # low, medium, high
)
```

**Levels:**
- `low` - Fast, less thorough reasoning
- `medium` - Balanced (default)
- `high` - Slower, more thorough reasoning

---

## Batching and Concurrency

### Concurrency Parameters

| Parameter | Description | Default | High Throughput | Low Latency |
|-----------|-------------|---------|-----------------|-------------|
| `--max-num-seqs` | Max sequences per batch | 1024 (V1) | 2048-4096 | 64-128 |
| `--max-num-batched-tokens` | Max tokens per batch | 2048 | 8192-32768 | 2048-4096 |
| `--max-concurrency` | Max concurrent requests | None | None (unlimited) | 100-500 |

### Tuning Guidelines

#### For High Throughput

**Goal:** Maximize tokens/second across all requests

```yaml
command: |
  vllm serve model \
    --max-num-seqs 2048 \
    --max-num-batched-tokens 16384 \
    --enable-chunked-prefill \
    --enable-prefix-caching \
    --gpu-memory-utilization 0.95 \
    --num-scheduler-steps 5
```

**Characteristics:**
- ✅ High batch sizes
- ✅ Chunked prefill enabled
- ✅ High GPU utilization
- ⚠️ Higher latency per request
- ⚠️ More memory usage

**Use cases:**
- Offline batch processing
- High-volume API serving
- Cost optimization (more requests per GPU)

#### For Low Latency

**Goal:** Minimize time-to-first-token and inter-token latency

```yaml
command: |
  vllm serve model \
    --max-num-seqs 64 \
    --max-num-batched-tokens 2048 \
    --gpu-memory-utilization 0.85 \
    --scheduler-delay-factor 0.0
```

**Characteristics:**
- ✅ Small batch sizes
- ✅ Predictable latency
- ✅ Fast response times
- ⚠️ Lower throughput
- ⚠️ Underutilizes GPU

**Use cases:**
- Interactive chatbots
- Real-time applications
- Single-user scenarios

#### For Memory-Constrained

**Goal:** Fit model in limited GPU memory

```yaml
command: |
  vllm serve model \
    --max-num-seqs 32 \
    --max-num-batched-tokens 2048 \
    --max-model-len 8192 \
    --gpu-memory-utilization 0.75 \
    --cpu-offload-gb 10
```

**Characteristics:**
- ✅ Conservative memory usage
- ✅ Stable under load
- ✅ No OOM errors
- ⚠️ Lower concurrency
- ⚠️ May need CPU offload

**Use cases:**
- Smaller GPUs (RTX 3090, 4090)
- Multi-model serving on same GPU
- Development/testing environments

### Scheduling Policies

#### V1 Engine (2026)

**Priority Mode:**
- Handles requests by priority value (lower = earlier)
- Set priority in API call: `extra_body={"priority": 0}`

**Chunked Prefill Policy:**
- Prioritizes decode requests before prefill
- Prevents starvation of ongoing generations

**Preemption Modes:**
| Mode | Description | Speed | Memory |
|------|-------------|-------|--------|
| `recompute` | Recompute preempted request (default) | ⚡⚡⚡ | 💾💾 |
| `swap` | Swap KV cache to CPU | ⚡⚡ | 💾💾💾 |

```yaml
command: |
  vllm serve model \
    --preemption-mode recompute  # or swap
```

---

## KV Cache Configuration

### KV Cache Parameters

| Flag | Description | Default |
|------|-------------|---------|
| `--kv-cache-dtype` | Data type for KV cache | auto (same as model) |
| `--kv-cache-memory-bytes` | Manual KV cache size (bytes) | None (automatic) |
| `--calculate-kv-scales` | Calculate KV cache scales for FP8 | False |
| `--kv-sharing-fast-prefill` | Enable KV sharing during prefill | False |

### KV Cache Data Types

| Type | Precision | Memory Savings | Quality Loss | Requirements |
|------|-----------|----------------|--------------|--------------|
| `auto` | FP16/BF16 | Baseline (0%) | None | Any GPU |
| `fp8` | FP8 E4M3 | ~50% | Minimal (<1%) | CUDA 11.8+, Ampere+ |
| `fp8_e4m3` | FP8 E4M3 | ~50% | Minimal (<1%) | CUDA 11.8+, Ampere+ |
| `fp8_e5m2` | FP8 E5M2 | ~50% | Minimal (<1%) | CUDA 11.8+, Ampere+ |

### Memory Impact

**Without FP8 KV Cache:**
```
KV cache = max-num-seqs × max-model-len × hidden_size × num_layers × 2 × 2 bytes (FP16)
Example: 256 seqs × 16384 tokens × 4096 hidden × 32 layers × 2 (K+V) × 2 bytes
       = 256 × 16384 × 4096 × 32 × 2 × 2 = ~4.4 TB (too large!)
Actual: Constrained by --gpu-memory-utilization
```

**With FP8 KV Cache:**
```
KV cache = [...] × 1 byte (FP8) = ~2.2 TB equivalent capacity
Benefit: 2x more cache capacity OR 2x longer contexts
```

### FP8 KV Cache Configuration

**Basic FP8:**
```yaml
command: |
  vllm serve model \
    --kv-cache-dtype fp8
```

**Optimized FP8:**
```yaml
command: |
  vllm serve model \
    --kv-cache-dtype fp8 \
    --calculate-kv-scales \
    --kv-sharing-fast-prefill
```

**When to use:**
- ✅ `--calculate-kv-scales`: Improves FP8 accuracy, minimal overhead
- ✅ `--kv-sharing-fast-prefill`: Better memory efficiency during prefill
- ✅ Both: Use together for best FP8 performance

### CPU Offloading (2026)

```yaml
command: |
  vllm serve model \
    --cpu-offload-gb 10  # Offload 10GB per GPU to CPU
```

**New in 2026:** Native CPU KV cache offloading enables progressive offloading when GPU memory is insufficient.

**Benefits:**
- Effectively increases GPU memory
- Prevents OOM errors
- Transparent to API users

**Trade-offs:**
- Slower than GPU memory (PCIe bandwidth)
- Best for infrequent access patterns

**Example:**
```yaml
# Serve 70B model on 24GB GPU
command: |
  vllm serve llama-70b \
    --quantization awq \
    --kv-cache-dtype fp8 \
    --cpu-offload-gb 20 \
    --max-model-len 8192
```

---

## Environment Variables

### Installation-Time Variables

These must be set **before installing vLLM**:

| Variable | Description | Default |
|----------|-------------|---------|
| `VLLM_TARGET_DEVICE` | Target device (cuda, rocm, cpu, neuron, tpu, xpu, hpu) | cuda |
| `CMAKE_BUILD_TYPE` | Build type (Release, Debug, RelWithDebInfo) | Release |
| `VLLM_CONFIG_ROOT` | Config root directory | ~/.config/vllm |
| `VLLM_ALLOW_LONG_MAX_MODEL_LEN` | Allow max length > config.json | 0 |

### Runtime Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `HF_TOKEN` | HuggingFace API token | None |
| `VLLM_USE_MODELSCOPE` | Use ModelScope instead of HuggingFace | False |
| `VLLM_LOGGING_LEVEL` | Logging level (DEBUG, INFO, WARNING, ERROR) | INFO |
| `VLLM_TRACE_FUNCTION` | Trace function calls (debugging) | 0 |
| `VLLM_CONFIGURE_LOGGING` | Auto-configure logging | 1 |
| `VLLM_LOGGING_CONFIG_PATH` | Custom logging config file | None |

### Memory and Performance

| Variable | Description | Default |
|----------|-------------|---------|
| `VLLM_USE_V1` | Use V1 engine | Auto (enabled for supported models) |
| `VLLM_CPU_KVCACHE_SPACE` | CPU KV cache space in GB (CPU mode only) | 4 |
| `VLLM_CPU_OMP_THREADS_BIND` | CPU thread binding strategy | None |
| `VLLM_OPENVINO_KVCACHE_SPACE` | OpenVINO KV cache space | 0 |
| `VLLM_OPENVINO_CPU_KV_CACHE_PRECISION` | OpenVINO KV cache precision | auto |
| `VLLM_OPENVINO_ENABLE_QUANTIZED_WEIGHTS` | Enable quantized weights | False |
| `VLLM_XLA_CACHE_PATH` | XLA cache directory | ~/.cache/vllm/xla_cache |
| `VLLM_FUSED_MOE_CHUNK_SIZE` | Fused MoE chunk size | 64K |

### Attention and Compute Backend

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `VLLM_ATTENTION_BACKEND` | Attention backend | auto | FLASH_ATTN, FLASHINFER, XFORMERS, TORCH_SDPA |
| `VLLM_USE_FLASHINFER_MOE_FP8` | FlashInfer MoE FP8 | 0 | 0, 1 |
| `VLLM_USE_FLASHINFER_MOE_FP16` | FlashInfer MoE FP16 | 0 | 0, 1 |
| `VLLM_FLASHINFER_MOE_BACKEND` | MoE backend | throughput | throughput, latency |
| `VLLM_USE_FLASHINFER_SAMPLER` | FlashInfer sampler | 1 | 0, 1 |
| `VLLM_USE_DEEP_GEMM` | DeepGEMM (DeepSeek models) | 0 | 0, 1 |

### Model-Specific Features

| Variable | Description | Default | Models |
|----------|-------------|---------|--------|
| `VLLM_MLA_DISABLE` | Disable MLA (Multi-head Latent Attention) | 0 | DeepSeek, GLM |
| `VLLM_XGRAMMAR_CACHE_MB` | XGrammar cache for JSON schema | 512 | All |
| `VLLM_RPC_TIMEOUT` | RPC timeout for distributed inference | 180000 | Multi-node |

### Distributed Execution

| Variable | Description | Default |
|----------|-------------|---------|
| `VLLM_WORKER_MULTIPROC_METHOD` | Multiprocessing method | fork |
| `VLLM_HOST_IP` | vLLM internal IP (not API server) | localhost |
| `VLLM_PORT` | vLLM internal port (not API server) | Random |
| `VLLM_RPC_BASE_PATH` | RPC base path for distributed | ~/.vllm |
| `VLLM_INSTANCE_ID` | Instance ID for multi-instance setup | None |

### Debugging and Testing

| Variable | Description | Default |
|----------|-------------|---------|
| `VLLM_USE_DUMMY_WEIGHTS` | Use dummy weights (testing) | 0 |
| `VLLM_SKIP_WARMUP` | Skip warmup iterations | 0 |
| `VLLM_TEST_FORCE_MIXED_CHUNKED_PREFILL` | Force mixed chunked prefill (testing) | 0 |
| `VLLM_ALLOW_RUNTIME_LORA_UPDATING` | Allow runtime LoRA updates | 0 |

### Other Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `OMP_NUM_THREADS` | OpenMP threads for CPU operations | Auto |
| `VLLM_RINGBUFFER_WARNING_INTERVAL` | Ringbuffer warning interval (seconds) | 60 |
| `VLLM_DISABLE_CUSTOM_ALL_REDUCE` | Disable custom all-reduce kernels | 0 |

### Important Notes

⚠️ **Warning from Documentation:**
- Don't set service name to "vllm" in Kubernetes - causes conflicts with `VLLM_*` environment variables
- `VLLM_PORT` and `VLLM_HOST_IP` are for internal distributed communication, NOT for API server host/port
- Use `--host` and `--port` command flags for API server configuration

### Example Configuration

```yaml
env:
  # Required
  HF_TOKEN: "hf_your_token_here"

  # Performance
  VLLM_USE_V1: "1"
  VLLM_ATTENTION_BACKEND: "FLASH_ATTN"

  # Model-specific (MoE)
  VLLM_USE_FLASHINFER_MOE_FP8: "1"
  VLLM_FLASHINFER_MOE_BACKEND: "latency"

  # Model-specific (DeepSeek/GLM)
  VLLM_MLA_DISABLE: "1"
  VLLM_USE_DEEP_GEMM: "0"

  # Debugging (optional)
  VLLM_LOGGING_LEVEL: "DEBUG"
```

---

## Distributed Inference

### Parallelism Types

| Type | Description | Use Case | Communication |
|------|-------------|----------|---------------|
| **Tensor Parallelism (TP)** | Split model layers across GPUs | Single node, multiple GPUs | High (NVLink) |
| **Pipeline Parallelism (PP)** | Split model stages across nodes | Multiple nodes | Medium (InfiniBand/Ethernet) |
| **Expert Parallelism (EP)** | Split MoE experts across GPUs | MoE models | Medium |

### Parallelism Configuration

| Flag | Description | Default |
|------|-------------|---------|
| `--tensor-parallel-size` | Number of GPUs for tensor parallelism | 1 |
| `--pipeline-parallel-size` | Number of nodes for pipeline parallelism | 1 |
| `--distributed-executor-backend` | Backend (ray, mp) | auto |
| `--enable-expert-parallel` | Enable expert parallelism (MoE) | False |
| `--enable-eplb` | Enable expert parallel load balancing | False |

### Decision Framework

#### Single GPU
```yaml
# No parallelism needed
command: |
  vllm serve model
```

#### Multi-GPU, Single Node (2-8 GPUs)
```yaml
# Use tensor parallelism
command: |
  vllm serve model \
    --tensor-parallel-size 4
```

#### Multi-Node (2+ nodes, 8+ GPUs each)
```yaml
# Use both tensor and pipeline parallelism
command: |
  vllm serve model \
    --tensor-parallel-size 8 \    # GPUs per node
    --pipeline-parallel-size 2     # Number of nodes
```

**Example:** 16 GPUs in 2 nodes (8 GPUs/node)
- TP = 8 (use all GPUs in each node)
- PP = 2 (2 nodes)
- Total GPUs = TP × PP = 8 × 2 = 16

#### MoE Models (Mixture of Experts)
```yaml
# Use expert parallelism
command: |
  vllm serve stepfun-ai/Step-3.5-Flash-FP8 \
    --tensor-parallel-size 2 \
    --enable-expert-parallel \
    --enable-eplb
```

### Performance Considerations

#### Tensor Parallelism
- ✅ Lowest latency (synchronous)
- ✅ Best within nodes with NVLink
- ❌ High communication overhead
- ❌ Requires fast interconnect (NVLink, NVSwitch)

**Recommended for:**
- Single-node multi-GPU (A100, H100 with NVLink)
- Models that fit with sharding (70B+)

#### Pipeline Parallelism
- ✅ Lower communication cost
- ✅ Good for multi-node with slower interconnects
- ❌ Higher latency (pipeline bubbles)
- ❌ Less efficient GPU utilization

**Recommended for:**
- Multi-node inference
- InfiniBand or fast Ethernet (100Gb+)
- Very large models (175B+)

#### Expert Parallelism
- ✅ Natural for MoE models
- ✅ Load balancing with EPLB
- ❌ Only for MoE architectures

**Recommended for:**
- MoE models (Mixtral, Step, DeepSeek)
- Combined with TP for best results

### Distributed Backends

| Backend | Use Case | Pros | Cons |
|---------|----------|------|------|
| `ray` | Multi-node | Robust, production-ready | Requires Ray cluster |
| `mp` (multiprocessing) | Single-node | Simple, no dependencies | Single-node only |
| `auto` | Any | Auto-selects | Recommended default |

### Example Configurations

#### Single Node, 4x A100 (40GB)
```yaml
# Serve Llama-70B
command: |
  vllm serve meta-llama/Llama-2-70b \
    --tensor-parallel-size 4 \
    --quantization awq \
    --kv-cache-dtype fp8
```

#### 2 Nodes, 8x H100 Each (16 GPUs Total)
```yaml
# Serve Llama-405B
command: |
  vllm serve meta-llama/Llama-3.1-405B \
    --tensor-parallel-size 8 \
    --pipeline-parallel-size 2 \
    --distributed-executor-backend ray
```

#### MoE Model with Expert Parallelism
```yaml
# Serve Mixtral-8x7B
command: |
  vllm serve mistralai/Mixtral-8x7B-Instruct-v0.1 \
    --tensor-parallel-size 2 \
    --enable-expert-parallel \
    --enable-eplb
```

---

## Advanced Features

### Speculative Decoding

**What it does:** Uses a smaller "draft" model to propose tokens, verified by main model.

**Benefits:**
- Faster generation (1.5-2x speedup)
- Same quality as non-speculative

**Configuration:**

#### Draft Model Speculation
```yaml
command: |
  vllm serve meta-llama/Llama-2-70b \
    --speculative-model meta-llama/Llama-2-7b \
    --num-speculative-tokens 5
```

#### Model-Specific Speculation (Step 3.5)
```yaml
command: |
  vllm serve stepfun-ai/Step-3.5-Flash-FP8 \
    --speculative_config '{"method": "step3p5_mtp", "num_speculative_tokens": 1}'
```

**Parameters:**
- `num_speculative_tokens`: Number of tokens to speculate (typically 3-7)
- Higher = more speedup potential, but lower acceptance rate

### Guided Decoding

**What it does:** Constrain generation to follow JSON schema, regex, or grammar.

| Backend | Speed | Features | Compatibility |
|---------|-------|----------|---------------|
| `xgrammar` | ⚡⚡⚡ | Full (recommended) | Most models |
| `outlines` | ⚡⚡ | JSON, regex | Most models |
| `lm-format-enforcer` | ⚡⚡ | JSON, regex | Most models |
| `guidance` | ⚡ | Full grammar | Limited models |

```yaml
command: |
  vllm serve model \
    --guided-decoding-backend xgrammar
```

**API Usage:**
```python
response = client.chat.completions.create(
    model="model",
    messages=[...],
    extra_body={
        "guided_json": {
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "age": {"type": "integer"}
            }
        }
    }
)
```

### RoPE Scaling

**What it does:** Extends context length beyond training length.

**Methods:**
- `linear` - Simple linear interpolation
- `dynamic` - Dynamic interpolation (better quality)
- `yarn` - YaRN (Yet another RoPE extensioN)

```yaml
command: |
  vllm serve model \
    --rope-scaling '{"rope_type":"dynamic","factor":2.0}' \
    --max-model-len 32768  # 2x original 16K context
```

**Guidelines:**
- Factor 2.0: Generally safe, minimal quality loss
- Factor 4.0: Noticeable quality degradation
- Factor 8.0+: Significant quality loss

**Recommended:** Use models trained with extended context instead of RoPE scaling when possible.

### LoRA Support

**What it does:** Serve multiple LoRA adapters on same base model.

```yaml
command: |
  vllm serve base-model \
    --enable-lora \
    --max-lora-rank 64 \
    --lora-modules adapter1=path/to/adapter1 adapter2=path/to/adapter2
```

**API Usage:**
```python
response = client.chat.completions.create(
    model="adapter1",  # Specify LoRA adapter
    messages=[...]
)
```

**Benefits:**
- Serve multiple specialized models on one GPU
- Switch between adapters per request
- Memory efficient (only base model + small adapters)

### Multimodal Support

**For vision-language models:**

```yaml
command: |
  vllm serve llava-hf/llava-1.5-7b-hf \
    --limit-mm-per-prompt image=4  # Max 4 images per prompt
```

**API Usage:**
```python
response = client.chat.completions.create(
    model="model",
    messages=[
        {
            "role": "user",
            "content": [
                {"type": "text", "text": "What's in this image?"},
                {"type": "image_url", "image_url": {"url": "https://..."}}
            ]
        }
    ]
)
```

### Async Tokenization

**For high-throughput serving:**

```yaml
command: |
  vllm serve model \
    --tokenizer-pool-size 8 \
    --tokenizer-pool-type ray
```

**Benefits:**
- Offload tokenization from main process
- Better CPU utilization
- Higher throughput for tokenization-heavy workloads

### Logging and Observability

```yaml
command: |
  vllm serve model \
    --max-logprobs 20 \  # Return top 20 token probabilities
    --seed 42             # Reproducible generation
```

**Environment:**
```yaml
env:
  VLLM_LOGGING_LEVEL: "DEBUG"
  VLLM_LOGGING_CONFIG_PATH: "/path/to/logging.yaml"
```

---

## Configuration Patterns

### 1. High-Throughput Production Server

**Goal:** Maximum tokens/second, cost efficiency

```yaml
model:
  command: |
    vllm serve model \
      --max-num-seqs 2048 \
      --max-num-batched-tokens 16384 \
      --enable-chunked-prefill \
      --enable-prefix-caching \
      --num-scheduler-steps 5 \
      --gpu-memory-utilization 0.95 \
      --quantization awq \
      --kv-cache-dtype fp8 \
      --load-format fastsafetensors

  env:
    VLLM_USE_V1: "1"
    VLLM_ATTENTION_BACKEND: "FLASH_ATTN"

  litellm:
    max_tokens: 8192
    temperature: 0.7
```

**Characteristics:**
- ✅ Highest throughput
- ✅ Cost-effective (more requests per GPU)
- ⚠️ Higher latency per request
- ⚠️ High memory usage

### 2. Low-Latency Interactive Chatbot

**Goal:** Fast response, conversational AI

```yaml
model:
  command: |
    vllm serve model \
      --max-num-seqs 128 \
      --max-num-batched-tokens 4096 \
      --enable-prefix-caching \
      --gpu-memory-utilization 0.85 \
      --scheduler-delay-factor 0.0 \
      --kv-cache-dtype fp8 \
      --load-format fastsafetensors

  env:
    VLLM_USE_V1: "1"
    VLLM_ATTENTION_BACKEND: "FLASH_ATTN"

  litellm:
    max_tokens: 4096
    temperature: 0.8
```

**Characteristics:**
- ✅ Low latency
- ✅ Predictable response times
- ✅ Prefix caching for system prompts
- ⚠️ Lower throughput

### 3. RAG (Retrieval-Augmented Generation)

**Goal:** Optimize for repeated system prompts, context reuse

```yaml
model:
  command: |
    vllm serve model \
      --enable-prefix-caching \
      --enable-chunked-prefill \
      --max-num-seqs 512 \
      --max-model-len 16384 \
      --gpu-memory-utilization 0.9 \
      --kv-cache-dtype fp8 \
      --enable-auto-tool-choice \
      --tool-call-parser llama3_json

  env:
    VLLM_USE_V1: "1"

  litellm:
    max_tokens: 8192
```

**Key Features:**
- ✅ Prefix caching (reuse system prompt KV cache)
- ✅ Long context support (16K+)
- ✅ Tool calling for knowledge retrieval
- ✅ Balanced throughput/latency

### 4. Memory-Constrained Setup (RTX 3090/4090)

**Goal:** Fit large model in consumer GPU

```yaml
model:
  command: |
    vllm serve model \
      --quantization awq \
      --kv-cache-dtype fp8 \
      --max-model-len 8192 \
      --max-num-seqs 64 \
      --gpu-memory-utilization 0.75 \
      --cpu-offload-gb 8 \
      --load-format fastsafetensors

  litellm:
    max_tokens: 4096
```

**Memory Optimizations:**
- ✅ AWQ 4-bit quantization (~75% memory savings)
- ✅ FP8 KV cache (~50% cache savings)
- ✅ CPU offload (virtual memory increase)
- ✅ Lower context length
- ✅ Conservative GPU utilization

### 5. Reasoning Model (o1-like, Step 3.5)

**Goal:** High-quality reasoning, complex tasks

```yaml
model:
  command: |
    vllm serve stepfun-ai/Step-3.5-Flash-FP8 \
      --quantization fp8 \
      --kv-cache-dtype fp8 \
      --calculate-kv-scales \
      --kv-sharing-fast-prefill \
      --max-num-seqs 16 \
      --enable-chunked-prefill \
      --reasoning-parser step3p5 \
      --enable-auto-tool-choice \
      --tool-call-parser step3p5 \
      --speculative_config '{"method": "step3p5_mtp", "num_speculative_tokens": 1}' \
      --enable-expert-parallel \
      --enable-eplb \
      --trust-remote-code

  env:
    VLLM_USE_FLASHINFER_MOE_FP8: "1"
    VLLM_ATTENTION_BACKEND: "FLASH_ATTN"
    VLLM_FLASHINFER_MOE_BACKEND: "latency"

  litellm:
    max_tokens: 8192
```

**Characteristics:**
- ✅ Low concurrency (quality over throughput)
- ✅ Reasoning and tool calling enabled
- ✅ Speculative decoding for speed
- ✅ MoE optimizations (expert parallelism)

### 6. Multi-GPU Server (4x A100/H100)

**Goal:** Serve large model with tensor parallelism

```yaml
model:
  command: |
    vllm serve meta-llama/Llama-2-70b \
      --tensor-parallel-size 4 \
      --quantization awq \
      --kv-cache-dtype fp8 \
      --max-num-seqs 1024 \
      --enable-chunked-prefill \
      --enable-prefix-caching \
      --gpu-memory-utilization 0.9

  env:
    VLLM_USE_V1: "1"

  litellm:
    max_tokens: 8192
```

**Parallelism:**
- ✅ Tensor parallelism across 4 GPUs
- ✅ NVLink communication
- ✅ Quantization + FP8 KV cache for efficiency

### 7. Tool-Calling Agent

**Goal:** LLM with function calling capabilities

```yaml
model:
  command: |
    vllm serve model \
      --enable-auto-tool-choice \
      --tool-call-parser llama3_json \
      --enable-prefix-caching \
      --max-num-seqs 256 \
      --kv-cache-dtype fp8

  litellm:
    max_tokens: 8192
    temperature: 0.3  # Lower temp for structured output
```

**Features:**
- ✅ Automatic tool call detection
- ✅ JSON schema validation
- ✅ Prefix caching for tool definitions
- ✅ Lower temperature for reliability

---

## Troubleshooting

### Common Issues and Solutions

#### 1. Out of Memory (OOM) Errors

**Symptoms:**
- `CUDA out of memory` errors
- Container crashes
- Failed to allocate memory

**Solutions:**

```yaml
# Reduce memory usage
command: |
  vllm serve model \
    --gpu-memory-utilization 0.75 \  # Lower from 0.9
    --max-num-seqs 64 \               # Reduce batch size
    --max-model-len 8192 \            # Shorter context
    --kv-cache-dtype fp8 \            # Use FP8 cache
    --quantization awq \              # Quantize model
    --cpu-offload-gb 10               # Offload to CPU
```

#### 2. Context Window Exceeded

**Symptoms:**
- `ContextWindowExceededError`
- `max_tokens + input_tokens > max_model_len`

**Root Cause:**
The error "max_tokens is too large" means: **input_tokens + requested_max_tokens > max_model_len**

**Solutions:**

```yaml
# Option 1: Reduce default max_tokens
litellm:
  max_tokens: 8192  # Instead of 32000 or 65536

# Option 2: Increase context window (if model supports it)
command: |
  vllm serve model \
    --max-model-len 32768  # or auto

# Option 3: Use RoPE scaling (quality trade-off)
command: |
  vllm serve model \
    --rope-scaling '{"rope_type":"dynamic","factor":2.0}' \
    --max-model-len 32768
```

**Important:** `max_tokens` in LiteLLM config should be **50-75% of max-model-len** to leave room for input tokens.

#### 3. Slow Throughput

**Symptoms:**
- Low tokens/second
- High latency
- Underutilized GPU

**Solutions:**

```yaml
# Enable chunked prefill and increase batch size
command: |
  vllm serve model \
    --enable-chunked-prefill \
    --max-num-seqs 2048 \              # Increase
    --max-num-batched-tokens 16384 \   # Increase
    --num-scheduler-steps 5 \
    --gpu-memory-utilization 0.95

# Use faster quantization
command: |
  vllm serve model \
    --quantization awq  # Marlin kernel auto-enabled
```

#### 4. Model Not Loading

**Symptoms:**
- `ModelNotFoundError`
- Download errors
- Authentication failures

**Solutions:**

```yaml
# Set HuggingFace token
env:
  HF_TOKEN: "hf_your_token_here"

# Use specific revision
command: |
  vllm serve model \
    --revision main \
    --trust-remote-code

# Try different load format
command: |
  vllm serve model \
    --load-format safetensors  # or pt, auto
```

#### 5. Quantization Errors

**Symptoms:**
- `Quantization format not supported`
- Incorrect quantization method

**Solutions:**

```bash
# Check model files
ls ~/.cache/huggingface/hub/models--*/snapshots/*/

# Match quantization to model format
--quantization awq    # For *-AWQ models
--quantization gptq   # For *-GPTQ models
--quantization fp8    # For *-FP8 models or dynamic quantization
```

#### 6. Tool Calling Not Working

**Symptoms:**
- Model doesn't generate tool calls
- Invalid JSON output

**Solutions:**

```yaml
# Enable tool calling with correct parser
command: |
  vllm serve model \
    --enable-auto-tool-choice \
    --tool-call-parser llama3_json \  # Match to model family
    --trust-remote-code

# Lower temperature for structured output
litellm:
  temperature: 0.3
```

#### 7. Wrong Model Running

**Symptoms:**
- Different model than expected
- Context window mismatch
- Model capabilities don't match

**Solution:**

```bash
# Check running model
curl -H "Authorization: Bearer sk-FAKE" http://localhost:8000/v1/models

# Restart containers to apply MODEL env var
docker compose restart
```

#### 8. MoE Model Performance Issues

**Symptoms:**
- Slow MoE models
- High memory usage

**Solutions:**

```yaml
# Enable MoE optimizations
command: |
  vllm serve moe-model \
    --enable-expert-parallel \
    --enable-eplb \
    --tensor-parallel-size 2  # If multi-GPU

env:
  VLLM_USE_FLASHINFER_MOE_FP8: "1"
  VLLM_FLASHINFER_MOE_BACKEND: "latency"  # or throughput
```

#### 9. V1 Engine Issues

**Symptoms:**
- Errors about V1 engine
- Performance regressions

**Solutions:**

```yaml
# Explicitly enable V1
env:
  VLLM_USE_V1: "1"

# Or disable if causing issues
env:
  VLLM_USE_V1: "0"
```

#### 10. Distributed Inference Failures

**Symptoms:**
- Multi-GPU not working
- Communication errors

**Solutions:**

```yaml
# Verify tensor parallelism setup
command: |
  vllm serve model \
    --tensor-parallel-size 4  # Must match available GPUs

# Use explicit backend
command: |
  vllm serve model \
    --tensor-parallel-size 4 \
    --distributed-executor-backend mp  # or ray

# Check GPU visibility
env:
  CUDA_VISIBLE_DEVICES: "0,1,2,3"
```

### Debug Logging

Enable detailed logging for troubleshooting:

```yaml
env:
  VLLM_LOGGING_LEVEL: "DEBUG"
  VLLM_TRACE_FUNCTION: "1"  # Trace function calls

command: |
  vllm serve model \
    --uvicorn-log-level debug
```

### Performance Profiling

```bash
# Check GPU utilization
nvidia-smi -l 1

# Monitor vLLM stats endpoint
curl http://localhost:8000/metrics

# Check LiteLLM logs
docker logs litellm -f
```

---

## References and Resources

### Official Documentation

- **vLLM Official Docs**: https://docs.vllm.ai/
- **vLLM GitHub**: https://github.com/vllm-project/vllm
- **LiteLLM Documentation**: https://docs.litellm.ai/

### Key Pages

- CLI Reference: https://docs.vllm.ai/en/latest/cli/
- Server Arguments: https://docs.vllm.ai/en/latest/configuration/serve_args/
- Engine Arguments: https://docs.vllm.ai/en/latest/configuration/engine_args/
- Environment Variables: https://docs.vllm.ai/en/stable/configuration/env_vars/
- Quantization Guide: https://docs.vllm.ai/en/latest/features/quantization/
- Tool Calling: https://docs.vllm.ai/en/latest/features/tool_calling/
- Optimization Guide: https://docs.vllm.ai/en/stable/configuration/optimization/
- Distributed Inference: https://docs.vllm.ai/en/stable/serving/parallelism_scaling/

### Community Resources

- vLLM Discord: https://discord.gg/vllm
- GitHub Issues: https://github.com/vllm-project/vllm/issues
- GitHub Discussions: https://github.com/vllm-project/vllm/discussions

---

## Current Configuration Analysis (Your Setup)

### GLM-4.7-Flash-AWQ

```yaml
glm47-flash:
  command: |
    vllm serve QuantTrio/GLM-4.7-Flash-AWQ \
      --max-model-len 16384 \
      --trust-remote-code \
      --tool-call-parser glm47 \
      --reasoning-parser glm45 \
      --enable-auto-tool-choice \
      --max-num-batched-tokens 16384 \
      --max-num-seqs 128 \
      --load-format fastsafetensors \
      --kv-cache-dtype fp8

  env:
    VLLM_USE_DEEP_GEMM: "0"
    VLLM_USE_FLASHINFER_MOE_FP8: "1"
    VLLM_MLA_DISABLE: "1"

  litellm:
    temperature: 0.7
    top_p: 0.8
    top_k: 20
    repetition_penalty: 1.05
    max_tokens: 8192
```

**Analysis:**
- ✅ AWQ quantization for memory efficiency
- ✅ FP8 KV cache (2x cache capacity)
- ✅ Tool calling and reasoning enabled
- ✅ Aggressive batching (16384 tokens)
- ✅ Moderate concurrency (128 seqs)
- ✅ Fast loading (fastsafetensors)
- ✅ **max_tokens: 8192** (safe: 8192 + inputs ≤ 16384)

**Optimizations to Consider:**
- Enable chunked prefill: `--enable-chunked-prefill`
- Enable prefix caching: `--enable-prefix-caching`
- Increase num-scheduler-steps: `--num-scheduler-steps 5`

### Step-3.5-Flash-FP8

```yaml
step-3.5-flash:
  command: |
    vllm serve stepfun-ai/Step-3.5-Flash-FP8 \
      --enable-expert-parallel --enable-eplb \
      --disable-cascade-attn \
      --reasoning-parser step3p5 \
      --enable-auto-tool-choice \
      --tool-call-parser step3p5 \
      --hf-overrides '{"num_nextn_predict_layers": 1}' \
      --speculative_config '{"method": "step3p5_mtp", "num_speculative_tokens": 1}' \
      --trust-remote-code \
      --quantization fp8 \
      --max-model-len auto \
      --max-num-seqs 16 \
      --enable-chunked-prefill \
      --calculate-kv-scales --kv-sharing-fast-prefill \
      --load-format fastsafetensors \
      --kv-cache-dtype fp8

  env:
    VLLM_USE_FLASHINFER_MOE_FP8: "1"
    VLLM_ATTENTION_BACKEND: "FLASH_ATTN"
    VLLM_FLASHINFER_MOE_BACKEND: "latency"
    VLLM_USE_DEEP_GEMM: "0"

  litellm:
    max_tokens: 8192
```

**Analysis:**
- ✅ FP8 quantization (H100/MI300x optimized)
- ✅ Expert parallelism for MoE (EPLB enabled)
- ✅ Speculative decoding (step3p5_mtp)
- ✅ Advanced FP8 KV cache (scales + fast prefill)
- ✅ Chunked prefill enabled
- ✅ Low concurrency (16 seqs) for reasoning quality
- ✅ Flash attention backend
- ✅ **max_tokens: 8192** (safe for variable context)

**Well Optimized!**
- All MoE optimizations enabled
- FP8 features fully utilized
- Appropriate for reasoning workload

---

**Document Version:** 1.0 (2026-02-04)
**vLLM Version:** v1 (2025/2026)
**Maintained By:** Generated from official vLLM documentation
