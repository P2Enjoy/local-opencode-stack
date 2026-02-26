#!/usr/bin/env python3
"""
Standalone MoE Profile Generator - No Docker or vLLM installation required!

This script generates MoE optimization configs directly on your local machine
by detecting your GPU and creating appropriate configuration files.
"""

import json
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Tuple


def get_gpu_info() -> Tuple[str, str]:
    """Detect GPU device name using nvidia-smi."""
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
        print("Using default fallback GPU name", file=sys.stderr)
        return "NVIDIA_GPU", "8.0"


def generate_default_moe_config(expert_size: int, num_experts: int) -> Dict:
    """
    Generate a reasonable default MoE config.

    These are heuristic defaults optimized for modern GPUs (Ampere/Hopper).
    """
    config = {
        "M": [128, 256, 512, 1024, 2048, 4096, 8192],
        "config": {}
    }

    # Generate configs for different batch sizes
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
    """Generate MoE configs for common model configurations."""
    # Common MoE configurations found in popular models
    common_configs = [
        (512, 512, "fp8_w8a8"),
        (1024, 1024, "fp8_w8a8"),
        (2048, 512, "fp8_w8a8"),
        (512, 512, "float16"),
        (1024, 1024, "float16"),
        (512, 512, "bfloat16"),
        (1024, 1024, "bfloat16"),
    ]

    generated_files = []

    for expert_size, num_experts, dtype in common_configs:
        filename = f"E={expert_size},N={num_experts},device_name={device_name},dtype={dtype}.json"
        filepath = config_dir / filename

        if not filepath.exists():
            config = generate_default_moe_config(expert_size, num_experts)

            with open(filepath, 'w') as f:
                json.dump(config, f, indent=2)

            generated_files.append(str(filepath))
            print(f"  ✓ Generated: {filename}")
        else:
            print(f"  ✓ Already exists: {filename}")

    return generated_files


def main():
    """Main entry point."""
    script_dir = Path(__file__).parent
    output_dir = script_dir / "moe_configs"

    print("=" * 70)
    print("vLLM MoE Profile Generator (Standalone)")
    print("=" * 70)
    print()

    # Detect GPU
    device_name, compute_cap = get_gpu_info()
    print(f"Detected GPU: {device_name}")
    print(f"Compute Capability: {compute_cap}")
    print()

    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"Output directory: {output_dir}")
    print()

    # Generate configs
    print("Generating MoE configurations...")
    generated_files = generate_configs_for_device(device_name, output_dir)

    print()
    if generated_files:
        print(f"✓ Successfully generated {len(generated_files)} new config file(s)")
    else:
        print("✓ All config files already exist")

    print()
    print("These profiles will be automatically mounted into the vLLM container")
    print("when you start it with docker-compose.")
    print()
    print("=" * 70)

    return 0


if __name__ == "__main__":
    sys.exit(main())
