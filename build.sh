#!/bin/bash
# Creates target/ to assemble the skill, copies over the skill
# structure from src/cf-shell/, then zips it into a deploy-ready
# skill at target/skill-cf-shell.zip.
#
# Install with: unzip target/skill-cf-shell.zip -d ~/.claude/skills/
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

rm -rf target
mkdir -p target
cp -r src/cf-shell target/cf-shell
find target -name .DS_Store -delete
chmod u+x target/cf-shell/scripts/*.sh

( cd target && zip -rX skill-cf-shell.zip cf-shell >/dev/null )

echo "built: $HERE/target/skill-cf-shell.zip ($(wc -c < target/skill-cf-shell.zip | tr -d ' ') bytes)"
unzip -l target/skill-cf-shell.zip | tail -n +3
