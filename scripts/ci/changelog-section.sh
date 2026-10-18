#!/usr/bin/env bash
# Prints the CHANGELOG.md section for a version (without its "## [x.y.z]" heading).
# Fails if the version has no section, so a release can't go out without notes.
#   scripts/ci/changelog-section.sh 0.7.0 [CHANGELOG.md]
set -euo pipefail
version="${1:?usage: changelog-section.sh <version> [file]}"
file="${2:-CHANGELOG.md}"
notes="$(awk -v v="$version" '
  /^## \[/ { if (found) exit; if (index($0, "## [" v "]") == 1) { found = 1; next } }
  /^\[[^]]+\]: / { if (found) exit }
  found { print }
' "$file" | sed '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
if [ -z "$(echo "$notes" | tr -d '[:space:]')" ]; then
  echo "No changelog section for $version in $file. Add a '## [$version] - date' section first." >&2
  exit 1
fi
printf '%s\n' "$notes"
