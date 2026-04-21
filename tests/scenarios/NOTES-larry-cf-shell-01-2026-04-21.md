# Notes from `larry-cf-shell-01` session — 2026-04-21

Source material:
- Transcript: `~/.claude/projects/-Users-cote-dev-larry-cf-shell-01/1cf9a35e-c372-4466-b4da-fd46c5501683.jsonl` (436 turns)
- Other Claude's writeup: `~/dev/larry-cf-shell-01/REPORT.md`
- Artifacts: `~/dev/larry-cf-shell-01/{manifest,scripts,ocr-text}/`, `ocr-package.zip`, `ocr.csv`

## What the other session did

Twelve user turns over ~2 hours. Two phases:

- **Cleanup + deploy.** Listed apps in `dev-advocates/cote`, deleted 6
  old demo apps after explicit confirmation (`EasyChatDM`,
  `pooch-assistant`, `pooch-auth`, `pooch-scheduler`, `solo-mcp-tools`,
  `thinktool`). Hand-rolled `manifest.yml` (apt + binary buildpacks)
  and `apt.yml` (tesseract-ocr + eng + spa) in the working dir.
  `cf push` directly — did **not** go through `cf-shell.sh deploy`.

- **OCR + package.** Upload six PNGs (~140–430 KB each), OCR in
  parallel with per-language `-l` flags, land results locally, build
  CSV, zip everything.

## Two gotchas, both caught

**1. `SH_BASIC_AUTH` unset after hand-rolled push.** Immediately
after `cf push`, Claude ran `cf env cfsh-demo | grep SH_BASIC_AUTH`,
saw nothing, told Coté plainly that `/exec` was currently open to
the internet, asked before proceeding. Coté approved, Claude
generated+set the cred, restarted. This is exactly the gap we
fixed afterwards with the `secure` subcommand (commit `0ceedbf`).

**2. `TESSDATA_PREFIX` per call.** First `tesseract` call came back
with "couldn't load any languages". Claude knew from `extending.md`
that apt-buildpack installs to `/home/vcap/deps/0/apt/usr/...`,
found the exact path, exported `TESSDATA_PREFIX` before every
tesseract invocation. No surprise — just honouring the doc.

## What the other Claude invented worth promoting

**Chunked base64 uploader** (`scripts/cfsh-upload.sh`, 37 lines):
64 KB chunks, heredoc-over-stdin to avoid argv length limits, five
parallel uploads. This capability is absent from the skill today —
Coté's session had to reinvent it. Should ship as
`scripts/upload.sh` in the skill.

## Permissions friction (biggest usability win)

Coté's final turn of the session asked about permission-prompt
optimisation. Root cause: artefacts scattered across
- cwd (`/Users/cote/dev/larry-cf-shell/pets/ocr/`)
- `~/.cache/cf-shell/push/cfsh-demo/` (skill's push staging)
- `~/.cache/cf-shell/bin/` (shell2http cache)
- the target dir `/Users/cote/dev/larry-cf-shell-01/`

Each fresh directory path triggered fresh permission prompts.
One-project-dir-for-everything would collapse this to one allow
rule.

`$CF_SHELL_CACHE` already exists — set it to `$PWD/.cf-shell` and
the skill's cache follows the project.

## Changes we agreed to implement

Three, smallest-high-impact set:

1. **`assets/settings.json.template`** — pre-baked allowlist for the
   `cf` commands this skill uses, grouped by risk level. User can
   paste into project `.claude/settings.json` or global
   `~/.claude/settings.json`. Destructive commands (`cf delete*`,
   `cf auth`, `cf login`) deliberately left prompting.

2. **`scripts/upload.sh`** — the chunked base64 uploader from the
   other session, generalised: `upload.sh <local-path> [app]
   [remote-path]`. Heredoc-over-stdin, 64 KB chunks, server-side
   decode, byte-count verification.

3. **`references/cf-cheatsheet.md` + SKILL.md note** — reframe the
   skill as "the dispatcher is a convenience, not a gate." Ship a
   one-page cf CLI reference so Claude knows it can skip the wrapper
   when it makes sense (e.g., extending manifests, binding services,
   `cf curl /v3/…` for audit events).

## Deferred to later but noted

From Coté's session notes:

- **Ship `manifest.yml` templates in `assets/`** — base, apt, python,
  apt+python, with-service. `extending.md` then points at them
  instead of inlining YAML. Good next step once #1–#3 land.
- **Audit-events watcher script** — `scripts/watch-events.sh`,
  wraps the `cf curl /v3/audit_events` polling one-liner. Space-wide
  if no app arg, app-scoped with one.
- **CF tasks vs shell2http** — write it up in a `design-choices.md`
  reference. Short answer: shell2http is ~two orders of magnitude
  faster per call because the container stays resident; tasks spin
  a fresh container per invocation.
- **Scenario 4 (service binding)** — bind an existing service (e.g.
  `pooch-genai-chat` or `pooch-db`) via `cf bind-service <app>
  <svc>`, read creds from `VCAP_SERVICES` in an `exec`. Most
  compelling demo of the skill's actual value prop.
- **Monitor the app in Tanzu Hub** — TAS/Hub-specific; worth noting
  but not skill-bound.
- **CredHub integration** — instead of env-var for `SH_BASIC_AUTH`,
  write to a CredHub-backed service binding. Only on foundations
  that expose CredHub as a broker.

## Coté's durable principles for the skill

Extracted from the session + notes, what the skill should stay
true to:

- **Slim and simple.** Wrapper is optional. Cheat sheet first-class.
- **One project dir.** No mandatory scatter into `~/.cache` / global
  state. `$CF_SHELL_CACHE` already honours this — document it as
  the preferred pattern for demos.
- **Explicit, not blanket, permissions.** Ship a granular allowlist
  template; never advise `Bash(*)` or equivalent.
- **Shareable publicly.** No Tanzu or org-specific assumptions in
  shipped files.

## Next session plan (redeploy after implementing #1–#3)

1. Blank slate project dir (e.g. `~/dev/larry-cf-shell-02/`).
2. `export CF_SHELL_CACHE=$PWD/.cf-shell` before launching `claude`.
3. Copy `assets/settings.json.template` into `.claude/settings.json`
   in the project dir to pre-allow the common `cf` calls.
4. Run the OCR demo again. Count permission prompts — goal is
   zero or near-zero for the expected happy path.
5. Note any new friction for round 3.
