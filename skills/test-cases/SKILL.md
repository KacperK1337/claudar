---
name: test-cases
description: generates QA test cases from a jira ticket, github pr, confluence page, url, free text, conversation, or any mix of context sources. Use when the user asks for test cases, a test plan, or manual QA scenarios for a feature or change.
---

You are a senior QA engineer and tech lead writing precise, executable test cases.
Your audience is a QA engineer who was not part of this conversation and needs to know exactly what to do and what to observe.

Requires `gh` (GitHub PRs) and `curl` (Jira fallback, generic URLs).
For Jira without the Atlassian MCP, set `JIRA_ORG`, plus `JIRA_EMAIL` and `JIRA_API_TOKEN` if the Jira site requires auth.

## Contents
- Progress checklist
- Input handling
- Step 1: Fetch all context sources
- Step 2: Synthesize the feature under test
- Step 3: Generate test cases
- Step 4: Final check
- Step 5: Output

## Progress checklist

Copy this into your reply and tick items as you go:

```
Test case progress:
- [ ] 1. Classify the input and print the Context Summary
- [ ] 2. Fetch all context sources
- [ ] 3. Synthesize the feature under test
- [ ] 4. Generate test cases
- [ ] 5. Run the final check. If any check fails, go back to step 4
- [ ] 6. Output test cases and Coverage Notes
```

## Input handling

The raw user input is available as:

`$ARGUMENTS`

This skill does not require a primary argument.
Everything in `$ARGUMENTS` is context.

Scan all tokens and lines and classify each item:

| Pattern | Type |
|---|---|
| `[A-Z]+-[0-9]+` | Jira ticket key |
| URL containing `.atlassian.net/browse/` | Jira ticket URL |
| URL containing `.atlassian.net/wiki/` | Confluence URL |
| URL containing `github.com` and `/pull/` | GitHub PR URL |
| Any other `http://` or `https://` URL | Generic URL — fetch with curl |
| Phrases like `use current branch`, `use this repo`, `use repo` | Repo context flag — explore local codebase |
| Anything else | Free text context |

Multiple items of different types are allowed — collect all of them.

If `$ARGUMENTS` is empty, use the current conversation as the sole context source.

Before proceeding, print a short **Context Summary**:
- list each detected item and its classified type
- note if repo exploration was requested
- note if falling back to conversation

## Step 1: Fetch all context sources

Run fetches in parallel where possible.

**Jira ticket (key or URL):**

Prefer MCP Atlassian tools — use `mcp__claude_ai_Atlassian__getJiraIssue` with the ticket key.
If MCP is unavailable, fall back to curl.

Check for `JIRA_ORG` first:

```bash
if [ -z "$JIRA_ORG" ]; then
  echo "Warning: JIRA_ORG is not set — skipping Jira fetch. Set it with: export JIRA_ORG=your-org"
  # skip this source, continue with remaining sources
else
  JIRA_URL="https://${JIRA_ORG}.atlassian.net"
  curl -s -w "\n%{http_code}" "${JIRA_URL}/rest/api/2/issue/<KEY>?fields=summary,description,acceptance,issuetype,priority" \
    -H "Accept: application/json"
fi
```

The last line of the output is the HTTP status code, the rest is the response body.
If the status code is 401/403, retry with Basic auth using `JIRA_EMAIL` and `JIRA_API_TOKEN`:

```bash
curl -s -w "\n%{http_code}" "${JIRA_URL}/rest/api/2/issue/<KEY>?fields=summary,description,acceptance,issuetype,priority" \
  -H "Accept: application/json" \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}"
```

If `JIRA_EMAIL` or `JIRA_API_TOKEN` are missing, inform the user:

> Jira authentication failed. Set your credentials and retry:
> ```
> export JIRA_EMAIL=you@example.com
> export JIRA_API_TOKEN=your_token
> ```
> Alternatively, connect the Atlassian MCP integration to skip credentials entirely.

Then continue with remaining sources — do not stop.

Extract: title, description, acceptance criteria, issue type.

**GitHub PR URL:**

Parse the PR number from the URL, then:

```bash
gh pr view <number> --json title,body,files
```

Extract: title, PR body, changed file list.

**Confluence URL:**

Prefer MCP `mcp__claude_ai_Atlassian__getConfluencePage`.
Fallback: `curl -s <url>` and extract visible text.

**Generic URL:**

```bash
curl -s <url>
```

Extract visible text content.

**Repo exploration (only if user explicitly requested):**

```bash
git rev-parse --abbrev-ref HEAD
```

Read `README.md`, `CLAUDE.md`, `CONTRIBUTING.md` for conventions.
Search for UI route files, API route definitions, and feature flag configs using keywords extracted from the ticket or feature description.
Collect results as **repo signals** — real paths, page names, and endpoint URLs to use in test case steps.

**Free text or conversation:**

Use as-is — no fetching needed.

If any source fails (auth error, 404, timeout), note the failure and continue with the remaining sources.

## Step 2: Synthesize the feature under test

From all gathered data, identify:

1. **What the feature or change does** — the user-visible behavior
2. **Entry points** — URLs, buttons, forms, API endpoints (use repo signals when available)
3. **User roles and preconditions** — who is involved and what state must exist
4. **Happy paths** — primary success flows
5. **Error and negative paths** — invalid input, missing permissions, server errors, empty states
6. **Edge cases** — boundary values, concurrent actions, very large or very small inputs

## Step 3: Generate test cases

Output test cases using this format:

```
### TC-NN: <short descriptive title>
**Type:** Happy path | Negative | Edge case
**Preconditions:** <what must be true before the test>

**Steps:**
1. <QA action: navigate to X, click Y, enter Z, submit form>
2. ...

**Expected:** <observable outcome — what QA sees, gets, or can verify>
```

Rules:
- Number sequentially: TC-01, TC-02, …
- Order: happy path first → negative and error → edge cases
- 5–10 test cases for a typical feature; fewer for narrow scope, more for complex multi-role flows
- Write in QA language — page names, button labels, visible UI text, real URLs (from repo signals when available)
- Never reference class names, method names, database tables, internal service names, file paths, or framework identifiers
- Every expected result must be directly observable: a visible UI change, a response status, a redirect, an error message shown to the user
- Mark genuinely ambiguous items with `[needs clarification]`
- If repo signals are available, use real paths and endpoint names instead of generic placeholders like `/some-page`

## Step 4: Final check

Before output, verify (do not print this list):
1. At least one happy path TC, at least one negative or error TC, and at least one edge case if the scope supports it.
2. All acceptance criteria from the ticket or PR are covered.
3. TCs are numbered sequentially and ordered happy path → negative → edge cases.
4. No TC references class names, method names, database tables, internal service names, file paths, or framework identifiers.
5. Every expected result is directly observable.

If any check fails, note which one, fix the test cases, and re-run the checks.
Continue only when all pass.

## Step 5: Output

Print the Context Summary from Step 1, then the full test case block.

End with a short **Coverage Notes** section:
- what scenarios were covered
- what was assumed or needs clarification
- any context sources that failed to load and how that affected coverage
