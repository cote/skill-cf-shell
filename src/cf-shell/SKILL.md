---
name: cf-shell
description: >
  Run bash commands in a Cloud Foundry-hosted shell. Use when asked to
  execute commands on a CF foundation, stand up a throwaway cloud
  shell, or route work through a CF container instead of running it
  locally.
compatibility: Requires bash, cf CLI v8+, curl, jq. Assumes `cf target` already succeeded.
metadata:
  author: cote
  version: "1.0"
---

# cf-shell

Tiny CF app that exposes `bash` over HTTPS via
[shell2http](https://github.com/msoap/shell2http). POST a command,
get stdout+stderr back. Each call is a fresh `bash -lc`.

## Actions

One dispatcher with subcommands. Default app name is `cf-shell`
(override with `$CF_SHELL_APP` or a positional arg).

    scripts/cf-shell.sh preflight
    scripts/cf-shell.sh deploy   [app]
    scripts/cf-shell.sh secure   [app]
    scripts/cf-shell.sh exec     [app] "uname -a"
    scripts/cf-shell.sh exec     [app] -           # read cmd from stdin
    scripts/cf-shell.sh url      [app]
    scripts/cf-shell.sh destroy  [app]

- **preflight** — verifies `cf` / `curl` / `jq`, `cf target`, and
  downloads `shell2http` into a local cache if missing.
- **deploy** — pushes `binary_buildpack` + `shell2http` with a random
  `SH_BASIC_AUTH` (username `admin`), or updates in place if the app
  already exists (preserving the existing credential).
- **secure** — idempotent: sets `SH_BASIC_AUTH` on an existing app if
  it isn't set, restarts to pick it up. Use this when you extended
  the container by running your own `cf push` (rather than via
  `deploy`) — the hand-rolled push leaves `/exec` *unauthenticated*
  until you run `secure`. See `references/extending.md`.
- **exec** — reads `SH_BASIC_AUTH` from `cf env <app>`, POSTs `cmd=...`
  to `/exec`, prints the body, exits with the remote exit code (from
  the `X-Shell2http-Exit-Code` header).
- **url** — prints the `https://...` route.
- **destroy** — `cf delete -f <app>`.

## CF-side start command

    ./shell2http -form -export-all-vars -include-stderr \
                 -no-log-timestamp -timeout=300 -port=$PORT \
                 /exec 'bash -lc "$v_cmd"'

## Extending

Need tools beyond the base stack (apt packages, Python libs)? Edit the
pushed `manifest.yml` to add buildpacks in front of `binary_buildpack`
and drop in the companion files. See `references/extending.md`.

## Limits

- Filesystem state (including `/home/vcap/app/data/`) usually persists
  across calls within the same container but is not reliable —
  containers can be replaced at any time, and any `cf push` / restart
  wipes it. Treat it as scratch, not storage.
- Each call is a fresh `bash -lc`; cwd and exported env do not carry
  across calls.
- 300s per-call timeout.
- Large uploads: base64-chunk through `/home/vcap/app/data/`.

## Security

- User owns `cf login`. Skill never calls `cf login` / `cf auth`.
- Basic auth lives only in `cf env` (`SH_BASIC_AUTH`), no local secrets file.
- The route is public — anyone with URL + password can `bash`.
  `destroy` when done.
- Commands passed to `exec` run in the container, not locally.
- **If you `cf push` the app outside `deploy`** (e.g., extending by
  authoring your own manifest), the new droplet has no
  `SH_BASIC_AUTH` set and `/exec` is **open to the internet**. Run
  `scripts/cf-shell.sh secure <app>` immediately after any such push
  to lock it down.
