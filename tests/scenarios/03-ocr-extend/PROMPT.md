# Scenario 03 — OCR invoices, extending the container

You're being handed this task in a fresh Claude Code session.

## Setup (human, before starting)

- `cf target` is already succeeded against a reachable foundation.
- `RUN_LIVE=1` is set. You are allowed to `cf push` a non-trivial
  container (apt + python buildpacks on top of binary) — expect it to
  take a few minutes.
- The `cf-shell` skill is installed at `~/.claude/skills/cf-shell/`.
- `input/` holds six invoice PNGs (three `factura_*.png` in Spanish or
  Catalan, three `invoice_*.png` in English).

## Your task

OCR each invoice and give the human:

1. A one-line "total" per invoice (currency + amount).
2. A grand total across all six, in EUR. If an invoice is in USD,
   convert at 1 USD = 0.92 EUR for this exercise (state the rule).
3. A note on which language each `factura_*` is in.

## Constraint — how you run it

**Do not OCR locally.** Everything happens in the CF-hosted container,
via the `cf-shell` skill.

The wrinkle: the default `cf-shell` deploy is `binary_buildpack` only —
no `tesseract`, no `pytesseract`, no `Pillow`. You'll hit that
immediately. Before you can OCR anything you need to extend the
container. The skill documents this in
`~/.claude/skills/cf-shell/references/extending.md` — read it.

Rough flow:

1. `scripts/cf-shell.sh preflight`
2. `scripts/cf-shell.sh deploy` (get the push dir created).
3. `scripts/cf-shell.sh exec ... "which tesseract || echo MISSING"` —
   confirm it's not there.
4. Read `references/extending.md`. Edit the pushed `manifest.yml` under
   `~/apps/cf-shell/cache/push/<app>/` to layer `apt-buildpack` and
   `python_buildpack` ahead of `binary_buildpack`. Drop in `apt.yml`
   (with `tesseract-ocr` + whatever language packs you'll need — at
   least `eng`, plus `spa` and/or `cat` for the facturas) and
   `requirements.txt` (with `pytesseract` and `Pillow`).
5. Re-`cf push` from the push dir. `SH_BASIC_AUTH` persists across
   pushes — you do not need to re-generate credentials.
6. `exec` → `tesseract --version` to confirm it's there.
7. Upload the six PNGs into `/home/vcap/app/data/` via base64.
   Some of them are >90 KB — you'll need to chunk them (append to a
   staging file, then one final `base64 -d` call). The skill's
   `SKILL.md` describes this pattern.
8. OCR each one with pytesseract (or `tesseract` CLI directly —
   either's fine). For the Spanish/Catalan ones, pick the right
   language via `-l spa` or `-l cat`.
9. Aggregate totals, compute the grand total, return the report.
10. `scripts/cf-shell.sh destroy` when done.

## Oracle

`oracle/` contains a working reference — `manifest.yml`, `apt.yml`,
`requirements.txt` — from the `ocr-shell-platform/` project that the
skill was abstracted from. **Don't read this during the run** unless
you're stuck; it spoils the "did the model figure it out" signal. The
reviewer uses it to grade what you produced.

## Report format

Markdown with:
- Per-invoice: filename, detected language (for facturas), total.
- Grand total in EUR with the conversion rule stated.
- The buildpack stack you ended up with.
- The final manifest.yml / apt.yml / requirements.txt you used (inline,
  so the reviewer can diff against `oracle/`).
- The sequence of `cf-shell` subcommands you ran.
