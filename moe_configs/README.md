# vLLM MoE Optimization Profiles

This directory contains optimized kernel configurations for Mixture of Experts (MoE) models in vLLM.

## What are these profiles?

MoE optimization profiles are GPU-specific configuration files that tune the performance of MoE kernels. They contain parameters like:
- Block sizes for matrix multiplications
- Thread block configurations
- Memory access patterns
- Kernel launch parameters

These optimizations can improve MoE model inference performance by 20-30% compared to generic defaults.

## Generating Profiles

To generate profiles for your GPU, run:

```bash
./generate_moe_profiles.sh
```

This script will:
1. Detect your GPU model
2. Generate optimized configurations for common MoE model sizes
3. Save the profiles to this directory
4. The profiles are automatically mounted into the vLLM container

## Profile Format

Profile filenames follow this pattern:
```
E=<expert_size>,N=<num_experts>,device_name=<GPU>,dtype=<precision>.json
```

For example:
- `E=512,N=512,device_name=NVIDIA_GB10,dtype=fp8_w8a8.json`
- `E=1024,N=1024,device_name=NVIDIA_GB10,dtype=float16.json`

## When to Regenerate

Regenerate profiles when:
- You upgrade your GPU
- You upgrade vLLM to a major version
- You want to optimize for different model configurations
- Performance seems suboptimal

## Manual Tuning

For best performance, you can run vLLM's MoE benchmarking tool:

```bash
# Inside the vllm container
python -m vllm.model_executor.layers.fused_moe.benchmark_moe \
  --expert-size 512 \
  --num-experts 512 \
  --dtype fp8_w8a8 \
  --output-dir /app/moe_configs
```

This will profile actual performance and generate optimal configurations.
