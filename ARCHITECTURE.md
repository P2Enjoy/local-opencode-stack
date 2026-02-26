# Architecture Documentation

## Overview

This is a **vLLM Multi-Model Server** - a production-ready Docker-based deployment system for running multiple large language models using vLLM with LiteLLM proxy integration. It provides OpenAI-compatible API endpoints for various LLMs optimized for different use cases (reasoning, tool calling, code generation, high-throughput serving).

---

## System Architecture

```mermaid
flowchart TB
    subgraph "External Clients"
        client1[Claude Code]
        client2[VS Code]
        client3[cURL / curl]
    end

    subgraph "LiteLLM Layer"
        litellm[LiteLLM Proxy<br/>Port: 4000]
        db[(PostgreSQL 16<br/>Metrics Storage)]
    end

    subgraph "vLLM Engine"
        vllm[vLLM Inference Engine<br/>Port: 8000]
        gpu[GPU Memory<br/>模型加载]
    end

    subgraph "Volumes"
        config_vol[Shared Config Volume<br/>tmpfs]
        huggingface_cache[HuggingFace Cache<br/>~/.cache/huggingface]
    end

    client1 -->|OpenAI SDK| litellm
    client2 -->|HTTP Request| litellm
    client3 -->|curl localhost:4000| litellm

    litellm -->|Proxy Request| vllm
    litellm -->|Store Metrics| db
    vllm -->|Models| gpu
    vllm -->|Config Mount| config_vol
    vllm -->|Model Weights| huggingface_cache

    style litellm fill:#e1f5ff
    style vllm fill:#fff3e0
    style gpu fill:#fce4ec
    style db fill:#e8f5e9
```

---

## Deployment Architecture

```mermaid
flowchart LR
    subgraph "Host Machine"
        subgraph "Docker Network (bridge)"
            container1["Container: vllm-container<br/>vLLM + Custom Model Config"]
            container2["Container: litellm<br/>LiteLLM Proxy"]
            container3["Container: litellm_db<br/>PostgreSQL"]
        end

        subgraph "Mounts"
            m1["./models → /app/models:ro"]
            m2["./secrets → /app/secrets:ro"]
            m3["./scripts → /app/scripts:ro"]
            m4["vars.env → /app/vars.env:ro"]
            m5["tmpfs → /app/generated_configs"]
        end

        client[Your Application]
    end

    client -->|"POST /chat/completions"| container2
    container2 --> container1
    container1 -->|GPU Access| NVIDIA_Driver

    m1 --> container1
    m2 --> container1
    m3 --> container1
    m4 --> container1
    m5 -->|shared| container1
    m5 -->|shared| container2

    style container1 fill:#ffebee
    style container2 fill:#e3f2fd
    style container3 fill:#e8f5e9
```

---

## Runtime Flow

```mermaid
sequenceDiagram
    participant U as User/Script
    participant R as runMe.sh
    participant DC as docker-compose
    participant VC as vllm-container
    participant PY as Python Config Gen
    participant L as LiteLLM

    U->>R: MODEL=glm47-flash ./runMe.sh
    R->>DC: docker compose up -d

    DC->>VC: Start container
    VC->>VC: Load vars.env (global env)
    VC->>VC: Load secrets/* files

    VC->>PY: gen_models_yml.sh --model glm47-flash
    PY->>PY: Read models/glm47-flash.yml
    PY-->>VC: Generate /app/generated_configs/models.yml

    VC->>PY: generate_litellm_config.py
    PY->>PY: Load vars.env defaults
    PY->>PY: Apply models.yml overrides
    PY->>PY: Render litellm_config.template.yaml
    PY-->>VC: Generate /app/generated_configs/config.yaml

    VC->>VC: Extract vllm serve command
    VC->>VC: Apply dynamic arguments (--port, --api-key, etc.)
    VC->>VC: Execute: vllm serve ... --port 8000

    VC->>L: Wait for vLLM healthcheck
    L->>L: Startup + config load
    L-->>VC: Healthcheck passed

    Note over VC,L: Service ready at ports 8000 & 4000

    U->>L: POST /chat/completions
    L->>L: Validate API key (sk-FAKE)
    L->>L: Apply temperature/top_p from config
    L->>VC: Forward to http://vllm-node:8000
    VC->>VC: Process with vLLM
    VC-->>L: Streaming response
    L-->>U: OpenAI-compatible response
```

---

## Configuration System

```mermaid
graph TD
    subgraph "Layer 1: Global Defaults"
        vars[vars.env]
        template[litellm_config.template.yaml]
    end

    subgraph "Layer 2: Model Overrides"
        glm47[models/glm47-flash.yml]
        step35[models/step-3.5-flash.yml]
        qwen3[models/qwen3-next-coder.yml]
    end

    subgraph "Layer 3: Generator"
        gen[generate_litellm_config.py]
    end

    subgraph "Output"
        final[generated_configs/config.yaml]
    end

    vars --> gen
    template --> gen
    glm47 --> gen
    step35 --> gen
    qwen3 --> gen
    gen --> final

    style gen fill:#fff9c4
    style final fill:#c5cae9
```

### Configuration Data Flow

```mermaid
flowchart LR
    A1[Environment Variables] -->|Load| A2[vars.env]
    A2 -->|Parse| A3[Global Litellm Params]

    B1[Model YAML Fragments] -->|Merge| B2[models.yml]
    B2 -->|Extract| B3[Model-Specific Override]

    A3 --> C1[Merge Strategy]
    B3 --> C1
    C1 -->|Priority: Model > Global| C2[Final Config]

    D1[Template YAML] -->|Replace Placeholders| C2
    C2 -->|Write| D2[config.yaml]

    style C1 fill:#fff3e0
    style D2 fill:#e8f5e9
```

---

## Model Configuration Format

Each model in `models/` follows a consistent three-section structure:

```yaml
# Section 1: vLLM Command (how to serve the model)
command: |
  vllm serve <huggingface-model-id> \
    --tokenizer-mode auto \
    --enable-auto-tool-choice \
    --tool-call-parser <parser> \
    --load-format fastsafetensors \
    --attention-backend flashinfer \
    --enable-prefix-caching \
    --kv-cache-dtype fp8

# Section 2: Model-Specific Environment Variables
env:
  SAFETENSORS_FAST_GPU: "1"
  VLLM_USE_DEEP_GEMM: "1"
  VLLM_FLASHINFER_MOE_BACKEND: "latency"

# Section 3: LiteLLM Parameters (ratelimiting, defaults)
litellm:
  temperature: 0.7
  top_p: 0.9
  top_k: 50
  repetition_penalty: 1.1
  max_tokens: 128K
```

---

## Services Breakdown

### 1. vllm-node (Custom Image)

```mermaid
graph TD
    subgraph "Base Image"
        base["scitrera/dgx-spark-vllm:0.16.0-t5<br/>vLLM v0.16.0 + DeepGEMM"]
    end

    subgraph "Build Layer"
        build1["apt-get install<br/>git build-essential curl"]
        build2["WORKDIR /app"]
    end

    base --> build1
    build1 --> build2

    style build2 fill:#ffe0b2
```

**Key Features:**
- Custom vLLM build with DeepGEMM for FP8 computation
- Optimized for multi-model serving
- Includes FlashInfer attention backend

### 2. LiteLLM (BerriAI)

```mermaid
graph LR
    A[LiteLLM Proxy] --> B[Router]
    A --> C[Middleware Chain]
    A --> D[Logging]

    B --> B1[simple-shuffle<br/>load balancing]
    B --> B2[round-robin<br/>fallback]

    C --> C1[Drop unknown params]
    C --> C2[Request timeout]

    D --> D1[PostgreSQL<br/>metrics storage]

    style A fill:#90caf9
    style D1 fill:#a5d6a7
```

### 3. PostgreSQL (Database)

```mermaid
graph LR
    A[PostgreSQL 16] --> B[Data Persistence]
    A --> C[User Authentication]
    A --> D[Usage Tracking]

    B --> B1[postgres_data volume]

    style A fill:#c5e1a5
```

---

## Environment Variables

### Global Defaults (`vars.env`)

| Variable | Description | Default |
|----------|-------------|---------|
| `LITELLM_TEMPERATURE` | Default temperature for all models | `0.7` |
| `LITELLM_TOP_P` | Top-p sampling threshold | `0.9` |
| `LITELLM_TOP_K` | Top-k sampling pool size | `50` |
| `LITELLM_REPETITION_PENALTY` | Repetition penalty factor | `1.1` |
| `LITELLM_MAX_TOKENS` | Maximum output tokens | `128K` |
| `MAX_PARALLEL_REQUESTS` | Concurrent request limit | `16` |
| `NCCL_ENABLE_SO_RCLO | NCCL socket RCLO setting | `1` |
| `NCCL_IB_DISABLE` | Disable InfiniBand if problematic | `1` |

### Model-Specific Overrides

Each model can override any LiteLLM parameter in its `litellm:` section.

---

## Health Checks

### vLLM Container

```bash
test -f /app/generated_configs/config.yaml && \
curl -s -H 'Authorization: Bearer sk-FAKE' \
  http://localhost:8000/v1/models | grep -q vllm_agent
```

**Schedule:** Every 30s (after 150s start period)

### LiteLLM

```bash
wget --no-verbose --tries=1 http://localhost:4000/health/liveliness
```

**Schedule:** Every 30s (after 30s start period)

### PostgreSQL

```bash
pg_isready -d litellm -U llmproxy
```

**Schedule:** Every 1s (immediate start)

---

## Request Processing Pipeline

```mermaid
flowchart LR
    A[Incoming Request<br/>Port 4000] --> B[LiteLLM Middleware]

    B --> B1[Validate API Key<br/>sk-FAKE]
    B1 --> B2[Apply Temperature<br/>From Config]
    B2 --> B3[Check Rate Limits]

    B3 --> B4[Forward to vLLM<br/>Port 8000]
    B4 --> B5[vLLM Tokenizer]
    B5 --> B6[Model Inferencer]
    B6 --> B7[Sampler]
    B7 --> B8[Response Formatter]

    B8 --> B9[Stream Back to Client]

    B3 -.->|Violation| B10[Return Error 429]

    style B fill:#fff9c4
    style B6 fill:#ffe0b2
    style B10 fill:#ffcdd2
```

---

## Volumes Architecture

```mermaid
graph LR
    Host[Host Machine] -->|Persistent| P1[/home/user/.cache/huggingface]
    Host -->|Persistent| P2[postgres_data]

    Host -->|Read-Only| RO1[./models]
    Host -->|Read-Only| RO2[./secrets]
    Host -->|Read-Only| RO3[./scripts]
    Host -->|Read-Only| RO4[vars.env]

    Shared[tmpfs:<br/>litellm_config] -->|Read-Write| C1[vllm-container]
    Shared -->|Read-Write| C2[litellm]

    P1 -->|Model weights| vLLM
    P2 -->|Metrics| DB
    RO1 -->|YAML configs| ConfigGen
    RO2 -->|Tokens| SecretLoader
    RO3 -->|Scripts| Entry point
    RO4 -->|Defaults| ConfigGen

    style Shared fill:#e3f2fd
    style P1 fill:#e8f5e9
    style P2 fill:#e8f5e9
```

---

## Model Selection Flow

```mermaid
flowchart TD
    Start[Start Service] --> Decide[MODEL Env Set?]

    Decide -->|Yes| Load[Load model YAML]
    Decide -->|No| Fallback[Use Default: glm47-flash]

    Load --> Check[Model Exists?]
    Fallback --> Check

    Check -->|Yes| GenConfig[Generate LiteLLM Config]
    Check -->|No| Error[Exit with Error]

    GenConfig --> Exec[Execute vllm serve]

    Exec --> Ready[Service Running]

    style Ready fill:#c5cae9
    style Error fill:#ffcdd2
```

---

## Key Design Patterns

### 1. Configuration Composition

The system uses a **layered configuration approach**:
- **Global defaults** in `vars.env` apply to all models
- **Model-specific overrides** in `models/*.yml` customize per-model behavior
- **Template rendering** produces final `config.yaml`

### 2. Runtime Configuration Generation

No Docker rebuilds needed to change models - configuration is generated at container startup based on the `MODEL` environment variable.

### 3. Shared Configuration Volume

Both containers share a `tmpfs` volume for configuration files, enabling:
- Fast config file sharing
- Automatic cleanup on shutdown
- No persistent state in config directory

### 4. Secret Management via Files

Secrets are loaded from files (standard Docker practice):
```
secrets/
├── HF_TOKEN           # Hugging Face access token
└── ANTHROPIC_AUTH_TOKEN
```

### 5. OpenAI Compatibility

LiteLLM acts as a drop-in replacement adapter, translating between:
- Client expectations (OpenAI SDK)
- vLLM's native API
- Model-specific parameters

---

## Scalability Considerations

### Current Limitations

| Aspect | Limitation | Workaround |
|--------|-----------|------------|
| Model Switching | One model per container | Deploy multiple containers with different `MODEL` values |
| Concurrency | Limited by `--max-num-seqs` | Adjust in model `command` section |
| Throughput | Single GPU | Add horizontal replicas |

### Horizontal Scaling Options

```mermaid
flowchart LR
    subgraph "Load Balancer"
        lb[Nginx / Traefik]
    end

    subgraph "vLLM Cluster"
        replica1[vLLM Node 1<br/>PORT=8001]
        replica2[vLLM Node 2<br/>PORT=8002]
        replica3[vLLM Node 3<br/>PORT=8003]
    end

    subgraph "LiteLLM Router"
        lr[LiteLLM with<br/>weighted routing]
    end

    lb --> replica1
    lb --> replica2
    lb --> replica3

    replica1 --> lr
    replica2 --> lr
    replica3 --> lr

    style lb fill:#90caf9
    style lr fill:#90caf9
```

---

## Troubleshooting Architecture

### Common Issues Diagram

```mermaid
flowchart TD
    Start[Issue Detected] --> Check1[Health Checks Pass?]

    Check1 -->|No| Sol1[Check container logs:<br/>docker compose logs]
    Sol1 --> Resolve[Resolution]

    Check1 -->|Yes| Check2[API Endpoint Responsive?]

    Check2 -->|No| Sol2[Verify port binding:<br/>docker compose ps]
    Sol2 --> Resolve

    Check2 -->|Yes| Check3[Config Generated?]

    Check3 -->|No| Sol3[Check model YAML validity:<br/>python -c 'import yaml; yaml.safe_load(...)']
    Sol3 --> Resolve

    Check3 -->|Yes| Check4[Network Connectivity?]

    Check4 -->|No| Sol4[Verify docker network:<br/>docker network inspect bridge]
    Sol4 --> Resolve

    Check4 -->|Yes| Sol5[Model-specific config error]
    Sol5 --> Resolve

    style Resolve fill:#c5cae9
```

---

## Security Considerations

```mermaid
graph TD
    subgraph "Attack Surface"
        A1[API Keys]
        A2[Environment Variables]
        A3[Secret Files]
        A4[Network Exposure]
    end

    subgraph "Mitigations"
        M1[Fixed key: sk-FAKE<br/>for local-only access]
        M2[ vars.env excluded from git]
        M3[secrets/ is gitignored]
        M4[bind to 127.0.0.1 locally]
    end

    A1 --> M1
    A2 --> M2
    A3 --> M3
    A4 --> M4

    style M1 fill:#c8e6c9
    style M2 fill:#c8e6c9
    style M3 fill:#c8e6c9
    style M4 fill:#c8e6c9
```

---

## Performance Tuning Parameters

### vLLM Settings

| Parameter | Location | Effect |
|-----------|----------|--------|
| `--gpu-memory-utilization` | Model command | Memory budget (default: 0.75) |
| `--max-num-seqs` | Model command | Concurrent sequences |
| `--kv-cache-dtype fp8` | Model command | KV cache compression |
| `--attention-backend flashinfer` | Model command | Faster attention |

### LiteLLM Settings

| Parameter | File | Effect |
|-----------|------|--------|
| `max_parallel_requests` | litellm_config.template.yaml | Request queue depth |
| `request_timeout` | litellm_config.template.yaml | Per-request timeout |
| `num_retries` | litellm_config.template.yaml | Retry attempts (disabled) |

---

## Future Enhancement Opportunities

### Potential Improvements

```mermaid
graph TD
    subgraph "Current State"
        CS[Single GPU Serving]
    end

    subgraph "Near Term Enhancements"
        E1[Model Pooling<br/>Multiple GPUs]
        E2[Automatic Model Loading<br/>On-demand]
        E3[Request Prioritization]
    end

    subgraph "Long Term"
        E4[Distributed Serving<br/>Multi-node]
        E5[Auto-scaling Based on Load]
        E6[Model Versioning & Rollback]
    end

    CS --> E1
    E1 --> E2
    E2 --> E3
    E3 --> E4
    E4 --> E5
    E5 --> E6

    style CS fill:#fff9c4
    style E6 fill:#e3f2fd
```

---

## Related Documentation

- [`README.md`](./README.md) - Project overview and quick start
- [`CONFIGURATION.md`](./CONFIGURATION.md) - Configuration system details
- [`MODELS.md`](./MODELS.md) - Model catalog and specifications
- [`LAUNCHER_GUIDE.md`](./LAUNCHER_GUIDE.md) - Client launcher documentation
