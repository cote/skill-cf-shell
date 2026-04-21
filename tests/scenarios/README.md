# cf-shell test scenarios

Prompt-level scenarios for the `cf-shell` skill. Not unit tests. Each
scenario is a `PROMPT.md` you hand to a fresh Claude Code session. The
reviewer (human) eyeballs the result against `expected-output.md`.

## The three scenarios

| # | Dir | Tests | Buildpack extension? |
|---|-----|-------|----------------------|
| 1 | `01-sed-awk/` | Base-stack command execution via `exec`; CSV upload + awk aggregation | No |
| 2 | `02-run-script/` | Container filesystem persistence; script write → separate `exec` to run | No |
| 3 | `03-ocr-extend/` | Reading `references/extending.md`, editing the pushed manifest, adding apt + python buildpacks, base64 chunked uploads, language-aware OCR | **Yes** |

Tier 1 is "does the skill work at all." Tier 2 is "does the model use
the filesystem-persists / env-doesn't model correctly." Tier 3 is "can
the model drive a non-trivial buildpack extension from the skill's
reference doc."

## Running a scenario

These need a real CF foundation, a successful `cf target`, and (for
scenario 3) a few minutes of push time. They are **live** — don't run
them by accident.

1. Start a fresh Claude Code session.
2. `export RUN_LIVE=1` so the prompt knows pushes are allowed.
3. Paste the scenario's `PROMPT.md` as your first message. Attach the
   `input/` dir path in the prompt if Claude doesn't pick it up
   automatically.
4. Let it run. Watch for the signals in `expected-output.md`.
5. After the session, grade against `expected-output.md` and note
   anything surprising in a run log.

## Grading

Each scenario's `expected-output.md` lists the signals the reviewer
checks. Passes are fuzzy ("did Claude use the skill?", "did it clean
up?") rather than strict diffs, because model behavior varies run to
run. Log the grade somewhere — a line in `~/diane2/logs/diane/system.log`
or a short note in this directory — so regressions across skill
revisions are visible.

## Known costs

- Scenarios 1 and 2: one `cf push` each, quick (binary_buildpack only,
  seconds to a minute).
- Scenario 3: one `cf push` with apt+python+binary buildpacks, a few
  minutes of staging against archive.ubuntu.com and pypi.org. Heavier.
- All three: leave no residue if `destroy` is called at the end.

## Related

- The skill itself: `../../src/cf-shell/SKILL.md`
- Dispatcher: `../../src/cf-shell/scripts/cf-shell.sh`
- Extension reference: `../../src/cf-shell/references/extending.md`
- Origin of the OCR scenario: `~/dev/larry-cf-shell/ocr-shell-platform/`
  (the purpose-built setup the skill was generalized from).
