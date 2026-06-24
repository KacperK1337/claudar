# test-cases

Generate executable QA test cases from any combination of context sources: Jira tickets, GitHub PRs, Confluence pages, free text, or the current conversation.

## Why use it

Writing test cases from scratch takes time and often misses edge cases.
This skill reads your feature context — wherever it lives — and produces structured, step-by-step test cases in a format QA can execute directly without needing additional explanation.
It covers happy paths, negative flows, and edge cases in one pass.

## Quick example

```text
/test-cases ABC-123
```

Output:

```
### TC-01: Submit form with valid data
**Type:** Happy path
**Preconditions:** User is logged in with edit permissions

**Steps:**
1. Navigate to /dashboard/new-item
2. Fill in all required fields with valid values
3. Click Save

**Expected:** Item appears in the list, success banner shown at top of page

---

### TC-02: Submit form with missing required field
**Type:** Negative
**Preconditions:** User is logged in

**Steps:**
1. Navigate to /dashboard/new-item
2. Leave the Name field empty
3. Click Save

**Expected:** Form does not submit, inline error shown below Name field: "Name is required"
```

## Setup

Optional — only needed when fetching from Jira without the Atlassian MCP integration:

```bash
export JIRA_ORG=your-org          # your Atlassian subdomain
export JIRA_EMAIL=you@example.com
export JIRA_API_TOKEN=your_token
```

Required CLI tools: `gh` (for GitHub PR fetching), `curl` (for Jira fallback and generic URLs).

## Installation

```bash
./install.sh test-cases
```

## Usage

Basic shapes:

```text
/test-cases                                        # uses current conversation
/test-cases ABC-123                                # Jira ticket key
/test-cases https://github.com/org/repo/pull/42   # GitHub PR URL
/test-cases some free text describing the feature  # free text
/test-cases ABC-123 use current branch             # Jira + repo exploration
```

Multiple context sources are allowed — combine them freely:

```text
/test-cases ABC-123 https://github.com/org/repo/pull/42
/test-cases ABC-123 use current branch focus on permissions edge cases
/test-cases ABC-123 https://confluence.example.com/wiki/spaces/TEAM/pages/123
```

Everything that is not a recognized URL or ticket key is treated as additional free text context that shapes the test cases.

## What happens when you run it

1. The skill classifies every token in your input — Jira key, GitHub URL, Confluence URL, generic URL, repo flag, or free text.
2. It fetches each source: Jira via MCP or REST API, GitHub PRs via `gh`, URLs via `curl`.
3. If you included a repo flag (e.g., `use current branch`), it explores the local codebase for real routes, endpoints, and page names to use in test steps.
4. It synthesizes a feature description covering user flows, entry points, error paths, and edge cases.
5. It outputs 5–10 numbered test cases in Steps + Expected Result format, ordered happy path → negative → edge cases.
6. It ends with a Coverage Notes section listing assumptions, ambiguities, and any sources that failed to load.
