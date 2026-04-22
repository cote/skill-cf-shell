# Scenario 02  -  write a script, land it in the container, run it

You're being handed this task in a fresh Claude Code session.

## Setup (human, before starting)

- `cf target` is already succeeded against a reachable foundation.
- `RUN_LIVE=1` is set.
- The `cf-shell` skill is installed at `~/.claude/skills/cf-shell/`.

## Your task

Write a bash script called `multiplier.sh` that, given an integer N on
argv, prints an N×N multiplication table (space-separated, N rows × N
columns, tab-aligned). Run it in the CF-hosted container for N=12 and
return the output.

## Constraint  -  how you run it

**Do not execute the script locally.** It has to live in the CF
container and run there, via the `cf-shell` skill.

Suggested flow:

1. `scripts/cf-shell.sh preflight`
2. `scripts/cf-shell.sh deploy` (default app name fine  -  base stack is
   enough, no buildpack extension).
3. Write `multiplier.sh` **in one `exec` call**  -  base64 the script
   locally, POST a `cmd=` that writes it to
   `/home/vcap/app/data/multiplier.sh` and `chmod +x` it.
4. In a **separate `exec` call**, invoke
   `/home/vcap/app/data/multiplier.sh 12` and capture the output.
5. `scripts/cf-shell.sh destroy` when done.

Why separate calls: each `exec` is a fresh `bash -lc`, so cwd and env
don't persist, but the container filesystem does (best-effort). The
test is whether you correctly use the fs-persists / env-doesn't model.

## Report format

Markdown with:
- The `multiplier.sh` source you wrote.
- The 12×12 output from the container.
- The sequence of `cf-shell` calls you made, so the reviewer can see
  you used two separate `exec` invocations (write then run) instead of
  collapsing it into one.
