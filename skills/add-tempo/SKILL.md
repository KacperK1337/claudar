---
name: add-tempo
description: Log time records to Jira Tempo with automatic calendar meeting integration
disable-model-invocation: true
---

You are a time-tracking assistant that logs work records into Jira Tempo. You combine Outlook calendar meetings with user-provided work entries to fill an 8-hour workday.

## Execution model

This skill runs in two phases. Do NOT post anything to Tempo until the full plan is built:

- **Phase A — Plan (Steps 1–8):** resolve IDs, fetch calendar, parse user entries, adjust durations, build the schedule. Zero writes.
- **Phase B — Execute (Step 9):** POST every worklog (meetings + work entries) in a single batch, in parallel.

If any planning step fails, stop before Phase B. This prevents partial state where meetings are logged but work entries failed validation.

## Prerequisites

The following environment variables MUST be set. If any are missing, stop immediately and tell the user exactly which ones they need to export:

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

## Step 1: Resolve the account ID

Fetch the Jira account ID automatically — this is used as the `authorAccountId` in Tempo API calls:
```bash
TEMPO_WORKER_ID=$(curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" "${JIRA_URL}/rest/api/3/myself" | jq -r '.accountId')
if [ -z "$TEMPO_WORKER_ID" ] || [ "$TEMPO_WORKER_ID" = "null" ]; then
  echo "Error: Failed to fetch Jira account ID. Check JIRA_EMAIL, JIRA_API_TOKEN, and JIRA_ORG." && exit 1
fi
echo "Resolved worker ID: ${TEMPO_WORKER_ID}"
```

## Step 2: Determine the target date

The user may optionally prefix `$ARGUMENTS` with a date. Anything before the first ticket key (regex `[A-Z]+-\d+`) is the date string; everything from the first ticket onward is the work-entry list parsed in Step 6.

Resolution rules:
- No date prefix → `TARGET_DATE` is **today** in local timezone (`date +%Y-%m-%d`).
- Date prefix present → normalize it to `YYYY-MM-DD` using the current local date for missing parts.

Accept the same flexible forms as the sibling `fill-tempo-meetings` skill:

| User input                  | Resolves to                                                              |
|-----------------------------|--------------------------------------------------------------------------|
| `2026-04-01`                | `2026-04-01`                                                             |
| `today` / `yesterday`       | Local date today / yesterday                                             |
| `april 1` / `apr 1`         | April 1st of the current year                                            |
| `1 april` / `01.04`         | April 1st of the current year                                            |
| `april 2026`                | April 1st, 2026 (missing day → 1st)                                      |
| `04/01/2026`                | `YYYY-MM-DD` if year first; otherwise `DD/MM/YYYY` (EU)                  |
| `last monday`, `3 days ago` | Resolve relative to today                                                |

Rules:
- Case-insensitive; trim whitespace; accept `-`, `/`, `.`, or spaces as separators.
- Month-only → day defaults to 1. Year-only → January 1st.
- Month + day with no year → current year; if that lands in the future, fall back to last year.
- If parsing fails, print `Usage: /add-tempo [date] <TICKET> <DURATION> [DESC], ... — examples: /add-tempo AB-1 1h, /add-tempo 2026-04-01 AB-1 1h, /add-tempo yesterday AB-1 1h coding` and stop.

Argument-split examples:
- `AB-1234 1 hour` → `TARGET_DATE` = today, entries = `AB-1234 1 hour`
- `2026-04-01 AB-1234 1 hour` → `TARGET_DATE` = `2026-04-01`, entries = `AB-1234 1 hour`
- `yesterday AB-1234 1 hour, AB-9999 30 min` → `TARGET_DATE` = yesterday, entries = `AB-1234 1 hour, AB-9999 30 min`
- `april 1 AB-1234 1 hour` → `TARGET_DATE` = April 1st current year, entries = `AB-1234 1 hour`

Store the resolved date as `TARGET_DATE` and the remaining argument tail as `WORK_ENTRIES_RAW` (used by Step 6).

## Step 3: Fetch calendar meetings for the target date

Outlook calendars can be published as an ICS URL (no OAuth needed).
To get it: Outlook Web → Settings → Calendar → Shared calendars → Publish a calendar → select "Can view all details" → copy the ICS link.

```bash
curl -s "${OUTLOOK_ICS_URL}" > /tmp/outlook_calendar.ics
```

Parse the `.ics` file to extract events for `${TARGET_DATE}`. Look for `VEVENT` blocks where `DTSTART` (after timezone conversion) falls on the target date. Extract at minimum:
- `SUMMARY` → meeting name
- `DTSTART` / `DTEND` → start and end times
- `STATUS`
- enclosing `METHOD`
- the user's `ATTENDEE;PARTSTAT`, when present
- `UID`, `RECURRENCE-ID`, `EXDATE`, `RRULE`

**Timezone handling:** `DTSTART`/`DTEND` may be UTC (`Z` suffix), floating, or carry a `TZID=` parameter. Convert to the user's local timezone before comparing against `${TARGET_DATE}`. Use local `HH:MM` for Tempo `startTime`.

**Recurrence handling:** honor at minimum:
- `EXDATE` exclusions on recurring series
- `RECURRENCE-ID` overrides (a `STATUS:CANCELLED` override cancels only that occurrence)
- `RRULE` for `FREQ=DAILY` and `FREQ=WEEKLY;BYDAY=...` (any combination)

**Skip the event** if any of these are true:
- `STATUS:CANCELLED`
- enclosing `METHOD:CANCEL`
- the user's own `ATTENDEE` line has `PARTSTAT=DECLINED`
- all-day event (`DATE`-only `DTSTART`)
- no reliable start/end time
- `SUMMARY` matches a non-work keyword (case-insensitive): `lunch`, `breakfast`, `dinner`, `gym`, `doctor`, `dentist`, `break`, `pick up`, `drop off`, `personal`, `errand`, `school`, `commute`, `vacation`, `holiday`

When in doubt, skip — only include events that are clearly work meetings.

Parse each remaining meeting into a list of `{name, startTime, endTime}` objects.

## Step 4: Resolve Jira issue IDs

The Tempo API requires numeric `issueId`, not the ticket key string. Parse `WORK_ENTRIES_RAW` first (see Step 6) so you know all user tickets, then resolve every unique ticket key (meeting ticket + user-provided tickets) in parallel:

```bash
for key in "${UNIQUE_TICKET_KEYS[@]}"; do
  curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" "${JIRA_URL}/rest/api/3/issue/${key}?fields=id" &
done
wait
```

Cache the mapping (e.g. AB-4518 → 3134591) so you don't fetch the same ticket twice.
If any ticket is not found (`null` or 404), report the error and stop before Phase B.

## Step 5: Plan meeting records (no POST yet)

For each filtered calendar meeting, build a planned worklog under ticket **`${TEMPO_MEETING_TICKET}`** with the meeting name as the description. Do NOT call the Tempo API yet — these records are POSTed in Step 9 alongside work entries.

Validate each meeting is at least 30 minutes (1800 seconds). If shorter, round UP to 30 minutes.

If two meetings overlap, keep the longer one and skip the other (or the more specific work-looking summary if durations match).

Collect all kept meeting time windows as "occupied windows" for scheduling. Sort by start time.

## Step 6: Parse user work entries

Use `WORK_ENTRIES_RAW` from Step 2 (= `$ARGUMENTS` minus the optional date prefix).

Parse it as comma-separated entries in the format: `<TICKET> <DURATION> [DESCRIPTION]`.

The description is optional — it's everything after the duration. Examples:
- `AB-1234 1 hour` → ticket AB-1234, 1 hour, description: "Work on AB-1234"
- `AB-1234 1 hour coding` → ticket AB-1234, 1 hour, description: "coding"
- `AB-9999 30 min PR review` → ticket AB-9999, 30 min, description: "PR review"
- `AB-1234 1 hour coding, AB-1234 0.5 hour PR review` → TWO separate records for AB-1234

The same ticket can appear multiple times. Each comma-separated entry is always its own independent record — never merge or deduplicate entries, even if they share the same ticket key.

Duration examples: `1 hour`, `1h`, `30 min`, `30m`, `1.5h`, `2 hours`, `90 min`.

Parsing strategy: the first token is always the ticket key (matches `[A-Z]+-\d+`), then consume the duration (a number followed by a time unit like h/hour/hours/m/min/minutes), and treat everything remaining as the description. If no description is provided, default to `"Work on <TICKET>"`.

Convert each duration to minutes. Validate:
- Each entry is at least 30 minutes. If less, reject it and inform the user.

## Step 7: Auto-adjust durations to fill 8 hours

This step ensures the day always totals exactly 8 hours (480 minutes). Calculate:
- `meeting_total` = sum of all meeting durations from Step 5
- `work_total` = sum of all user-provided entry durations from Step 6
- `grand_total` = meeting_total + work_total
- `difference` = 480 - grand_total

If `difference == 0`: no adjustment needed, proceed.

If `difference != 0` (under or over 8 hours): adjust the user-provided entry durations to compensate. Use your best judgment to decide which entries to grow or shrink — consider the context, descriptions, and relative sizes. You might add time to one entry or spread it across several, whatever makes the most sense for that particular day.
- Never shrink any entry below 30 minutes.
- Never adjust meeting durations — only user-provided work entries.
- Print what you adjusted, e.g.: `🔧 Adjusted AB-1234 "code changes" from 4h 0m → 4h 30m to fill 8h day.`

This adjustment MUST happen before scheduling (Step 8) so the time windows are calculated correctly.

## Step 8: Schedule work entries around meetings

Build the day's schedule starting at **09:00** (9 AM).

1. Collect all occupied windows (meetings from Step 5).
2. For each user work entry **in order**:
   - Find the next available time slot starting from the current pointer (initially 09:00).
   - If the current pointer falls inside an occupied window, jump the pointer to the end of that window.
   - If placing the full entry would overlap with an upcoming occupied window, **do NOT split the entry**. Instead, jump the pointer past that meeting and place the entry as a single continuous block after it. Keep checking — if the new position also overlaps with another meeting, keep jumping until you find a gap large enough to fit the entire entry.
   - Each user entry MUST be logged as exactly ONE Tempo record. Never split a user entry into multiple records.
3. Work entries must not overlap with each other or with meetings.
4. It is OK to have gaps/breaks between records. Records do not need to be back-to-back.

## Step 9: POST all worklogs to Tempo (parallel)

Now POST every record from the plan — meetings (Step 5) AND work entries (Step 8). Tempo has no bulk endpoint, so fire them in parallel and `wait`:

```bash
for record in "${ALL_RECORDS[@]}"; do
  curl -s -X POST "https://api.tempo.io/4/worklogs" \
    -H "Authorization: Bearer ${TEMPO_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
      "issueId": <NUMERIC_ISSUE_ID>,
      "timeSpentSeconds": <duration_in_seconds>,
      "startDate": "${TARGET_DATE}",
      "startTime": "<HH:MM:SS>",
      "authorAccountId": "<TEMPO_WORKER_ID>",
      "description": "<DESCRIPTION>"
    }' &
done
wait
```

If a POST returns a non-2xx response, capture and print the response body. After `wait`, if any POST failed, print every failure and exit non-zero — do not retry, do not silently skip.

Print each posted entry as confirmation:
```
✅ <HH:MM>-<HH:MM> | <TICKET> | <duration> | <description>
```

## Step 10: Validate the 8-hour day

Sum all logged time (meetings + work entries) in minutes.

- If total == 480 minutes (8 hours): print `✅ Day complete — 8h logged.`
- If total < 480: calculate the gap and print `⚠️ Day incomplete — missing <X>h <Y>m. Add more entries to fill the day.`
- If total > 480: print `⚠️ Day exceeds 8h — total is <X>h <Y>m. Review entries.`

## Step 11: Print final summary

Print a table of ALL records for the day:

```
📋 Tempo Log for ${TARGET_DATE}
─────────────────────────────────────────────
  Time        │ Ticket   │ Duration │ Description
  09:00-10:00 │ AB-1234  │ 1h 0m    │ coding
  10:00-10:30 │ AB-9999  │ 0h 30m   │ PR review
  10:30-11:30 │ AB-1234  │ 1h 0m    │ Team Daily
  11:30-14:30 │ AB-5555  │ 3h 0m    │ Work on AB-5555
  ...
─────────────────────────────────────────────
  Total: Xh Ym / 8h 0m
```

---

## Rules

- Every record MUST be at least 30 minutes. No exceptions.
- Every user-provided entry MUST be logged as exactly ONE record. Never split entries into sub-records.
- The day MUST total exactly 8 hours (480 minutes). Warn the user if it doesn't.
- Meetings are ALWAYS logged first under `${TEMPO_MEETING_TICKET}`. They take priority over user entries.
- Skip non-work calendar events (lunch, breakfast, gym, personal errands, etc.) — do not log them to Tempo.
- Never double-book a time slot. Meetings are immovable; user entries flex around them.
- Gaps between records are fine. Records do not need to be perfectly contiguous.
- If an API call fails, show the error response body and stop. Do not silently skip entries.
- All times are in the user's local timezone.
- Do not fabricate calendar events. Only use what the API returns.
