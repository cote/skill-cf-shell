# Changelog

## 1.0  -  2026-04-22

First public release.

- Dispatcher `scripts/cf-shell.sh` with subcommands: `preflight`,
  `deploy`, `secure`, `exec`, `url`, `destroy`. Deploy auto-generates
  and sets a random basic-auth credential; re-pushes of the same app
  preserve it. `secure` is idempotent  -  safe to run after a
  hand-rolled `cf push`.
- Upload helper `scripts/upload.sh` for chunked base64 uploads of
  files over the single-POST size limit.
- `references/extending.md`  -  cookbook for extending the container
  with apt packages, Python packages, and bound services, including
  the TESSDATA_PREFIX gotcha for apt-buildpack installs.
- `references/cf-cheatsheet.md`  -  short `cf` CLI reference for when
  using `cf` directly is cleaner than the dispatcher.
- `assets/settings.json.example`  -  a curated allowlist of the `cf`
  commands the skill uses, grouped by risk. Destructive commands
  deliberately omitted.
- `SECURITY.md`  -  auth/security model writeup.
- Three scenario-style tests under `tests/scenarios/`: sed/awk,
  run-script, and OCR-with-buildpack-extension.
- XDG-style cache dir at `${XDG_CACHE_HOME:-~/.cache}/cf-shell/`.
  Point `XDG_CACHE_HOME` at a project dir to keep the skill's local
  state project-scoped.
