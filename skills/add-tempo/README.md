# add-tempo
Log time spend on Jira tickets as Tempo records with automatic calendar meeting resolution.
Only supports Outlook calendar for now.

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
export TEMPO_MEETING_TICKET="ABC-1234" # Ticket to log meetings under

# Jira:
export JIRA_ORG="your-org"
export JIRA_EMAIL="you@company.com"
export JIRA_API_TOKEN="your-atlassian-api-token"

# Outlook Calendar:
export OUTLOOK_ICS_URL="url.ics"
```

### How to get your Tempo API Token
1. Open your Jira instance and go to **Tempo** (top navigation)
2. Click **Settings** (gear icon, bottom-left)
3. Go to **API Integration**
4. Click **New Token**, give it a name, and hit **Create**
5. Copy the token

### How to get your Jira API Token
1. Go to [Atlassian API Tokens](https://id.atlassian.com/manage-profile/security/api-tokens)
2. Click **Create API token**
3. Give it a label and hit **Create**
4. Copy the token

### How to get your Outlook ICS URL
1. Go to [Outlook Web](https://outlook.office.com/calendar)
2. **Settings** (gear icon) → **Calendar** → **Shared calendars**
3. Under **Publish a calendar**, select your calendar and set permission to **"Can view all details"**
4. Click **Publish** and copy the **ICS** link

## Installation
```bash
./install.sh add-tempo
```

## Usage
```text
/add-tempo AB-1234 1 hour, AB-9999 30 min, AB-5555 3h
/add-tempo AB-1234 1 hour coding, AB-9999 30 min PR review, AB-5555 3h bugfixes
```
Description after the duration is optional. If omitted, defaults to "Work on AB-1234".
Same ticket can appear multiple times — each entry is logged as a separate record.

## What it does
1. Fetches today's calendar meetings and logs them to Tempo under specified meeting ticket
2. Parses your comma-separated ticket + duration entries
3. Schedules work entries starting around 9 AM, automatically skipping around meetings
4. Logs everything to Tempo via the API
5. Validates the day totals 8 hours and warns you if it doesn't
