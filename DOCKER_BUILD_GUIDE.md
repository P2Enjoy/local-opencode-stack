# Docker Build Guide - vLLM with DeepGEMM fp8 Support

## Quick Start

```bash
# Build the custom Docker image
docker-compose build

# Start all services
docker-compose up -d

# Check logs
docker logs -f vllm-container
```

## Build Process Overview

The build process does the following:
1. Extends the existing `scitrera/dgx-spark-vllm:0.14.0-t5` image
2. Installs build dependencies (git, build-essential)
3. Clones the DeepGEMM repository with all submodules
4. Installs DeepGEMM via `setup.py install`
5. Installs in editable mode with `uv pip install -e .`
6. Cleans up build artifacts to minimize image size

## Testing & Validation

### 1. Validate Configuration
```bash
docker-compose config
```
This checks your docker-compose.yml for syntax errors before building.

### 2. Build the Image
```bash
# Standard build
docker-compose build

# Force rebuild without cache (useful if dependencies changed)
docker-compose build --no-cache

# View build progress (verbose)
docker-compose build --progress=plain
```

### 3. Check Image Size
```bash
docker images | grep vllm
```

### 4. Dry Run (Create containers without starting)
```bash
docker-compose up --no-start
docker ps -a  # List all containers
```

### 5. Start Services
```bash
docker-compose up -d
```

### 6. Monitor Startup
```bash
# Watch logs in real-time
docker logs -f vllm-container

# Check if vLLM is ready (look for "Application startup complete")
docker logs vllm-container | tail -20
```

### 7. Test vLLM API
```bash
# Once the service is running
curl http://localhost:8000/v1/models

# Or check health
curl http://localhost:8000/health
```

## Troubleshooting

### Build Fails During Git Clone
**Problem:** `fatal: unable to access 'https://github.com/deepseek-ai/DeepGEMM'`

**Solutions:**
- Check internet connectivity
- Verify the repository URL is correct
- If behind a proxy, configure Docker to use it

### Build Fails at Python Setup
**Problem:** `error: command 'gcc' not found`

**Solution:** The Dockerfile includes `build-essential`. If still failing:
```bash
# Check if g++ is available
docker-compose build --progress=plain 2>&1 | grep -i error
```

### Image Size is Too Large
**Solutions:**
- The `--depth 1` flag in git clone reduces download size
- Build artifacts are cleaned up automatically
- Consider using `docker image prune` to clean unused layers

### vLLM Container Won't Start
```bash
# Check detailed logs
docker logs vllm-container

# Check resource constraints
docker stats vllm-container

# Verify GPU access
docker exec vllm-container nvidia-smi
```

## Optimization Tips

### 1. Multi-Stage Builds (Optional)
If the image grows too large, you can use a multi-stage build to separate build dependencies from runtime:

```dockerfile
FROM scitrera/dgx-spark-vllm:0.14.0-t5 as builder
# ... install and build DeepGEMM ...

FROM scitrera/dgx-spark-vllm:0.14.0-t5
COPY --from=builder /usr/local/lib/python*/dist-packages/ /usr/local/lib/python*/dist-packages/
```

### 2. Layer Caching
Docker caches layers. To maximize efficiency:
- Change frequently modified layers (like adding local files) last
- Group stable dependencies together
- Use `.dockerignore` to prevent unnecessary rebuilds

### 3. Build Optimization Flags
In `docker-compose.yml`, you can add:
```yaml
build:
  context: .
  dockerfile: Dockerfile
  args:
    BUILDKIT_INLINE_CACHE: 1
```

## Performance Tuning

### GPU Memory Allocation
The base image already has optimizations. To verify:
```bash
docker exec vllm-container nvidia-smi --query-gpu=memory.total,memory.used --format=csv
```

### Batch & Sequence Limits
Check `docker-compose.yml` for environment variables that control:
- `VLLM_TENSOR_PARALLEL_SIZE`
- `VLLM_GPU_MEMORY_UTILIZATION`
- `MAX_SEQ_LEN_TO_CAPTURE`

## Cleanup

```bash
# Stop all services
docker-compose down

# Remove images
docker rmi <image_id>

# Remove unused images and layers
docker image prune -a

# Remove all containers, volumes (careful!)
docker-compose down -v
```

## Building Locally vs CI/CD

For local development:
```bash
docker-compose build --no-cache
docker-compose up -d
```

For CI/CD pipelines, consider:
- Using `docker buildx` for multi-platform builds
- Tagging images with version numbers
- Pushing to a registry (Docker Hub, ECR, etc.)
