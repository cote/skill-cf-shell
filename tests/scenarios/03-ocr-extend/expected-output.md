# Scenario 03 — expected output

This is the hardest scenario. The invoice PNGs are synthetic fixtures;
their exact totals aren't encoded here because OCR of the dummies will
drift slightly between Tesseract versions / language data. The
reviewer grades on the *shape* of the answer and the *behavior* of the
model, not pixel-perfect totals.

## What the reviewer checks

### Did the container get extended correctly?

The pushed stack should end up with three buildpacks, in this order:

1. `https://github.com/cloudfoundry/apt-buildpack`
2. `python_buildpack`
3. `binary_buildpack`  ← must stay last; it supplies shell2http

Compare Claude's final `manifest.yml` against `oracle/manifest.yml`.
Order matters.

`apt.yml` must include `tesseract-ocr` and at least one language pack
beyond `-eng` (the facturas are Spanish and/or Catalan — `tesseract-ocr-spa`
or `tesseract-ocr-cat` expected). `oracle/apt.yml` is the full set.

`requirements.txt` should include `pytesseract` and `Pillow`. Version
pins are nice but not required.

### Did OCR actually run in the container?

- `tesseract --version` call shown in the transcript after the
  extension push.
- OCR invocations via `cf-shell exec` — either `tesseract <img>.png -`
  or a Python snippet using `pytesseract.image_to_string`.
- If Claude used pytesseract, did it set `TESSDATA_PREFIX` when needed?
  (Some apt-buildpack layouts require it — see the main project's
  `invoice-cleanup/CLAUDE.md`.)

### Did base64 chunking come up?

Several of the invoices are >90 KB. A naive single-POST upload will
fail or truncate. The reviewer looks for evidence of chunked staging:
either multiple `>>`-append POSTs into `/tmp/stage.b64` and a final
`base64 -d`, or equivalent. If Claude got lucky and they all fit in
one POST, confirm by checking file sizes post-upload.

### Language handling for facturas

For `factura_*.png`, Claude should either:
- specify `-l spa` or `-l cat` to tesseract, or
- run with default `-l eng` first, notice the output is garbage, and
  switch.

Either path is fine. Silent fallback to English with bad output is
a fail.

### Report quality

- Six line items with filename + total.
- One grand total in EUR.
- Conversion rule for USD invoices explicitly stated (1 USD = 0.92 EUR
  per the prompt).
- The final manifest / apt.yml / requirements.txt inline.
- `cf-shell` subcommand transcript.

### Did Claude peek at `oracle/`?

Not during the run. If the transcript shows a read of
`oracle/manifest.yml` before Claude wrote its own, flag it as a spoiled
trial — the whole point is "did the model figure out the extension
from `references/extending.md`."

### Cleanup

`destroy` called at the end, or an explicit decision to leave it.
