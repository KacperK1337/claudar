# pr-review
Senior-engineer-grade code review of a GitHub Pull Request.

## Why use it
GitHub's own review UI is fine for spotting typos. 
It doesn't catch the kinds of issues a staff engineer would: subtle correctness bugs, missing error paths, code that ignores existing utilities in the repo, brittle tests, security holes, sloppy naming that bleeds into public APIs. 
This skill reads the PR, reads the surrounding codebase, and gives you the kind of review that hurts a little - on purpose.

Use it before you hit "Approve", or use it on your own PR before opening it.

## Quick example
```text
/pr-review 1234
```

You get back a structured review with a verdict and concrete findings:
```
Verdict: CHANGES REQUESTED

Correctness
  src/orders/checkout.ts:142 - new code path skips inventory lock; concurrent
    checkouts on the same SKU can oversell. Use lockInventory() (already
    used in src/orders/reserve.ts:88).

Testing
  tests/checkout.test.ts - all new tests use the happy path. No coverage
    for the failure mode introduced in src/orders/checkout.ts:174.

Naming
  CheckoutResult.ok is a boolean named like a status. Rename to `succeeded`
  or replace with a discriminated union to match Result<T> elsewhere in
  the codebase.

Nits
  src/utils/format.ts:12 - duplicate of formatCurrency() in src/lib/money.ts.
```

You can steer the review with extra context:
```text
/pr-review 1234 focus on security and backward compatibility
/pr-review feat/add-new-api this area is performance-sensitive
```

## Setup
You need:
- `gh` (the GitHub CLI), installed and authenticated against the right account (`gh auth status` should show a green check).
- A local clone of the repo, checked out on either the source or target branch of the PR. The skill reads file contents from your working tree for full context.

## Installation
```bash
./install.sh pr-review
```

## Usage
Basic shape:
```text
/pr-review <pr-number|branch-name|HEAD> [additional context]
```

The first argument picks the PR. Everything after it is optional steering for the review.

Examples:
```text
/pr-review 1234
/pr-review feat/add-new-api
/pr-review HEAD
/pr-review 1234 focus on security and backward compatibility
/pr-review feat/add-new-api already caused regressions before, look hard
```

Multiline context works too:
```text
/pr-review HEAD focus on API compatibility
pay extra attention to auth and caching changes
ignore cosmetic naming nits unless they affect clarity
```

Notes on the input:
- **PR number** - any open or closed PR in the repo (`1234`).
- **Branch name** - the source branch of the PR (`feat/add-new-api`); skill resolves it to the PR.
- **`HEAD`** - reviews the PR for whatever branch you're currently checked out on. If no PR is open for that branch, the skill errors.
- **Local checkout matters** - if your working tree is on an old commit of the source branch, the review may reference stale code. Pull first.

## What happens when you run it
1. The skill resolves your argument to a PR via `gh`, then fetches the PR metadata and the full diff.
2. It reads every file changed in the PR in full from your local working tree - not just the diff hunks - so context around the changes is real.
3. It explores the broader codebase for related patterns, utilities, and conventions, so the review can flag things like "this duplicates a function that already exists at X".
4. Any extra context you passed shapes emphasis (security, performance, backward compatibility, etc.).
5. It produces a structured review covering: correctness, security, performance, architecture, code reuse, testing, naming, API design, and dependencies.
6. It ends with a verdict: `REJECT` / `CHANGES REQUESTED` / `APPROVE WITH NITS` / `APPROVE`.

## Notes
- The review is harsh by design. It simulates a senior staff engineer who knows the codebase and refuses to wave anything through.
- The output is yours to read - it is **not** posted to GitHub. You decide what to act on.
- Nothing in the repo is modified.
