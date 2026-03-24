# pr-review
Deep, in-depth code review of a GitHub Pull Request.

## Installation
```
./install.sh pr-review
```

## Usage
Inside any repo, open Claude Code and run:
```
/pr-review <pr-number|branch-name>
```
Examples:
```
/pr-review 1234
/pr-review feat/add-new-api
```

## What it does
1. Fetches PR metadata and diff via `gh` CLI
2. Reads every changed file in full for context
3. Explores the broader codebase for related patterns, utilities, and conventions
4. Produces a structured review covering: correctness, security, performance, architecture, code reuse, testing, naming, API design, and dependencies
5. Gives a verdict: `REJECT`/`CHANGES REQUESTED`/`APPROVE WITH NITS`/`APPROVE`

The review is harsh by design — it simulates a senior staff engineer who knows the codebase and won't let anything slide.
