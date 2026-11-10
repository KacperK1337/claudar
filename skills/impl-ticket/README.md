# impl-ticket
Give it a Jira ticket link and it implements the ticket in your current repo.

## Contents
- Why use it
- Quick example
- Setup
- Installation
- Usage
- What happens when you run it
- Safety guarantees

## Why use it
The ticket description is rarely the full story.
The real scope is spread across comments, linked tickets, the parent epic, and Confluence pages, and decisions made in comment number 14 quietly override the description.
This skill reads all of it, works out exactly what is in and out of scope, and then writes the code, tests included, following the patterns your repo already uses.

It also knows when not to code.
Spikes, research, and documentation tickets are not something you can just implement, so for those it stops, changes nothing, and tells you what the ticket really needs.

## Quick example
```text
/impl-ticket https://mycompany.atlassian.net/browse/ABC-4221
```

First you get the scope it worked out:
```
ABC-4221 - Reject orders with negative discount totals   [Bug, In Progress]

In scope
- Reject orders whose discount total is below 0 with a 400 response

Out of scope
- UI error message - handled in ABC-4230

Acceptance criteria
- Order with discount total -5 is rejected with 400
- Order with discount total 0 is accepted

Decisions from comments and links
- Use the existing OrderValidationError, no new error type (tech lead, 2026-10-02)
```

Then it implements the change, runs the tests, and reports:
```
ABC-4221 - Reject orders with negative discount totals
Branch: ABC-4221

What changed
- src/orders/validate.ts: added negative discount guard next to validateLineItems()
- tests/orders/validate.test.ts: regression tests for -5 and 0

Acceptance criteria
- [x] Order with discount total -5 is rejected with 400 - validate.test.ts "rejects negative discount"
- [x] Order with discount total 0 is accepted - validate.test.ts "accepts zero discount"

Verification
- npm test -- orders: passed
- npm run lint: passed
- Regression test fails without the fix: yes

Review
- no issues found
```

For a spike it stops instead:
```
ABC-4300 - Investigate moving order exports to a queue
Type: Spike -> classified as spike

This ticket is not work that can be just implemented.
It needs more abstract processing: compare queue options and write up a recommendation.
```

## Setup
You need `git`, plus one way to reach Jira.

If you have the Atlassian MCP integration connected in Claude Code, nothing else is needed - the skill uses it automatically.

If you don't have the MCP, the skill falls back to the Jira REST API with `curl`.
The Jira site is taken from the ticket link, so set only the credentials if your Jira requires auth:
```bash
export JIRA_EMAIL="you@company.com"
export JIRA_API_TOKEN="your-token"   # create at https://id.atlassian.com/manage-profile/security/api-tokens
export JIRA_ORG="mycompany"          # only if you pass a bare key instead of a link
```

## Installation
```bash
./install.sh impl-ticket
```

## Usage
Basic shape:
```text
/impl-ticket <ticket-link> [extra info]
```

The first argument is the Jira ticket link (a bare key like `ABC-4221` also works).
Everything after it is optional extra info about how you want it done.
When extra info conflicts with the ticket, your extra info wins and the conflict is called out in the report.

Examples:
```text
/impl-ticket https://mycompany.atlassian.net/browse/ABC-4221
/impl-ticket https://mycompany.atlassian.net/browse/PROJ-100 backend only, keep the API backward compatible
/impl-ticket https://mycompany.atlassian.net/browse/API-77 reuse the retry helper from src/http/retry.ts
/impl-ticket https://mycompany.atlassian.net/browse/DOC-12 update the README section on auth with what the ticket says
```

Multiline extra info works too:
```text
/impl-ticket https://mycompany.atlassian.net/browse/ABC-4221
no schema changes
there is a partial attempt in branch feat/old-discount, do not reuse it
```

## What happens when you run it
1. It reads the ticket through the Atlassian MCP (or the Jira REST API when the MCP is not connected): description, acceptance criteria, all comments (every page), the parent, subtasks, linked tickets that block or duplicate it (plus loosely related ones only when they touch the scope), and linked Confluence pages.
2. It classifies the work.
   For a spike, research, or documentation ticket it stops, changes nothing, and tells you what the ticket needs - unless your extra info says what to do with it.
3. It merges everything into one scope, with later comment decisions winning over the description and work owned by linked tickets left out.
   It shows you the scope and keeps going; it only stops to ask if two readings of the ticket would lead to different code.
4. It checks that the ticket's code lives in this repo, then which branch you are on before creating one, since you may have made it already.
   - Branch name contains the exact ticket key in any case (`ABC-12` does not match `ABC-123`, `abc-123` does), or it is a fresh branch with no commits yet: it stays on it.
   - On the default branch: it fetches it and switches to a branch named exactly after the ticket key (e.g. `ABC-4221`), creating it from the latest remote version if needed.
   - On some other branch with its own commits: it asks you.

   If you have uncommitted changes, it asks before going on.
5. It reads the code the change touches, the patterns around it, and the tests next to it.
6. It implements the scope - nothing more - and adds tests (a regression test for bugs).
   Every new file it creates is added to git with `git add` right away (only its own files, never ignored ones).
7. It runs your tests, lint, type check, and build, and fixes anything its change broke.
8. It reviews its own diff like a strict reviewer: correctness and edge cases, callers of changed code, matching the repo's patterns, and tests that check real behavior.
   For a bug fix it proves the regression test fails without the fix.
   When it can, it also asks a fresh subagent to review the diff.
   Anything found is fixed and checked again.
9. It checks that every acceptance criterion maps to a change and a test and that nothing out of scope slipped in, then reports.

## Safety guarantees
- Nothing is committed, pushed, or opened as a PR.
  The only git writes are fetching and creating or switching to the ticket branch, `git add` for files the skill itself created, and a short `git stash` to prove a regression test fails without the fix.
- Branches are never renamed, deleted, or reset.
- Nothing is written to Jira or Confluence: no comments, no status changes.
- For spike, research, and documentation tickets nothing is changed anywhere unless your extra info says what to do.
- Commands, scripts, or deploys mentioned in the ticket are never run; the ticket only defines the code change.
- If the ticket cannot be fetched, or its code lives in another repo, it stops and says so instead of guessing.
- If tests could not run, the report says so rather than claiming they passed.
