---
name: fill-tempo-meetings
description: Backfill missing Tempo meeting worklogs from a user-provided start date.
disable-model-invocation: true
---

# Fill tempo meetings
Backfill missing Tempo worklogs for calendar meetings from a start date.

This skill logs **only meetings** from the user's Outlook ICS calendar. It logs every valid meeting under `TEMPO_MEETING_TICKET`.

## Core principle
Calendar meetings are the authoritative source for meeting worklogs. If a past workday has valid meetings, log those meeting durations under the configured meeting ticket. Existing non-meeting Tempo worklogs must not block meetings; move or shorten them when needed so meeting records occupy their real calendar windows and the day remains safely capped at 8h.

## Prerequisites
Required env vars:

| Variable                | Description                                                                      |
|-------------------------|----------------------------------------------------------------------------------|
| `TEMPO_API_TOKEN`       | Tempo REST API token                                                             |
| `TEMPO_MEETING_TICKET`  | Jira ticket key to log meetings under, e.g. `AB-1234`                            |
| `JIRA_API_TOKEN`        | Jira/Atlassian API token, used only to resolve the meeting ticket issue ID        |
| `JIRA_ORG`              | Jira organization slug, e.g. `my-company` for `https://my-company.atlassian.net` |
| `JIRA_EMAIL`            | Jira account email address                                                       |
| `OUTLOOK_ICS_URL`       | Outlook published ICS calendar URL                                               |

Verify them; if any are missing, tell the user to export them and stop:
```bash
for var in TEMPO_API_TOKEN JIRA_ORG JIRA_EMAIL JIRA_API_TOKEN TEMPO_MEETING_TICKET OUTLOOK_ICS_URL; do
  if [ -z "${!var}" ]; then echo "MISSING: $var"; fi
done
JIRA_URL="https://${JIRA_ORG}.atlassian.net"
```

## Step 1: Parse arguments
One arg: a start date the user typed in any reasonable form. Normalize it to `YYYY-MM-DD` before doing anything else, using the **current local date** for missing parts:

| User input              | Resolves to                                                              |
|-------------------------|--------------------------------------------------------------------------|
| `2026-04-01`            | `2026-04-01`                                                             |
| `april 1` / `apr 1`     | April 1st of the **current year**                                        |
| `1 april` / `01.04`     | Same — April 1st of the current year                                     |
| `april 2026`            | **April 1st**, 2026 (missing day → 1st)                                  |
| `january`               | January 1st of the current year (missing day → 1st, missing year → now)  |
| `2026`                  | January 1st, 2026                                                        |
| `04/01/2026`            | Treat as `YYYY-MM-DD` if year first; otherwise assume `DD/MM/YYYY` (EU). |
| `last monday`, `3 weeks ago` | Resolve relative to today.                                          |

Rules:
- Case-insensitive; trim whitespace; accept `-`, `/`, `.`, or spaces as separators.
- If only a month is given → day defaults to **1**.
- If only a year is given → month and day default to **January 1st**.
- If only month + day → year defaults to the **current year**; if that date is in the future, fall back to **last year**.
- If the resolved date is today or later, print `Start date must be before today.` and stop.
- If parsing fails, print `Usage: /fill-tempo-meetings <date> — examples: /fill-tempo-meetings 2026-04-01, /fill-tempo-meetings "april 1", /fill-tempo-meetings "january 2026"` and stop.

After normalization, build the workday list (Mon–Fri only) from the start date through **yesterday**, inclusive. Never include today — today's hours aren't done yet, so this skill must not touch them.

## Step 2: Fetch all setup data in parallel
Steps 2a–2d are independent. Fire all four requests concurrently (background `&` + `wait`, or async client) — do not run them serially.

2a. Tempo worker ID:
```bash
curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" "${JIRA_URL}/rest/api/3/myself" > /tmp/myself.json &
```
2b. Outlook ICS (only call to `OUTLOOK_ICS_URL`):
```bash
curl -s "${OUTLOOK_ICS_URL}" -o /tmp/outlook_calendar.ics &
```
2c. Meeting Jira issue ID:
```bash
curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  "${JIRA_URL}/rest/api/3/issue/${TEMPO_MEETING_TICKET}?fields=id" > /tmp/issue.json &
```
2d. Existing Tempo worklogs for the full date range (paginate via `offset` if >1000):
```bash
curl -s -H "Authorization: Bearer ${TEMPO_API_TOKEN}" \
  "https://api.tempo.io/4/worklogs/user/${TEMPO_WORKER_ID_PLACEHOLDER}?from=<START_DATE>&to=<END_DATE>&limit=1000" > /tmp/worklogs.json &
```
Note: 2d depends on the worker ID from 2a. To keep parallelism, either (a) run 2a–2c in parallel first, then 2d, or (b) defer worker ID by using the `myself` call's `accountId` once 2a returns, while 2b/2c are still in flight.

`wait`. Then:
- Parse worker ID; fail fast if empty/null.
- Verify ICS file non-empty and starts with `BEGIN:VCALENDAR`; fail fast otherwise.
- Parse meeting issue ID; fail fast if empty/null.
- Group worklogs by `startDate`. Per date compute total logged seconds, logged issue IDs, occupied windows (`startTime` + duration), and the **full payload fields needed for later PUT calls** (`issue.id`, `startDate`, `startTime`, `description`, `author.accountId`, `tempoWorklogId`, `timeSpentSeconds`).

Reuse this in-memory worklog snapshot for all downstream logic. **Do not re-GET individual worklogs before PUT** — the Step 2d response has every field needed for the update body.

Use existing worklogs to detect already-logged meetings, occupied windows, and total daily time. Existing meeting worklogs on `TEMPO_MEETING_TICKET` may cover meetings and should prevent duplicates. Existing non-meeting worklogs are movable/resizable when they conflict with valid meetings or when the day would exceed 8h after adding meetings.

## Step 6: Extract calendar meetings for each date
From `/tmp/outlook_calendar.ics`, extract `VEVENT`s occurring on the target date. Pull at least:
- `SUMMARY`
- `DTSTART`
- `DTEND`
- `STATUS`
- `METHOD`
- the user's `ATTENDEE;PARTSTAT`, when present
- `UID`
- `RECURRENCE-ID`
- `EXDATE`
- `RRULE`

Skip the event if any of these are true:
- `STATUS:CANCELLED`.
- Enclosing `METHOD:CANCEL`.
- `SUMMARY` starts with `Canceled:` or `Cancelled:` (case-insensitive) — Outlook flags some cancellations only via the summary prefix, not `STATUS`.
- The user's own `ATTENDEE` line has `PARTSTAT=DECLINED`.
- It is an all-day event (`DATE`-only `DTSTART`).
- It has no reliable start or end time.
- Duration is under 30 minutes.
- The `SUMMARY` matches a non-work keyword, case-insensitive: `lunch`, `breakfast`, `dinner`, `gym`, `doctor`, `dentist`, `break`, `pick up`, `drop off`, `personal`, `errand`, `school`, `commute`, `vacation`, `holiday`.

When unsure whether an event is personal/non-work, skip it.

### Recurrence handling
Honor recurrence enough to avoid false logs:
- Honor `EXDATE` for recurring series.
- Honor recurrence overrides via `RECURRENCE-ID`.
- A recurrence override with `STATUS:CANCELLED` cancels only that occurrence.
- Handle RRULEs at minimum:
  - `FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR`
  - `FREQ=WEEKLY;BYDAY=TH`
  - any weekly `BYDAY` combination
  - `FREQ=DAILY`

Convert `DTSTART`/`DTEND` to the user's local timezone and use local `HH:MM` for Tempo `startTime`.

## Step 7: Deduplicate meetings and make room for them
For each valid meeting candidate:
- Log it under `TEMPO_MEETING_TICKET` / `TEMPO_MEETING_ISSUE_ID`.
- Preserve the real meeting duration. Never trim meetings.
- Skip it only if an existing worklog on `TEMPO_MEETING_TICKET` already appears to cover the same meeting time or duration.
- Skip it if it overlaps another new meeting already selected for the same date.
- If two calendar events overlap, keep the one with the more specific work-looking summary; otherwise keep the longer one and skip the other.

Existing non-meeting Tempo worklogs must not cause a meeting to be skipped. Selected meeting windows are fixed and authoritative. Move or shorten existing non-meeting worklogs when needed so meetings occupy their real calendar times.

### Existing worklog adjustment policy
Use Tempo update APIs for existing non-meeting worklogs only when required. Never delete records.

For each date:
1. Compute selected meeting windows, existing meeting worklogs, existing non-meeting worklogs, and total logged time.
2. Treat existing meeting worklogs on `TEMPO_MEETING_TICKET` as fixed; use them to avoid duplicate meeting logs.
3. Treat selected calendar meetings as fixed; they must keep their real start/end times.
4. Move every existing non-meeting worklog that overlaps a selected meeting window to another free slot on the same date.
5. Preserve existing non-meeting duration when possible.
6. If no same-day free slot can preserve duration, or if adding meetings would push the day above 8h, shorten existing non-meeting worklogs in 30-minute increments until:
   - all selected meetings fit at their real calendar times,
   - no worklog windows overlap,
   - total logged time for the date is at most 8h,
   - no remaining worklog is below 30 minutes.
7. Prefer shortening the largest existing non-meeting worklog first. If tied, shorten the latest one first. Never shorten meeting worklogs.
8. If an existing non-meeting worklog would need to shrink below 30 minutes, leave it unchanged and shorten another eligible non-meeting worklog.
9. If there is still no safe way to fit all meetings while keeping valid records and total daily time at or below 8h, log the meetings that fit after safe adjustments and print the reason for any skipped meeting.

Every Tempo record must be at least 30 minutes.

## Step 8: Process each date chronologically

### 8a — Weekends
Weekends are not in the workday list. If encountered defensively:
```text
⏭️ <DATE> — weekend, skipping.
```

### 8b — No valid meetings
If no valid meetings remain after duplicate detection:
```text
⏭️ <DATE> (<Day>) — no meetings to log.
```

### 8c — Adjust existing non-meeting worklogs
Before posting new meeting logs, update existing non-meeting records that conflict with selected meeting windows or push the day over 8h.

For moved records:
- Keep the same issue, description, author, and duration.
- Change only `startTime` unless a duration reduction is also required.
- Prefer free slots between 09:00 and 17:00 local time, then any same-day free slot that does not overlap another worklog.

For shortened records:
- Reduce `timeSpentSeconds` only in 30-minute increments.
- Keep at least 30 minutes.
- Never shorten records on `TEMPO_MEETING_TICKET`.

Use Tempo's worklog update endpoint (`PUT /4/worklogs/{tempoWorklogId}`) for each changed record. Build the PUT body **directly from the Step 2d snapshot** — do not issue a fresh GET per worklog. If an update fails, do not post a meeting into an overlapping slot; mark the day partial and continue.

### 8d — Build meeting worklogs
Each meeting becomes exactly one Tempo worklog:
- `issueId`: `TEMPO_MEETING_ISSUE_ID`
- `startDate`: target date
- `startTime`: meeting local start time, `HH:MM:SS`
- `timeSpentSeconds`: actual meeting duration in seconds
- `description`: meeting summary, or `Meeting` if summary is blank
- `authorAccountId` / worker field: `TEMPO_WORKER_ID`, according to Tempo API requirements

### 8e — Post all worklogs in one parallel batch
Tempo has no bulk API. After all per-day plans (adjustments + new meeting POSTs) are computed, fire the entire batch concurrently across **all dates at once** — do not serialize per record and do not wait between days.

```bash
# adjustments first (PUTs), then meeting creates (POSTs), all in parallel
for body in "${PUT_BODIES[@]}"; do
  curl -s -X PUT "https://api.tempo.io/4/worklogs/${id}" \
    -H "Authorization: Bearer ${TEMPO_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$body" > "/tmp/resp_put_${id}.json" &
done
for body in "${POST_BODIES[@]}"; do
  curl -s -X POST "https://api.tempo.io/4/worklogs" \
    -H "Authorization: Bearer ${TEMPO_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$body" > "/tmp/resp_post_${i}.json" &
done
wait
```
Capture each response to a file (or array) keyed by record ID/index so per-day results can be aggregated after `wait`. If a PUT (adjustment) fails for a date, drop the meeting that needed that adjustment, mark the day partial, and continue. If a POST fails, mark only that meeting failed; do not retry inside the run.

Equivalent in a single Python script: use `asyncio` + `aiohttp` or `concurrent.futures.ThreadPoolExecutor(max_workers=16)` and submit every adjustment + meeting at once. **Do not call `subprocess.run(['curl', ...])` in a serial Python loop** — that defeats parallelism.

### 8f — One-line day result
```text
✅ <DATE> (<Day>) — <N> meeting records, <H>h <M>m logged, <A> existing records adjusted.
⚠️ <DATE> (<Day>) — partial, <H>h <M>m logged (<reason>).
```

## Step 9: Grand summary
```text
🏁 fill-tempo-meetings complete
─────────────────────────────────
  Backfilled:          15 days
  Meeting records:     42
  Adjusted existing:   8 records
  Skipped:             4 weekends, 6 no meetings, 3 already covered
  Partial/error:       1 day
  Total meeting time:  38h 30m
─────────────────────────────────
```
Include: backfilled days, meeting records created, existing records adjusted, weekends skipped, days with no meetings, meetings skipped as already covered, partial/error days, and total logged meeting time.

## Hard rules
- Log only meetings from the Outlook ICS calendar.
- Log every valid meeting under `TEMPO_MEETING_TICKET`.
- Never fabricate work, meetings, durations, summaries, or activity.
- Never delete existing worklogs.
- Existing non-meeting worklogs may be moved or shortened only to make room for valid meetings and keep the day at or below 8h.
- Never double-book a slot.
- Never trim meetings; move or shorten non-meeting records first.
- Every Tempo record must be at least 30 minutes.
- Keep each day at or below 8h total logged time after meeting additions and existing-record adjustments.
- Skip non-work calendar events.
- Skip cancelled events (`STATUS:CANCELLED`, `METHOD:CANCEL`, cancelled recurrence overrides).
- Skip meetings the user declined (`PARTSTAT=DECLINED`).
- Skip all-day events.
- Skip weekends.
- Never log today — date range stops at yesterday in the user's local timezone.
- Continue past API errors.
- Use the user's local timezone for all date and time comparisons.

## Accuracy note (use when asked)
```text
This logs past meetings from the Outlook ICS calendar under the configured Tempo meeting ticket.
```
