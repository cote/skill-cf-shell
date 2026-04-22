# Scenario 02  -  expected output

## 12×12 multiplication table (reference)

```
  1   2   3   4   5   6   7   8   9  10  11  12
  2   4   6   8  10  12  14  16  18  20  22  24
  3   6   9  12  15  18  21  24  27  30  33  36
  4   8  12  16  20  24  28  32  36  40  44  48
  5  10  15  20  25  30  35  40  45  50  55  60
  6  12  18  24  30  36  42  48  54  60  66  72
  7  14  21  28  35  42  49  56  63  70  77  84
  8  16  24  32  40  48  56  64  72  80  88  96
  9  18  27  36  45  54  63  72  81  90  99 108
 10  20  30  40  50  60  70  80  90 100 110 120
 11  22  33  44  55  66  77  88  99 110 121 132
 12  24  36  48  60  72  84  96 108 120 132 144
```

(Exact whitespace will vary  -  tab-aligned or column-aligned both fine.
What matters is that all 144 products are present and correct.)

## What the reviewer checks

- Did Claude use **two separate `exec` calls**  -  one to stage
  `multiplier.sh` into `/home/vcap/app/data/` and one to run it? A
  single-call `echo script | bash -s -- 12` collapses the interesting
  test and is a soft fail  -  note it and move on.
- Script got written to `/home/vcap/app/data/multiplier.sh` (survives
  across calls) rather than `/tmp` (may or may not, depending on
  backend).
- Output contains all 144 products, row 12 col 12 = 144.
- `destroy` at the end, or an explicit decision to leave it.
- Script did not run locally. Transcript should not contain a local
  Bash tool call that invokes `multiplier.sh`.
