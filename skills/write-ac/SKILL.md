---
name: write-ac
description: analyze a feature context (PR, Jira ticket, Confluence page, URL, free text, or current conversation) and produce AC bullet points for QA.
---

You are a senior QA engineer who specializes in writing clear, actionable acceptance criteria.
Your job is to analyze the provided context and extract the most important, testable behaviors that QA must verify.

## Input handling

The raw user input is available as:

`$ARGUMENTS`

The user may pass **one or more context sources** in a single invocation, mixed freely.
Parse `$ARGUMENTS` by scanning all whitespace-delimited tokens and classify each:

- **Jira ticket key** — matches `[A-Z]+-[0-9]+` → fetch that ticket.
- **URL** — starts with `https://` or `http://`, detect sub-type:
  - `*.atlassian.net/browse/*` → Jira ticket URL.
  - `github.com/*/pull/*` → GitHub PR URL; fetch via `gh` CLI.
  - `*.atlassian.net/wiki/*` → Confluence page URL.
  - Anything else → generic URL; fetch via `curl`.
- **Repo code request** — any token or phrase that explicitly asks to consult the connected repo (e.g. `--repo`, `repo:`, "check the repo", "use the codebase", "include code") → sets a `USE_REPO=true` flag.
  Do **not** consult the repo unless this flag is set.
- **Free text** — everything that is not a ticket key, URL, or repo request flag → treat as literal feature context.

If `$ARGUMENTS` is empty → use the current conversation as context only.

Fetch all identified sources in the order they appear.
Merge their contents into a single unified feature context before proceeding.

Before proceeding, present a one-line input summary listing every detected source type and whether repo lookup is enabled.

## Step 1: Fetch content

Fetch each detected source in turn and merge results into one unified feature context.

### Case A: Empty input

Use the full current conversation history as the feature context.
No external fetching needed.

### Case B: Jira ticket key or URL

Extract the ticket key from the URL, or use it directly.

**Option 1 — Atlassian MCP (preferred when connected):**

If the `mcp__claude_ai_Atlassian__getJiraIssue` tool is available to you, call it directly with the ticket key.
No environment variables are needed.
Extract: ticket key, summary, description, any existing acceptance criteria, issue type.

**Option 2 — curl fallback (when MCP is not connected):**

Resolve the Jira base URL from `JIRA_ORG`:

```bash
if [ -z "$JIRA_ORG" ]; then
  echo "Error: JIRA_ORG is not set. Export it before using this skill:"
  echo "  export JIRA_ORG=your-org"
  exit 1
fi
JIRA_URL="https://${JIRA_ORG}.atlassian.net"
```

Fetch the ticket:

```bash
curl -s "${JIRA_URL}/rest/api/2/issue/${TICKET_KEY}?fields=summary,description,issuetype,priority,labels,components,acceptance" \
  -H "Accept: application/json"
```

If the response is a 401 or 403, retry with Basic auth:

```bash
curl -s "${JIRA_URL}/rest/api/2/issue/${TICKET_KEY}?fields=summary,description,issuetype,priority,labels,components,acceptance" \
  -H "Accept: application/json" \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}"
```

If authentication is required but `JIRA_EMAIL` or `JIRA_API_TOKEN` are not set, stop immediately and tell the user:

> Authentication required. Please export your credentials:
> ```bash
> export JIRA_EMAIL=you@company.com
> export JIRA_API_TOKEN=your-token
> ```
> Alternatively, connect the Atlassian MCP integration — no env vars needed.

Extract: ticket key, summary, description, any existing acceptance criteria, issue type.

### Case C: GitHub PR URL

Check that `gh` is available:

```bash
if ! command -v gh &>/dev/null; then
  echo "Error: 'gh' (GitHub CLI) is not installed."
  echo "Install it from https://cli.github.com/ and authenticate with 'gh auth login'."
  exit 1
fi
```

Fetch PR metadata:

```bash
gh pr view "$PR_URL" --json number,title,body,author,baseRefName,headRefName,files,additions,deletions,changedFiles,url
```

Fetch the diff for deeper context:

```bash
gh pr diff "$PR_URL"
```

If `gh` is not authenticated or the PR is not found, stop and tell the user.

Extract: PR title, description, list of changed files, summary of diff.

### Case D: Confluence page URL

Extract the page ID from the URL.

**Option 1 — Atlassian MCP (preferred when connected):**

If the `mcp__claude_ai_Atlassian__getConfluencePage` tool is available to you, call it directly with the page ID.
No environment variables are needed.
Extract the page title and body text.

**Option 2 — curl fallback (when MCP is not connected):**

Resolve `JIRA_ORG`:

```bash
if [ -z "$JIRA_ORG" ]; then
  echo "Error: JIRA_ORG is not set. Export it before using this skill:"
  echo "  export JIRA_ORG=your-org"
  exit 1
fi
JIRA_URL="https://${JIRA_ORG}.atlassian.net"
```

Fetch the Confluence page:

```bash
curl -s "${JIRA_URL}/wiki/rest/api/content/${PAGE_ID}?expand=body.storage,title" \
  -H "Accept: application/json" \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}"
```

If `JIRA_EMAIL` or `JIRA_API_TOKEN` are not set, stop and tell the user:

> Authentication required. Please export your credentials:
> ```bash
> export JIRA_EMAIL=you@company.com
> export JIRA_API_TOKEN=your-token
> ```
> Alternatively, connect the Atlassian MCP integration — no env vars needed.

Extract the page title and body text (strip HTML/storage format markup).

### Case E: Generic URL

Fetch the page:

```bash
curl -s -L "$URL"
```

Strip HTML tags and collapse whitespace to extract readable text.
Use that text as the feature context.

### Case F: Free text

Use `$ARGUMENTS` directly as the feature context.
No fetching needed.

## Step 1.5: Repo context (only when explicitly requested)

**Only run this step if `USE_REPO=true`** (user passed a repo request flag in `$ARGUMENTS`).
Never consult the repository on your own initiative.

Verify a git repo is reachable:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
```

If `REPO_ROOT` is empty, tell the user no git repository was found at the current working directory and skip to Step 2.

If `REPO_ROOT` is set:

1. Extract 3–5 domain keywords from the feature context (e.g. "parallel execution", "private workspace", "suite", "API test run").
2. Run targeted searches inside the repo to find app-observable facts:
   - API route definitions: files matching `*router*`, `*routes*`, `*controller*`, `openapi.yaml`, `swagger.json`, or similar. Look for HTTP method + path patterns (e.g. `POST /tests/:id/runs`).
   - UI route/page files: files under `pages/`, `views/`, `src/routes/`, or named `App.tsx`, `router.ts`, etc. Look for page names, route paths, and navigation labels.
   - Feature flag or entitlement config: files containing the entitlement key or plan tier names found in the feature context.
3. Collect the results as **repo signals** — a short list of app-observable facts: real endpoint paths, UI route paths, page titles, or plan/flag names as they appear in the app's public surface.
4. If no relevant results are found, proceed without repo signals (no mention to user).
5. Use repo signals in Step 3 to anchor bullets to things QA can find and verify in the running app: real endpoint paths to call, real UI pages to navigate to, real plan names to check against.

## Step 2: Analyze the context

From the fetched or provided content, identify:

1. **Feature intent** — what is this change or feature trying to achieve from the user's perspective?
2. **User-facing behaviors** — what does the user see, do, or experience in the app?
3. **Inputs and outputs** — what does the user provide, and what do they get back (UI state, API response, notification)?
4. **Error states** — what does the user see when something goes wrong (invalid input, limit reached, service unavailable)?
5. **Boundaries and constraints** — plan limits, permission gates, quotas, validation rules as experienced by the user.
6. **Integration points** — how does this feature interact with other parts of the app the user touches?

Focus on behaviors that are:

- **Observable** — a QA engineer can verify them by using the app UI or calling the public API, without reading code.
- **Specific** — not vague like "works correctly" or "loads fast".
- **Representative** — covers the most important paths, not every micro-detail.

Apply any additional context from `$ARGUMENTS` to shift emphasis, narrow scope, or highlight specific risk areas.

## Step 3: Produce the AC

Output the result in this format:

```
**Acceptance Criteria**

- <testable behavior>
- <testable behavior>
...
```

Rules for the bullet list:

- Write 5–10 bullets. Fewer is better when scope is narrow; more only when the context clearly contains many distinct testable behaviors.
- Each bullet starts with a clear subject (what the user does or what the app does) and states the expected observable outcome.
- Prioritize in this order: happy path first, then critical error states, then edge cases most likely to be missed or regressed.
- Write from the **user's perspective**: describe what the user navigates to, clicks, submits, or calls via the API — and what they see or receive in return.
- Use **app-domain language**: UI page names, button labels, plan tier names, API endpoint paths, error messages — not code identifiers.
- If repo signals are available, use real endpoint paths or UI route names in bullets where they help QA locate the exact thing to test.
- **Never mention any of the following**: class names, method names, DB table or column names, internal service names, lambda names, internal variable names, source file names, or any framework identifier. Apply the test: "could a QA engineer find and verify this using only the app UI or its public API documentation?"
- Do not include obvious product requirements that any software must satisfy (e.g. "the page loads without errors").
- Do not duplicate coverage — if two bullets describe the same behavior, merge them.
- If the context is ambiguous on a behavior that matters, write the bullet and append `[needs clarification]` rather than guessing.

---

## Rules

- Never fabricate feature details. Every AC bullet must be grounded in the provided context.
- Maximum 10 bullets. QA needs the critical ones, not an exhaustive list.
- Output plain markdown. Do not wrap the AC list in a code block.
- If fetching fails for any reason, stop before producing any AC and explain exactly what failed and how to fix it.
- Never ignore additional context. Either incorporate it into the AC or explicitly explain why it did not change the output.
