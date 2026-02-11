"""Model serving configuration loader."""
import os
from pathlib import Path
from typing import Dict, List, Optional, TypedDict
from dotenv import load_dotenv


__version__ = "0.1.0"


class BaseModelConfig(TypedDict):
    """Base typed dict for model configurations."""

    command: str
    env: Dict[str, str]
    litellm: Dict[str, float]


def _load_env_vars() -> Dict[str, str]:
    """Load and export all environment variables from .env file."""
    load_dotenv()
    return {
        k: v
        for k, v in os.environ.items()
        if v != "" and not k.startswith("__")
    }


_model_dir = Path(__file__).parent.parent / "models"
_global_env_vars: Dict[str, str] = {}


def init_environment(global_env_file: Optional[str] = None) -> None:
    """
    Initialize the environment with global variables.

    Args:
        global_env_file: Path to a .env file containing global variables.
                         If None, loads from ./global.env or ./.env
    """
    global _global_env_vars

    if global_env_file:
        load_dotenv(dotenv_path=Path(global_env_file))
    elif Path("./global.env").exists():
        load_dotenv(dotenv_path="./global.env")

    _global_env_vars = _load_env_vars()


def scan_available_models(model_dir: Optional[Path] = None) -> List[str]:
    """
    Scan the models directory for available model configurations.

    Args:
        model_dir: Custom directory path. Defaults to ../models/

    Returns:
        List of available model names (filenames without .yml extension).
    """
    if model_dir is None:
        model_dir = _model_dir

    if not model_dir.exists():
        raise FileNotFoundError(f"Models directory not found: {model_dir}")

    yml_files = sorted([f.stem for f in model_dir.glob("*.yml")])
    return yml_files


def load_model(
    model_name: str,
    model_dir: Optional[Path] = None,
    inject_globals: bool = True,
) -> BaseModelConfig:
    """
    Load a specific model configuration.

    Args:
        model_name: Name of the model (filename without .yml suffix)
        model_dir: Custom directory path. Defaults to ../models/
        inject_globals: Whether to inject global ENV vars into model-specific env

    Returns:
        Dictionary containing the model configuration.

    Raises:
        FileNotFoundError: If the model file doesn't exist.
    """
    if model_dir is None:
        model_dir = _model_dir

    model_path = model_dir / f"{model_name}.yml"

    if not model_path.exists():
        available = ", ".join(scan_available_models())
        raise FileNotFoundError(
            f"Model '{model_name}' not found. "
            f"Available models: [{available}]"
        )

    import yaml

    with open(model_path, "r") as f:
        config = yaml.safe_load(f)

    # Inject global environment variables if requested
    if inject_globals and _global_env_vars:
        merged_env = {}
        merged_env.update(config.get("env", {}))
        merged_env.update(_global_env_vars)
        config["env"] = merged_env

    return cast(BaseModelConfig, config)


def load_all_models(
    *,
    model_names: Optional[List[str]] = None,
    model_dir: Optional[Path] = None,
    inject_globals: bool = True,
) -> Dict[str, BaseModelConfig]:
    """
    Load all or specified model configurations.

    Args:
        model_names: Specific models to load. If None, loads all scanned models.
        model_dir: Custom directory path. Defaults to ../models/
        inject_globals: Whether to inject global ENV vars into model-specific env

    Returns:
        Dictionary mapping model names to their configurations.
    """
    if model_names is None:
        model_names = scan_available_models()

    return {
        name: load_model(name, model_dir=model_dir, inject_globals=inject_globals)
        for name in model_names
    }