---
name: fix-tempo
description: backfill missing tempo worklogs since date provided by the user
---

# Fix Tempo
Backfill missing Tempo worklogs from a start date. 
Jira activity is the required work signal.
Outlook ICS meetings fill the rest up to 8h/day. 
Never log without real Jira activity for that date — meetings alone don't count.

## Core principle
Tempo's Activity Feed isn't exposed publicly. Approximate it via public Jira APIs using comments, creations, transitions, assignee changes, field edits, and updates by the current user — not just status changes.

## Prerequisites
Required env vars:

| Variable                | Description                                                                      |
|-------------------------|----------------------------------------------------------------------------------|
| `TEMPO_API_TOKEN`       | Tempo REST API token                                                             |
| `TEMPO_MEETING_TICKET`  | Jira ticket key to log meetings under, e.g. `AB-1234`                            |
| `JIRA_API_TOKEN`        | Jira/Atlassian API token                                                         |
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
- If parsing fails, print `Usage: /fix-tempo <date> — examples: /fix-tempo 2026-04-01, /fix-tempo "april 1", /fix-tempo "january 2026"` and stop.

After normalization, build the workday list (Mon–Fri only) from the start date through **yesterday**, inclusive. Never include today — today's hours aren't done yet, so this skill must not touch them.

## Step 2: Resolve Tempo worker ID
```bash
TEMPO_WORKER_ID=$(curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" "${JIRA_URL}/rest/api/3/myself" | jq -r '.accountId')
```
Fail fast if empty/null. Use this same ID to identify changelog authors.

## Step 3: Determine project prefix
Start with the prefix from `TEMPO_MEETING_TICKET` (e.g. `RF-4518` → `RF`). After collecting Jira activity, if ≥70% of scored activity belongs to a different prefix, switch to that one. Only log work tickets from the selected prefix.

## Step 4: Fetch Outlook ICS once
```bash
curl -s "${OUTLOOK_ICS_URL}" > /tmp/outlook_calendar.ics
```
Re-parse this file for each date.

## Step 5: Batch-fetch existing Tempo worklogs
One call for the full range (paginate via `offset` if >1000):
```bash
curl -s -H "Authorization: Bearer ${TEMPO_API_TOKEN}" \
  "https://api.tempo.io/4/worklogs/user/${TEMPO_WORKER_ID}?from=<START_DATE>&to=<END_DATE>&limit=1000"
```
Group by `startDate`. Per date compute total logged seconds, logged ticket keys/issue IDs, and occupied windows (`startTime` + duration). Use this to skip ≥8h days, fill only gaps on partial days, avoid double-booking, and avoid logging the same ticket twice on the same day.

## Step 6: Fetch Jira activity (Tempo-like signals)
For each workday not already fully logged, run these queries with `<DATE>` inclusive and `<DATE_PLUS_1>` exclusive.

**A — status transitions by current user (strong):**
```bash
curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  "${JIRA_URL}/rest/api/3/search/jql?jql=status%20changed%20BY%20currentUser()%20DURING%20(%22<DATE>%22%2C%22<DATE_PLUS_1>%22)&maxResults=50&fields=key,summary,updated,status"
```

**B — issues commented by user** (skip if `commentedBy` unsupported):
```bash
curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  "${JIRA_URL}/rest/api/3/search/jql?jql=commentedBy%20%3D%20currentUser()%20AND%20updated%20%3E%3D%20%22<DATE>%22%20AND%20updated%20%3C%20%22<DATE_PLUS_1>%22&maxResults=50&fields=key,summary,updated,status"
```

**C — issues created by user:**
```bash
curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  "${JIRA_URL}/rest/api/3/search/jql?jql=creator%20%3D%20currentUser()%20AND%20created%20%3E%3D%20%22<DATE>%22%20AND%20created%20%3C%20%22<DATE_PLUS_1>%22&maxResults=50&fields=key,summary,created,updated,status"
```

**D — assigned issues updated that day (weak, must not dominate over A/B/changelog):**
```bash
curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  "${JIRA_URL}/rest/api/3/search/jql?jql=assignee%20%3D%20currentUser()%20AND%20updated%20%3E%3D%20%22<DATE>%22%20AND%20updated%20%3C%20%22<DATE_PLUS_1>%22&maxResults=50&fields=key,summary,updated,status,assignee"
```

**E — optional dev links** (commits/PRs/builds): extra evidence only; if unavailable, continue silently.

## Step 7: Enrich with changelog
For each unique issue:
```bash
curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  "${JIRA_URL}/rest/api/3/issue/<TICKET_KEY>?fields=key,summary,status,assignee,created,updated&expand=changelog"
```
Paginate if needed. Only count entries where `author.accountId == TEMPO_WORKER_ID` and `created` is on the target date in the user's local timezone.

Score each issue:

| Signal                                                                                        |  Score |
|-----------------------------------------------------------------------------------------------|-------:|
| User comment on issue                                                                         |     +5 |
| Status transition by user                                                                     |     +5 |
| Issue created by user                                                                         |     +4 |
| Assignee changed by user                                                                      |     +3 |
| Issue moved, sprint/priority/labels/fix version changed by user                               |     +2 |
| Description/summary/other field edited by user                                                |     +2 |
| Issue assigned to user and updated that day                                                   |     +1 |
| Development link signal, if available                                                         |     +2 |

Track signal reasons (`comment`, `transition`, `created`, `assignee change`, `field edit`, `updated assigned issue`). Drop tickets with score `0`.

## Step 8: Merge, rank, filter
Per date: merge query results by issue key, add changelog scores, sort by score desc, apply prefix filter, drop empty results. If nothing remains:
```text
⏭️ <DATE> — no Jira activity signals found, skipping.
```

## Step 9: Resolve Jira issue IDs upfront
Collect every unique ticket key (incl. `TEMPO_MEETING_TICKET`) and resolve once; cache key→ID. Don't re-resolve in the logging loop.
```bash
curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" "${JIRA_URL}/rest/api/3/issue/<TICKET_KEY>?fields=id" | jq -r '.id'
```

## Step 10: Process each date chronologically

**10a — Weekends:** `⏭️ <DATE> — weekend, skipping.`

**10b — Existing worklogs** (from Step 5; never modify or delete):
- ≥ 8h → `⏭️ <DATE> — already logged (Xh Ym), skipping.`
- 0 < total < 8h → `remaining_target = 480 - existing_minutes`; track `existing_tickets` and `existing_windows`.
- 0 → target = 480 min.

**10c — Calendar meetings for the date:** From `/tmp/outlook_calendar.ics`, extract `VEVENT`s with `DTSTART` on the target date; pull `SUMMARY`, `DTSTART`, `DTEND`, `STATUS`, and the user's `ATTENDEE;PARTSTAT`. Skip the event if any of these are true:
- `STATUS:CANCELLED` (event was cancelled)
- enclosing `METHOD:CANCEL`
- the user's own `ATTENDEE` line has `PARTSTAT=DECLINED`
- it's an all-day event (DATE-only `DTSTART`)
- the `SUMMARY` matches a non-work keyword (case-insensitive): lunch, breakfast, dinner, gym, doctor, dentist, break, pick up, drop off, personal, errand, school, commute, vacation, holiday — when unsure, skip.

Also honor `EXDATE` for recurring series and recurrence overrides via `RECURRENCE-ID` (a recurrence override with `STATUS:CANCELLED` cancels just that one occurrence). Convert `DTSTART`/`DTEND` to local `HH:MM`. Handle RRULEs at minimum: `FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR`, `FREQ=WEEKLY;BYDAY=TH`, `FREQ=DAILY`. Meetings that survive all filters are logged under `TEMPO_MEETING_TICKET` and take priority over work entries.

**10d — Jira work entries:** Use scored Jira activity for the date. On partial days, remove tickets already logged that day, treat existing windows as occupied, and distribute only the remaining target. If no new valid tickets remain, skip the day.

**10e — Allocate work time by score:**
```text
target_minutes  = 480 if no existing logs else 480 - existing_minutes
meeting_minutes = sum(new valid work meeting durations)
work_minutes    = target_minutes - meeting_minutes
```
If `work_minutes < 30`: skip work entries; log only meetings if Jira activity exists for the date and meetings fit. Never trim meetings — drop ones that don't fit.

Allocate proportionally to score: sum scores → split minutes → round to 30-min blocks → drop lowest-score tickets if any would receive <30 min → every entry ≥ 30 min → apply rounding adjustment to highest-score ticket first → never split a ticket across multiple Tempo records.

Each work entry description: `Working hard`.

**10f — Adjust to target:** New entries must sum to `target_minutes` unless impossible. Never shrink any record below 30 min. Never adjust meeting durations. If impossible, log the closest safe amount below target and print the reason.

**10g — Schedule:** Start at 09:00 local. Meetings and existing windows are immovable; new work entries flex around them. Never double-book or split. Gaps allowed; not required to be contiguous.

**10h — Post worklogs in parallel per day** (no bulk API):
```bash
for each record; do
  curl -s -X POST "https://api.tempo.io/4/worklogs" \
    -H "Authorization: Bearer ${TEMPO_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{...}' &
done
wait
```
On any failure, mark the day partial and continue.

**10i — One-line day result:**
```text
✅ <DATE> (<Day>) — <N> records, 8h 0m logged.
⚠️ <DATE> (<Day>) — partial, 5h 30m logged (API error on 2 records).
```

## Step 11: Grand summary
```text
🏁 fix-tempo complete
─────────────────────────────────
  Backfilled:  15 days
  Skipped:     4 weekends, 2 already logged, 3 no Jira activity
  Total logged: 120h 0m
─────────────────────────────────
```
Include: backfilled, weekends skipped, already logged, skipped (no activity), partial/error, total logged.

## Hard rules
- Never log without real Jira activity for that date; never use status transitions as the only signal; never fabricate work, meetings, or activity; never claim to fetch exact Tempo UI suggestions.
- No meetings-only days unless valid Jira activity exists for that date.
- Every Tempo record ≥ 30 min; every work entry = exactly one Tempo record (no splitting).
- Fully backfilled days = exactly 8h when safely possible; partial days fill only the gap.
- Never modify or delete existing worklogs; never double-book a slot.
- Meetings always under `TEMPO_MEETING_TICKET` and take priority; skip non-work calendar events; skip cancelled events (`STATUS:CANCELLED`, `METHOD:CANCEL`, cancelled recurrence overrides) and meetings the user declined (`PARTSTAT=DECLINED`).
- Only log work tickets from the selected main prefix.
- Skip weekends and days already ≥8h.
- Never log today — date range stops at yesterday (in the user's local timezone).
- Continue past API errors. Cache Jira issue ID lookups. Use the user's local timezone for all comparisons.

## Accuracy note (use when asked)
```text
This uses the best available approximation of Tempo's Jira activity suggestions through public Jira APIs.
Tempo's private Activity Feed can include signals that are not exposed publicly, so the result may not exactly match the cards shown in Tempo UI.
```

