# ticket-guide
Fetch a Jira ticket and produce a detailed implementation guide based on the current codebase.

## Requirements
- `git` installed and authenticated
- `curl` installed
- `JIRA_ORG` variable set to your jira organization name (e.g. `mycompany` if your Jira URL is `mycompany.atlassian.net`)
- Access to your Jira instance (if authentication is needed it requires `JIRA_API_TOKEN` and `JIRA_EMAIL` environment variables exported)

## Installation
```
./install.sh ticket-guide
```

## Usage
Inside any repo, open Claude Code and run:
```
/ticket-guide <ticket-number>
```
Examples:
```
/ticket-guide ABC-4221
/ticket-guide PROJ-100
```

## What it does
1. Fetches the Jira ticket title, description, and acceptance criteria from your Jira instance
2. Analyzes the current codebase on the default branch for relevant patterns, conventions, and existing code
3. Produces a structured implementation guide covering: step-by-step plan, files to modify, patterns to follow, testing strategy, gotchas, and a self-review checklist
4. Grounds every suggestion in actual code from the repo — no generic advice

The guide targets PR-ready quality: the resulting implementation should pass review from the most senior engineer on the team with zero comments.
