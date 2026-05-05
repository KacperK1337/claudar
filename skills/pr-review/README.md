# pr-review
Deep, in-depth code review of a GitHub Pull Request.

## Requirements
- `gh` installed and authenticated

## Installation
```bash
./install.sh pr-review
```

## Usage
Inside any repo, open Claude Code and run:
```text
/pr-review <pr-number|branch-name|HEAD> [additional context]
```
The first argument selects the PR to review. Everything after that is treated as optional additional review context.

Examples:
```text
/pr-review 1234
/pr-review feat/add-new-api
/pr-review HEAD
/pr-review 1234 focus on security and backward compatibility
/pr-review feat/add-new-api this area is performance-sensitive and already caused regressions before
```

You can also provide multiline context after the first argument, for example:
```text
/pr-review HEAD focus on API compatibility
pay extra attention to auth and caching changes
ignore cosmetic naming nits unless they affect clarity
```

Using `HEAD` will review the PR associated with whatever branch you're currently checked out on. If no open PR exists for the current branch, it will throw an error.

For the best review results, make sure you're locally checked out on the latest version of either the source or target branch of the PR you want to review.
The skill reads full file contents from your local working tree for context - if your local files are outdated, the review may reference stale code.

## What it does
1. Fetches PR metadata and diff via `gh` CLI
2. Parses the first argument as the PR selector and treats everything after it as optional additional review context
3. Reads every changed file in full for context
4. Explores the broader codebase for related patterns, utilities, and conventions
5. Produces a structured review covering: correctness, security, performance, architecture, code reuse, testing, naming, API design, and dependencies
6. Gives a verdict: `REJECT` / `CHANGES REQUESTED` / `APPROVE WITH NITS` / `APPROVE`

The review is harsh by design - it simulates a senior staff engineer who knows the codebase and won't let anything slide.
