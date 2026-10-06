# skill-auditor
Audit an installed skill against Anthropic's skill-writing best practices and fix what is wrong.

## Why use it
Skills get written fast and drift from good practice.
They grow past 500 lines, bury important rules, use first-person descriptions, or skip checks on their output.
This skill takes the name of one skill, checks it against 10 rules, including the frontmatter limits, shows you a findings table, fixes the ones you pick, and reports what changed.
It never changes anything before you choose which fixes to apply.

## Quick example
```text
/skill-auditor write-ac
```

You get back a findings table like:
```text
| # | Rule | Status | Evidence | Planned fix |
|---|------|--------|----------|-------------|
| 1 | Progressive disclosure | PASS | SKILL.md is 120 lines | |
| 2 | Contents lists | FAIL | SKILL.md 261 lines, no contents list | Add contents list |
| 5 | Concise / 3rd-person | FAIL | Description does not say when to use | Rewrite description |
```

Then it asks which fixes to apply: `all`, or a list like `2, 5`.
After your answer it edits the skill and reports every change.

## Setup
No extra tools needed.
The skill uses standard shell commands like `wc` and `grep` to gather facts.

## Installation
```bash
./install.sh skill-auditor
```

## Usage
Basic shape:
```text
/skill-auditor <skill-name>
```

The argument is the name of an installed skill.
If you omit it, the skill asks for one.
Pass `all` to audit every skill in `./skills` (or `~/.claude/skills` if there is no such folder), one at a time.

Examples:
```text
/skill-auditor pr-review
/skill-auditor write-ac
/skill-auditor all
```

## What happens when you run it
1. It finds the skill by name in `./skills/`, `./.claude/skills/`, or `~/.claude/skills/`.
2. It gathers facts with `wc` and `grep`: line counts, links between files, description and name length, repeated text, and shell snippets.
3. It judges 10 rules: progressive disclosure, contents lists, degrees of freedom, model fit, concise writing, checklists, feedback loops, patterns, portability, and hooks.
4. It shows a findings table with evidence and the planned fix for each rule, then asks which fixes to apply: all, or a list of numbers.
5. It edits the original files in place, only with the fixes you chose, keeping every instruction, number, and path from the original.
6. It updates the skill's `README.md` if a fix changes usage, requirements, or behavior.
7. It re-checks all rules, shows the diff, and reports what changed.

## Safety guarantees
- Nothing is changed before you answer which fixes to apply.
- Skills inside a git repo are edited in place, and git is your backup.
If the skill folder already has uncommitted changes, it asks before continuing.
- Skills outside git, like those in `~/.claude/skills`, are backed up to `/tmp/audit/` first.
- Nothing is committed.
- Hooks are proposed in the report only.
Nothing is added to your settings unless you agree.
- It never claims a skill was tested on a model when it was not.
