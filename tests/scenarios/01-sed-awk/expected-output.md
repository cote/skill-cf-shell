# Scenario 01 — expected output

## Totals by chain (descending)

| Chain               | Cases |
|---------------------|------:|
| Lidl                |   243 |
| Jumbo               |   184 |
| Vomar               |   183 |
| Aldi                |   178 |
| Coop                |   154 |
| Plus                |   147 |
| Albert Heijn        |   144 |
| Dirk van den Broek  |   103 |

## Winner

Lidl — 243 cases.

## What the reviewer checks

- Did Claude invoke `cf-shell` subcommands (preflight, deploy, exec) via
  the skill dispatcher rather than running awk locally? Transcript
  should show `scripts/cf-shell.sh exec ...` calls or the equivalent.
- Is the totals table within ±1 of the numbers above? (Small drift ok
  if Claude used a slightly different aggregation, but the ordering and
  winner must match.)
- Did Claude call `destroy` at the end? Or at least leave a note
  explaining why not (e.g., "left running for follow-up"). Leaving the
  app up silently is a fail — the route is public.
- No local `awk`/`sort` invocations on the raw CSV outside of sanity
  checks. The computation must happen in the container.
