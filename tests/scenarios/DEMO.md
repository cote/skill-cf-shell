# cf-shell demo runbook

A step-by-step script you drive by hand. No Claude required; every
step is a shell command you paste. Designed to be watched — each
tier has milestones with observation suggestions between them.

## Before anything

```bash
cf target
```

Must show a logged-in API endpoint, org, space. If not, `cf login`
and come back.

Alias the dispatcher so the commands below stay readable:

```bash
CFS=~/.claude/skills/cf-shell/scripts/cf-shell.sh
```

(Re-export `CFS` in every new shell you use during the demo.)

## Suggested terminal layout

Three panes (or tabs) alongside the one you're running commands in:

- **Left**: `watch -n 2 cf apps` — see apps appear and disappear.
- **Middle**: idle, used on demand for `cf env <app>` /
  `cf logs <app> --recent`.
- **Right**: idle, used during Tier 3 for
  `cf logs cfsh-demo-03` (no `--recent` = live tail) to watch
  staging output.

## Preflight

Check the space is clean of leftover scenario apps:

```bash
cf apps | grep '^cfsh-' || echo "no cfsh-* apps — clean"
```

If anything shows up, wipe it before starting:

```bash
bash ~/dev/skill-cf-shell/tests/scenarios/cleanup.sh --yes
```

Pick a tier. Three independent tracks — do one, all, or skip around.

---

# Tier 1 — sed/awk on a CSV

~60 seconds. Binary buildpack only, no extension. The cheapest way
to see the whole deploy → auth → exec → destroy loop.

App name throughout: `cfsh-demo-01`.

## M1. Deploy

```bash
bash $CFS deploy cfsh-demo-01
```

**What to look for:**
- Final lines:
  - `cf-shell: SH_BASIC_AUTH set to admin:xxxxxxxxxxxxxxxxxxxxxxxx`
  - `cf-shell: ready at https://cfsh-demo-01.apps.<domain>/exec`
- In the **watch pane**, `cfsh-demo-01` appears in `cf apps`.

**Optional observation:**

```bash
cf env cfsh-demo-01 | grep -A1 User-Provided
```

That's where the credential lives. Nowhere local.

## M2. Smoke test — prove the shell works

```bash
bash $CFS exec cfsh-demo-01 'uname -a; whoami; hostname; echo pwd=$(pwd)'
```

**What to look for:**
- `Linux ... x86_64 GNU/Linux`
- `uid=2000(vcap)` — we run as `vcap`, not root.
- `hostname` is a container UUID; `pwd` is `/home/vcap/app`.

## M3. Upload the CSV

22 KB raw → ~30 KB base64, fits in one form-POST.

```bash
B64=$(base64 < ~/dev/skill-cf-shell/tests/scenarios/01-sed-awk/input/shipments.csv | tr -d '\n')
bash $CFS exec cfsh-demo-01 "mkdir -p /home/vcap/app/data && printf %s '$B64' | base64 -d > /home/vcap/app/data/shipments.csv && wc -l /home/vcap/app/data/shipments.csv && md5sum /home/vcap/app/data/shipments.csv"
```

**What to look for:**
- `201 /home/vcap/app/data/shipments.csv`
- An md5 hash. Compare against local:
  ```bash
  md5 -q ~/dev/skill-cf-shell/tests/scenarios/01-sed-awk/input/shipments.csv
  ```
  Should match exactly.

## M4. Aggregate inside the container

The awk runs over there, not on your laptop.

```bash
bash $CFS exec cfsh-demo-01 - <<'REMOTE'
awk -F, 'NR>1 {sum[$4] += $7} END {for (k in sum) printf "%-25s %d\n", k, sum[k]}' /home/vcap/app/data/shipments.csv | sort -k2 -rn
REMOTE
```

**What to look for:**

```
Lidl                      243
Jumbo                     184
Vomar                     183
Aldi                      178
Coop                      154
Plus                      147
Albert Heijn              144
Dirk van den Broek        103
```

Lidl wins with 243 cases.

## M5. Cleanup

```bash
bash ~/dev/skill-cf-shell/tests/scenarios/cleanup.sh --yes
```

**What to look for:**
- `cf delete -f cfsh-demo-01` → `OK`
- Local push dir removed.
- `cf apps` (watch pane) drops back to the pre-demo state.

---

# Tier 2 — write a script, run it

~60 seconds. Binary only. Demonstrates "container filesystem persists
across exec calls, env does not."

App name: `cfsh-demo-02`.

## M1. Deploy

```bash
bash $CFS deploy cfsh-demo-02
```

Same signals as Tier 1 M1.

## M2. Write `multiplier.sh` locally, then stage it in the container

Create the script on your laptop first:

```bash
cat > /tmp/multiplier.sh <<'SCRIPT'
#!/bin/bash
set -eu
N="${1:-10}"
for i in $(seq 1 "$N"); do
  row=""
  for j in $(seq 1 "$N"); do row+=$(printf "%4d" $((i*j))); done
  echo "$row"
done
SCRIPT
```

Then stage it into the container — **one exec call**:

```bash
B64=$(base64 < /tmp/multiplier.sh | tr -d '\n')
bash $CFS exec cfsh-demo-02 "mkdir -p /home/vcap/app/data && printf %s '$B64' | base64 -d > /home/vcap/app/data/multiplier.sh && chmod +x /home/vcap/app/data/multiplier.sh && ls -l /home/vcap/app/data/multiplier.sh"
```

**What to look for:**
- `-rwxr-xr-x 1 vcap vcap 222 ... /home/vcap/app/data/multiplier.sh`

## M3. Prove env doesn't persist, fs does

**Separate exec.** The script from M2 should still be there, but
anything we "exported" in M2 is gone.

```bash
bash $CFS exec cfsh-demo-02 - <<'REMOTE'
echo "=== files in /home/vcap/app/data: ==="
ls /home/vcap/app/data
echo
echo "=== env check ==="
echo "SOMETHING=[$SOMETHING]"
echo "pwd=$(pwd)"
REMOTE
```

**What to look for:**
- `multiplier.sh` listed (fs persisted).
- `SOMETHING=[]` (env didn't persist — no error because of lazy
  expansion, just empty).
- `pwd=/home/vcap/app` (cwd is fresh, same starting point as any new
  `bash -lc`).

## M4. Run the staged script

```bash
bash $CFS exec cfsh-demo-02 '/home/vcap/app/data/multiplier.sh 12'
```

**What to look for:**

12 rows × 12 columns. Bottom-right cell:

```
  12  24  36  48  60  72  84  96 108 120 132 144
```

## M5. Cleanup

```bash
bash ~/dev/skill-cf-shell/tests/scenarios/cleanup.sh --yes
```

---

# Tier 3 — extend the container with apt + python, then OCR

3–5 minutes. Real `cf push` with extra buildpacks. Worth watching
`cf logs cfsh-demo-03` live during M4.

App name: `cfsh-demo-03`.

## M1. Deploy the base stack first

```bash
bash $CFS deploy cfsh-demo-03
```

Why deploy bare first: to see the "missing tool" state before we
extend. Also so we can show `SH_BASIC_AUTH` persists across the
re-push in M4.

## M2. Prove the base stack has no OCR tooling

```bash
bash $CFS exec cfsh-demo-03 "which tesseract || echo TESSERACT_MISSING; python3 -c 'import pytesseract' 2>&1 | tail -1"
```

**What to look for:**
- `TESSERACT_MISSING`
- `ModuleNotFoundError: No module named 'pytesseract'`

(python3 itself IS in the base stack — only the module is missing.)

## M3. Write the extension files into the push dir

The `cf-shell deploy` step in M1 created a push dir at
`~/.cache/cf-shell/push/cfsh-demo-03/` with a `manifest.yml` and the
`shell2http` binary. We edit those in place.

**Replace `manifest.yml`:**

```bash
cat > ~/.cache/cf-shell/push/cfsh-demo-03/manifest.yml <<'YAML'
---
applications:
  - name: cfsh-demo-03
    memory: 512M
    disk_quota: 1G
    instances: 1
    buildpacks:
      - https://github.com/cloudfoundry/apt-buildpack
      - python_buildpack
      - binary_buildpack
    command: ./shell2http -form -export-all-vars -include-stderr -no-log-timestamp -timeout=300 -port=$PORT /exec 'bash -lc "$v_cmd"'
    health-check-type: port
YAML
```

Buildpack order matters: `binary_buildpack` must stay **last** — it
supplies `shell2http`.

**Add `apt.yml`:**

```bash
cat > ~/.cache/cf-shell/push/cfsh-demo-03/apt.yml <<'YAML'
---
packages:
  - tesseract-ocr
  - tesseract-ocr-eng
  - tesseract-ocr-spa
  - tesseract-ocr-cat
YAML
```

**Add `requirements.txt`:**

```bash
cat > ~/.cache/cf-shell/push/cfsh-demo-03/requirements.txt <<'TXT'
pytesseract==0.3.13
Pillow==11.0.0
TXT
```

**Eyeball it:**

```bash
ls -la ~/.cache/cf-shell/push/cfsh-demo-03/
```

You should see: `apt.yml`, `manifest.yml`, `requirements.txt`,
`shell2http` (the Go binary, ~5.5 MB).

## M4. Re-push

**Before starting**, in the right-hand pane:

```bash
cf logs cfsh-demo-03   # no --recent — live tail
```

Then in the main pane:

```bash
( cd ~/.cache/cf-shell/push/cfsh-demo-03 && cf push -f manifest.yml -p . )
```

**What to watch in the log pane:**
- `apt-get install ... tesseract-ocr ...`
- `pip install ... pytesseract ...`
- Eventually `-----> Uploading droplet...`

When the main pane returns, you should see three buildpacks listed:

```
buildpacks:
  https://github.com/cloudfoundry/apt-buildpack   0.3.15
  python_buildpack                                1.8.81
  binary_buildpack                                1.1.59    binary
```

**Confirm `SH_BASIC_AUTH` survived:**

```bash
cf env cfsh-demo-03 | grep SH_BASIC_AUTH
```

Same credential as M1. Re-pushes don't rotate.

## M5. Verify the stack

`apt-buildpack` installs under `/home/vcap/deps/0/apt/usr/...` rather
than `/usr/...`, so `tesseract` can't find its data files without
`TESSDATA_PREFIX` set. Each `exec` is a fresh `bash -lc` so the
prefix has to be exported every time.

```bash
bash $CFS exec cfsh-demo-03 - <<'REMOTE'
export TESSDATA_PREFIX=/home/vcap/deps/0/apt/usr/share/tesseract-ocr/4.00/tessdata
which tesseract && tesseract --version 2>&1 | head -1
echo
echo "=== available langs ==="
tesseract --list-langs
echo
echo "=== python pkgs ==="
python3 -c 'import pytesseract, PIL; print("pytesseract", pytesseract.__version__, "PIL", PIL.__version__)'
REMOTE
```

**What to look for:**
- `/home/vcap/deps/0/bin/tesseract`
- `tesseract 4.1.1`
- Four languages: `cat eng osd spa`
- `pytesseract 0.3.13 PIL 11.0.0`

## M6. Upload one invoice (single-POST)

The fixture has 6 PNGs, up to 430 KB each. For the demo we do the
smallest one (`invoice_01.png`, 140 KB → ~188 KB base64) in a single
POST. The full flow with chunked uploads is in
`03-ocr-extend/PROMPT.md`.

```bash
B64=$(base64 < ~/dev/skill-cf-shell/tests/scenarios/03-ocr-extend/input/invoice_01.png | tr -d '\n')
bash $CFS exec cfsh-demo-03 "mkdir -p /home/vcap/app/data/invoices && printf %s '$B64' | base64 -d > /home/vcap/app/data/invoices/invoice_01.png && wc -c /home/vcap/app/data/invoices/invoice_01.png"
```

**What to look for:** `140597 /home/vcap/app/data/invoices/invoice_01.png` — exact byte match.

## M7. OCR it

```bash
bash $CFS exec cfsh-demo-03 - <<'REMOTE'
export TESSDATA_PREFIX=/home/vcap/deps/0/apt/usr/share/tesseract-ocr/4.00/tessdata
cd /home/vcap/app/data/invoices
tesseract invoice_01.png - -l eng 2>/dev/null
REMOTE
```

**What to look for:**
- `POOCH PALACE` header
- Line items (Spay/neuter surgery, Orthopedic surgery, etc.)
- `TOTAL DUE $10974.70`

If you want the full six-invoice flow (chunked uploads for the large
ones, mixed-language OCR, grand total in EUR), follow
`03-ocr-extend/PROMPT.md` end to end.

## M8. Cleanup

```bash
bash ~/dev/skill-cf-shell/tests/scenarios/cleanup.sh --yes
```

---

# Quick reference

| Command | Purpose |
|---------|---------|
| `bash $CFS preflight` | Check cf/curl/jq + cache shell2http |
| `bash $CFS deploy <app>` | Push + set SH_BASIC_AUTH |
| `bash $CFS exec <app> '<cmd>'` | Run `<cmd>` in a fresh `bash -lc` |
| `bash $CFS exec <app> -` | Read the command from stdin (heredoc-friendly) |
| `bash $CFS url <app>` | Print `https://.../exec` |
| `bash $CFS destroy <app>` | `cf delete -f` |
| `bash cleanup.sh --yes` | Nuke all `cfsh-*` apps, services, and local push dirs |

# Tips

- **Pipe heredocs for anything multi-line.** Bash quoting is the
  single biggest papercut when crafting `cmd=` payloads.
- **Each exec is a fresh `bash -lc`.** No cwd, no env, no open file
  handles carry across calls. The container filesystem DOES carry
  (same container instance), but don't rely on that across a
  `cf push` or restart.
- **Credentials only live in `cf env`.** Not in a file on your
  laptop, not in the dispatcher's state. If you destroy and
  re-deploy, you get a new random `SH_BASIC_AUTH`.
- **Re-push preserves `SH_BASIC_AUTH`** (Tier 3 relies on this).
- **Watch `cf logs <app>` live** during `cf push` in Tier 3 — the
  staging logs are where "the platform is actually building this
  thing" becomes visible.
