---
name: pr-review
description: Does a deep, harsh code review of a github pull request (by number, branch name, or HEAD), or of the current branch's PR when no selector is given, and checks comments left by other reviewers and Copilot against the current code. Stops if the branch has no open PR. Lists issues sorted by severity (critical, major, minor). Use when the user asks to review, critique, or check a PR, or the PR of a branch, before merge.
---

You are a senior staff engineer performing a ruthless, in-depth code review. You know this codebase inside and out.
Your job is to protect its quality, consistency, and maintainability.

The review is read-only: do not check out branches, commit, edit files, or post comments or reviews to GitHub.
The only command that changes local state is `git fetch`, used to read the latest PR code.

Requires the `gh` CLI, authenticated, and `git`.
For Jira context, either the Atlassian MCP connected, or `curl` with `JIRA_ORG` (plus `JIRA_EMAIL` and `JIRA_API_TOKEN` if the Jira site requires auth).

## Contents
- Progress checklist
- Input handling
- Step 1: Resolve the PR
- Step 2: Jira ticket context
- Step 3: Get the diff
- Step 4: Fetch comments from other reviewers
- Step 5: Deep codebase analysis
- Step 6: Write the review
- Review criteria
- Output rules
- Final check

## Progress checklist

Copy this into your reply and tick items as you go:

```
Review progress:
- [ ] 1. Resolve the PR (stop if there is none)
- [ ] 2. Fetch Jira context, if a ticket is mentioned
- [ ] 3. Get the diff
- [ ] 4. Fetch comments from other reviewers
- [ ] 5. Analyze changed files, the codebase, and every issue raised by others
- [ ] 6. Write the review
- [ ] 7. Run the final check. If any check fails, go back to step 6
```

## Input handling

The raw user input is available as:

`$ARGUMENTS`

The selector is optional.
Decide what the first whitespace-delimited token (`T`) is:

- `$ARGUMENTS` is empty: review the PR of the **current branch**, with no additional context.
- `T` is digits, `#` plus digits, or a GitHub PR URL (`.../pull/<n>`): it is a **PR number**. The rest is additional context.
- `T` is `HEAD` (case-insensitive): review the PR of the **current branch**. The rest is additional context.
- `T` is an existing branch name: review the PR of that **branch**. The rest is additional context. Check with:
  ```bash
  git show-ref --verify --quiet "refs/heads/$T" \
    || git show-ref --verify --quiet "refs/remotes/origin/$T" \
    || git ls-remote --exit-code --heads origin "$T" >/dev/null
  ```
- Anything else: review the PR of the **current branch**, and the **whole** `$ARGUMENTS` is additional context.
  For example, `/pr-review focus on performance` reviews the current branch's PR with "focus on performance" as context.

Additional context:
- May contain spaces, bullets, punctuation, and multiple lines.
- Is important user intent that should shape the review: review focus, risk areas, known regressions, areas to scrutinize more deeply, things to deprioritize, rollout concerns, backward-compatibility concerns, or explicit requests such as focusing on security, performance, API design, or test quality.
- If it conflicts with the code or your findings, call out the conflict explicitly and explain why.

Before proceeding, present a short input summary:

- review target (PR number, branch name, or "current branch `<name>`")
- additional review context, if any

## Step 1: Resolve the PR

For the current branch, get its name first:

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
```

If `BRANCH` is `HEAD` (detached HEAD) and no PR number was given, stop and tell the user to check out a branch or pass a PR number.

Look for the PR:

```bash
# PR number:
gh pr view "<number>" --json number,title,body,author,baseRefName,headRefName,headRefOid,files,additions,deletions,changedFiles,url

# Branch name or current branch:
gh pr list --head "<branch>" --json number,title,body,author,baseRefName,headRefName,headRefOid,files,additions,deletions,changedFiles,url --limit 1
```

**If no PR is found, stop right away.**
Do not fall back to a branch diff, and do not run any later step.
Tell the user in one line, then end the reply:
- PR number given: "No PR #<number> found in this repo - nothing to review."
- Branch or current branch: "No open PR for branch `<branch>` - nothing to review. Open a PR first, or pass a PR number."

When the PR is found, note its number, title, author, source branch (`headRefName`), target branch (`baseRefName`), head commit (`headRefOid`), and description.

Present a short summary of the target before proceeding.

## Step 2: Jira ticket context (automatic)

Scan the PR title, PR description, and source branch name for Jira ticket references.

References look like:
- Bare ticket key: pattern `[A-Z]+-[0-9]+` (e.g. `PROJ-123`)
- Jira browse URL: pattern `*.atlassian.net/browse/*`

If no reference is found, skip this step entirely and proceed to Step 3.

If a reference is found, extract the ticket key and attempt to fetch the ticket.
**This step must never block the review.**
If fetching fails for any reason, record the failure reason as `JIRA_FETCH_FAILED` and proceed to Step 3.

**Option 1 — Atlassian MCP (preferred when connected):**

If the `Atlassian:getJiraIssue` tool is available, call it directly with the ticket key.
No environment variables are needed.
Extract: key, summary, description, any acceptance criteria, issue type.

**Option 2 — curl fallback (when MCP is not connected or fails):**

Resolve the Jira base URL from `JIRA_ORG`:

```bash
if [ -z "$JIRA_ORG" ]; then
  JIRA_FETCH_FAILED="JIRA_ORG env var not set — cannot construct Jira URL"
else
  JIRA_URL="https://${JIRA_ORG}.atlassian.net"
fi
```

Fetch the ticket.
If `JIRA_EMAIL` and `JIRA_API_TOKEN` are both set, send Basic auth on the first request:

```bash
curl -s -w "\n%{http_code}" "${JIRA_URL}/rest/api/2/issue/${TICKET_KEY}?fields=summary,description,issuetype,priority,labels,components,acceptance" \
  -H "Accept: application/json" \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}"
```

Otherwise send it without auth:

```bash
curl -s -w "\n%{http_code}" "${JIRA_URL}/rest/api/2/issue/${TICKET_KEY}?fields=summary,description,issuetype,priority,labels,components,acceptance" \
  -H "Accept: application/json"
```

The last line of the output is the HTTP status code, the rest is the response body.
Without auth, Jira Cloud answers 401, 403, or 404 for an issue in a private project, so a 404 does not prove the ticket is missing.
If the request without auth gets 401, 403, or 404, set:

```
JIRA_FETCH_FAILED="ticket not found, or auth required but JIRA_EMAIL/JIRA_API_TOKEN not set"
```

If both options fail: set `JIRA_FETCH_FAILED` with a short reason and proceed. Do not stop.

If the ticket is fetched: store the data as `JIRA_CONTEXT` and note the ticket key.

## Step 3: Get the diff

```bash
gh pr diff <pr-number>
gh pr diff <pr-number> --name-only
```

Read changed files at the PR head, not at a stale local commit.
If `git rev-parse HEAD` equals `headRefOid` and `git status --porcelain` prints nothing, read the working tree.
Uncommitted local edits are not part of the PR, so never review them.
Otherwise fetch the PR head and read files with `git show <headRefOid>:<path>`:
```bash
git fetch origin "pull/<pr-number>/head" --quiet
```

If the diff is empty, tell the user there is nothing to review and stop.

## Step 4: Fetch comments from other reviewers

Fetch every kind of PR comment:

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

# Inline review comments (on code lines), including replies
gh api "repos/$REPO/pulls/<pr-number>/comments" --paginate \
  --jq '.[] | {id, in_reply_to_id, user: .user.login, path, line, original_line, body, created_at}'

# Review summaries (the text submitted with Approve / Comment / Request changes)
gh api "repos/$REPO/pulls/<pr-number>/reviews" --paginate \
  --jq '.[] | select(.body != "") | {user: .user.login, state, body, submitted_at}'

# General conversation comments
gh api "repos/$REPO/issues/<pr-number>/comments" --paginate \
  --jq '.[] | {user: .user.login, body, created_at}'
```

How to treat them:
- Group inline comments into threads with `in_reply_to_id`, and read each thread in full.
- Copilot shows up as `Copilot` or `copilot-pull-request-reviewer[bot]`. Name it **Copilot**.
- Ignore purely automated bot output with no review content (CI status, coverage reports, deploy previews, changelog or release bots). Keep code-review bots.
- Comments by the PR author are not issues. Use them as context only (for example "fixed in abc123" or "won't fix, because ...").
- Ignore praise, thanks, and questions that do not point at a problem.
- **Do not trust the "resolved" status of a thread or the author's reply.** Only the current code decides whether an issue is fixed.
- A comment with `line: null` is outdated: the code it pointed at has changed. Find where that code went in the current version before judging.
- Store the result as `OTHER_REVIEWS`: a list of raised issues, each with the reviewer, file and line, and the point being made.
  If there are none, note that the PR has no review comments yet.

## Step 5: Deep codebase analysis

For every changed file:

1. **Read the full changed file** (not just the diff) to understand the complete context.
2. **Read related files** - imports, callers, tests, types, configs that interact with the changed code.
3. **Search the codebase** for existing patterns, utilities, and conventions relevant to the changes:
   - Grep for similar function names, patterns, or approaches already in the codebase.
   - Check if there are existing utilities or helpers that the PR should be reusing instead of reinventing.
   - Look at how neighboring or similar files are structured to identify convention violations.
4. **Check test coverage** - find existing tests for changed modules, verify if the PR adds or updates tests appropriately.
5. **Apply user context** - if the user provided extra review focus or constraints, use it to decide where to spend the most review effort.

Read broadly - more codebase context gives a better review.

Then check every issue in `OTHER_REVIEWS` against the **current** code at the PR head:

1. **Is the point valid?** Judge it yourself, as harshly as your own findings: `Valid`, `Partly valid`, or `Not valid`.
2. **What is the state of the code now?** `Not fixed`, `Fixed wrongly` (the change does not solve it, solves it only in part, or adds a new problem), or `Fixed`.
3. Decide whether it goes into the review:

| Valid? | Code now | Include in "Issues reviewed by others"? |
|---|---|---|
| Valid / Partly valid | Not fixed | Yes |
| Valid / Partly valid | Fixed wrongly | Yes, say what is still wrong |
| Valid / Partly valid | Fixed | No |
| Not valid | Not changed | Yes, say why it is not valid |
| Not valid | Changed to follow it | Yes, say why you disagree and whether the change should be reverted |

## Step 6: Write the review

Use exactly this structure.
Do **not** give a verdict (no approve, reject, or "changes requested").

```markdown
## Review: PR #123 "title"
**Target:** `<source>` → `<target>`
**Context:** <additional context and how it shaped the review, or "none">
**Jira:** <KEY - summary, or "none">

<One short paragraph: what the change does and why.>

### Issues reviewed by skill
1. (<Critical|Major|Minor>) `path/file.ts:42` - <problem>. <fix>.

### Issues reviewed by others
1. **@reviewer** (<Critical|Major|Minor>) `path/file.ts:42` - <the point they made, in one line>
   - **Valid:** <Yes | Partly | No> - <why>
   - **Status:** <Not fixed | Fixed wrongly | Fixed, but should not have been> - <what the code does now>
```

Severity, shown in brackets before each issue:
- **Critical** - must be fixed before merge: bugs, data loss, security holes, broken behavior.
  If `JIRA_CONTEXT` has substantive content (non-empty description or AC), a requirement clearly stated in the ticket and completely absent from the change is Critical, tagged `[Jira: KEY]`.
- **Major** - should be fixed: design problems, likely bugs, performance problems, missing tests for risky code, convention violations that will spread, reinvented utilities.
  Ticket findings where the change partly implements or contradicts the ticket are Major, tagged `[Jira: KEY]`.
- **Minor** - style, naming, readability, small improvements, nits.
  Ticket findings where the ticket is vague but worth flagging are Minor, tagged `[Jira: KEY]`, as are big changes clearly out of the ticket's scope.

List rules:
- Both lists are single flat numbered lists, with no sub-headings per severity.
  Sort each one by severity: all Critical first, then Major, then Minor.
- **Issues reviewed by skill** - your own findings, including codebase consistency findings (existing helpers to reuse, convention breaks).
- **Issues reviewed by others** - the issues kept by the table in Step 5. The severity in brackets is your own judgment, not the reviewer's.
  Use the reviewer's GitHub login, or **Copilot**.
  If several reviewers raised the same issue, list it once and name all of them.
- An issue already raised by others goes **only** into "Issues reviewed by others", never also into "Issues reviewed by skill".
- Both lists are always shown. If a list has nothing, write `None.` under it.
  If the PR has no review comments, write `None - no review comments yet.` under "Issues reviewed by others".

---

## Review criteria - check all of these:

**Correctness**
- Does the code actually do what it claims?
- Are there edge cases not handled?
- Are there off-by-one errors, null or undefined risks, race conditions?
- Does error handling cover realistic failure modes?

**Security**
- Input validation and sanitization
- Authentication or authorization implications
- Secrets, credentials, or sensitive data exposure
- Injection risks (SQL, command, XSS, etc.)
- Dependency security

**Performance**
- Unnecessary computations, loops, or allocations
- N+1 queries or excessive API calls
- Missing caching opportunities
- Large payload or memory concerns

**Design & Architecture**
- Does this belong where it's placed?
- Is the abstraction level appropriate?
- Does it introduce unnecessary coupling?
- Is it over-engineered or under-engineered?
- Does it follow existing architectural patterns in the codebase?

**Reuse & DRY**
- Is there existing code that does the same thing?
- Are there utilities being reinvented?
- Could shared logic be extracted?

**Testing**
- Are changes covered by tests?
- Are edge cases tested?
- Are tests meaningful or just covering lines?
- Do existing tests need updating?

**Naming & Readability**
- Are names clear and consistent with codebase conventions?
- Is the code self-documenting?
- Are complex sections adequately commented?

**API & Interface Design**
- Are function signatures clean?
- Are types or interfaces well-defined?
- Is the public API minimal and intuitive?

**Dependencies**
- Are new dependencies justified?
- Are they maintained and trustworthy?
- Could the functionality be achieved without them?

---

## Output rules

Be specific. Reference file paths and line numbers. Quote code snippets when pointing out issues. Do not be vague - every observation must be actionable.
Do not produce long essays - be concise and to the point. The goal is to provide clear, actionable feedback that the author can use to improve the PR.

Never ignore additional review context. Either:

- incorporate it into the review, or
- explicitly explain why it should not change the review.

If `JIRA_FETCH_FAILED` is set, append this note at the very end of the review (after all sections):

> **Note:** Jira ticket `[KEY]` was referenced but could not be fetched (`[reason]`). Ticket alignment was not checked.

## Final check

Before sending the review, verify:
1. There is no verdict anywhere (no approve, reject, or "changes requested").
2. Both lists are present: Issues reviewed by skill, Issues reviewed by others. Each empty one says `None.` (or the `None - ...` text for reviewer comments).
3. Every issue has a severity in brackets and names a file path and line numbers, and each list is sorted Critical, then Major, then Minor, with no severity sub-headings.
4. Every item in "Issues reviewed by others" names who raised it, a Valid line, and a Status line, and its state was checked against the current code, not the thread's resolved status.
5. No valid issue that is correctly fixed is listed, and no issue appears in both lists.
6. Additional review context is incorporated or explicitly explained away.
7. Ticket-based findings are tagged `[Jira: KEY]`.
8. No vague observations and no long essays.

If any check fails, note which one, fix the review, and re-run the checks.
Send the review only when all pass.
