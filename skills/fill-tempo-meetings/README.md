# fill-tempo-meetings
Backfill missed Tempo entries for **past calendar meetings**, in bulk.

## Why use it
If you forgot to log time for a week (or a month), opening Tempo and clicking through every meeting one by one is painful. 
This skill reads your Outlook calendar, finds every real meeting on every workday since the date you give it, and creates the matching Tempo entries under one ticket.

It does **not** invent any work.
It only logs meetings that actually happened on your calendar.

## Quick example
```text
/fill-tempo-meetings april 1
```

For each workday from April 1st through yesterday, the skill:
- pulls real meetings from your Outlook calendar,
- skips lunches, gym, declined meetings, and anything cancelled,
- creates one Tempo entry per meeting under your meeting ticket.

At the end you get a per-day report and a grand total of hours logged.

## Setup
You need `curl` and `jq` on your machine, plus the following environment variables exported in your shell:

```bash
# Tempo
export TEMPO_API_TOKEN="your-tempo-api-token"
export TEMPO_MEETING_TICKET="AB-1234"   # Ticket key for which all meetings will be logged

# Jira (used to look up your account ID and the meeting ticket's internal ID)
export JIRA_ORG="your-org"              # The slug in https://<org>.atlassian.net
export JIRA_EMAIL="you@company.com"
export JIRA_API_TOKEN="your-atlassian-api-token"

# Outlook calendar (published ICS feed)
export OUTLOOK_ICS_URL="https://outlook.office365.com/.../calendar.ics"
```

How to get each one:

| Variable               | Where to get it                                                                                                                          |
|------------------------|------------------------------------------------------------------------------------------------------------------------------------------|
| `TEMPO_API_TOKEN`      | Tempo → Settings → API Integration → **New Token**                                                                                       |
| `TEMPO_MEETING_TICKET` | Any Jira ticket key your team uses for meeting time, e.g. `ABC-1234`                                                                     |
| `JIRA_ORG`             | The subdomain in your Jira URL (`https://<org>.atlassian.net`)                                                                           |
| `JIRA_EMAIL`           | The email on your Atlassian account                                                                                                      |
| `JIRA_API_TOKEN`       | https://id.atlassian.com/manage-profile/security/api-tokens → **Create API token**                                                       |
| `OUTLOOK_ICS_URL`      | Outlook Web → Settings → Calendar → Shared calendars → Publish a calendar (set permission to "Can view all details") → copy the ICS link |

## Installation
```bash
./install.sh fill-tempo-meetings
```

## Usage
```text
/fill-tempo-meetings 2026-04-01
/fill-tempo-meetings april 1
/fill-tempo-meetings january 2026
/fill-tempo-meetings last monday
/fill-tempo-meetings 3 weeks ago
```

The date you pass is the **starting** day.
The skill walks forward from there, one workday at a time, up to **yesterday**.
Today is never touched (the day isn't over yet).

The date is forgiving:

| You type                      | It means                                  |
|-------------------------------|-------------------------------------------|
| `2026-04-01`                  | April 1st, 2026                           |
| `april 1` / `apr 1` / `01.04` | April 1st of the current year             |
| `april 2026`                  | April 1st, 2026 (day defaults to the 1st) |
| `2026`                        | January 1st, 2026                         |
| `last monday`, `3 weeks ago`  | Resolved relative to today                |

Weekends are automatically skipped.

## What happens on each day
For every workday in the range, the skill:

1. Reads that day's events from your Outlook calendar.
2. Throws out anything that isn't a real work meeting:
   - cancelled events (including ones flagged only by a `Canceled:` / `Cancelled:` summary prefix)
   - meetings you declined
   - all-day events
   - lunches, gym, doctor, dentist, breaks, commutes, vacations, errands, etc.
   - anything shorter than 30 minutes
3. Skips meetings already logged in Tempo under your meeting ticket - no duplicates.
4. If a non-meeting Tempo entry overlaps with a real meeting (or would push the day above 8h), it shifts or shortens that entry to make room. Existing meeting entries are left alone.
5. Creates one Tempo record per remaining meeting, with the real start time and duration, under `TEMPO_MEETING_TICKET`.

At the end you get a per-day line:
```
✅ 2026-04-02 (Thu) - 4 meeting records, 4h 20m logged, 0 existing records adjusted.
⏭️ 2026-04-06 (Mon) - no meetings to log.
```

and a grand summary:
```
🏁 fill-tempo-meetings complete
  Backfilled:          22 days
  Meeting records:     54
  Adjusted existing:   1
  Skipped:             1 day no meetings, 1 already covered
  Total meeting time:  40h 0m
```

## Safety guarantees
- Only real meetings from your calendar are logged. Nothing is fabricated.
- Existing Tempo entries are never deleted.
- Meeting durations are never shortened - they're authoritative.
- Existing **non-meeting** entries can be moved or shortened (in 30-minute steps) to make room for meetings or to keep the day at or below 8h.
- Every record is at least 30 minutes.
- Weekends and today are skipped.
- Errors on individual API calls don't stop the run - the day is marked partial and the rest continues.
