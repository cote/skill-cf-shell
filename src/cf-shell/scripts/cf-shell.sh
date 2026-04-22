#!/bin/bash
# cf-shell.sh  -  dispatcher for the cf-shell skill.
# Subcommands: preflight | deploy | exec | url | destroy
set -euo pipefail

SHELL2HTTP_VERSION="1.17.0"
SHELL2HTTP_URL="https://github.com/msoap/shell2http/releases/download/v${SHELL2HTTP_VERSION}/shell2http_${SHELL2HTTP_VERSION}_linux_amd64.tar.gz"

CACHE_DIR="${CF_SHELL_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/cf-shell}"
BIN_DIR="$CACHE_DIR/bin"
PUSH_ROOT="$CACHE_DIR/push"
SHELL2HTTP_BIN="$BIN_DIR/shell2http"

# Resolve the skill's assets dir relative to this script's location.
# Layout:  <skill>/scripts/cf-shell.sh  +  <skill>/assets/manifest.yml.template
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$(dirname "$SCRIPT_DIR")/assets"

default_app() { echo "${CF_SHELL_APP:-cf-shell}"; }

die() { echo "cf-shell: $*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

ensure_shell2http() {
  if [[ -x "$SHELL2HTTP_BIN" ]]; then
    return 0
  fi
  mkdir -p "$BIN_DIR"
  echo "cf-shell: downloading shell2http v${SHELL2HTTP_VERSION}..." >&2
  curl -fsSL "$SHELL2HTTP_URL" | tar -xz -C "$BIN_DIR" shell2http
  chmod u+x "$SHELL2HTTP_BIN"
}

cmd_preflight() {
  for tool in cf curl jq; do
    have "$tool" || die "$tool not on PATH"
  done
  cf target >/dev/null 2>&1 || die "'cf target' failed  -  run cf login first"
  echo "cf target:"
  cf target
  ensure_shell2http
  echo "shell2http: $SHELL2HTTP_BIN"
}

app_route() {
  local app="$1"
  cf curl "/v3/apps/$(cf app "$app" --guid)/routes" 2>/dev/null \
    | jq -r '.resources[0].url // empty'
}

app_basic_auth() {
  local app="$1"
  # Read cf env fully first, then parse. A piped `awk '... exit'` would
  # SIGPIPE cf env on match, which pipefail propagates as 141.
  local env_out
  env_out="$(cf env "$app" 2>/dev/null)" || return 0
  printf %s "$env_out" \
    | awk '/^SH_BASIC_AUTH:/{sub(/^SH_BASIC_AUTH:[[:space:]]*/,""); print; exit}'
}

random_password() {
  # tr reads /dev/urandom forever; head closes stdin after 24 bytes and
  # tr gets SIGPIPE. Without a subshell, pipefail would propagate 141
  # to the caller, killing the script under `set -e`.
  ( LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 ) || true
}

ensure_auth() {
  # Set SH_BASIC_AUTH on $app if not already set; restart if we set it.
  # Idempotent. Works whether the app came from `deploy` or a hand `cf push`.
  local app="$1"
  local existing
  existing="$(app_basic_auth "$app" || true)"
  if [[ -n "$existing" ]]; then
    echo "cf-shell: SH_BASIC_AUTH already set ($(echo "$existing" | cut -d: -f1):***)"
    return 0
  fi
  local pw cred
  pw="$(random_password)"
  cred="admin:$pw"
  cf set-env "$app" SH_BASIC_AUTH "$cred" >/dev/null
  cf restart "$app" >/dev/null
  echo "cf-shell: SH_BASIC_AUTH set to admin:$pw"
}

cmd_secure() {
  # Lock down an existing app's /exec with basic auth. Useful when you
  # extended the container by re-`cf push`ing your own manifest instead
  # of going through `deploy`  -  the re-push leaves the endpoint open
  # until this is run.
  local app="${1:-$(default_app)}"
  cf target >/dev/null 2>&1 || die "'cf target' failed  -  run cf login first"
  cf app "$app" >/dev/null 2>&1 || die "app $app not found"
  ensure_auth "$app"
}

cmd_deploy() {
  local app="${1:-$(default_app)}"
  cf target >/dev/null 2>&1 || die "'cf target' failed  -  run cf login first"
  ensure_shell2http

  local push_dir="$PUSH_ROOT/$app"
  rm -rf "$push_dir"
  mkdir -p "$push_dir"
  cp "$SHELL2HTTP_BIN" "$push_dir/shell2http"
  chmod u+x "$push_dir/shell2http"

  local tmpl="$ASSETS_DIR/manifest.yml.template"
  [[ -r "$tmpl" ]] || die "manifest template not found at $tmpl"
  sed "s/{{APP}}/$app/g" "$tmpl" > "$push_dir/manifest.yml"

  echo "cf-shell: pushing $app from $push_dir"
  ( cd "$push_dir" && cf push -f manifest.yml -p . )

  ensure_auth "$app"

  local route
  route="$(app_route "$app")"
  [[ -n "$route" ]] || die "deployed but could not read route for $app"
  echo "cf-shell: ready at https://$route/exec"
  echo "cf-shell: try: scripts/cf-shell.sh exec $app 'uname -a'"
}

cmd_exec() {
  local app="${1:-$(default_app)}"
  local cmd="${2:-}"
  [[ -n "$cmd" ]] || die "usage: cf-shell.sh exec [app] <cmd|->"

  if [[ "$cmd" = "-" ]]; then
    cmd="$(cat)"
  fi

  local route cred
  route="$(app_route "$app")" || die "no route for $app"
  [[ -n "$route" ]] || die "no route for $app"
  cred="$(app_basic_auth "$app")" || die "no SH_BASIC_AUTH on $app"
  [[ -n "$cred" ]] || die "no SH_BASIC_AUTH on $app"

  local headers_file
  headers_file="$(mktemp -t cf-shell-hdr.XXXXXX)"
  trap 'rm -f "$headers_file"' EXIT

  curl -sS -u "$cred" \
    -D "$headers_file" \
    --data-urlencode "cmd=$cmd" \
    "https://$route/exec"

  local rc
  rc="$(awk 'BEGIN{IGNORECASE=1} /^X-Shell2http-Exit-Code:/ {gsub(/\r/,""); print $2; exit}' "$headers_file")"
  [[ -n "$rc" ]] || rc=0
  exit "$rc"
}

cmd_url() {
  local app="${1:-$(default_app)}"
  local route
  route="$(app_route "$app")" || die "no route for $app"
  [[ -n "$route" ]] || die "no route for $app"
  echo "https://$route/exec"
}

cmd_destroy() {
  local app="${1:-$(default_app)}"
  cf delete -f "$app"
}

usage() {
  cat >&2 <<EOF
usage: cf-shell.sh <preflight|deploy|secure|exec|url|destroy> [app] [args...]

  preflight                 check cf/curl/jq, cf target, cache shell2http
  deploy   [app]            push (or update) the shell app and set auth
  secure   [app]            set SH_BASIC_AUTH on an existing app (idempotent).
                            Use after a hand-rolled cf push that bypassed deploy.
  exec     [app] <cmd|->    run a command in the shell
  url      [app]            print the shell URL
  destroy  [app]            cf delete -f

Default app name: cf-shell (override with \$CF_SHELL_APP).
EOF
  exit 2
}

main() {
  local sub="${1:-}"
  [[ -n "$sub" ]] || usage
  shift
  case "$sub" in
    preflight) cmd_preflight "$@" ;;
    deploy)    cmd_deploy    "$@" ;;
    secure)    cmd_secure    "$@" ;;
    exec)      cmd_exec      "$@" ;;
    url)       cmd_url       "$@" ;;
    destroy)   cmd_destroy   "$@" ;;
    -h|--help) usage ;;
    *)         echo "unknown subcommand: $sub" >&2; usage ;;
  esac
}

main "$@"
