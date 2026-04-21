#!/bin/bash
# upload.sh — upload a local file into a cf-shell container via
# chunked base64 over shell2http.
#
# shell2http's /exec endpoint is form-urlencoded, so binary uploads
# have to be base64'd. Files over ~60 KB won't fit in a single POST
# once URL-encoded, so we split and append.
#
# Usage:
#   upload.sh <local-path> [app] [remote-path]
#
# Defaults:
#   app          = $CF_SHELL_APP or "cf-shell"
#   remote-path  = /home/vcap/app/data/in/<basename>
#
# Exit codes: 0 success. Non-zero if chunk append, decode, or
# size verification fails.
set -euo pipefail

SRC="${1:?usage: upload.sh <local-path> [app] [remote-path]}"
APP="${2:-${CF_SHELL_APP:-cf-shell}}"

[[ -r "$SRC" ]] || { echo "upload.sh: $SRC: not readable" >&2; exit 2; }

HERE="$(cd "$(dirname "$0")" && pwd)"
DISPATCH="$HERE/cf-shell.sh"
[[ -x "$DISPATCH" ]] || { echo "upload.sh: dispatcher not found at $DISPATCH" >&2; exit 2; }

NAME="$(basename "$SRC")"
REMOTE_BIN="${3:-/home/vcap/app/data/in/$NAME}"
REMOTE_B64="${REMOTE_BIN}.b64"
REMOTE_DIR="$(dirname "$REMOTE_BIN")"
LOCAL_SIZE="$(wc -c < "$SRC" | tr -d ' ')"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# base64 encode, strip newlines, split into 60 KB chunks.
# 60 KB keeps us well under shell2http + gorouter POST size limits
# once URL-encoded.
base64 -i "$SRC" | tr -d '\n' > "$SCRATCH/b64"
split -b 61440 "$SCRATCH/b64" "$SCRATCH/chunk."

chunks=("$SCRATCH"/chunk.*)
echo "upload.sh: $NAME → $APP:$REMOTE_BIN  ($LOCAL_SIZE bytes, ${#chunks[@]} chunks)"

# Clear the staging file and ensure the remote dir exists.
"$DISPATCH" exec "$APP" "mkdir -p $REMOTE_DIR && : > $REMOTE_B64" >/dev/null

i=0
for chunk in "${chunks[@]}"; do
  i=$((i+1))
  {
    echo "cat >> $REMOTE_B64 <<'CFSH_UPLOAD_EOF'"
    cat "$chunk"
    echo
    echo "CFSH_UPLOAD_EOF"
  } | "$DISPATCH" exec "$APP" - >/dev/null
  printf "  chunk %d/%d (%s bytes)\n" "$i" "${#chunks[@]}" "$(wc -c < "$chunk" | tr -d ' ')"
done

# Decode in-place, clean up staging, verify size.
REMOTE_SIZE="$(
  "$DISPATCH" exec "$APP" "base64 -d < $REMOTE_B64 > $REMOTE_BIN && rm $REMOTE_B64 && wc -c < $REMOTE_BIN" \
  | tr -d '[:space:]'
)"

if [[ "$REMOTE_SIZE" != "$LOCAL_SIZE" ]]; then
  echo "upload.sh: size mismatch — local $LOCAL_SIZE, remote $REMOTE_SIZE" >&2
  exit 3
fi

echo "upload.sh: OK — $REMOTE_BIN ($REMOTE_SIZE bytes)"
