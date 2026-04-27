# fix-tempo
Backfill missing Tempo logs for past dates using Jira activity and calendar meetings.

Forgot to log Tempo for the last 3 weeks? Run this once and enjoy.

## Requirements

### CMD tools
- `curl` installed
- `jq` installed

### Environment Variables
```bash
# Tempo:
export TEMPO_API_TOKEN="your-tempo-api-token"
export TEMPO_MEETING_TICKET="ABC-1234"

# Jira:
export JIRA_ORG="your-org"
export JIRA_EMAIL="you@company.com"
export JIRA_API_TOKEN="your-atlassian-api-token"

# Outlook Calendar:
export OUTLOOK_ICS_URL="url.ics"
```

Here's how to get each of those:
- `TEMPO_API_TOKEN`: Tempo → Settings → API Integration → create a new token.
- `TEMPO_MEETING_TICKET`: any Jira ticket key you use to log meetings under (e.g. `ABC-1234`).
- `JIRA_ORG`: the slug in your Jira URL `https://<org>.atlassian.net`.
- `JIRA_EMAIL`: the email tied to your Atlassian account.
- `JIRA_API_TOKEN`: create at https://id.atlassian.com/manage-profile/security/api-tokens.
- `OUTLOOK_ICS_URL`: Outlook → Calendar → Share → Publish a calendar → copy the ICS link.

## Installation
```bash
./install.sh fix-tempo
```

## Usage
```text
/fix-tempo 2026-04-01
/fix-tempo april 1
/fix-tempo january 2026
/fix-tempo last monday
```
The date argument is flexible:
- `april 1` → April 1st of the current year
- `january 2026` → January 1st, 2026 (missing day defaults to the 1st)
- `2026` → January 1st, 2026
- `2026-04-01`, `04/01/2026`, `last monday`, `3 weeks ago` — all work too
Whatever you pass, the skill backfills every workday from that date through **yesterday** (today is never touched).

## What it does
1. Builds a list of dates from the provided start date to yesterday
2. Skips weekends and days that already have 8h logged in Tempo
3. For each missing day:
   - Fetches calendar meetings from Outlook ICS (skips non-work events, cancelled meetings, and meetings you declined)
   - Queries Jira for issues the user actively worked on (status transitions, active tickets) — filtered to main project only
   - Distributes remaining work time across those tickets (min 30min each)
   - Auto-adjusts durations to total exactly 8 hours
   - Schedules entries around meetings and logs everything to Tempo
4. Prints a summary for each day and a grand total at the end
