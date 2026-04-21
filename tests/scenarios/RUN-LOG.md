# Scenario run log — 2026-04-21

Ran all three prompt-level scenarios live against
`api.sys.tas-ndc.kuhn-labs.com` (space `cote/agent-demo`, user
`agent-cote`). Claude drove each one via the installed `cf-shell`
skill, not the local Bash tool, except where the skill itself had
bugs that needed fixing.

## Scenario 01 — sed/awk (PASS)

- App: `cfsh-01` on `cflinuxfs4` + `binary_buildpack`.
- Upload: one POST, 22 KB CSV → ~30 KB base64. md5 round-tripped.
- Aggregation: single `awk` pipeline via `exec`, matched the expected
  totals exactly. Winner: **Lidl, 243 cases**.
- Destroy: clean.

## Scenario 02 — write+run script (PASS)

- App: `cfsh-02`, same stack.
- Exec #1: base64-staged `multiplier.sh` into
  `/home/vcap/app/data/`, `chmod +x`, verified `ls -l`.
- Exec #2: separate `exec` invocation ran the staged script and
  returned the full 12×12 table. Filesystem-persists /
  env-doesn't-persist model confirmed.
- Fixed a `77`→`84` typo in `expected-output.md` from my earlier
  hand-written reference.
- Destroy: clean.

## Scenario 03 — OCR w/ container extension (PASS)

- App: `cfsh-03`.
- Initial deploy: base stack, `tesseract` missing, `pytesseract`
  import fails — as designed.
- Extension: edited pushed `manifest.yml` under
  `~/.cache/cf-shell/push/cfsh-03/` to layer
  `apt-buildpack` → `python_buildpack` → `binary_buildpack`. Added
  `apt.yml` (tesseract-ocr + eng/spa/cat) and `requirements.txt`
  (pytesseract, Pillow). Re-pushed; `SH_BASIC_AUTH` persisted as
  designed.
- TESSDATA_PREFIX gotcha: `apt-buildpack` installs tesseract data at
  `/home/vcap/deps/0/apt/usr/share/tesseract-ocr/4.00/tessdata` but
  tesseract defaults to `/usr/share/...`. Every `exec` that invokes
  tesseract has to export `TESSDATA_PREFIX` first. Worth adding a
  note to `references/extending.md` under the apt-packages section.
- Upload: six PNGs, largest 430 KB → 573 KB base64. Chunked at 45 000
  char/POST into `/tmp/stage.b64`, then `base64 -d` in a final call
  per file. All six round-tripped byte-exact.
- OCR: `-l eng` for the invoices, `-l spa+cat` for the facturas (they
  mix both languages in header/body). Six totals:

    | File | Lang | Total |
    |------|------|------:|
    | invoice_01.png | eng | $10,974.70 |
    | invoice_02.png | eng | $ 2,898.78 |
    | invoice_03.png | eng | $ 6,238.75 |
    | factura_01.png | spa+cat | €2,868.91 |
    | factura_02.png | spa+cat | €5,830.00 |
    | factura_03.png | spa+cat | €1,594.78 |

- Grand total **€28,796.94** in EUR (€10,293.69 native EUR +
  $20,112.23 USD × 0.92).
- Destroy: clean.

## Bugs found in the skill

### 1. `deploy` exited 141 (SIGPIPE) — fixed

Two separate SIGPIPE sources under `set -euo pipefail`:

- `random_password()` was `tr -dc ... </dev/urandom | head -c 24`.
  `head` closes stdin after 24 bytes → `tr` gets SIGPIPE → `pipefail`
  propagates 141 to the caller → script dies before `cf set-env` ever
  runs. This is why the first cfsh-01 deploy silently failed to set
  auth.
- `app_basic_auth()` was `cf env | awk '... exit'`. `awk exit` on
  match would SIGPIPE `cf env`. Benign when no match (awk reads to
  EOF), latent when reusing an app with an existing token.

Fix: `random_password` wraps the pipeline in `( ... ) || true` so
SIGPIPE is absorbed at the subshell boundary. `app_basic_auth` now
reads `cf env` fully into a variable first, then pipes the string to
awk.

### 2. Cache path was opinionated

Was `$HOME/apps/cf-shell/cache` (companion-app-dir convention). For a
general-purpose skill, pinning a non-standard path is wrong. Now:

    CACHE_DIR="${CF_SHELL_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/cf-shell}"

— standard XDG fallback with an env-var override, which is what an
unconfigured Claude would naturally pick.

## Auth observations

The skill's current model:

1. `deploy` generates `SH_BASIC_AUTH=admin:<24 random alnums>`, calls
   `cf set-env`, then `cf restart` so shell2http picks it up.
2. The credential never lives on the local disk. `cf env <app>` is the
   only store. `exec` reads it back on every call.
3. `cf push` preserves `SH_BASIC_AUTH` — only the initial deploy
   generates one. Re-pushes (like the OCR extension push) do not
   rotate.
4. The basic-auth is applied by shell2http itself; there is no
   platform-level auth in front of the route. The app's route
   (`<app>.apps.<domain>`) is publicly reachable — anyone with URL +
   credential can `bash`. This is the "destroy when done" invariant
   in `SKILL.md` and is genuine.
5. `cf login` / OAuth / whatever the platform uses is fully outside
   the skill's concern. We lean on `cf target` having already
   succeeded and fail fast if it hasn't (`preflight` + `deploy`
   both check).

### What this means for binding a service

Adding a service binding (e.g. a marketplace Postgres) is a
manifest-layer change, not an auth-layer change. It slots into the
same `extending.md` flow:

```yaml
applications:
  - name: cf-shell
    services:
      - my-pg-instance
```

Then `cf push`. Credentials arrive in `VCAP_SERVICES` as JSON.
`shell2http` is started with `-export-all-vars`, so every `exec` gets
`VCAP_SERVICES` in its env and can `jq` it:

```bash
exec ... 'jq -r ".\"postgres\"[0].credentials.uri" <<<"$VCAP_SERVICES"'
```

The interesting security question for the service-binding phase is
whether we want the DB credentials visible to every `exec` call (they
are, by default via `-export-all-vars`) or scoped down. For a
throwaway shell that's fine. For anything persistent it is not — but
that's a separate conversation.

## Remaining TODOs

- Add the `TESSDATA_PREFIX` note to `references/extending.md` under
  apt packages (paper cut, hit me and will hit a fresh Claude too).
- Commit the bug fixes + run log + scenarios.
- Add a `bind-service` scenario once we start that work — likely
  scenario `04-pg-binding/` with a marketplace Postgres, a `psql`
  query, teardown.
