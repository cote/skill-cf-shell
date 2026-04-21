# Extending the cf-shell container

Default deploy uses only `binary_buildpack` + `shell2http`. Base stack
gives you bash, coreutils, curl, usually python3, awk, sed. To add
more, edit `manifest.yml` under `$CACHE/push/<app>/` (where `$CACHE`
defaults to `${XDG_CACHE_HOME:-~/.cache}/cf-shell`, override with
`$CF_SHELL_CACHE`), drop in companion files, re-`cf push`.

**`binary_buildpack` always stays last** — it provides shell2http.
Everything else goes before it.

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

Unknown package names will fail the push — whatever apt archive the
foundation is wired to decides availability.

**apt-buildpack installs to a non-standard prefix.** Packages land
under `/home/vcap/deps/0/apt/usr/...` rather than `/usr/...`. Binaries
are on `$PATH` automatically, but tools that look up data by a
compiled-in path may not find it. Example — tesseract:

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

`SH_BASIC_AUTH` persists across pushes. Container filesystem is
replaced on every push.
