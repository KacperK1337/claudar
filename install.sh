#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${SCRIPT_DIR}/skills"
DEST_DIR="${HOME}/.claude/skills"

# Print usage if no skill name provided
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <skill-name>"
  echo ""
  echo "Available skills:"
  for dir in "${SKILLS_DIR}"/*/; do
    [[ -d "${dir}" ]] || continue
    name="$(basename "${dir}")"
    desc=$(grep '^description:' "${dir}/SKILL.md" 2>/dev/null | head -1 | sed 's/^description: *//')
    echo "  ${name} - ${desc}"
  done
  exit 1
fi

skill="$1"
source="${SKILLS_DIR}/${skill}"
# Exit if skill not found
if [[ ! -f "${source}/SKILL.md" ]]; then
  echo "Error: skill '${skill}' not found."
  exit 1
fi

# Check tools required by the skill
if [[ -f "${source}/requirements.txt" ]]; then
  missing=()
  while IFS= read -r tool || [[ -n "${tool}" ]]; do
    tool="$(echo "${tool}" | xargs)"
    [[ -z "${tool}" ]] && continue
    command -v "${tool}" &>/dev/null || missing+=("${tool}")
  done < "${source}/requirements.txt"
  # Fail if any tool is missing
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: missing required tools: ${missing[*]}"
    exit 1
  fi
fi

# Copy skill to claude skills directory
dest="${DEST_DIR}/${skill}"
updating=false
[[ -f "${dest}/SKILL.md" ]] && updating=true

mkdir -p "${dest}"
cp "${source}/SKILL.md" "${dest}/SKILL.md"

if [[ "${updating}" == true ]]; then
  echo "Updated '${skill}' in ${dest}"
else
  echo "Installed '${skill}' to ${dest}"
  echo "Use it in Claude Code by running '/${skill}'"
fi
