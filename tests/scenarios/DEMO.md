# cf-shell demo

Five-step flow. You run Claude, Claude uses the `cf-shell` skill to
do real work on a CF foundation. No paste-along milestones.

## 1. Install the skill

A Claude Code "skill" is just a directory at
`~/.claude/skills/<name>/` containing a `SKILL.md` (plus any scripts
and references it ships). There is no `claude skill install`
subcommand today. Two ways to land this one:

**From the dev repo (preferred if you have it cloned):**

```bash
git clone <wherever skill-cf-shell lives> ~/dev/skill-cf-shell
bash ~/.claude/skills/make-skill/scripts/build-skill.sh cf-shell
bash ~/.claude/skills/make-skill/scripts/install-skill.sh cf-shell
```

That copies the built artifact to `~/.claude/skills/cf-shell/`.
Requires the `make-skill` skill already installed — if you don't have
it, the manual path below is fine.

**Manual copy:**

```bash
mkdir -p ~/.claude/skills/cf-shell
cp -r ~/dev/skill-cf-shell/src/cf-shell/* ~/.claude/skills/cf-shell/
chmod u+x ~/.claude/skills/cf-shell/scripts/*.sh
```

Either way, confirm:

```bash
ls ~/.claude/skills/cf-shell/
# expect: SKILL.md  references/  scripts/
```

## 2. Log into CF

The skill never handles your CF login. It assumes `cf target` already
succeeded and lets you do whatever SSO flow your foundation uses.

```bash
cf login -a https://api.sys.<your-foundation>
```

Follow the prompts (password, SSO one-time code, whatever). On
success, `cf` writes an OAuth refresh token to
`~/.cf/config.json` (mode 0600). That's the only credential store —
you don't need to export anything into your shell env, you don't
pass a token to Claude, and you don't put it in a `.env` file.

Sanity check:

```bash
cf target
# API endpoint, user, org, space all shown
```

Every `cf` command from now on — including the ones the skill shells
out — reads from `~/.cf/config.json`. Tokens refresh automatically
until the session expires.

## 3. Launch Claude in that same terminal

```bash
cd ~/dev/skill-cf-shell     # or wherever makes sense for your task
claude
```

Why same terminal: any bash Claude spawns inherits your environment,
and therefore inherits `cf`'s config. If you log in in one terminal
and launch `claude` in another fresh shell, you're still fine because
`~/.cf/config.json` is filesystem state, not env state — but keeping
it to one terminal avoids the "which `cf target` am I on?" confusion
during the demo.

## 4. Ask Claude to confirm it has CF access

Opening turn, plain English:

> Can you check that you have access to a Cloud Foundry foundation?
> If so, tell me which one.

**Expected behavior:** Claude runs `cf target`, reads the output,
reports back the API endpoint, user, org, and space. If the login
expired or you skipped step 2, it'll say so and stop.

You can sharpen the test with:

> List the apps in my current space, and tell me if any of them look
> like existing `cf-shell` deployments.

Claude should `cf apps`, recognize that nothing starts with `cfsh-`
(if the space is clean), and say so.

## 5. Ask Claude to OCR the invoices via cf-shell

Natural language, no mention of the skill by name — the skill's
description triggers:

> There are six invoice images at
> `~/dev/skill-cf-shell/tests/scenarios/03-ocr-extend/input/`. Use
> a Cloud Foundry-hosted shell to OCR them and give me the totals
> plus a grand total in EUR. For any invoices in USD, convert at
> 1 USD = 0.92 EUR.

**What Claude should do (roughly):**

1. Pick up the `cf-shell` skill from its description.
2. Preflight → deploy a default binary-stack shell (~20s).
3. Notice tesseract isn't there. Read
   `references/extending.md`. Edit the pushed `manifest.yml` under
   `~/.cache/cf-shell/push/<app>/` to add `apt-buildpack` +
   `python_buildpack` in front of `binary_buildpack`. Drop in
   `apt.yml` (tesseract + language packs) and `requirements.txt`
   (pytesseract + Pillow). Re-`cf push` (~3–5 min).
4. Upload the six PNGs via chunked base64 (the biggest is ~430 KB,
   too large for a single POST).
5. OCR each one. `-l eng` for the English invoices, `-l spa+cat`
   for the Spanish/Catalan `factura_*.png` files.
6. Aggregate, compute the grand total, report.
7. Destroy the app when done.

**What to watch in a second terminal if you want live feedback:**

```bash
watch -n 2 cf apps                  # app appears + disappears
cf logs <app-name>                  # shell2http POSTs as they land
                                    # + cf push staging output
```

## Troubleshooting

- **"Claude doesn't seem to know about cf-shell"** — the skill's
  description has to match the user turn strongly enough to trigger.
  If Claude goes off-piste, say "use the cf-shell skill" explicitly
  and it'll pick up. Long-term fix: tune the skill description.
- **`cf target` fails inside Claude's bash calls** — you either
  didn't run step 2, or your foundation invalidated the token. Run
  `cf login` again in the same terminal and continue.
- **App already exists from a prior run** — either tell Claude
  "destroy any existing cfsh-* apps first" or run the cleanup script
  yourself before launching claude:
  ```bash
  bash ~/dev/skill-cf-shell/tests/scenarios/cleanup.sh --yes
  ```

## Variants

- **Lighter demo**: swap step 5 for "Aggregate
  `tests/scenarios/01-sed-awk/input/shipments.csv` by store chain
  via a CF-hosted shell." No buildpack extension, whole thing runs
  in ~90 seconds.
- **Service binding (when we get to it)**: "Bind a seaweedfs
  instance to your cf-shell and stash the OCR results in the bucket
  so they survive restart." Different shape — requires the skill to
  accept a service-binding arg at deploy time, which it doesn't yet.
