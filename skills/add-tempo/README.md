# add-tempo
Log time spend on Jira tickets as Tempo records with automatic calendar meeting resolution.
Only supports Outlook calendar for now.

Run once a day after your work-day is done and go home.

## Requirements
- `curl` installed
- `jq` installed

## Environment Variables
Skills need access to Tempo, Jira and your meetings calendar.
Export these in your terminal before using it:

```bash
# Tempo:
export TEMPO_API_TOKEN="your-tempo-api-token"
export TEMPO_MEETING_TICKET="AB-1234" # Ticket to log meetings under

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
/add-tempo yesterday AB-1234 2h code review
/add-tempo 2026-04-01 AB-1234 1h
```
Description after the duration is optional. If omitted, defaults to "Work on AB-1234".
Same ticket can appear multiple times — each entry is logged as a separate record.
An optional date prefix (`today`, `yesterday`, `2026-04-01`, `april 1`, `last monday`, etc.) targets a different day; without it, today is used.

### Optional date prefix
By default the skill logs to **today**. You can prefix the arguments with a date to log to a different day instead. The date prefix covers anything before the first ticket key.

```text
/add-tempo 2026-04-01 AB-1234 1 hour
/add-tempo yesterday AB-1234 1 hour, AB-9999 30 min PR review
/add-tempo april 1 AB-1234 1 hour coding
/add-tempo last monday AB-5555 2h bugfixes
```

Accepted forms: `YYYY-MM-DD`, `today`, `yesterday`, `april 1`, `1 april`, `april 2026`, `04/01/2026` (EU `DD/MM/YYYY` if not year-first), `last monday`, `3 days ago`. Calendar meetings for that target date are fetched and logged the same way.

## What it does
1. Resolves the target date (today by default, or from an optional date prefix in the arguments).
2. In a single parallel batch, fetches: your Jira account ID, Outlook calendar (ICS) for that date, issue IDs for all relevant tickets (meeting ticket + user-provided), and existing Tempo worklogs on that day.
3. Filters calendar events to include only work meetings (skipping non-work events like breakfast, lunch, etc.).
4. Plans and logs meetings under `TEMPO_MEETING_TICKET`, skipping any meeting already covered by an existing worklog on the same day (no duplicates).
5. Parses your comma-separated ticket + duration + optional description entries.
6. Auto-adjusts durations so the total logged time equals exactly 8 hours — factoring in existing worklogs, meetings, and new entries. 
   Adjustments apply only to user-provided entries.
7. Schedules work entries starting at 9 AM around all occupied time windows (meetings + existing records). 
   Each entry remains a single continuous block; conflicts are skipped, not split.
8. Logs all new records (meetings + work entries) to Tempo in a single parallel batch. Existing records are never modified, re-posted, or deleted.
9. Prints a final summary table of all records for the day, clearly marking which entries are new vs. already existing.

Note: Your Jira account ID (needed by Tempo) is fetched automatically — no need to export it.
