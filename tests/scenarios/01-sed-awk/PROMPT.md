# Scenario 01  -  sed/awk on the CF shell (base stack only)

You're being handed this task in a fresh Claude Code session.

## Setup (human, before starting)

- `cf target` is already succeeded against a reachable foundation.
- `RUN_LIVE=1` is set so you know a real `cf push` is acceptable.
- The `cf-shell` skill is installed at `~/.claude/skills/cf-shell/`.

## Your task

`input/shipments.csv` is a log of hot-dog deliveries to Dutch grocery
chains. First column is the timestamp; the relevant columns for this
task are `store_chain` (col 4) and `cases` (col 7).

Give the human:

1. Total cases delivered per `store_chain`, sorted descending.
2. The single chain with the most cases, called out on its own line.

## Constraint  -  how you run it

**Do not use your local Bash tool to compute this.** Use the `cf-shell`
skill to run the aggregation inside a CF-hosted container:

- `preflight`, `deploy` (default app name is fine), then `exec` for the
  actual work.
- Upload `shipments.csv` into the container (base64 in a single `cmd=`
  POST is fine at this size  -  ~22 KB).
- The aggregation itself should be a single `awk` or `sort | awk`
  pipeline invoked via `exec`.
- `destroy` the app when you're done.

The base `cflinuxfs4` stack already has `bash`, `awk`, `sort`, `base64`
 -  no buildpack extension needed for this one.

## Report format

Markdown, with the totals table and the winning chain. Also note which
`cf-shell` subcommands you ran (preflight/deploy/exec/destroy) so the
reviewer can confirm the skill did the work.
