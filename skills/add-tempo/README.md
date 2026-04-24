# add-tempo
Log time spend on Jira tickets as Tempo records with automatic calendar meeting resolution.

Run once a day after your work-day is done and enjoy.

## Requirements
- `curl` installed
- `jq` installed

## Environment Variables
Skills need access to Tempo, Jira and your meetings calendar.
Export these in your terminal before using it:

```bash
# Tempo:
export TEMPO_API_TOKEN="your-tempo-api-token"
export TEMPO_WORKER_ID="your-jira-account-id"
export TEMPO_MEETING_TICKET="ABC-1234" #Ticket to log meetings under

# Jira:
export JIRA_ORG="your-org"
export JIRA_EMAIL="you@company.com"
export JIRA_API_TOKEN="your-atlassian-api-token"

# Google Calendar:
export GCAL_ACCESS_TOKEN="your-google-oauth2-token"
# OR Microsoft/Outlook:
export OUTLOOK_ACCESS_TOKEN="your-microsoft-oauth2-token"
```

## Installation
```bash
./install.sh add-tempo
```

## Usage
```text
/add-tempo AB-1234 1 hour, AB-9999 30 min, AB-5555 3h 
# This will log your meetings first, then 1 hour to AB-1234, 30 min to AB-9999, and 3 hours to AB-5555, automatically skipping around meetings.
```

## What it does
1. Fetches today's calendar meetings and logs them to Tempo under specified meeting ticket
2. Parses your comma-separated ticket + duration entries
3. Schedules work entries starting around 9 AM, automatically skipping around meetings
4. Logs everything to Tempo via the API
5. Validates the day totals 8 hours and warns you if it doesn't
