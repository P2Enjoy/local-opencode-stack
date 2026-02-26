#!/usr/bin/env python3
"""
resolve_variant.py — Merge a model family YAML defaults + named variant into a flat config.

Usage:
  python3 resolve_variant.py --models-dir DIR --model FAMILY [--variant NAME]

Output: YAML on stdout, ready to be indented and appended under the model key in models.yml.

Merge rules:
  - description: variant overrides if set, else defaults
  - command:     variant provides it, else defaults; must be present in one of them
  - env:         shallow merge; null value removes the key from defaults
  - litellm:     shallow merge; null value removes the key from defaults
"""

import argparse
import sys
from typing import Optional

import yaml


# ---------------------------------------------------------------------------
# Merge helpers
# ---------------------------------------------------------------------------


def _merge_with_null_removal(base: dict, override: dict) -> dict:
    """Merge *override* into a copy of *base*.

    A ``None`` value in *override* deletes that key from the result instead
    of setting it to ``None``.  All other values replace the base value.
    """
    result = dict(base)
    for key, value in override.items():
        if value is None:
            result.pop(key, None)
        else:
            result[key] = value
    return result


# ---------------------------------------------------------------------------
# Core resolver
# ---------------------------------------------------------------------------


def resolve(models_dir: str, model: str, variant_name: Optional[str]) -> dict:
    """Load *model* family file, merge defaults + *variant_name*, return flat dict."""
    model_file = f"{models_dir}/{model}.yml"

    try:
        with open(model_file) as f:
            family = yaml.safe_load(f)
    except FileNotFoundError:
        print(f"Error: Model file not found: {model_file}", file=sys.stderr)
        sys.exit(1)
    except yaml.YAMLError as exc:
        print(f"Error: Failed to parse {model_file}: {exc}", file=sys.stderr)
        sys.exit(1)

    if not isinstance(family, dict) or "variants" not in family:
        print(
            f"Error: '{model_file}' is not a family file (missing 'variants:' key).",
            file=sys.stderr,
        )
        sys.exit(1)

    defaults = family.get("defaults") or {}
    variants = family["variants"] or {}

    # Auto-select when there is exactly one variant.
    if variant_name is None:
        if len(variants) == 1:
            variant_name = next(iter(variants))
        else:
            available = ", ".join(sorted(variants))
            print(
                f"Error: Model '{model}' has multiple variants; "
                f"specify one with --variant.",
                file=sys.stderr,
            )
            print(f"Available variants: {available}", file=sys.stderr)
            sys.exit(1)

    if variant_name not in variants:
        available = ", ".join(sorted(variants))
        print(
            f"Error: Variant '{variant_name}' not found in model '{model}'.",
            file=sys.stderr,
        )
        print(f"Available variants: {available}", file=sys.stderr)
        sys.exit(1)

    vdata = variants[variant_name] or {}
    result: dict = {}

    # description: variant wins if present
    if "description" in vdata:
        result["description"] = vdata["description"]
    elif "description" in defaults:
        result["description"] = defaults["description"]

    # command: variant wins; fallback to defaults; must exist somewhere
    command = vdata.get("command") or defaults.get("command")
    if not command:
        print(
            f"Error: No 'command' defined in variant '{variant_name}' "
            f"or defaults for model '{model}'.",
            file=sys.stderr,
        )
        sys.exit(1)
    # Normalise: one trailing newline (required for YAML '|' block style)
    result["command"] = command.strip() + "\n"

    # env: shallow merge with null-removal
    merged_env = _merge_with_null_removal(
        defaults.get("env") or {},
        vdata.get("env") or {},
    )
    if merged_env:
        result["env"] = merged_env

    # litellm: shallow merge with null-removal
    merged_litellm = _merge_with_null_removal(
        defaults.get("litellm") or {},
        vdata.get("litellm") or {},
    )
    if merged_litellm:
        result["litellm"] = merged_litellm

    return result


# ---------------------------------------------------------------------------
# YAML output: force literal block style for multiline strings
# ---------------------------------------------------------------------------


def _literal_representer(dumper: yaml.Dumper, data: str) -> yaml.ScalarNode:
    if "\n" in data:
        return dumper.represent_scalar("tag:yaml.org,2002:str", data, style="|")
    return dumper.represent_scalar("tag:yaml.org,2002:str", data)


class _LiteralDumper(yaml.Dumper):
    pass


_LiteralDumper.add_representer(str, _literal_representer)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Resolve a model family variant to a flat YAML config."
    )
    parser.add_argument(
        "--models-dir", required=True, help="Directory containing model YAML files"
    )
    parser.add_argument(
        "--model", required=True, help="Model family name (without .yml extension)"
    )
    parser.add_argument(
        "--variant",
        default=None,
        help="Variant name (optional when the family has exactly one variant)",
    )
    args = parser.parse_args()

    resolved = resolve(args.models_dir, args.model, args.variant)
    print(
        yaml.dump(
            resolved,
            Dumper=_LiteralDumper,
            default_flow_style=False,
            allow_unicode=True,
            sort_keys=False,
        ),
        end="",
    )


if __name__ == "__main__":
    main()
