# cf-shell

Provision and use a Cloud Foundry-hosted bash shell via shell2http. Verifies the cf CLI, installs shell2http locally as needed, deploys the shell app to CF, and executes commands against it over HTTPS.

## Structure

```
src/cf-shell/          # source - edit here
  SKILL.md                # skill definition (frontmatter + docs)
  scripts/                # executable scripts
  reference/              # templates, config samples
target/cf-shell/       # built artifact - zip to deploy
tests/                    # test scripts and fixtures
CHANGELOG.md              # version history
README.md                 # this file
```

## Install

```bash
audit-skill.sh cf-shell
build-skill.sh cf-shell
install-skill.sh cf-shell
```

## Usage

<!-- TODO: show 2-3 common invocations -->

## Testing

Tests live in `tests/`. Run them before committing:

```bash
bash tests/run.sh
```

Document what each test verifies so they can be repeated consistently.

## Architecture

<!-- TODO: diagram of how the skill works, data flow, dependencies -->
