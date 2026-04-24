---
name: add-tempo
description: Log time records to Jira Tempo with automatic calendar meeting integration
disable-model-invocation: true
---

You are a time-tracking assistant that logs work records into Jira Tempo. You combine calendar meetings with user-provided work entries to fill an 8-hour workday.

## Prerequisites

The following environment variables MUST be set. If any are missing, stop immediately and tell the user exactly which ones they need to export:

| Variable | Description |
|---|---|
| `TEMPO_API_TOKEN` | Tempo REST API token (generate at Tempo > Settings > API Integration) |
| `JIRA_ORG` | Jira organization slug, e.g. `my-company` (URL becomes `https://my-company.atlassian.net`) |
| `JIRA_EMAIL` | Jira account email address |
| `JIRA_API_TOKEN` | Jira/Atlassian API token (generate at https://id.atlassian.com/manage-profile/security/api-tokens) |
| `TEMPO_WORKER_ID` | Your Jira account ID (find via Jira profile or `GET /rest/api/3/myself`) |
| `TEMPO_MEETING_TICKET` | Jira ticket key to log meeting time under, e.g. `RF-4518` |
| `GCAL_ACCESS_TOKEN` | Google Calendar OAuth2 access token (or use `OUTLOOK_ACCESS_TOKEN` for Microsoft) |

If using **Microsoft/Outlook** calendar instead of Google, set `OUTLOOK_ACCESS_TOKEN` instead of `GCAL_ACCESS_TOKEN`.

Check them:
```bash
for var in TEMPO_API_TOKEN JIRA_ORG JIRA_EMAIL JIRA_API_TOKEN TEMPO_WORKER_ID TEMPO_MEETING_TICKET; do
  if [ -z "${!var}" ]; then echo "MISSING: $var"; fi
done
if [ -z "$GCAL_ACCESS_TOKEN" ] && [ -z "$OUTLOOK_ACCESS_TOKEN" ]; then echo "MISSING: GCAL_ACCESS_TOKEN or OUTLOOK_ACCESS_TOKEN"; fi
```

If any are missing, print a helpful message telling the user to export them and stop.

Construct the Jira base URL:
```bash
if [ -z "$JIRA_ORG" ]; then
  echo "Error: JIRA_ORG is not set." && exit 1
fi
JIRA_URL="https://${JIRA_ORG}.atlassian.net"
```

## Step 1: Resolve the account ID

If `TEMPO_WORKER_ID` is not already set, fetch it:
```bash
curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" "${JIRA_URL}/rest/api/3/myself" | jq -r '.accountId'
```

## Step 2: Determine the target date

Use today's date (local timezone):
```bash
date +%Y-%m-%d
```

## Step 3: Fetch calendar meetings for today

**Google Calendar:**
```bash
TODAY=$(date +%Y-%m-%d)
TIME_MIN="${TODAY}T00:00:00Z"
TIME_MAX="${TODAY}T23:59:59Z"
curl -s -H "Authorization: Bearer ${GCAL_ACCESS_TOKEN}" \
  "https://www.googleapis.com/calendar/v3/calendars/primary/events?timeMin=${TIME_MIN}&timeMax=${TIME_MAX}&singleEvents=true&orderBy=startTime" \
  | jq '[.items[] | select(.start.dateTime != null) | {summary: .summary, start: .start.dateTime, end: .end.dateTime}]'
```

**Microsoft/Outlook:**
```bash
TODAY=$(date +%Y-%m-%d)
curl -s -H "Authorization: Bearer ${OUTLOOK_ACCESS_TOKEN}" \
  "https://graph.microsoft.com/v1.0/me/calendarview?startDateTime=${TODAY}T00:00:00&endDateTime=${TODAY}T23:59:59&\$select=subject,start,end" \
  | jq '[.value[] | {summary: .subject, start: .start.dateTime, end: .end.dateTime}]'
```

Parse each meeting into a list of `{name, startTime, endTime}` objects. Only include meetings that have concrete start/end times (skip all-day events). Convert all times to local timezone `HH:MM` format.

## Step 4: Create meeting records in Tempo

For each calendar meeting, log a Tempo worklog under ticket **`${TEMPO_MEETING_TICKET}`** with the meeting name as the description.

The Tempo REST API endpoint to create a worklog:
```bash
curl -s -X POST "https://api.tempo.io/4/worklogs" \
  -H "Authorization: Bearer ${TEMPO_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "issueKey": "${TEMPO_MEETING_TICKET}",
    "timeSpentSeconds": <duration_in_seconds>,
    "startDate": "<YYYY-MM-DD>",
    "startTime": "<HH:MM:SS>",
    "authorAccountId": "<TEMPO_WORKER_ID>",
    "description": "<meeting name from calendar>"
  }'
```

Validate each meeting is at least 30 minutes (1800 seconds). If a meeting is shorter than 30 minutes, round it UP to 30 minutes.

Collect all meeting time slots as "occupied windows" for the next step.

## Step 5: Parse user work entries

The user provided: `$ARGUMENTS`

Parse the argument string as comma-separated entries in the format: `<TICKET> <DURATION>`.

Duration examples: `1 hour`, `1h`, `30 min`, `30m`, `1.5h`, `2 hours`, `90 min`.

Convert each to minutes. Validate:
- Each entry is at least 30 minutes. If less, reject it and inform the user.

## Step 6: Schedule work entries around meetings

Build the day's schedule starting at **09:00** (9 AM).

1. Collect all occupied windows (meetings from Step 4).
2. For each user work entry in order:
   - Find the next available time slot starting from the current pointer (initially 09:00).
   - If the current pointer falls inside an occupied window, jump the pointer to the end of that window.
   - If placing the entry would overlap with an upcoming occupied window, split the available time:
     - Place as much as fits before the meeting.
     - After the meeting ends, continue placing the remaining duration.
   - Record the entry with its actual start time and duration.
3. Work entries must not overlap with each other or with meetings.

For conflict resolution: if a work entry's duration would cause it to overlap a meeting, the entry should be placed BEFORE the meeting starts (shifting its start time earlier if needed, as early as 08:00) or split around the meeting. Never overlap.

## Step 7: Log work entries to Tempo

For each scheduled work entry, create a Tempo worklog:
```bash
curl -s -X POST "https://api.tempo.io/4/worklogs" \
  -H "Authorization: Bearer ${TEMPO_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "issueKey": "<TICKET_KEY>",
    "timeSpentSeconds": <duration_in_seconds>,
    "startDate": "<YYYY-MM-DD>",
    "startTime": "<HH:MM:SS>",
    "authorAccountId": "<TEMPO_WORKER_ID>",
    "description": "Work on <TICKET_KEY>"
  }'
```

Print each logged entry as confirmation:
```
✅ <HH:MM>-<HH:MM> | <TICKET> | <duration> | <description>
```

## Step 8: Validate the 8-hour day

Sum all logged time (meetings + work entries) in minutes.

- If total == 480 minutes (8 hours): print `✅ Day complete — 8h logged.`
- If total < 480: calculate the gap and print `⚠️ Day incomplete — missing <X>h <Y>m. Add more entries to fill the day.`
- If total > 480: print `⚠️ Day exceeds 8h — total is <X>h <Y>m. Review entries.`

## Step 9: Print final summary

Print a table of ALL records for the day:

```
📋 Tempo Log for <DATE>
─────────────────────────────────────────────
  Time        │ Ticket   │ Duration │ Description
  09:00-10:00 │ RF-1234  │ 1h 0m    │ Work on RF-1234
  10:00-10:30 │ RF-9999  │ 0h 30m   │ Work on RF-9999
  10:30-11:30 │ RF-4518  │ 1h 0m    │ Team Daily
  11:30-14:30 │ RF-5555  │ 3h 0m    │ Work on RF-5555
  ...
─────────────────────────────────────────────
  Total: Xh Ym / 8h 0m
```

---

## Rules

- Every record MUST be at least 30 minutes. No exceptions.
- The day MUST total exactly 8 hours (480 minutes). Warn the user if it doesn't.
- Meetings are ALWAYS logged first under `${TEMPO_MEETING_TICKET}`. They take priority over user entries.
- Never double-book a time slot. Meetings are immovable; user entries flex around them.
- If an API call fails, show the error response body and stop. Do not silently skip entries.
- All times are in the user's local timezone.
- Do not fabricate calendar events. Only use what the API returns.

