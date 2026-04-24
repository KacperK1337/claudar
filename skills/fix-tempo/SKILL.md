---
name: fix-tempo
description: Backfill missing Tempo logs for past dates using Jira activity and calendar meetings
disable-model-invocation: true
---

You are a time-tracking assistant that backfills missing Tempo worklogs for a range of past dates. For each missing day, you automatically determine what the user worked on using Jira issue activity, combine it with calendar meetings, and log a full 8-hour day to Tempo.

## Prerequisites

Same environment variables as `add-tempo`. All MUST be set:

| Variable | Description |
|---|---|
| `TEMPO_API_TOKEN` | Tempo REST API token (generate at Tempo > Settings > API Integration) |
| `JIRA_ORG` | Jira organization slug, e.g. `my-company` (URL becomes `https://my-company.atlassian.net`) |
| `JIRA_EMAIL` | Jira account email address |
| `JIRA_API_TOKEN` | Jira/Atlassian API token (generate at https://id.atlassian.com/manage-profile/security/api-tokens) |
| `TEMPO_MEETING_TICKET` | Jira ticket key to log meeting time under, e.g. `AB-1234` |
| `OUTLOOK_ICS_URL` | Outlook published ICS calendar URL |

Check them:
```bash
for var in TEMPO_API_TOKEN JIRA_ORG JIRA_EMAIL JIRA_API_TOKEN TEMPO_MEETING_TICKET OUTLOOK_ICS_URL; do
  if [ -z "${!var}" ]; then echo "MISSING: $var"; fi
done
```

If any are missing, print a helpful message telling the user to export them and stop.

Construct the Jira base URL:
```bash
if [ -z "$JIRA_ORG" ]; then
  echo "Error: JIRA_ORG is not set." && exit 1
fi
JIRA_URL="https://${JIRA_ORG}.atlassian.net"
```

## Step 1: Parse arguments

The user provided: `$ARGUMENTS`

This is a **start date** in `YYYY-MM-DD` format (e.g. `2026-04-01`).
The end date is always **yesterday** (today is handled by `add-tempo`).

If the argument is missing or invalid, tell the user:
```
Usage: /fix-tempo 2026-04-01
```

Build the list of dates from start date to yesterday (inclusive).

## Step 2: Resolve the account ID

```bash
TEMPO_WORKER_ID=$(curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" "${JIRA_URL}/rest/api/3/myself" | jq -r '.accountId')
if [ -z "$TEMPO_WORKER_ID" ] || [ "$TEMPO_WORKER_ID" = "null" ]; then
  echo "Error: Failed to fetch Jira account ID. Check JIRA_EMAIL, JIRA_API_TOKEN, and JIRA_ORG." && exit 1
fi
echo "Resolved worker ID: ${TEMPO_WORKER_ID}"
```

## Step 3: Determine the user's project prefix

The project prefix is used to filter out tickets that don't belong to the user's main project.

Extract the prefix from `TEMPO_MEETING_TICKET` — it's everything before the dash. E.g. if `TEMPO_MEETING_TICKET=RF-4518`, the prefix is `RF`.

This will be validated later: when fetching Jira activity, if the vast majority of tickets (e.g. 70%+) share a different prefix, use that one instead. But start with the meeting ticket prefix as the default.

## Step 4: Fetch the ICS calendar once

Download the ICS file once — it contains all past and future events:
```bash
curl -s "${OUTLOOK_ICS_URL}" > /tmp/outlook_calendar.ics
```

This file will be re-parsed for each date in the loop.

## Step 5: Batch-fetch existing Tempo worklogs for the entire range

Instead of checking each day individually, fetch ALL existing worklogs for the full date range in one call:
```bash
curl -s -H "Authorization: Bearer ${TEMPO_API_TOKEN}" \
  "https://api.tempo.io/4/worklogs/user/${TEMPO_WORKER_ID}?from=<START_DATE>&to=<END_DATE>&limit=1000"
```

If there are more than 1000 results, paginate using the `offset` parameter.

Group the results by `startDate`. For each date, sum `timeSpentSeconds` to know:
- Which days are fully logged (>= 28800s / 8h) → skip
- Which days are partially logged → calculate the gap
- Which days have nothing → full 8h to fill

## Step 6: Batch-fetch Jira activity for the entire range

Instead of querying Jira day-by-day, fetch ALL activity for the full range in one query:

```bash
curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  "${JIRA_URL}/rest/api/3/search" \
  -H "Content-Type: application/json" \
  -d '{
    "jql": "assignee = currentUser() AND updated >= \"<START_DATE>\" AND updated <= \"<END_DATE>\" ORDER BY updated DESC",
    "maxResults": 100,
    "fields": ["key", "summary", "updated"]
  }'
```

If there are more results, paginate using `startAt`. Collect ALL issues.

**Filter to main project only:** Only keep tickets whose key starts with the project prefix from Step 3. If a different prefix accounts for 70%+ of all results, use that prefix instead.

Group the filtered issues by their `updated` date. Each date gets a list of ticket keys the user touched that day.

For dates with no Jira activity after filtering, use the meeting ticket as a fallback — all remaining time goes under `TEMPO_MEETING_TICKET` with description "General work".

## Step 7: Resolve ALL Jira issue IDs upfront

Collect every unique ticket key across all days (meeting ticket + all work tickets). Resolve them all before starting the logging loop:

```bash
curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" "${JIRA_URL}/rest/api/3/issue/<TICKET_KEY>?fields=id" | jq -r '.id'
```

Store the full mapping. This avoids redundant lookups during the per-day loop.

## Step 8: Process each date

For each date in the range, perform the following sub-steps. Process dates **in chronological order**.

### Step 8a: Skip weekends

If the date is a Saturday or Sunday, skip it and print:
```
⏭️ <DATE> — weekend, skipping.
```

### Step 8b: Skip fully logged days

Using the data from Step 5, if this date already has >= 8h logged:
```
⏭️ <DATE> — already logged (Xh Ym), skipping.
```

If partially logged, note the existing total and reduce the target accordingly.

### Step 8c: Fetch calendar meetings for this date

Parse the already-downloaded `/tmp/outlook_calendar.ics` file to extract events for this specific date.

Look for `VEVENT` blocks where `DTSTART` falls on this date. Extract:
- `SUMMARY` → meeting name
- `DTSTART` / `DTEND` → start and end times

Skip all-day events (DTSTART is DATE not DATETIME). Convert to local timezone `HH:MM` format.

**Filter out non-work events:** Skip any event that looks like a personal or non-work activity (lunch, breakfast, dinner, gym, doctor, dentist, break, pick up, drop off, personal, errand, etc.). Match case-insensitively. When in doubt, skip it.

**Also handle recurring events:** ICS files encode recurring events with `RRULE`. For each `VEVENT` with an `RRULE`, check if the recurrence pattern includes the target date. Common patterns:
- `RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR` — weekday recurrence
- `RRULE:FREQ=WEEKLY;BYDAY=TH` — every Thursday
- `RRULE:FREQ=DAILY` — every day

Also check `EXDATE` entries which exclude specific dates from the recurrence.

If parsing RRULE is too complex, at minimum handle `FREQ=WEEKLY;BYDAY=XX` patterns since most work meetings are weekly recurring.

### Step 8d: Build work entries from Jira activity

Using the grouped data from Step 6, get the list of tickets for this date.

Distribute the remaining work time (target minus meetings) across them:
- If there's only 1 ticket: assign all remaining time to it.
- If there are 2-5 tickets: distribute time roughly evenly, but use your judgment. If one ticket has much more activity, give it more time.
- If there are 6+ tickets: distribute time across all of them, giving more time to tickets with more activity. Every entry must be at least 30 minutes — if distributing evenly would push some below 30min, drop the least-active tickets until all entries fit.
- Every entry must be at least 30 minutes.
- Each entry gets description "Work on <TICKET_KEY>".

### Step 8e: Auto-adjust durations to fill 8 hours (or remaining gap)

Calculate the target for this day:
- If no existing worklogs: target = 480 minutes
- If partially logged: target = 480 - existing_minutes

Sum meetings + work entries. If the total doesn't match the target, adjust work entry durations using your best judgment. Never shrink below 30 minutes. Never adjust meeting durations.

### Step 8f: Schedule entries

Schedule work entries around meetings starting at 09:00, same logic as `add-tempo`:
- Jump past meetings, never split entries, gaps are OK.

### Step 8g: Log all records for this day in parallel

Tempo has no bulk API, so fire all POST requests for this day in parallel using background processes:

```bash
# Fire all curls for one day in parallel
for each record; do
  curl -s -X POST "https://api.tempo.io/4/worklogs" \
    -H "Authorization: Bearer ${TEMPO_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{...}' &
done
wait  # wait for all background jobs to finish
```

This means a day with 5 records takes ~1 API round-trip instead of 5 sequential ones.

Collect results and check for errors.

### Step 8h: Print day confirmation

After logging all records for a day, print a single line:
```
✅ <DATE> (<Day>) — <N> records, 8h 0m logged.
```

If a day had errors:
```
⚠️ <DATE> (<Day>) — partial, 5h 30m logged (API error on 2 records).
```

Do NOT print a full table per day — it's too noisy for large date ranges.

## Step 9: Print grand summary

After processing all dates, print a final overview:

```
🏁 fix-tempo complete
─────────────────────────────────
  Backfilled:  15 days
  Skipped:     4 weekends, 2 already logged
  Total logged: 120h 0m
─────────────────────────────────
```

---

## Rules

- Every record MUST be at least 30 minutes. No exceptions.
- Every work entry MUST be logged as exactly ONE record. Never split entries.
- Each day MUST total exactly 8 hours (480 minutes), unless partially pre-logged.
- Meetings are ALWAYS logged first under `${TEMPO_MEETING_TICKET}`. They take priority.
- Skip non-work calendar events (lunch, breakfast, gym, personal errands, etc.).
- Only log tickets from the user's main project (determined by `TEMPO_MEETING_TICKET` prefix or dominant prefix in Jira activity).
- Never double-book a time slot. Meetings are immovable; work entries flex around them.
- Gaps between records are fine. Records do not need to be contiguous.
- Skip weekends entirely.
- Skip days that already have 8h logged.
- For partially logged days, only fill the gap.
- If an API call fails for one day, log the error and continue to the next day.
- Cache Jira issue ID lookups across all days to minimize API calls.
- All times are in the user's local timezone.
- Do not fabricate calendar events or Jira activity. Only use what the APIs return.

