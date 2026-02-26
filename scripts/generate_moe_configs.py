#!/usr/bin/env python3
"""
Generate MoE optimization configs for vLLM to avoid warnings about missing config files.

This script creates optimized kernel configurations for Mixture of Experts (MoE) models
based on the detected GPU device. The configs are written to vLLM's expected location.
"""

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Tuple


def get_gpu_info() -> Tuple[str, str]:
    """
    Detect GPU device name using nvidia-smi.

    Returns:
        Tuple of (device_name, compute_capability)
    """
    try:
        # Get GPU name
        result = subprocess.run(
            ['nvidia-smi', '--query-gpu=name', '--format=csv,noheader'],
            capture_output=True,
            text=True,
            check=True
        )
        gpu_name = result.stdout.strip().split('\n')[0]

        # Normalize device name (replace spaces with underscores, remove special chars)
        device_name = gpu_name.replace(' ', '_').replace('-', '_')

        # Get compute capability
        result = subprocess.run(
            ['nvidia-smi', '--query-gpu=compute_cap', '--format=csv,noheader'],
            capture_output=True,
            text=True,
            check=True
        )
        compute_cap = result.stdout.strip().split('\n')[0]

        return device_name, compute_cap
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        print(f"Warning: Could not detect GPU: {e}", file=sys.stderr)
        # Default fallback
        return "NVIDIA_GPU", "8.0"


def get_vllm_config_dir() -> Path:
    """
    Find the vLLM MoE configs directory.

    Returns:
        Path to the fused_moe configs directory
    """
    try:
        # Try to import vllm and find its installation path
        import vllm
        vllm_path = Path(vllm.__file__).parent
        config_dir = vllm_path / "model_executor" / "layers" / "fused_moe" / "configs"

        if config_dir.exists():
            return config_dir

        # If not exists, create it
        config_dir.mkdir(parents=True, exist_ok=True)
        return config_dir
    except ImportError:
        # Fallback to common installation path
        config_dir = Path("/usr/local/lib/python3.12/dist-packages/vllm/model_executor/layers/fused_moe/configs")
        config_dir.mkdir(parents=True, exist_ok=True)
        return config_dir


def generate_default_moe_config(expert_size: int, num_experts: int) -> Dict:
    """
    Generate a reasonable default MoE config.

    These are heuristic defaults that should work reasonably well across devices.
    For optimal performance, these should be tuned via benchmarking.

    Args:
        expert_size: Expert hidden size (E parameter)
        num_experts: Number of experts (N parameter)

    Returns:
        Dict with MoE kernel configuration
    """
    # These are conservative defaults that should work on most modern GPUs
    # For FP8, we use smaller block sizes to maximize throughput
    config = {
        "M": [128, 256, 512, 1024, 2048, 4096, 8192],  # Batch sizes to optimize for
        "config": {}
    }

    # Generate configs for different batch sizes
    # These are based on typical Ampere/Hopper architecture parameters
    for m in config["M"]:
        if m <= 512:
            # Small batch: prioritize latency
            config["config"][str(m)] = {
                "BLOCK_SIZE_M": 64,
                "BLOCK_SIZE_N": 64,
                "BLOCK_SIZE_K": 32,
                "GROUP_SIZE_M": 8,
                "num_warps": 4,
                "num_stages": 2
            }
        elif m <= 2048:
            # Medium batch: balance latency and throughput
            config["config"][str(m)] = {
                "BLOCK_SIZE_M": 128,
                "BLOCK_SIZE_N": 128,
                "BLOCK_SIZE_K": 64,
                "GROUP_SIZE_M": 8,
                "num_warps": 8,
                "num_stages": 3
            }
        else:
            # Large batch: prioritize throughput
            config["config"][str(m)] = {
                "BLOCK_SIZE_M": 256,
                "BLOCK_SIZE_N": 256,
                "BLOCK_SIZE_K": 64,
                "GROUP_SIZE_M": 8,
                "num_warps": 8,
                "num_stages": 4
            }

    return config


def generate_configs_for_device(device_name: str, config_dir: Path) -> List[str]:
    """
    Generate MoE configs for common model configurations.

    Args:
        device_name: GPU device name
        config_dir: Directory to write configs to

    Returns:
        List of generated config file paths
    """
    # Common MoE configurations found in popular models
    # (expert_size, num_experts, dtype)
    common_configs = [
        (512, 512, "fp8_w8a8"),    # Common for many MoE models
        (1024, 1024, "fp8_w8a8"),  # Larger MoE models
        (2048, 512, "fp8_w8a8"),   # Alternative configuration
        (512, 512, "float16"),     # FP16 variants
        (1024, 1024, "float16"),
        (512, 512, "bfloat16"),    # BF16 variants
        (1024, 1024, "bfloat16"),
    ]

    generated_files = []

    for expert_size, num_experts, dtype in common_configs:
        filename = f"E={expert_size},N={num_experts},device_name={device_name},dtype={dtype}.json"
        filepath = config_dir / filename

        # Only generate if it doesn't exist
        if not filepath.exists():
            config = generate_default_moe_config(expert_size, num_experts)

            # Write config file
            with open(filepath, 'w') as f:
                json.dump(config, f, indent=2)

            generated_files.append(str(filepath))
            print(f"✓ Generated: {filename}")
        else:
            print(f"✓ Already exists: {filename}")

    return generated_files


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Generate MoE optimization configs for vLLM"
    )
    parser.add_argument(
        "output_dir",
        nargs="?",
        default=None,
        help="Output directory for config files (default: auto-detect vLLM installation)"
    )
    args = parser.parse_args()

    print("=" * 70)
    print("vLLM MoE Configuration Generator")
    print("=" * 70)
    print()

    # Detect GPU
    device_name, compute_cap = get_gpu_info()
    print(f"Detected GPU: {device_name}")
    print(f"Compute Capability: {compute_cap}")
    print()

    # Determine config directory
    if args.output_dir:
        config_dir = Path(args.output_dir)
        config_dir.mkdir(parents=True, exist_ok=True)
        print(f"Output directory: {config_dir}")
    else:
        config_dir = get_vllm_config_dir()
        print(f"Config directory (auto-detected): {config_dir}")
    print()

    # Generate configs
    print("Generating MoE configurations...")
    generated_files = generate_configs_for_device(device_name, config_dir)

    print()
    if generated_files:
        print(f"✓ Successfully generated {len(generated_files)} new config file(s)")
    else:
        print("✓ All config files already exist")

    print()
    print("MoE configuration complete!")
    print("=" * 70)

    return 0


if __name__ == "__main__":
    sys.exit(main())
