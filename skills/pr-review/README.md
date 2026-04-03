# pr-review
Deep, in-depth code review of a GitHub Pull Request.

## Requirements
- `gh` installed and authenticated

## Installation
```
./install.sh pr-review
```

## Usage
Inside any repo, open Claude Code and run:
```
/pr-review <pr-number|branch-name|HEAD>
```
Examples:
```
/pr-review 1234
/pr-review feat/add-new-api
/pr-review HEAD
```

Using `HEAD` will review the PR associated with whatever branch you're currently checked out on. If no open PR exists for the current branch, it will throw an error.

For the best review results, make sure you're locally checked out on the latest version of either the source or target branch of the PR you want to review. 
The skill reads full file contents from your local working tree for context — if your local files are outdated, the review may reference stale code.

## What it does
1. Fetches PR metadata and diff via `gh` CLI
2. Reads every changed file in full for context
3. Explores the broader codebase for related patterns, utilities, and conventions
4. Produces a structured review covering: correctness, security, performance, architecture, code reuse, testing, naming, API design, and dependencies
5. Gives a verdict: `REJECT`/`CHANGES REQUESTED`/`APPROVE WITH NITS`/`APPROVE`

The review is harsh by design — it simulates a senior staff engineer who knows the codebase and won't let anything slide.
