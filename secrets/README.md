# Secrets Usage

This project supports file-based secrets so you can keep tokens out of `vars.env`.

## How It Works

Secret files are loaded as environment variables:

- File name = environment variable name
- File content = environment variable value

Example:

```text
secrets/HF_TOKEN
secrets/ANTHROPIC_AUTH_TOKEN
secrets/OPENAI_API_KEY
```

The runtime loads secrets from:

1. `${SECRETS_DIR}` (default: `/app/secrets` in container, `./secrets` for local launchers)
2. `/run/secrets` (Docker secrets path, container only)

## Precedence Rules

`vars.env` and existing process environment variables win by default.

- If a variable already has a non-empty value, the secret file is ignored.
- If a variable is missing or empty, the secret file value is used.

## Setup

1. Create secret files:

```bash
mkdir -p secrets
printf '%s' 'hf_xxx' > secrets/HF_TOKEN
printf '%s' 'sk-xxx' > secrets/ANTHROPIC_AUTH_TOKEN
chmod 600 secrets/*
```

2. Keep sensitive values out of `vars.env` (or leave those keys unset).
3. Start/restart services:

```bash
docker compose up -d --build
```

## Implemented Integration

Secrets loading is enabled in:

- `run_vllm_agent.sh` (container startup)
- `launchers/local_claude.sh`
- `launchers/local_codex.sh`
- `launchers/open_code.sh`

Shared loader:

- `scripts/load_secrets_env.sh`

Compose mount:

- `docker-compose.yml` mounts `./secrets` to `/app/secrets:ro`

## Notes

- `secrets/*` is ignored by git.
- `secrets/README.md` is tracked to document this behavior.
