# Extending the cf-shell container

Default deploy uses only `binary_buildpack` + `shell2http`. The base
stack gives you bash, coreutils, curl, usually python3, awk, sed.

To add more: deploy first, then edit the generated `manifest.yml`
under `${XDG_CACHE_HOME:-~/.cache}/cf-shell/push/<app>/`, drop in
companion files, and re-`cf push` from that dir. Re-pushes preserve
`SH_BASIC_AUTH`.

**`binary_buildpack` always stays last**  -  it provides shell2http.
Everything else goes before it.

## Auth when hand-rolling the push

`cf push` does NOT set `SH_BASIC_AUTH`  -  only the skill's `deploy`
subcommand does.

> [!WARNING]
> A from-scratch `cf push` with your own manifest brings `/exec` up
> **open to the internet**: no basic auth, anyone with the URL can
> run `bash`.

Two ways to avoid that:

1. **Preferred**  -  `cf-shell.sh deploy <app>` first, then edit the
   generated manifest and `cf push -f manifest.yml -p .` from the
   push dir. The re-push preserves the existing credential.
2. **Recovery**  -  if you already pushed cold, run
   `cf-shell.sh secure <app>` immediately. It sets `SH_BASIC_AUTH`
   on the existing app and restarts it.

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

If the foundation's apt archive doesn't have a package, the push fails.

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

> [!CAUTION]
> Anyone with `/exec` access has those credentials. Only bind what
> you'd accept exposing behind basic auth.
