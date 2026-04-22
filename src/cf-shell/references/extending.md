# Extending the cf-shell container

Default deploy uses only `binary_buildpack` + `shell2http`. Base stack
gives you bash, coreutils, curl, usually python3, awk, sed. To add
more, **run `scripts/cf-shell.sh deploy <app>` first** so the initial
push sets `SH_BASIC_AUTH`, then edit `manifest.yml` under
`$CACHE/push/<app>/` (where `$CACHE` defaults to
`${XDG_CACHE_HOME:-~/.cache}/cf-shell`, override with
`$CF_SHELL_CACHE`), drop in companion files, re-`cf push`. The
re-push preserves the credential.

**`binary_buildpack` always stays last**  -  it provides shell2http.
Everything else goes before it.

## Auth gotcha when hand-rolling the push

`cf push` does NOT set `SH_BASIC_AUTH`  -  only the skill's `deploy`
subcommand does. If you `cf push` an app from scratch with your own
manifest (skipping `deploy`), the `/exec` endpoint comes up **open
to the internet**: no basic auth, anyone with the URL can `bash`.
Two ways to avoid the hole:

1. **Preferred**  -  `cf-shell.sh deploy <app>` first. That does the
   initial push and sets `SH_BASIC_AUTH`. Then edit the generated
   `manifest.yml` under `$CACHE/push/<app>/` to add your buildpacks
   and `cf push -f manifest.yml -p .` from that dir. The re-push
   preserves the existing `SH_BASIC_AUTH`.
2. **Recovery**  -  if you already pushed without going through
   `deploy`, run `cf-shell.sh secure <app>` immediately. That sets
   `SH_BASIC_AUTH` on the existing app and restarts it.

## apt packages

```yaml
# manifest.yml
applications:
  - name: cf-shell
    memory: 512M
    disk_quota: 1G
    buildpacks:
      - https://github.com/cloudfoundry/apt-buildpack
      - binary_buildpack
    command: ./shell2http -form -export-all-vars -include-stderr -no-log-timestamp -timeout=300 -port=$PORT /exec 'bash -lc "$v_cmd"'
    health-check-type: port
```

```yaml
# apt.yml
---
packages:
  - tesseract-ocr
  - tesseract-ocr-eng
  - ffmpeg
```

Unknown package names will fail the push  -  whatever apt archive the
foundation is wired to decides availability.

**apt-buildpack installs to a non-standard prefix.** Packages land
under `/home/vcap/deps/0/apt/usr/...` rather than `/usr/...`. Binaries
are on `$PATH` automatically, but tools that look up data by a
compiled-in path may not find it. Example  -  tesseract:

    export TESSDATA_PREFIX=/home/vcap/deps/0/apt/usr/share/tesseract-ocr/4.00/tessdata

You need to do this in every `exec` that invokes `tesseract`; each
call is a fresh `bash -lc` and env doesn't carry.

## Python packages

```yaml
buildpacks:
  - python_buildpack
  - binary_buildpack
```

```
# requirements.txt
pillow==11.0.0
pytesseract==0.3.13
```

## Both apt + Python

```yaml
buildpacks:
  - https://github.com/cloudfoundry/apt-buildpack
  - python_buildpack
  - binary_buildpack
```

## Bind a service

```yaml
applications:
  - name: cf-shell
    services:
      - my-pg-instance
```

Credentials land in `VCAP_SERVICES`. `-export-all-vars` makes them
available to every exec (parse with `jq`).

## After editing

    cd "${XDG_CACHE_HOME:-$HOME/.cache}/cf-shell/push/<app>"
    cf push -f manifest.yml -p .

`SH_BASIC_AUTH` persists across re-pushes *of the same app*. Container
filesystem is replaced on every push. If you pushed a brand-new app
manually instead of going through `deploy`, run
`scripts/cf-shell.sh secure <app>` right after the push to lock
`/exec` down  -  see the "Auth gotcha" section above.
