# pr-review
Senior-engineer-grade code review of a GitHub Pull Request or of your current branch.

## Why use it
GitHub's own review UI is fine for spotting typos. 
It doesn't catch the kinds of issues a staff engineer would: subtle correctness bugs, missing error paths, code that ignores existing utilities in the repo, brittle tests, security holes, sloppy naming that bleeds into public APIs. 
This skill reads the PR, reads the surrounding codebase, and gives you the kind of review that hurts a little - on purpose.
It also checks what other reviewers (people and Copilot) already said, and tells you which of their points still stand.

Use it before you hit "Approve", or use it on your own branch before opening a PR.

## Quick example
```text
/pr-review 1234
```

You get back two lists, each sorted by severity (critical first, then major, then minor):
```
### Issues reviewed by skill
1. (Critical) `src/orders/checkout.ts:142` - new code path skips the inventory lock;
   concurrent checkouts on the same SKU can oversell. Use `lockInventory()` (already
   used in `src/orders/reserve.ts:88`).
2. (Major) `tests/checkout.test.ts:20-64` - all new tests cover the happy path only.
   No test for the failure path added in `src/orders/checkout.ts:174`.
3. (Minor) `src/utils/format.ts:12` - duplicate of `formatCurrency()` in `src/lib/money.ts:5`.

### Issues reviewed by others
1. **@jdoe** (Major) `src/orders/checkout.ts:98` - retry loop has no upper bound
   - **Valid:** Yes - a failing payment provider makes the loop spin forever.
   - **Status:** Fixed wrongly - a max of 3 was added, but the counter resets inside the loop.
2. **Copilot** (Minor) `src/orders/types.ts:14` - suggests making `CheckoutResult` an interface
   - **Valid:** No - the rest of the codebase uses `type` for result unions.
   - **Status:** Fixed, but should not have been - revert to `type`.
```

There is no verdict (approve / reject).
You decide what to do with the list.

You can steer the review with extra context:
```text
/pr-review 1234 focus on security and backward compatibility
/pr-review feat/add-new-api this area is performance-sensitive
/pr-review focus on performance
```

## Setup
You need:
- `gh` (the GitHub CLI), installed and authenticated against the right account (`gh auth status` should show a green check).
- `git` and a local clone of the repo. The skill reads file contents from your local clone for full context.

## Installation
```bash
./install.sh pr-review
```

## Usage
Basic shape:
```text
/pr-review [pr-number|branch-name|HEAD] [additional context]
```

The selector is optional.
If the first word is not a PR number, `HEAD`, or an existing branch, the skill reviews your current branch and treats everything you typed as extra context.

Examples:
```text
/pr-review
/pr-review focus on performance
/pr-review 1234
/pr-review feat/add-new-api
/pr-review HEAD
/pr-review 1234 focus on security and backward compatibility
/pr-review feat/add-new-api already caused regressions before, look hard
```

Multiline context works too:
```text
/pr-review focus on API compatibility
pay extra attention to auth and caching changes
ignore cosmetic naming nits unless they affect clarity
```

Notes on the input:
- **Nothing** - reviews the current branch.
- **PR number** - any PR in the repo (`1234`, `#1234`, or the PR URL).
- **Branch name** - a branch that exists locally or on `origin` (`feat/add-new-api`); the skill finds its PR.
- **`HEAD`** - same as nothing: the current branch.
- **No PR for the branch** - the skill does not stop. It reviews the branch against the repo's default branch instead (for the current branch, uncommitted and untracked files are included). There are no reviewer comments to check in this case.

## What happens when you run it
1. The skill resolves your input to a PR, or to a branch when there is no PR, and fetches the metadata and the full diff.
2. If the PR title, description, branch name, or (without a PR) commit messages contain a Jira ticket key (`PROJ-123`) or a Jira browse URL, the skill fetches that ticket and uses it to check the change does what was asked.
Fetch uses the Atlassian MCP integration if connected, otherwise falls back to `curl` with `JIRA_ORG`/`JIRA_EMAIL`/`JIRA_API_TOKEN`.
If the ticket cannot be fetched, the review still goes on and a note is added at the end.
3. For a PR, it fetches all comments: inline code comments with their replies, review summaries, and general conversation comments, from people and from Copilot.
4. It reads every changed file in full at the PR head - not just the diff hunks - so context around the changes is real.
5. It explores the broader codebase for related patterns, utilities, and conventions, so the review can flag things like "this duplicates a function that already exists at X".
6. It checks every issue raised by other reviewers against the current code.
It ignores the "resolved" status of threads, because a thread can be resolved without a real fix.
7. Any extra context you passed shapes emphasis (security, performance, backward compatibility, etc.).
8. It writes the review as two lists: **Issues reviewed by skill** and **Issues reviewed by others**.
Each issue has its severity in brackets (`Critical`, `Major`, or `Minor`), and each list is sorted critical first, then major, then minor.
Empty lists say `None.`.
Ticket-based findings are tagged `[Jira: KEY]`.
9. Before sending, it checks the review (no verdict, both lists present and sorted by severity, file and line references, reviewer issues checked against the code, extra context handled, Jira tags) and fixes it if a check fails.

## Issues reviewed by others
Each issue someone else raised gets the reviewer's name, a severity, whether the point is valid, and what the code does now.
What gets listed:

| Point is | Code now | Listed? |
|---|---|---|
| Valid | Not fixed | Yes |
| Valid | Fixed wrongly or only in part | Yes, with what is still wrong |
| Valid | Fixed | No |
| Not valid | Not changed | Yes, with why it is not valid |
| Not valid | Changed to follow it | Yes, with why the skill disagrees |

Issues already raised by others are not repeated in "Issues reviewed by skill".

## Notes
- The review is harsh by design. It simulates a senior staff engineer who knows the codebase and refuses to wave anything through.
- The output is yours to read - it is **not** posted to GitHub. You decide what to act on.
- Nothing in the repo is modified. The skill may run `git fetch` to read the latest PR code.
