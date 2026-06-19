# write-ac
Turn any feature context into clear acceptance criteria for QA.

## Why use it
Writing acceptance criteria is easy to skip and hard to do well.
When you hand a ticket or PR to QA without clear AC, you get back "what exactly should I test?" or bugs caught too late.
This skill reads any context — a Jira ticket, a GitHub PR, a Confluence page, any URL, free text you type, or the current Claude Code conversation — and distills it into the most important, testable bullet points.
QA gets a list they can work from immediately, without having to reverse-engineer intent from code or specs.

## Quick example
After describing a new feature in Claude Code, run:
```text
/write-ac
```

Or point it at a ticket or PR:
```text
/write-ac PROJ-123
/write-ac https://github.com/myorg/myrepo/pull/456
/write-ac https://mycompany.atlassian.net/browse/PROJ-123
```

You get back something like:
```
Acceptance Criteria

- When a user fills in all required fields and submits the form, a confirmation toast appears and the form clears
- Submitting with an invalid email shows an inline validation error beneath the email field before the form is sent
- After a successful submission, reloading the page does not resubmit the form
- Submitting while offline shows a "connection error" message; the entered data is not lost
- A user on the Free plan sees a disabled submit button with an upgrade prompt when the monthly limit is reached
```

You can add context to sharpen the focus:
```text
/write-ac PROJ-123 focus on edge cases around concurrent edits
/write-ac https://github.com/myorg/myrepo/pull/456 QA is doing regression testing, highlight what could break existing behavior
/write-ac The checkout flow now supports Apple Pay and Google Pay focus on error states
```

## Setup
If you run the skill from inside your app's repository, it automatically scans for relevant API endpoint paths, UI routes, and feature flag names to ground the AC bullets in observable app behavior — no extra setup needed.

The tools and environment variables you need depend on the input type:

| Input type | Option A (MCP) | Option B (curl fallback) |
|---|---|---|
| Current conversation or free text | — | — |
| Any URL (generic) | — | `curl`, no env vars |
| Jira ticket URL or key | Atlassian MCP connected | `curl` + `JIRA_ORG`; optionally `JIRA_EMAIL` + `JIRA_API_TOKEN` if auth required |
| Confluence page URL | Atlassian MCP connected | `curl` + `JIRA_ORG`, `JIRA_EMAIL`, `JIRA_API_TOKEN` |
| GitHub PR URL | — | `gh` CLI authenticated (`gh auth login`) |

If you have the Atlassian MCP integration connected in Claude Code, no environment variables are needed for Jira or Confluence — the skill uses it automatically.

If you don't have the MCP, set these:
```bash
export JIRA_ORG="mycompany"         # slug from your Jira URL
export JIRA_EMAIL="you@company.com" # only if Jira requires auth
export JIRA_API_TOKEN="your-token"  # create at https://id.atlassian.com/manage-profile/security/api-tokens
```

## Installation
```bash
./install.sh write-ac
```

## Usage
Basic shape:
```text
/write-ac [url-or-ticket-key-or-text] [additional context]
```

The argument is optional.
When omitted, the skill uses the current Claude Code conversation as the feature context.

Examples:
```text
/write-ac
/write-ac PROJ-123
/write-ac https://github.com/myorg/myrepo/pull/456
/write-ac https://mycompany.atlassian.net/wiki/spaces/ENG/pages/12345678
/write-ac https://mycompany.atlassian.net/browse/PROJ-123
/write-ac The checkout flow now supports Apple Pay and Google Pay
/write-ac PROJ-123 focus on mobile behavior
/write-ac PROJ-123 audience is a manual QA engineer unfamiliar with the codebase
```

Multiline context works too:
```text
/write-ac PROJ-123
focus on error handling
the feature is customer-facing and release-blocking
ignore internal admin flows
```

## What happens when you run it
1. The skill detects what type of input was provided: URL, Jira ticket key, free text, or nothing.
2. It fetches the content if a URL or ticket key was given.
3. If running inside the app repo, it scans for relevant API endpoints, UI routes, and feature flag names to use as anchors for the AC bullets.
4. It analyzes the content for user-facing behaviors, inputs and outputs, error states, and constraints — described from the user's perspective, not the implementation's.
5. Any context you passed shapes the scope, focus, or emphasis of the output.
6. It produces 5–10 bullet points written in app-domain language: what the user does, what they see, what the app returns — nothing from the codebase.
7. Output is plain markdown, ready to paste into Jira, Confluence, a test plan, or a PR description.

## Safety guarantees
- Read-only.
Nothing is written or posted anywhere.
- If fetching fails (bad credentials, missing env vars, inaccessible URL), the skill stops and explains exactly what to fix before producing any AC.
- AC bullets are grounded in the provided context.
Ambiguous behaviors are marked `[needs clarification]` rather than guessed or invented.
- No external service is called unless you provide a URL or ticket key.
