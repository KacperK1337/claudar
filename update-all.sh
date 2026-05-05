#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${SCRIPT_DIR}/skills"
DEST_DIR="${HOME}/.claude/skills"
INSTALL_SCRIPT="${SCRIPT_DIR}/install.sh"

if [[ ! -x "${INSTALL_SCRIPT}" ]]; then
  echo "Error: install.sh not found or not executable at ${INSTALL_SCRIPT}"
  exit 1
fi

if [[ ! -d "${DEST_DIR}" ]]; then
  echo "No skills installed: ${DEST_DIR} does not exist."
  exit 0
fi

updated=()
failed=()

for dir in "${SKILLS_DIR}"/*/; do
  [[ -d "${dir}" ]] || continue
  name="$(basename "${dir}")"
  if [[ -f "${DEST_DIR}/${name}/SKILL.md" ]]; then
    echo "==> Updating '${name}'"
    if "${INSTALL_SCRIPT}" "${name}"; then
      updated+=("${name}")
    else
      failed+=("${name}")
    fi
  fi
done

echo ""
if [[ ${#updated[@]} -eq 0 && ${#failed[@]} -eq 0 ]]; then
  echo "No installed skills from this repo found in ${DEST_DIR}."
  exit 0
fi

echo "Updated: ${#updated[@]} skill(s)${updated[*]:+: ${updated[*]}}"
if [[ ${#failed[@]} -gt 0 ]]; then
  echo "Failed: ${#failed[@]} skill(s): ${failed[*]}"
  exit 1
fi
