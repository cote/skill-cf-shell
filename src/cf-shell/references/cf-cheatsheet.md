# cf CLI cheat sheet for cf-shell work

The dispatcher in `scripts/cf-shell.sh` is a convenience, not a
requirement. You can do everything it does with the `cf` CLI
directly, and sometimes that's cleaner  -  especially when extending
a manifest or binding services. Use whichever is more legible for
the task.

This reference covers the `cf` subset that's useful when working
with cf-shell. It is not a full `cf` reference.

## Orientation

| Command | What it prints |
|---------|----------------|
| `cf target` | API endpoint, user, org, space |
| `cf orgs` | Orgs you can see |
| `cf spaces` | Spaces in current org |
| `cf target -o ORG -s SPACE` | Switch target |

## Apps in the current space

| Command | Purpose |
|---------|---------|
| `cf apps` | List apps (name, state, instances, routes) |
| `cf app <app>` | One app: health, stack, buildpacks, instance stats |
| `cf app <app> --guid` | GUID only  -  useful for `cf curl` queries |
| `cf routes` | Routes in the space |
| `cf events <app>` | Audit events for one app (push, restart, etc.) |

## Deploying

| Command | Purpose |
|---------|---------|
| `cf push -f manifest.yml -p .` | Push using the manifest in cwd, app content from cwd |
| `cf push <app> -f manifest.yml -p path/to/src` | Same, explicit app name + source path |
| `cf restart <app>` | Restart (pick up env var changes) |
| `cf restage <app>` | Re-stage droplet (re-run buildpacks against same bits) |
| `cf start <app>` / `cf stop <app>` | Self-explanatory |

## Env vars

| Command | Purpose |
|---------|---------|
| `cf env <app>` | All env (system + user-provided). `SH_BASIC_AUTH` lives here. |
| `cf set-env <app> KEY VALUE` | Add/overwrite. Takes effect after `cf restart`. |
| `cf unset-env <app> KEY` | Remove. Same restart requirement. |

## Logs

| Command | Purpose |
|---------|---------|
| `cf logs <app>` | Live tail  -  `STG/0`, `CELL/0`, `APP/…`, `RTR/…`, `API/…` |
| `cf logs <app> --recent` | Snapshot of recent buffered logs (not live) |
| `cf logs <app> \| grep RTR` | Trim to HTTP access log only  -  one line per exec |

Prefix guide:
- `STG/0`  -  staging (buildpack output during `cf push`)
- `CELL/0`  -  container lifecycle (create, start, destroy)
- `APP/PROC/WEB/0`  -  app stdout/stderr
- `RTR/0`  -  gorouter access log (one per HTTP request)
- `API/0`  -  control-plane events (`set-env`, `restart`, etc.)

## Services

| Command | Purpose |
|---------|---------|
| `cf marketplace` | All service offerings on the foundation |
| `cf marketplace -e <offering>` | Plans + descriptions for one offering |
| `cf services` | Service instances in the space |
| `cf service <instance>` | Detail: broker, plan, bound apps, dashboard |
| `cf create-service <offering> <plan> <name>` | Provision a new instance |
| `cf bind-service <app> <instance>` | Inject creds into `VCAP_SERVICES`; requires `cf restart` |
| `cf unbind-service <app> <instance>` | Reverse of bind |
| `cf delete-service -f <name>` | Deprovision. Irreversible. |

## Reading bound-service creds from inside an exec

Because shell2http starts with `-export-all-vars`, `VCAP_SERVICES`
is in every `bash -lc` env. Parse it with `jq`:

```bash
# List bound services:
echo "$VCAP_SERVICES" | jq 'keys'

# Postgres URI (works for Tanzu postgres broker):
echo "$VCAP_SERVICES" | jq -r '.postgres[0].credentials.uri'

# GenAI proxy details (Tanzu genai broker):
echo "$VCAP_SERVICES" | jq -r '.genai[0].credentials'
```

## Audit events (cross-app or per-app)

```bash
# Most recent 10 events in the whole space
cf curl "/v3/audit_events?order_by=-created_at&per_page=10" \
  | jq -r '.resources[] | "\(.created_at)  \(.type)  \(.target.name // "-")  by \(.actor.name)"'

# Same, scoped to one app
cf curl "/v3/audit_events?order_by=-created_at&per_page=10&target_guids=$(cf app <app> --guid)" \
  | jq -r '.resources[] | "\(.created_at)  \(.type)  \(.target.name // "-")  by \(.actor.name)"'
```

Wrap either in `watch -n 5 '...'` for a live console.

## Destruction (always confirm)

| Command | Effect |
|---------|--------|
| `cf delete -f <app>` | Delete the app + its droplet |
| `cf delete -f -r <app>` | Same, also remove the route |
| `cf delete-service -f <name>` | Deprovision a service instance (permanent data loss for Postgres, etc.) |

These are left out of `settings.json.example`'s allowlist
deliberately  -  always prompt before running.

## When to use the dispatcher vs `cf` directly

- **Use the dispatcher** for the everyday loop: `deploy`, `exec`,
  `secure`, `destroy`. It handles `SH_BASIC_AUTH` generation,
  passes auth on every `exec`, surfaces remote exit codes via the
  `X-Shell2http-Exit-Code` header.
- **Use `cf` directly** for manifest extensions, service bindings,
  logs inspection, audit queries, anything where the extra shell
  layer just obscures what's happening.

One useful pattern: `scripts/cf-shell.sh deploy <app>` for the
initial push + auth, then `cf push -f manifest.yml -p .` from the
push dir when you need to edit the manifest. `SH_BASIC_AUTH`
persists across re-pushes, so you don't need `secure` on re-push  - 
only when you push a brand-new app from scratch without going
through `deploy`.
