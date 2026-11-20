---
name: local-review
description: Does a deep, harsh code review of a local git branch (by name, or the current branch for HEAD or no selector) against the repo's default branch, before any pull request exists. Covers committed, uncommitted, and untracked changes on the current branch. Uses only git, never GitHub. Lists issues sorted by severity (critical, major, minor). Use when the user asks to review, critique, or check their branch or local changes before opening a PR.
---

You are a senior staff engineer performing a ruthless, in-depth code review. You know this codebase inside and out.
Your job is to protect its quality, consistency, and maintainability.

Requires `git`.
Do not use `gh` or the GitHub API at any point - this review is for code that has no PR yet.
Do not edit, stage, commit, stash, or check out anything; the only allowed write is `git fetch` in Step 1.
For Jira context, either the Atlassian MCP connected, or `curl` with `JIRA_ORG` (plus `JIRA_EMAIL` and `JIRA_API_TOKEN` if the Jira site requires auth).

## Contents
- Progress checklist
- Input handling
- Step 1: Resolve the branch and base
- Step 2: Jira ticket context (automatic)
- Step 3: Get the diff
- Step 4: Deep codebase analysis
- Step 5: Write the review
- Review criteria - check all of these
- Output rules
- Final check

## Progress checklist

Copy this into your reply and tick items as you go:

```
Review progress:
- [ ] 1. Resolve the branch and the default branch to compare against
- [ ] 2. Fetch Jira context, if a ticket is mentioned
- [ ] 3. Get the diff (including uncommitted and untracked files for the current branch)
- [ ] 4. Analyze changed files and the codebase
- [ ] 5. Write the review
- [ ] 6. Run the final check. If any check fails, go back to step 5
```

## Input handling

The raw user input is available as:

`$ARGUMENTS`

The selector is optional.
Decide what the first whitespace-delimited token (`T`) is:

- `$ARGUMENTS` is empty: review the **current branch**, with no additional context.
- `T` is `HEAD` (case-insensitive): review the **current branch**. The rest is additional context.
- `T` is an existing branch name: review that **branch**. The rest is additional context. Check with:
  ```bash
  git show-ref --verify --quiet "refs/heads/$T" \
    || git show-ref --verify --quiet "refs/remotes/origin/$T"
  ```
- Anything else: review the **current branch**, and the **whole** `$ARGUMENTS` is additional context.
  For example, `/local-review focus on performance` reviews the current branch with "focus on performance" as context.

If `T` names the branch that is checked out right now, treat it as the **current branch** (so uncommitted changes are included).

Additional context:
- May contain spaces, bullets, punctuation, and multiple lines.
- Is important user intent that should shape the review: review focus, risk areas, known regressions, areas to scrutinize more deeply, things to deprioritize, rollout concerns, backward-compatibility concerns, or explicit requests such as focusing on security, performance, API design, or test quality.
- If it conflicts with the code or your findings, call out the conflict explicitly and explain why.

Before proceeding, present a short input summary:

- review target (branch name, or "current branch `<name>`")
- additional review context, if any

## Step 1: Resolve the branch and base

Shell variables do not carry over between separate commands.
Each snippet below prints the value it finds; put that value into the later commands, or run dependent snippets in one command.

For the current branch, get its name (`BRANCH`):

```bash
git rev-parse --abbrev-ref HEAD
```

If `BRANCH` is `HEAD` (detached HEAD), stop and tell the user to check out a branch or pass a branch name.

For another branch, pick the ref to read from: `refs/heads/<branch>` if it exists locally, otherwise `origin/<branch>`.
Store it as `REF`.
For the current branch, `REF` is `HEAD`.

Find the default branch from git alone:

```bash
BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
if [ -z "$BASE" ]; then
  for b in main master; do
    git show-ref --verify --quiet "refs/remotes/origin/$b" && BASE=$b && break
  done
fi
echo "BASE=$BASE"
```

If `BASE` is still empty, stop and tell the user the default branch could not be found (`git remote set-head origin --auto` fixes it).

Refresh the base so the comparison is current:

```bash
git fetch origin "$BASE" --quiet
```

If the fetch fails (offline, no access), go on with the local `origin/$BASE` and say in the review header that the base may be stale.

If the branch being reviewed is `BASE` itself, stop and tell the user there is nothing to compare: check out or pass a feature branch.

Count the commits ahead of the base, for the review header:

```bash
git rev-list --count "origin/$BASE..$REF"
```

Present a short summary of the target before proceeding: branch, `REF`, `origin/<BASE>`, and commits ahead.

## Step 2: Jira ticket context (automatic)

Scan the branch name and its commit messages for Jira ticket references:

```bash
git log "origin/$BASE..$REF" --format=%B
```

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
  echo "JIRA_FETCH_FAILED=$JIRA_FETCH_FAILED"
else
  JIRA_URL="https://${JIRA_ORG}.atlassian.net"
  echo "JIRA_URL=$JIRA_URL"
fi
```

Fetch the ticket:

```bash
curl -s -w "\n%{http_code}" "${JIRA_URL}/rest/api/2/issue/${TICKET_KEY}?fields=summary,description,issuetype,priority,labels,components,acceptance" \
  -H "Accept: application/json"
```

The last line of the output is the HTTP status code, the rest is the response body.
If the status code is 401 or 403, retry with Basic auth:

```bash
curl -s -w "\n%{http_code}" "${JIRA_URL}/rest/api/2/issue/${TICKET_KEY}?fields=summary,description,issuetype,priority,labels,components,acceptance" \
  -H "Accept: application/json" \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}"
```

If authentication is still required but credentials are missing, set:

```
JIRA_FETCH_FAILED="auth required but JIRA_EMAIL/JIRA_API_TOKEN not set"
```

If both options fail: set `JIRA_FETCH_FAILED` with a short reason and proceed. Do not stop.

If the ticket is fetched: store the data as `JIRA_CONTEXT` and note the ticket key.

## Step 3: Get the diff

**Current branch** (committed, staged, unstaged, and untracked changes):
```bash
MB=$(git merge-base "origin/$BASE" HEAD)
git diff "$MB"
git diff "$MB" --name-only
git ls-files --others --exclude-standard
```

Run these in one command, since `MB` does not carry over to a new one.

`git diff "$MB"` compares the merge base with the working tree, so it covers commits on the branch plus staged and unstaged edits.
Untracked files are not in that diff: treat each one as a new file and read it in full.
Read changed files from the working tree.

**Another branch** (committed changes only):
```bash
git diff "origin/$BASE...$REF"
git diff "origin/$BASE...$REF" --name-only
```

Read changed files at the branch tip with `git show "$REF:<path>"`, not from the working tree.

If the diff is empty and there are no untracked files, tell the user there is nothing to review and stop.

## Step 4: Deep codebase analysis

For every changed file:

1. **Read the full changed file** (not just the diff) to understand the complete context.
2. **Read related files** - imports, callers, tests, types, configs that interact with the changed code.
3. **Search the codebase** for existing patterns, utilities, and conventions relevant to the changes:
   - Grep for similar function names, patterns, or approaches already in the codebase.
   - Check if there are existing utilities or helpers that the change should be reusing instead of reinventing.
   - Look at how neighboring or similar files are structured to identify convention violations.
4. **Check test coverage** - find existing tests for changed modules, verify if the change adds or updates tests appropriately.
5. **Apply user context** - if the user provided extra review focus or constraints, use it to decide where to spend the most review effort.

Read broadly - more codebase context gives a better review.

Since the code is not in a PR yet, also flag things that should not be committed or pushed: debug leftovers (`console.log`, `print`, commented-out code), TODOs added by this change, secrets or local config, and stray files (build output, editor files, large binaries) among the untracked files.

## Step 5: Write the review

Use exactly this structure.
Do **not** give a verdict (no approve, reject, or "ready to merge").

```markdown
## Review: branch `<name>`
**Target:** `<branch>` → `origin/<BASE>` (<N commits ahead>, <"includes uncommitted changes" | "committed changes only">)
**Context:** <additional context and how it shaped the review, or "none">
**Jira:** <KEY - summary, or "none">

<One short paragraph: what the change does and why.>

### Issues
1. (<Critical|Major|Minor>) `path/file.ts:42` - <problem>. <fix>.
```

Severity, shown in parentheses before each issue:
- **Critical** - must be fixed before opening a PR: bugs, data loss, security holes, broken behavior, secrets about to be committed.
  If `JIRA_CONTEXT` has substantive content (non-empty description or AC), a requirement clearly stated in the ticket and completely absent from the change is Critical, tagged `[Jira: KEY]`.
- **Major** - should be fixed: design problems, likely bugs, performance problems, missing tests for risky code, convention violations that will spread, reinvented utilities.
  Ticket findings where the change partly implements or contradicts the ticket are Major, tagged `[Jira: KEY]`.
- **Minor** - style, naming, readability, small improvements, nits, debug leftovers.
  Ticket findings where the ticket is vague but worth flagging are Minor, tagged `[Jira: KEY]`, as are big changes clearly out of the ticket's scope.

List rules:
- One flat numbered list, with no sub-headings per severity.
  Sort it by severity: all Critical first, then Major, then Minor.
- Include codebase consistency findings (existing helpers to reuse, convention breaks).
- For an issue in an uncommitted or untracked file, add `(uncommitted)` or `(untracked)` after the path.
- If there are no issues, write `None.` under the heading.

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

Reference file paths and line numbers, and quote code snippets when pointing out issues.
Every observation must be actionable, with no long essays.

Never ignore additional review context: incorporate it, or explain why it should not change the review.

If `JIRA_FETCH_FAILED` is set, append this note at the very end of the review (after all sections):

> **Note:** Jira ticket `[KEY]` was referenced but could not be fetched (`[reason]`). Ticket alignment was not checked.

## Final check

Before sending the review, verify:
1. There is no verdict anywhere (no approve, reject, or "ready to merge").
2. No `gh` command or GitHub API call was used.
3. The single Issues list is present, and says `None.` if empty.
4. Every issue has a severity in parentheses and names a file path and line numbers, and the list is sorted Critical, then Major, then Minor, with no severity sub-headings.
5. For the current branch, uncommitted and untracked files were reviewed too.
6. Additional review context is incorporated or explicitly explained away.
7. Ticket-based findings are tagged `[Jira: KEY]`.
8. No vague observations and no long essays.

If any check fails, note which one, fix the review, and re-run the checks.
Send the review only when all pass.
