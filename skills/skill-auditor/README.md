# skill-auditor
Audit an installed skill against Anthropic's skill-writing best practices and fix what is wrong.

## Why use it
Skills get written fast and drift from good practice.
They grow past 500 lines, bury important rules, use first-person descriptions, or skip checks on their output.
This skill takes the name of one skill, checks it against 10 rules, including the frontmatter limits, shows you a findings table, fixes the violations, and reports what changed.
It works on a copy and never edits the original without your approval.

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

Then the fixed skill and a short report of every change.

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
2. It copies the skill to `/tmp/audit/` and keeps an untouched backup next to it.
3. It gathers facts with `wc` and `grep`: line counts, links between files, description and name length, and scripts.
4. It judges 10 rules: progressive disclosure, contents lists, degrees of freedom, model fit, concise writing, checklists, feedback loops, patterns, portability, and hooks.
5. It shows a findings table with evidence and the planned fix for each rule.
6. It fixes violations one rule at a time, keeping every instruction, number, and path from the original.
7. It re-checks all rules until every rule passes or a decision is left to you.
8. It shows a diff and a final report, and offers to copy the fixed skill over the original.

## Safety guarantees
- Edits happen only on a copy in `/tmp/audit/`.
- The original is replaced only after you approve.
- Fixes that change what a skill does (not just how it is written) need your confirmation first.
- Hooks are proposed in the report only.
Nothing is added to your settings unless you agree.
- It never claims a skill was tested on a model when it was not.
