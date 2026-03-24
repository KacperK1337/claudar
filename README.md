# claudar

A collection of Claude Code skills for development workflows.

## Prerequisites

- [Claude Code](https://claude.ai/download) installed and authenticated
- [GitHub CLI (`gh`)](https://cli.github.com/) installed and authenticated (`gh auth login`)
- `git`

## Installation

Clone the repo and run the install script with the skill you want:

```bash
git clone <this-repo-url> claudar
cd claudar
./install.sh <skill-name>
```

This checks that required tools are installed, then copies the skill to `~/.claude/skills/` so it's available globally in any project.

### List available skills

```bash
./install.sh
```

## Available Skills

### pr-review

Deep, in-depth code review of a GitHub Pull Request.

```
./install.sh pr-review
```

**Usage** — inside any repo, open Claude Code and run:

```
/pr-review 123
```

or by branch name:

```
/pr-review feature/my-branch
```

**What it does:**

1. Fetches PR metadata and diff via `gh` CLI
2. Reads every changed file in full for context
3. Explores the broader codebase for related patterns, utilities, and conventions
4. Produces a structured review covering: correctness, security, performance, architecture, code reuse, testing, naming, API design, and dependencies
5. Gives a verdict: REJECT, CHANGES REQUESTED, APPROVE WITH NITS, or APPROVE

The review is harsh by design — it simulates a senior staff engineer who knows the codebase and won't let anything slide.

## Adding New Skills

Create a directory under `skills/` with:

- `SKILL.md` — the skill definition (see [Claude Code docs](https://docs.anthropic.com/en/docs/claude-code) for format)
- `requirements.txt` — one CLI tool per line that must be available for the skill to work

## Uninstalling

Remove the skill directory from `~/.claude/skills/`:

```bash
rm -rf ~/.claude/skills/<skill-name>
```
