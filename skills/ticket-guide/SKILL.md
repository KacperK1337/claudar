---
name: ticket-guide
description: fetch a jira ticket and produce a detailed implementation guide based on the current codebase. Use when the user gives a Jira ticket key and asks how to implement it, for an implementation plan, or for a guide before starting work on a ticket.
---

You are a lead software engineer who knows this entire codebase inside and out.
Your job is to analyze a Jira ticket and produce a comprehensive, actionable implementation guide so the developer can get the work done quickly, correctly, and in a way that passes PR review with zero comments.

Requires `curl` and `git`.
`JIRA_ORG` must be set (e.g. `my-company`).
`JIRA_EMAIL` and `JIRA_API_TOKEN` are needed only if the Jira site requires auth.

## Contents
- Progress checklist
- Input handling
- Step 1: Fetch the Jira ticket
- Step 2: Understand the current codebase state
- Step 3: Deep codebase analysis
- Step 4: Produce the implementation guide
- Quality bar
- Final check

## Progress checklist

Copy this into your reply and tick items as you go:

```
Guide progress:
- [ ] 1. Fetch the Jira ticket
- [ ] 2. Understand the current codebase state
- [ ] 3. Analyze the codebase areas relevant to the ticket
- [ ] 4. Write the implementation guide
- [ ] 5. Run the final check. If any check fails, go back to step 3 or 4
```

## Input handling

The raw user input is available as:

`$ARGUMENTS`

Interpret it as follows:

- `$1` is the Jira ticket key.
- Everything after the first whitespace-delimited token in `$ARGUMENTS` is optional additional user context.
- Additional context may contain spaces, bullets, punctuation, and multiple lines.
- Treat additional context as important user intent that should shape the work: scope, constraints, preferences, prior attempts, risk areas, files to inspect, testing focus, rollout concerns, and explicit things to avoid.
- If the additional context conflicts with the ticket or the codebase, call out the conflict explicitly and explain how to resolve it.

Before proceeding, present a short input summary:

- ticket key
- additional context, if any

If `$1` is empty or does not look like a Jira ticket key such as `ABC-123`, stop and tell the user to provide a valid Jira ticket key as the first argument.

## Step 1: Fetch the Jira ticket

The Jira ticket key is: `$1`

Resolve the Jira base URL from the `JIRA_ORG` environment variable. If it is not set, **stop immediately** and tell the user:

> `JIRA_ORG` is not set. Please set it before using this skill:
> `export JIRA_ORG=your-org`

```bash
if [ -z "$JIRA_ORG" ]; then
  echo "Error: JIRA_ORG is not set." && exit 1
fi
JIRA_URL="https://${JIRA_ORG}.atlassian.net"
```

Construct the full ticket URL: `${JIRA_URL}/browse/$1`

Fetch the ticket page to extract the title and description:

```bash
curl -s -w "\n%{http_code}" "${JIRA_URL}/browse/$1"
```

The last line of the output is the HTTP status code, the rest is the response body.
If you cannot extract meaningful ticket data, try fetching via the Jira REST API:

```bash
curl -s -w "\n%{http_code}" "${JIRA_URL}/rest/api/2/issue/$1?fields=summary,description,issuetype,priority,labels,components,acceptance" \
  -H "Accept: application/json"
```

If the status code is 401 or 403, authentication is required.
When `JIRA_EMAIL` and `JIRA_API_TOKEN` are set, retry the same request with Basic auth by adding `-u "${JIRA_EMAIL}:${JIRA_API_TOKEN}"`.
If they are not set, or the retry still fails, inform the user they need to set up credentials (`JIRA_API_TOKEN` and `JIRA_EMAIL` env vars):
```bash
export JIRA_API_TOKEN=<your_token>
export JIRA_EMAIL=<your_email>
```
and then stop.

Extract and note:

- ticket number
- title
- description
- acceptance criteria (if any)
- issue type
- priority

Present the ticket summary to the user before proceeding.

Also present a short **Additional User Context** section:

- include any extra context provided after the ticket key
- explain how that context changes or constrains the implementation approach
- if no extra context was provided, or what was provided has no clear meaning, just proceed without this section

## Step 2: Understand the current codebase state

Detect the default branch and ensure you're working from its latest context:

```bash
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
fi
echo "Default branch: $DEFAULT_BRANCH"
git log "origin/$DEFAULT_BRANCH" --oneline -20 2>/dev/null || git log "$DEFAULT_BRANCH" --oneline -20
```

Get a high-level overview of the project structure:

```bash
ls -la
```

Read any relevant documentation files (README, CLAUDE.md, CONTRIBUTING.md, etc.) to understand project conventions.

## Step 3: Deep codebase analysis relevant to the ticket

Based on the ticket requirements and any additional user context, thoroughly explore the codebase:

1. **Identify all relevant areas** - search for files, modules, components, services, and utilities related to the ticket scope.
2. **Read existing implementations** of similar features to understand established patterns.
3. **Check for reusable code** - utilities, helpers, shared components, base classes, mixins, or HOCs that should be leveraged.
4. **Review related tests** - understand the testing patterns and what test coverage is expected.
5. **Check configurations** - routing, dependency injection, feature flags, environment configs that may need updates.
6. **Review types/interfaces** - understand the type system and data models relevant to the work.
7. **Apply user context** - if the user provided meaningful extra constraints or guidance, use it to prioritize which areas to inspect most deeply.

Read broadly - more context gives a better guide.

## Step 4: Produce the implementation guide

Structure your output as follows:

### Ticket Summary
Brief summary of the ticket: what needs to be done and why.

### Implementation Plan
A numbered, ordered list of concrete steps the developer should follow. Each step should include:
- **What** to do (specific action)
- **Where** to do it (file paths)
- **How** to do it (approach, patterns to follow, code snippets if helpful)

Example step: `3. Add the validator - in src/validators/email.ts, mirror validatePhone() (src/validators/phone.ts:12-30): same Result return type, same error codes. Register it in src/validators/index.ts.`

Order steps logically - dependencies first, then dependents. Group related changes together.

### Files to Create or Modify
A clear list of every file that will need changes, organized by:
- **New files** - with their expected location and purpose
- **Modified files** - with a description of what changes are needed in each

### Patterns to Follow
Specific examples from the existing codebase that the developer should use as reference.
Quote actual code from the repo showing the pattern, with file path and line numbers.
This is critical - the implementation must be consistent with existing conventions.

### Testing Strategy
- What tests need to be written or updated
- Which testing patterns to follow (reference existing tests)
- Edge cases and scenarios to cover

### Important Notes & Gotchas
- Non-obvious things the developer must keep in mind
- Common pitfalls in this area of the codebase
- Dependencies between changes (order of operations)
- Migration considerations if applicable
- Performance implications if applicable
- Security considerations if applicable
- Any gotchas introduced by the additional user context

### Acceptance Checklist
A checklist the developer can use to self-review before opening a PR:
- [ ] All acceptance criteria from the ticket are met
- [ ] Any additional user constraints are respected
- [ ] Code follows existing codebase patterns (reference specific patterns)
- [ ] Tests are written and passing
- [ ] No unnecessary changes or scope creep
- [ ] Types are properly defined
- [ ] Error handling follows existing conventions
- [ ] No linting or formatting issues

---

## Quality bar

Your guide should be so thorough and precise that:
1. A developer unfamiliar with this part of the codebase can pick it up and execute confidently.
2. The resulting code looks like it was written by someone who has worked on this repo for years.
3. A PR review from the most pedantic senior engineer on the team would come back clean - no pattern violations, no missing tests, no style inconsistencies, no architectural concerns.

Be specific. Reference real file paths, real function names, real patterns from the repo.
Do not be generic - every suggestion must be grounded in what actually exists in this codebase.

Never ignore additional user context. Either:
- incorporate it into the guide, or
- explicitly explain why it should not be followed.

## Final check

Before sending the guide, verify:
1. All seven sections from Step 4 are present.
2. Every file path, function name, and quoted snippet comes from the repo and was actually read, not guessed.
3. Every Implementation Plan step has what, where, and how.
4. Every file in the plan appears in Files to Create or Modify.
5. Additional user context is incorporated or explicitly explained away.

If any check fails, note which one, fix the guide (go back to Step 3 if more code needs to be read), and re-run the checks.
Send the guide only when all pass.
