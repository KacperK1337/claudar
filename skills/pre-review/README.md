# pre-review
Senior-engineer-grade code review of a local branch, before you open a Pull Request.

## Why use it
Use it before you open a Pull Request: you have the code (committed or not), and you want a harsh review before anyone else sees it.
It compares your branch with the repo's default branch using only `git` - it never calls GitHub.
It reads the changes, reads the surrounding codebase, and catches subtle correctness bugs, missing error paths, reinvented utilities, brittle tests, security holes, and leftovers you don't want to push.

## Quick example
```text
/pre-review
```

You get back one list, sorted by severity (critical first, then major, then minor):
```
### Issues
1. (Critical) `src/orders/checkout.ts:142` - new code path skips the inventory lock;
   concurrent checkouts on the same SKU can oversell. Use `lockInventory()` (already
   used in `src/orders/reserve.ts:88`).
2. (Major) `tests/checkout.test.ts:20-64` (uncommitted) - all new tests cover the happy
   path only. No test for the failure path added in `src/orders/checkout.ts:174`.
3. (Minor) `src/utils/format.ts:12` (untracked) - duplicate of `formatCurrency()` in
   `src/lib/money.ts:5`.
4. (Minor) `src/orders/checkout.ts:60` - leftover `console.log(order)`. Remove it.
```

There is no verdict (approve / reject).
You decide what to do with the list.

You can steer the review with extra context:
```text
/pre-review focus on security and backward compatibility
/pre-review feat/add-new-api this area is performance-sensitive
```

## Setup
You need:
- `git` and a local clone of the repo with an `origin` remote.

## Installation
```bash
./install.sh pre-review
```

## Usage
Basic shape:
```text
/pre-review [branch-name|HEAD] [additional context]
```

The selector is optional.
If the first word is not `HEAD` or an existing branch, the skill reviews your current branch and treats everything you typed as extra context.

Examples:
```text
/pre-review
/pre-review focus on performance
/pre-review HEAD
/pre-review feat/add-new-api
/pre-review feat/add-new-api already caused regressions before, look hard
```

Multiline context works too:
```text
/pre-review focus on API compatibility
pay extra attention to auth and caching changes
ignore cosmetic naming nits unless they affect clarity
```

Notes on the input:
- **Nothing** or **`HEAD`** - reviews the current branch, including uncommitted and untracked files.
- **Branch name** - a branch that exists locally or on `origin` (`feat/add-new-api`).
Only its committed changes are reviewed, unless it is the branch you have checked out.
- **Default branch** - there is nothing to compare, so the skill stops.

## What happens when you run it
1. The skill resolves the branch and finds the default branch (`main`, `master`, or whatever `origin/HEAD` points to), then runs `git fetch` on it so the comparison is current.
If the fetch fails, it goes on with the local copy and says so.
2. If the branch name or commit messages contain a Jira ticket key (`PROJ-123`) or a Jira browse URL, the skill fetches that ticket and uses it to check the change does what was asked.
Fetch uses the Atlassian MCP integration if connected, otherwise falls back to `curl` with `JIRA_ORG`/`JIRA_EMAIL`/`JIRA_API_TOKEN`.
If the ticket cannot be fetched, the review still goes on and a note is added at the end.
3. It builds the diff against the merge base with the default branch.
For the current branch, that includes commits, staged and unstaged edits, and untracked files.
4. It reads every changed file in full - not just the diff hunks - so context around the changes is real.
5. It explores the broader codebase for related patterns, utilities, and conventions, so the review can flag things like "this duplicates a function that already exists at X".
6. It also looks for things that should not be pushed: debug leftovers, new TODOs, secrets, and stray untracked files.
7. Any extra context you passed shapes emphasis (security, performance, backward compatibility, etc.).
8. It writes the review as one **Issues** list.
Each issue has its severity in brackets (`Critical`, `Major`, or `Minor`), and the list is sorted critical first, then major, then minor.
Issues in uncommitted or untracked files are marked as such.
Ticket-based findings are tagged `[Jira: KEY]`.
9. Before sending, it checks the review (no verdict, no GitHub calls, list sorted by severity, file and line references, uncommitted files covered, extra context handled, Jira tags) and fixes it if a check fails.

## Notes
- The review is harsh by design. It simulates a senior staff engineer who knows the codebase and refuses to wave anything through.
- Nothing in the repo is modified. The skill may run `git fetch` to get the latest default branch.
