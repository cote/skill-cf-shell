---
name: cf-shell
description: >
  Provision and use a Cloud Foundry-hosted bash shell via shell2http. Verifies the cf CLI, installs shell2http locally as needed, deploys the shell app to CF, and executes commands against it over HTTPS.
  Use when asked to work with cf-shell.
compatibility: Requires bash.
metadata:
  author: cote
  version: "1.0"
---

# cf-shell

## Actions

<!-- TODO: document commands, examples, options -->

## Security

- Credentials via vals (per-skill secrets.yaml)
- Never log or echo secrets

## XDG Paths

| What | Location |
|------|----------|
| Config | `~/.config/io.cote.ai/cf-shell/` |
| Data | `~/.local/share/io.cote.ai/cf-shell/` |
| State | `~/.local/state/io.cote.ai/cf-shell/` |
