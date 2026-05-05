# ticket-guide
Fetch a Jira ticket and produce a detailed implementation guide based on the current codebase.

## Requirements
- `git` installed and authenticated
- `curl` installed
- `JIRA_ORG` variable set to your Jira organization name (e.g. `mycompany` if your Jira URL is `mycompany.atlassian.net`)
- Access to your Jira instance (if authentication is needed it requires `JIRA_API_TOKEN` and `JIRA_EMAIL` environment variables exported)

## Installation
```bash
./install.sh ticket-guide
```

## Usage
Inside any repo, open Claude Code and run:
```bash
/ticket-guide <ticket-number> [additional context]
```

The first argument must be the Jira ticket key. Everything after that is treated as optional additional context.
Examples:
```text
/ticket-guide ABC-4221
/ticket-guide PROJ-100 only touch backend validation, do not change UI copy
/ticket-guide API-77 customer says this is release-blocking and wants backward compatibility preserved
```

You can also provide multiline context after the ticket key, for example:
```text
/ticket-guide ABC-4221 backend only
avoid schema changes
there is already a partial implementation in branch feat/old-spike
```

## What it does
1. Fetches the Jira ticket title, description, and acceptance criteria from your Jira instance
2. Parses the first argument as the Jira ticket key and treats everything after it as optional additional implementation context
3. Analyzes the current codebase on the default branch for relevant patterns, conventions, and existing code
4. Produces a structured implementation guide covering: step-by-step plan, files to modify, patterns to follow, testing strategy, gotchas, and a self-review checklist
5. Grounds every suggestion in actual code from the repo - no generic advice

The guide targets PR-ready quality: the resulting implementation should pass review from the most senior engineer on the team with zero comments.
