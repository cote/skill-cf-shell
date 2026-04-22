#!/bin/bash
# cleanup.sh  -  remove any cf-shell scenario leftovers.
#
# Scoped strictly to names matching 'cfsh-*' in the current cf target.
# Never touches apps outside that pattern. Safe to run repeatedly.
#
# Usage:
#   ./cleanup.sh           # interactive confirmation
#   ./cleanup.sh --yes     # no prompt
#   KEEP_LOCAL=1 ./cleanup.sh  # keep local push dirs under ~/.cache/cf-shell
set -uo pipefail

AUTO=0
[[ "${1:-}" = "--yes" ]] && AUTO=1

cf target >/dev/null 2>&1 || {
  echo "cf target not set  -  run 'cf login' first" >&2
  exit 1
}

mapfile -t APPS < <(cf apps 2>/dev/null | awk 'NR>3 && $1 ~ /^cfsh-/ {print $1}')
mapfile -t SVCS < <(cf services 2>/dev/null | awk 'NR>3 && $1 ~ /^cfsh-/ {print $1}')

PUSH_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/cf-shell/push"
LOCAL_DIRS=()
if [[ -d "$PUSH_ROOT" ]]; then
  for d in "$PUSH_ROOT"/cfsh-*; do
    [[ -d "$d" ]] && LOCAL_DIRS+=("$d")
  done
fi

if [[ ${#APPS[@]} -eq 0 && ${#SVCS[@]} -eq 0 && ${#LOCAL_DIRS[@]} -eq 0 ]]; then
  echo "nothing to clean up (no cfsh-* apps, services, or local push dirs)"
  exit 0
fi

echo "cf target:"
cf target | sed 's/^/  /'
echo
echo "Will delete:"
for a in "${APPS[@]}"; do echo "  app      : $a"; done
for s in "${SVCS[@]}"; do echo "  service  : $s"; done
if [[ "${KEEP_LOCAL:-0}" = "0" ]]; then
  for d in "${LOCAL_DIRS[@]}"; do echo "  local    : $d"; done
else
  for d in "${LOCAL_DIRS[@]}"; do echo "  local    : $d  (kept, KEEP_LOCAL=1)"; done
fi

if [[ $AUTO -eq 0 ]]; then
  read -r -p $'\nProceed? [y/N] ' ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "aborted"; exit 0; }
fi

rc=0
for a in "${APPS[@]}"; do
  echo "cf delete -f $a"
  cf delete -f "$a" || rc=1
done
for s in "${SVCS[@]}"; do
  echo "cf delete-service -f $s"
  cf delete-service -f "$s" || rc=1
done
if [[ "${KEEP_LOCAL:-0}" = "0" ]]; then
  for d in "${LOCAL_DIRS[@]}"; do
    echo "rm -rf $d"
    rm -rf "$d" || rc=1
  done
fi

echo
echo "done (exit $rc)"
exit $rc
