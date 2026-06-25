#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$(dirname "$SCRIPT_DIR")/.github/workflows"

if [[ ! -d "$WORKFLOW_DIR" ]]; then
	echo "Workflow directory not found: $WORKFLOW_DIR" >&2
	exit 1
fi

# find all files with pattern deps-*.sh in SCRIPT_DIR
deps_files=("$SCRIPT_DIR"/deps-*.sh)

# loop through each deps_file and extract all occurence of text "build_*" and add it to an array
builds=()
for file in "${deps_files[@]}"; do
	builds+=($(grep -o 'build_[a-zA-Z0-9_]*' "$file"))
done

# remove duplicates
builds=($(printf "%s\n" "${builds[@]}" | sort -u))

# for each build step in builds, create a workflow by running workflow.sh with the build step as argument
for build in "${builds[@]}"; do
	"$SCRIPT_DIR/workflow.sh" "$build"
done