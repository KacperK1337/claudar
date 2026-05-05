# ticket-guide
Turn a Jira ticket into a concrete implementation plan grounded in your actual codebase.

## Why use it
Most Jira tickets describe **what** needs to happen, not **how**. 
Before you can start, you have to read the ticket, hunt through the repo for the right place to make the change, figure out which patterns the codebase already uses, and decide where to add tests.
This skill does all of that for you and hands you a step-by-step plan referencing real files and real functions.

The goal: when you finish implementing the guide, the PR sails through review with zero comments.

## Quick example
```text
/ticket-guide ABC-4221
```

You get back a plan that looks like:
```
Ticket: ABC-4221 - Reject orders with negative discount totals

Plan
  1. Add a guard in src/orders/validate.ts:64 alongside the existing
     validateLineItems() check. Throw OrderValidationError, mirroring
     the pattern at line 81.
  2. Surface the error at the API boundary in src/api/orders.ts:212;
     the existing error mapper already routes OrderValidationError
     to a 400 response - no new wiring needed.
  3. Add a regression test in tests/orders/validate.test.ts mirroring
     the negative-quantity test on line 47.

Patterns to follow
  - Validation lives in src/orders/validate.ts; never in handlers.
  - All thrown validation errors must extend OrderValidationError
    (see src/orders/errors.ts:8).

Gotchas
  - There is a partial implementation in branch feat/discount-fix that
    mutated state instead of rejecting; do not reuse it.
  - Discount totals can legitimately be 0; only negative values are invalid.

Self-review checklist
  - [ ] New test covers exactly the negative-discount path
  - [ ] Error message matches the project style guide
  - [ ] No existing tests modified
```

You can steer the guide with context:
```text
/ticket-guide PROJ-100 only touch backend validation, do not change UI copy
/ticket-guide API-77 customer says release-blocking, preserve backward compatibility
```

## Setup
You need:
- `git` (so the skill can read the current repo).
- `curl` (used to call the Jira REST API).
- `JIRA_ORG` exported - the slug from your Jira URL (`mycompany` for `https://mycompany.atlassian.net`).
- If your Jira requires authentication, also export `JIRA_EMAIL` and `JIRA_API_TOKEN` (create a token at https://id.atlassian.com/manage-profile/security/api-tokens).

```bash
export JIRA_ORG="mycompany"
export JIRA_EMAIL="you@company.com"      # only if Jira needs auth
export JIRA_API_TOKEN="your-token"       # only if Jira needs auth
```

## Installation
```bash
./install.sh ticket-guide
```

## Usage
Basic shape:
```text
/ticket-guide <ticket-key> [additional context]
```

The first argument is the Jira key (e.g. `ABC-4221`).
Everything after it is optional steering for the plan.

Examples:
```text
/ticket-guide ABC-4221
/ticket-guide PROJ-100 only touch backend validation, do not change UI copy
/ticket-guide API-77 customer says release-blocking, preserve backward compatibility
```

Multiline context works too:
```text
/ticket-guide ABC-4221 backend only
avoid schema changes
there is already a partial implementation in branch feat/old-spike
```

## What happens when you run it
1. The skill fetches the ticket from Jira: title, description, acceptance criteria.
2. It scans the current repo on the default branch for relevant patterns, conventions, and existing code that the change should hook into.
3. Any context you passed shapes scope, constraints, or emphasis.
4. It produces a structured guide with: step-by-step plan, files to modify, patterns to follow, testing strategy, gotchas, and a self-review checklist.
5. Every suggestion points at real files, real functions, and real line numbers - no generic "consider adding validation".

## Safety guarantees
- The skill only reads files; it does not modify the repo or open a branch.
- Nothing is posted back to Jira.
- If the ticket is missing or inaccessible, the skill stops and says so - it does not invent ticket content.
- If the codebase doesn't have a clear hook point, the guide says so rather than recommending a generic approach.
