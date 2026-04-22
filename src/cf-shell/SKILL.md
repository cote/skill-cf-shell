---
name: cf-shell
description: Run bash commands in a Cloud Foundry (CF) hosted shell. Use when asked to execute commands on a CF install, platform, etc. stand up a throwaway cloud shell, or route work through a CF container instead of running it locally. Tanzu Platform is a common Cloud Foundry based platform
compatibility: Requires bash, cf CLI v8+, curl, jq. Assumes `cf target` already succeeded.
metadata:
  author: cote, Claude
  version: "1.0"
---

# cf-shell

Tiny CF app that exposes `bash` over HTTPS via
[shell2http](https://github.com/msoap/shell2http). POST a command,
get stdout+stderr back. Each call is a fresh `bash -lc`.

**The dispatcher script is a convenience, not a gate.** `scripts/cf-shell.sh`
wraps the common deploy+auth+exec loop, but you can do everything
with `cf` directly and you'll usually want to when extending
manifests or binding services. See `references/cf-cheatsheet.md`
for the subset of `cf` that's useful here.

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

Plus a helper:

    scripts/upload.sh <local-path> [app] [remote-path]

- **preflight**  -  verifies `cf` / `curl` / `jq`, `cf target`, and
  downloads `shell2http` into a local cache if missing.
- **deploy**  -  pushes `binary_buildpack` + `shell2http` with a random
  `SH_BASIC_AUTH` (username `admin`), or updates in place if the app
  already exists (preserving the existing credential).
- **secure**  -  idempotent: sets `SH_BASIC_AUTH` on an existing app if
  it isn't set, restarts to pick it up. Use this when you extended
  the container by running your own `cf push` (rather than via
  `deploy`)  -  the hand-rolled push leaves `/exec` *unauthenticated*
  until you run `secure`. See `references/extending.md`.
- **exec**  -  reads `SH_BASIC_AUTH` from `cf env <app>`, POSTs `cmd=...`
  to `/exec`, prints the body, exits with the remote exit code (from
  the `X-Shell2http-Exit-Code` header).
- **url**  -  prints the `https://...` route.
- **destroy**  -  `cf delete -f <app>`.
- **upload** (helper)  -  chunked-base64 upload of a local file into
  `/home/vcap/app/data/in/<basename>` (or a custom remote path).
  Use this for anything over ~50 KB, where a single form-POST
  won't fit.

## CF-side start command

    ./shell2http -form -export-all-vars -include-stderr \
                 -no-log-timestamp -timeout=300 -port=$PORT \
                 /exec 'bash -lc "$v_cmd"'

## Uploading files

See scripts/upload.sh for one way to upload files to the remote shell.

## Extending

Need tools beyond the base stack (apt packages, Python libs)? Edit the
pushed `manifest.yml` to add buildpacks in front of `binary_buildpack`
and drop in the companion files. See `references/extending.md`.

## Reducing permission prompts

Most of the permission prompts this skill triggers are for read-only
`cf` calls (`cf apps`, `cf env`, `cf logs`, `cf curl /v3/...`) or
safe deploy/run calls (`cf push`, `cf set-env`, `cf restart`).

`assets/settings.json.example` is a pure-JSON copy-paste allowlist
for those. Drop it into `.claude/settings.json`,
`.claude/settings.local.json`, wherever you put that file.
 
 Destructive calls (`cf delete*`,
`cf auth`) are intentionally NOT allowlisted  -  they always prompt.
See `README.md` for setup examples.

## Additional directory: cache

By default, caching is done [XDG style](https://specifications.freedesktop.org/basedir/latest/)
using `~/.cache/cf-shell/`. You can change the defaul location by by setting
`$XDG_CACHE_HOME`. Note that the `settings.json.template` uses the default path, so if you change the cache path, update your `settings.json` accordingly if you don't like pressing `Enter` all the damn time.

## Limits

- Filesystem state (including `/home/vcap/app/data/`) usually persists
  across calls within the same container but is not reliable  - 
  containers can be replaced at any time, and any `cf push` / restart
  wipes it. Treat it as scratch, not storage.
- Each call is a fresh `bash -lc`; cwd and exported env do not carry
  across calls.
- 300s per-call timeout.
- Large uploads: base64-chunk through `/home/vcap/app/data/`.

## Security

- User owns `cf login`. Skill never calls `cf login` / `cf auth`.
- Basic auth lives only in `cf env` (`SH_BASIC_AUTH`), no local secrets file.
- The route is public  -  anyone with URL + password can `bash`.
  `destroy` when done.
- Commands passed to `exec` run in the container, not locally.
- **If you `cf push` the app outside `deploy`** (e.g., extending by
  authoring your own manifest), the new droplet has no
  `SH_BASIC_AUTH` set and `/exec` is **open to the internet**. Run
  `scripts/cf-shell.sh secure <app>` immediately after any such push
  to lock it down.
