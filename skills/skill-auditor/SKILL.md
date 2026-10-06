---
name: skill-auditor
description: Audits and fixes a Claude skill against Anthropic's skill-authoring best practices. Use when the user gives a skill name and asks to audit, review, lint, upgrade, optimize or fix it, or asks whether a skill follows best practices.
---

Takes one argument: the **name of a skill**.
Checks it against the rules below, fixes every violation, and reports what changed.
If no name was given, ask for one.
If the argument is `all`, audit every skill found in `./skills`, or in `~/.claude/skills` if that folder does not exist.
Run the full procedure once per skill, one at a time.

## Contents
- Steps
- Rules (1-10)
- Findings table
- Final report

## Steps

Copy this checklist into your reply and tick items as you go:

```
Audit progress:
- [ ] 1. Locate the skill
- [ ] 2. Work on a copy
- [ ] 3. Gather facts
- [ ] 4. Judge every rule
- [ ] 5. Show the findings table
- [ ] 6. Apply fixes
- [ ] 7. Re-check every rule. If any still fails, go back to step 6
- [ ] 8. Report and deliver
```

1. **Locate.** Find a folder named exactly like the argument that contains `SKILL.md` (skip this when the argument is `all`). Search `./skills/<name>`, `./.claude/skills/<name>`, `~/.claude/skills/<name>`. If nothing matches, try a partial match on the `name:` field. If several match, list them and ask. If none match, list the skills you can see and stop.
2. **Copy.** Never edit in place. Run `mkdir -p /tmp/audit && cp -r "<found-path>" /tmp/audit/<name> && cp -r "<found-path>" /tmp/audit/<name>.orig`. Edit only `/tmp/audit/<name>`. Keep the original `name` and folder name.
3. **Facts.** Collect with `wc -l` and `grep`: line count of every `.md` file, whether files over 100 lines open with a contents list, links between files, description length, name length, and any scripts and what they import.
4. **Judge.** Mark each rule PASS, FAIL, or N/A with a one-line reason. Do not invent violations, and do not force a rule where it does not apply (a 30-line skill needs no references folder).
5. **Findings table.** Show it before changing anything (format below). If a planned fix changes what the skill *does*, not only how it is written, ask for confirmation first. Pure rewording and restructuring needs none.
6. **Fix.** Work in this order: Rule 5, then 1, 2, 3, 6, 7, 8, then 9. Rules 4 and 10 go in the report only.
7. **Re-check.** Re-judge all rules on the edited copy. Also confirm: `SKILL.md` under 500 lines, every link resolves, no link chain deeper than one level, frontmatter is valid. Diff against `<name>.orig` and account for every removed line.
8. **Deliver.** Show `diff -ru /tmp/audit/<name>.orig /tmp/audit/<name>` and the report (format below). Offer to copy the fixed version over the original, and only do it on approval.

Safety rules for every fix:
- **Preserve behavior.** Every instruction, constraint, number, path, and project-specific fact must still exist afterward. Cut only generic explanations Claude already knows.
- **Never delete a hard constraint** (limits, forbidden actions, required approvals).
- **Keep the skill's voice and language.** Do not restyle beyond what a rule needs.
- **Do not touch** scripts' logic or binary files unless a rule requires it.
- If the skill is not the user's to change (public or built-in), deliver the fixed copy as new and say the original was not modified.

## Rules

**Rule 1: Progressive disclosure.**
Claude may only read the first ~100 lines of a long file, so `SKILL.md` stays short.
Violations: `SKILL.md` over 500 lines, bulky reference material inline, a linked file that links onward to a third file, critical instructions far down a long file.
Fix: move bulky or situational content into files linked directly from `SKILL.md` with a "read when" hint.
Do not split a short skill just to have extra files, and do not move rules that apply to every run out of `SKILL.md`.

**Rule 2: Contents list on long files.**
Violation: any Markdown file over 100 lines with no contents list in its first ~15 lines.
Fix: add a `## Contents` list of the real headings after the title.
Do not add one to files under 100 lines.

**Rule 3: Degrees of freedom.**
Risky or irreversible steps need exact commands.
Harmless creative steps should be open-ended.
Violations: micro-steps for a low-stakes task, vague wording for a risky step, pervasive ALL CAPS or "ALWAYS/NEVER" on trivial items.
Fix: loosen low-stakes steps to goal plus real constraints, tighten risky steps to exact commands.
Never loosen a legal, financial, security, or data-loss constraint.
If unsure whether a step is risky, leave it and flag it.

**Rule 4: Model fit.**
Skills written for older models are often too prescriptive for newer ones and too thin for smaller ones.
Fix: over-explanation is trimmed under Rules 3 and 5, so here only list recommended test prompts per model tier in the report.
Do not add a "tested on" line you cannot back up.

**Rule 5: Concise writing, good frontmatter.**
Spend tokens only on what Claude cannot work out itself.
Violations:
- generic explanations, repeated instructions, filler
- description in first or second person ("I can help...", "You can use this...")
- description missing either what the skill does or when to use it
- description over 1024 characters, or empty
- name not lowercase-hyphenated, over 64 characters, or containing `anthropic` or `claude`
- XML tags in name or description
- one concept called by different terms, or time-sensitive text ("before August 2025 use...")

Fix: delete generic text, rewrite the description in third person with what and when plus trigger phrases, pick one term per concept, delete or isolate time-sensitive text.
Do not cut project-specific facts.
When unsure if something is common knowledge, keep it.

**Rule 6: Workflows and checklists.**
Violations: a process of 4+ steps written as a paragraph, no verification before a final or irreversible action, no stated order.
Fix: number the steps, add a copyable checklist block, add a go-back line at each check step.
Do not add checklists to 1-3 step skills.

**Rule 7: Feedback loops.**
Violation: output has objective requirements (schema, required sections, totals, style) but no validation step, or validation with no fix-and-recheck path.
Fix: add 3-6 concrete checks and: "If any check fails, note which criterion it breaks, fix it, and re-run the checks. Finish only when all pass."
Do not add loops to purely subjective output or invent criteria the author never intended.

**Rule 8: Common patterns.**
Violations: output format described only in prose, branching logic buried in paragraphs, style requirements with no example.
Fix: convert the format to a template (say whether it is strict or a default), add 1-3 realistic input/output examples, turn "depending on..." paragraphs into explicit if/then branches.
Derive examples from the skill's own content, never invent ones that contradict it.

**Rule 9: Portability.**
Violations:
- a tool or library used but not named, or a script importing a package never mentioned
- hard-coded personal paths, accounts, or private URLs
- Windows-style backslash paths
- scripts that fail on errors or use unexplained magic numbers
- MCP tools named without the server prefix (use `ServerName:tool_name`)

Fix: name exact packages with a conditional install note, state required tools up front, use relative paths and forward slashes.
Do not invent version pins.

**Rule 10: Hooks for must-never-break rules.**
Instructions are followed most of the time, a hook runs every time.
Violation: an absolute rule with real consequences ("never send above $10,000 without sign-off") and no enforcement.
Fix: keep the rule in the text, and propose a hook in the report with the event, the condition, the action, the script, and the config snippet.
Usually 0-3 per skill.
Only write hooks or edit settings if the user explicitly agrees.
Never turn ordinary preferences into hooks.

## Findings table

```
Skill audited: <name>   (location: <path>)

| # | Rule | Status | Evidence | Planned fix |
|---|------|--------|----------|-------------|
| 1 | Progressive disclosure | FAIL | SKILL.md is 640 lines | Move examples to a linked file |
| 2 | Contents list | PASS | | |
| 5 | Concise / frontmatter | FAIL | Description starts "I can help..." | Rewrite in third person |
```

Status values: PASS, FAIL, N/A, RECOMMEND (needs the user's action or consent).

## Final report

```
Result: <n> fixed, <n> passing, <n> recommendations

Changes made
- <file>: <what changed and why>

Behavior check
- Nothing removed / Removed as generic: <list>

Needs your decision
- <hook proposal, model testing suggestion, anything unclear>

Files
- Fixed skill: <path>
- Original untouched: <path>
```
