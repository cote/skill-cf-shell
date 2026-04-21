# cf-shell security model

A short reference for what the skill does and doesn't do for auth,
who can reach what, and where the hidey-holes are. Roughly in order
from outermost boundary inward.

## Layers

| Layer | Credential | Who manages it | Stored where |
|-------|-----------|----------------|--------------|
| 1. CF platform auth (push, set-env, delete) | `cf login` OAuth refresh token | The user, via SSO/UAA | `~/.cf/config.json` (mode 0600) |
| 2. HTTPS transport on the app route | TLS cert for `*.apps.<domain>` | The CF foundation | CF-managed, auto-renewed |
| 3. Shell2http HTTP Basic Auth on `/exec` | `SH_BASIC_AUTH=admin:<24 random alnums>` | The skill's `deploy` / `secure` subcommand | `cf env <app>` only — no local file |
| 4. Container user | uid 2000 `vcap` | CF cell | Not a credential; a confinement boundary |

The skill never touches layer 1 (it assumes `cf target` already
succeeded). It manages layer 3 entirely. Layers 2 and 4 are CF
platform properties the skill just inherits.

## The only credential the skill owns: `SH_BASIC_AUTH`

- **Generated** at `deploy` time: `admin:` + 24 random alphanumerics
  from `/dev/urandom`. ~142 bits of entropy — brute force isn't a
  realistic attack vector.
- **Set** via `cf set-env <app> SH_BASIC_AUTH <cred>`. Persists in CF
  DB as part of the app's env.
- **Read** by shell2http at container start — it's what gates
  `/exec`. 401s without it.
- **Read** by the skill's `exec` subcommand — looks it up with
  `cf env <app>`, sends it as `Authorization: Basic …` on every
  request.
- **Never** lands on local disk. No `.env` file, no keychain entry,
  no skill-state file. The dispatcher's own state dir
  (`~/.cache/cf-shell/`) holds shell2http and generated `manifest.yml`
  — not the credential.
- **Rotates** only on explicit destroy+redeploy, or
  `cf set-env`+`cf restart` by hand. Re-pushing the same app
  (e.g. to extend buildpacks) preserves whatever value is already
  there.

## What runs where on an `exec` call

1. Your laptop: `exec` subcommand shell-outs to `cf env` (reads cred),
   then `curl -u admin:… --data-urlencode cmd=… https://<route>/exec`.
2. CF gorouter: TLS terminates, routes to the cell running the app.
3. shell2http in the container: validates basic auth → 401 or forward.
4. `bash -lc "$cmd"` as `vcap`, with all app env vars in scope
   (`-export-all-vars` is how shell2http is configured).
5. stdout+stderr come back in the HTTP response body; exit code is
   in the `X-Shell2http-Exit-Code` header.

Each call is a fresh `bash -lc`. No persistent shell, no pty, no cwd
or exported-env carryover between calls. Container filesystem state
(including `/home/vcap/app/data/`) is the only thing that persists,
and only until the container gets replaced.

## Visibility of `SH_BASIC_AUTH`

The credential is visible to:

- Anyone with `SpaceDeveloper` on the space — `cf env <app>` returns
  it in plaintext.
- Anyone who sees the dispatcher's stdout at deploy time — the line
  `cf-shell: SH_BASIC_AUTH set to admin:xxxx` is printed. Watch for
  scrollback, screen shares, pasted transcripts, recorded terminals.
- The CF platform operators — CF DB + backups hold env vars. Standard
  platform-trust model.

## Known gotchas

### Hand-rolled `cf push` leaves `/exec` open

If you author your own `manifest.yml` and run `cf push` directly
(instead of `cf-shell.sh deploy` first), the new droplet starts with
**no `SH_BASIC_AUTH` set**. shell2http falls through to
"no basic auth configured" and serves `/exec` to the public internet.

**Mitigation**: `cf-shell.sh secure <app>` — idempotent, generates and
sets the credential on an existing app if missing. Run it immediately
after any hand-rolled push. (This happened once in practice, which
is why `secure` exists.)

### `VCAP_SERVICES` leaks through `-export-all-vars`

shell2http starts with `-export-all-vars`, which exposes every env
var (including `VCAP_SERVICES`) to every `bash -lc`. If you bind a
real database, API key, or credential-bearing service to the cf-shell
app, any `exec` can `echo "$VCAP_SERVICES"` and see the secret in
plaintext.

This is the same exposure model as any CF app with bound services.
Fine for a throwaway container; risky if you bind anything
production-adjacent. **Don't share a cf-shell app and a production
DB on the same binding.**

### No per-user auth; no rate limiting; no audit logging

One shared credential. Everyone who has it has the same access. No
per-user trail of who ran what — every request shows up as
`admin` in `RTR/0` access logs. shell2http doesn't rate-limit
failed auth attempts.

For anything beyond a one-person dev shell, put a real auth proxy
in front (oauth2-proxy, Cloudflare Access, Tanzu's own route-level
auth policies). Then the shared basic-auth becomes an inner belt
behind a proper outer fence.

## How the blast radius differs from plain `cf push`

Architecturally identical to any `cf push` — same public DNS, same
TLS, same `VCAP_SERVICES` model, same `SpaceDeveloper` visibility.
Deploying cf-shell is not a categorically different security action
from deploying Pet Clinic.

What differs is what a compromise yields:

| App | Compromise = |
|-----|--------------|
| Pet Clinic | CRUD on pet records at the app's DB privilege |
| cf-shell | Arbitrary bash in the container at the container's privilege, including reading `VCAP_SERVICES` for any bound service |

Same exposure surface, different leverage. The practical rule: don't
bind anything to a cf-shell app that you wouldn't paste into a shared
Slack channel.

## Lifecycle / rotation

- **Rotate credential**: `cf set-env <app> SH_BASIC_AUTH admin:<new>` +
  `cf restart <app>`. Or destroy + redeploy.
- **Revoke**: `cf delete -f <app>` — route stops resolving, container
  is destroyed. Fastest way to fully close the door.
- **Re-push preserves credential**: intentional. Lets you extend the
  container (add buildpacks) without regenerating the cred.
- **`destroy when done`** is the real operating norm. The skill's
  docs say it; the cleanup script enforces it at scenario boundaries.

## What the skill explicitly does NOT do

- Touch `cf login` or any SSO flow.
- Store, echo, or transmit the OAuth token to anyone.
- Write `SH_BASIC_AUTH` anywhere except `cf env`.
- Rotate credentials on a schedule.
- Log failed auth attempts, bind IP allowlists, or enforce rate
  limits.
- Audit individual `exec` calls beyond what CF's standard `RTR/0`
  access log captures.

If you want any of those, they belong in a real auth proxy or in
the foundation's route policies — not in a ~200-line dispatcher.

## Summary in one paragraph

`cf-shell` sits behind the same fences as any other CF app
(platform auth for push; TLS for transport; public route on the
apps domain), then adds one extra fence of its own: a randomly
generated shared HTTP basic-auth credential on `/exec`, stored only
in `cf env`, rotated only on deploy. Each `exec` round-trips through
that fence to a fresh non-root `bash -lc` in the container. The only
real pitfall is bypassing the skill's `deploy` path when extending
the container, which leaves the inner fence unset — `cf-shell.sh
secure <app>` exists specifically to close that case. For anything
beyond a single-operator dev shell, put a proper auth proxy in front.
