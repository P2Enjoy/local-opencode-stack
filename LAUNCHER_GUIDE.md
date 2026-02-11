# Local Claude Launcher Guide

This guide explains launcher scripts for testing and using the local LiteLLM proxy.

## Overview

- **test.sh** - Tests the LiteLLM proxy with Anthropic-style API calls
- **local_claude.sh** - Launches Claude Code routed through the local LiteLLM proxy
- **open_code.sh** - Launches OpenCode.ai routed through the local LiteLLM proxy
- **local_codex.sh** - Launches Codex CLI routed through the local LiteLLM proxy

## Setup

### 1. Start the Services

```bash
cd /home/p2enjoy/jupyterlab/vllm-server/launchers
docker compose up -d
```

Or from the root directory:

```bash
cd /home/p2enjoy/jupyterlab/vllm-server
docker compose up -d
```

This starts:
- **vllm-node** (port 8000) - The local LLM backend
- **litellm** (port 4000) - The proxy that translates API calls
- **db** - PostgreSQL database for litellm

### 2. Verify Services are Running

```bash
docker compose ps
```

All three services should show `healthy` status.

### 3. Test the Proxy

```bash
./test.sh
```

This runs 5 tests:
1. Basic message API call
2. Message with system prompt
3. Multi-turn conversation
4. Temperature and sampling parameters
5. Streaming API calls

Expected output: All tests should pass with ✓

## Using the Local Claude Launcher

### Quick Start

```bash
# Start with default settings (localhost:4000)
./local_claude.sh

# Or if added to PATH (see Setup below):
local_claude.sh
```

### Command Options

```bash
# Show help
local_claude.sh --help

# Show what would be set without launching
local_claude.sh --dry-run

# Verbose output
local_claude.sh --verbose

# Skip health check (faster)
local_claude.sh --no-check

# Custom proxy host/port
local_claude.sh --host 192.168.1.100 --port 8080

# Custom API token
local_claude.sh --token your-custom-token

# Pass arguments to Claude Code
local_claude.sh -- /path/to/project
```

### Advanced Usage

```bash
# Verbose with custom proxy
local_claude.sh --verbose --host 192.168.1.100 --port 8080

# Skip health check and pass project path
local_claude.sh --no-check -- /home/user/my-project

# Show config without health check or launch
local_claude.sh --dry-run
```

## Adding to System PATH

To use `local_claude.sh` from anywhere:

```bash
# This was already done during setup, but you can verify:
tail ~/.bashrc | grep "launchers"

# If not added, manually add this to ~/.bashrc:
export PATH="/home/p2enjoy/jupyterlab/vllm-server/launchers:$PATH"

# Then reload your shell:
source ~/.bashrc
```

After this, you can run from anywhere:

```bash
local_claude.sh
local_claude.sh --verbose
local_claude.sh -- /path/to/project
```

## What Happens When You Run local_claude.sh

1. **Configuration Load** - Reads `vars.env` for settings
2. **Claude Code Check** - Ensures Claude Code is installed (installs if needed)
3. **Health Check** - Verifies litellm proxy is running (can skip with `--no-check`)
4. **Environment Setup** - Sets Anthropic environment variables:
   - `ANTHROPIC_BASE_URL=http://localhost:4000`
   - `ANTHROPIC_AUTH_TOKEN=sk-FAKE`
   - `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`
5. **Launch** - Starts Claude Code with the local proxy configuration

## Environment Variables

These are automatically configured from `vars.env`:

| Variable | Purpose | Default |
|----------|---------|---------|
| `ANTHROPIC_BASE_URL` | LiteLLM proxy URL | `http://localhost:4000` |
| `ANTHROPIC_AUTH_TOKEN` | API authentication token | `sk-FAKE` |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | Disable non-essential traffic | `1` |
| `MODEL` | Model name used by vLLM | `glm47-flash` |
| `HF_TOKEN` | Hugging Face token (for model downloads) | From vars.env |

## Troubleshooting

### Claude Code Won't Launch

```bash
# Check if services are running
docker compose ps

# If not running:
docker compose up -d

# Check proxy health manually
curl http://localhost:4000/health/liveliness

# Verify Claude Code is installed
which claude-code || which claude
```

### Can't Find local_claude.sh from Other Directories

```bash
# Check if PATH is set
echo $PATH | grep vllm-server

# If not, add to ~/.bashrc and reload:
export PATH="/home/p2enjoy/jupyterlab/vllm-server:$PATH"
source ~/.bashrc
```

### LiteLLM Proxy Errors

```bash
# Check litellm logs
docker compose logs litellm

# Check vllm-node logs
docker compose logs vllm-node

# Restart services
docker compose restart
```

### Claude Code Doesn't Connect to Proxy

```bash
# Test with verbose mode
local_claude.sh --verbose

# Test the proxy manually
./test.sh

# Check if proxy is responding
curl -X GET http://localhost:4000/health/liveliness
```

## Workflow Example

```bash
# 1. Start services in the background
cd /home/p2enjoy/jupyterlab/vllm-server
docker compose up -d

# 2. Wait for services to be healthy
sleep 10

# 3. Test the connection
cd launchers
./test.sh

# 4. Launch Claude Code with local proxy
./local_claude.sh

# 5. In Claude Code, you can now:
#    - Create files
#    - Ask questions (will use local model)
#    - Get Anthropic-style API responses

# OR from anywhere after PATH is set:
local_claude.sh
```

## Performance Notes

- **First time setup** - Downloading models can take 5-10 minutes
- **Health checks** - Add `--no-check` flag to skip if you know services are running
- **Model context** - Check `models/*.yml` for context window limits
- **GPU memory** - Adjust `docker-compose.yml` if needed

## Files Reference

| File | Purpose |
|------|---------|
| `launchers/local_claude.sh` | Main launcher script - runs Claude Code with local proxy |
| `launchers/test.sh` | Test suite for the proxy - validates connection |
| `vars.env` | Configuration variables (in root directory) |
| `docker-compose.yml` | Service definitions (in root directory) |
| `models/*.yml` | Model-specific settings (source fragments in root directory) |
| `litellm_config.template.yaml` | LiteLLM proxy configuration (in root directory) |
| `LAUNCHER_GUIDE.md` | This file - complete usage documentation |

## Next Steps

1. Start the services: `docker compose up -d`
2. Test the connection: `./test.sh`
3. Launch Claude Code: `local_claude.sh`
4. Add to PATH: `source ~/.bashrc` (already done)
5. Use from anywhere: `local_claude.sh`
