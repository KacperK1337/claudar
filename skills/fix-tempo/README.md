# fix-tempo
Backfill missing Tempo logs for past dates using Jira activity and calendar meetings.

Forgot to log Tempo for the last 3 weeks? Run this once and enjoy.

## Requirements
- `curl` installed
- `jq` installed

## Environment Variables
Same as `add-tempo` — if you already have those exported, you're good:

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

See `add-tempo` README for how to get each token/URL.

## Installation
```bash
./install.sh fix-tempo
```

## Usage
```text
/fix-tempo 2026-04-01
```
This backfills every workday from April 1st through yesterday.

## What it does
1. Builds a list of dates from the provided start date to yesterday
2. Skips weekends and days that already have 8h logged in Tempo
3. For each missing day:
   - Fetches calendar meetings from Outlook ICS (skips non-work events)
   - Queries Jira for issues the user actively worked on (status transitions, active tickets) — filtered to main project only
   - Distributes remaining work time across those tickets (min 30min each)
   - Auto-adjusts durations to total exactly 8 hours
   - Schedules entries around meetings and logs everything to Tempo
4. Prints a summary for each day and a grand total at the end
