# vLLM Multi-Model Server

A production-ready Docker-based deployment system for running multiple vLLM models with LiteLLM proxy integration. This setup provides OpenAI-compatible API endpoints for various large language models optimized for different use cases.

## 🚀 Quick Start

### Launch a Model

The easiest way to launch a model is using the `runMe.sh` script:

```bash
# List available models
./runMe.sh

# Launch a specific model
./runMe.sh step-3.5-flash

# Launch with rebuild
./runMe.sh glm47-flash --build

# Launch in detached mode (background)
./runMe.sh qwen3-next-coder -d
```

### Alternative: Direct Docker Compose

If you prefer using docker compose directly:

```bash
# Set the model and launch
MODEL=step-3.5-flash sudo docker compose up

# With rebuild
MODEL=step-3.5-flash sudo docker compose up --build

# In detached mode
MODEL=glm47-flash sudo docker compose up -d
```

**⚠️ Important:** When using `sudo docker compose`, you must use `MODEL=name sudo docker compose up` (not `sudo MODEL=name docker compose up`) to ensure the environment variable is passed correctly.

## 📋 Available Models

This deployment supports multiple pre-configured models, each optimized for specific use cases:

| Model | Use Case | Context | Concurrency |
|-------|----------|---------|-------------|
| `glm47-flash` | General-purpose reasoning & tool calling | 128K | Low (16) |
| `step-3.5-flash` | Long-context reasoning & problem-solving | Auto | Medium (24) |
| `step-3.5-flash-hcsw` | High-throughput inference | 8K | High (64) |
| `qwen3-next-coder` | Code generation and analysis | Variable | Medium |

For detailed model specifications and configuration, see [models/README.md](./models/README.md).

## 🏗️ Architecture

The system consists of three main services:

1. **vllm-node**: Runs the vLLM inference engine with the selected model
2. **litellm**: Provides a unified OpenAI-compatible API proxy with rate limiting and monitoring
3. **db**: PostgreSQL database for LiteLLM's internal state and usage tracking

```
┌─────────────────┐
│   Your Client   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌──────────────┐
│    LiteLLM      │────▶│  PostgreSQL  │
│   Port: 4000    │     │   Database   │
└────────┬────────┘     └──────────────┘
         │
         ▼
┌─────────────────┐
│   vLLM Engine   │
│   Port: 8000    │
└─────────────────┘
```

## 🔧 Configuration

### Environment Variables

Global configuration is stored in `vars.env`. Common variables:

```bash
# NCCL Configuration
NCCL_P2P_DISABLE=1

# LiteLLM Defaults (optional, can override per-model)
#LITELLM_TEMPERATURE=0.7
#LITELLM_TOP_P=0.8
#LITELLM_MAX_TOKENS=65536
```

### Model-Specific Configuration

Each model has its own configuration file in the `models/` directory:

- `models/glm47-flash.yml`
- `models/step-3.5-flash.yml`
- `models/step-3.5-flash-hcsw.yml`
- `models/qwen3-next-coder.yml`

These files define:
- The vLLM command with model-specific flags
- Environment variables for optimization
- LiteLLM API parameters

### Secrets Management

Sensitive credentials (API keys, tokens) should be stored in the `secrets/` directory:

```bash
# Create secrets directory
mkdir -p secrets

# Add secrets as individual files (filename = env var name)
echo "your-hf-token" > secrets/HF_TOKEN
echo "your-api-key" > secrets/ANTHROPIC_API_KEY

# These will be automatically loaded as environment variables
```

See [secrets/README.md](./secrets/README.md) for more details.

## 📡 API Usage

### Accessing the API

Once launched, the services are available at:

- **LiteLLM Proxy**: http://localhost:4000 (Recommended - with rate limiting & monitoring)
- **Direct vLLM**: http://localhost:8000 (Direct access, no proxy features)

### Example Usage

#### Python (OpenAI SDK)

```python
from openai import OpenAI

# Use LiteLLM proxy (recommended)
client = OpenAI(
    base_url="http://localhost:4000/v1",
    api_key="sk-FAKE"  # Default API key
)

response = client.chat.completions.create(
    model="vllm_agent",
    messages=[
        {"role": "user", "content": "Explain quantum computing in simple terms"}
    ]
)

print(response.choices[0].message.content)
```

#### cURL

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-FAKE" \
  -d '{
    "model": "vllm_agent",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

#### Using Claude Code with Local Model

Use the launcher scripts in `launchers/` to route Claude Code through your local model:

```bash
# Launch Claude Code using your local vLLM instance
./launchers/local_claude.sh

# Or add to your PATH for easier access
export PATH="$PWD/launchers:$PATH"
local_claude.sh
```

See [launchers/local_claude.sh](./launchers/local_claude.sh) for more options.

## 🛠️ Management Commands

### Starting Services

```bash
# Foreground (see logs in terminal)
./runMe.sh step-3.5-flash

# Background (detached mode)
./runMe.sh step-3.5-flash -d
```

### Stopping Services

```bash
# Stop all services
sudo docker compose down

# Stop and remove volumes (clean slate)
sudo docker compose down -v
```

### Viewing Logs

```bash
# All services
sudo docker compose logs -f

# Specific service
sudo docker compose logs -f vllm-node
sudo docker compose logs -f litellm

# Last 100 lines
sudo docker compose logs --tail=100 vllm-node
```

### Switching Models

```bash
# Stop current model
sudo docker compose down

# Start with different model
./runMe.sh qwen3-next-coder
```

### Rebuilding After Configuration Changes

```bash
# Rebuild container image
./runMe.sh step-3.5-flash --build

# Or with docker compose directly
MODEL=step-3.5-flash sudo docker compose up --build
```

## 🔍 Health Checks

### Check Service Status

```bash
# vLLM health
curl http://localhost:8000/health

# LiteLLM health
curl http://localhost:4000/health/liveliness

# List loaded models
curl -H "Authorization: Bearer sk-FAKE" http://localhost:8000/v1/models
```

### Monitor GPU Usage

```bash
# Real-time GPU monitoring
watch -n 1 nvidia-smi

# Docker container stats
sudo docker stats
```

### Check Container Status

```bash
# List running containers
sudo docker compose ps

# Check specific container health
sudo docker compose ps vllm-node
```

## 🐛 Troubleshooting

### Issue: Model Always Defaults to glm47-flash

**Problem:** Running `MODEL="step-3.5-flash" sudo docker compose up` still launches glm47-flash.

**Cause:** The `sudo` command doesn't preserve environment variables by default.

**Solutions:**
1. ✅ **Use the runMe.sh script (Recommended):**
   ```bash
   ./runMe.sh step-3.5-flash
   ```

2. ✅ **Put MODEL before sudo:**
   ```bash
   MODEL=step-3.5-flash sudo docker compose up
   ```

3. ⚠️ **Use sudo -E (preserves all env vars):**
   ```bash
   sudo -E docker compose up
   # Note: This exposes ALL environment variables to sudo, which may be a security concern
   ```

### Issue: Out of Memory (OOM) Errors

**Symptoms:** Container crashes with CUDA out of memory errors.

**Solutions:**
1. Switch to a smaller model or high-concurrency variant:
   ```bash
   ./runMe.sh step-3.5-flash-hcsw  # Smaller context window
   ```

2. Reduce GPU memory utilization (edit model's `.yml` file):
   ```yaml
   command: |
     vllm serve ... --gpu-memory-utilization 0.85  # Was 0.96
   ```

3. Close other GPU-using processes:
   ```bash
   nvidia-smi  # Check what's using GPU
   ```

### Issue: Container Fails Health Check

**Symptoms:** Container marked as unhealthy, LiteLLM can't connect.

**Diagnosis:**
```bash
# Check container logs
sudo docker compose logs vllm-node

# Check if vLLM port is accessible
curl http://localhost:8000/health
```

**Common causes:**
- Model download in progress (wait longer, check logs)
- Insufficient GPU memory (see OOM solutions above)
- Model configuration error (check model .yml file syntax)

### Issue: Permission Denied

**Symptoms:** Docker commands fail with permission errors.

**Solutions:**
1. Add your user to docker group:
   ```bash
   sudo usermod -aG docker $USER
   newgrp docker  # Activate immediately
   ```

2. Or continue using sudo:
   ```bash
   ./runMe.sh step-3.5-flash  # Script handles sudo automatically (interactive terminal required if password prompt is needed)
   ```

### Issue: Model Download is Slow

**Cause:** Models are downloaded from HuggingFace on first run.

**Solution:**
- Be patient! Large models can be 10-50GB
- Monitor progress in logs:
  ```bash
  sudo docker compose logs -f vllm-node
  ```
- Pre-download models:
  ```bash
  huggingface-cli download stepfun-ai/Step-3.5-Flash-FP8
  ```

### Issue: Port Already in Use

**Symptoms:** Error: "port is already allocated"

**Solution:**
```bash
# Check what's using the port
sudo lsof -i :8000
sudo lsof -i :4000

# Stop conflicting service or change ports in docker-compose.yml
```

## 📁 Project Structure

```
vllm-server/
├── README.md                      # This file
├── docker-compose.yml             # Docker services definition
├── Dockerfile                     # Container image definition
├── runMe.sh                       # Simple model launcher script
├── run_vllm_agent.sh              # Container entrypoint script
├── vars.env                       # Global environment variables
├── generate_litellm_config.py     # LiteLLM config generator
├── litellm_config.template.yaml   # LiteLLM template
│
├── models/                        # Model configurations
│   ├── README.md                  # Model documentation
│   ├── glm47-flash.yml
│   ├── step-3.5-flash.yml
│   ├── step-3.5-flash-hcsw.yml
│   └── qwen3-next-coder.yml
│
├── scripts/                       # Helper scripts
│   ├── gen_models_yml.sh          # Model config builder
│   └── load_secrets_env.sh        # Secrets loader
│
├── secrets/                       # Sensitive credentials (gitignored)
│   ├── README.md
│   ├── HF_TOKEN                   # HuggingFace token
│   └── ANTHROPIC_API_KEY          # Anthropic API key
│
└── launchers/                     # Client launcher scripts
    ├── local_claude.sh            # Claude Code launcher
    ├── local_codex.sh             # Codex launcher
    └── open_code.sh               # VS Code launcher
```

## 🔐 Security Notes

1. **API Keys**: The default API key is `sk-FAKE` - change this for production use
2. **Secrets**: Never commit secrets to git. Use the `secrets/` directory (gitignored)
3. **Network**: Services are exposed on localhost by default. Configure firewall rules for external access
4. **Sudo**: The runMe.sh script uses sudo when needed. Review Docker group membership for sudo-less operation

## 🤝 Contributing

When adding a new model:

1. Create a new `.yml` file in `models/` directory
2. Follow the existing format (see [models/README.md](./models/README.md))
3. Test with `./runMe.sh your-new-model`
4. Update the models table in this README
5. Add model card details to models/README.md

## 📚 Further Reading

- **Model Configurations**: [models/README.md](./models/README.md) - Detailed model specs and tuning guide
- **vLLM Documentation**: https://docs.vllm.ai/
- **LiteLLM Documentation**: https://docs.litellm.ai/
- **Docker Compose Documentation**: https://docs.docker.com/compose/

## 📜 License

See LICENSE file for details.

## 🆘 Support

- **Issues**: Check logs first (`sudo docker compose logs -f`)
- **Documentation**: See `models/README.md` for model-specific details
- **vLLM Docs**: https://docs.vllm.ai/en/latest/
- **GPU Issues**: Run `nvidia-smi` to check GPU status

---

**Last Updated:** February 2026
**Compatible With:** vLLM v1+, Docker Compose v2+
