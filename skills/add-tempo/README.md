# add-tempo
Log a single workday to Tempo: your calendar meetings + the work you actually did, in one command.

## Why use it
At the end of the day, opening Tempo and creating an entry for every meeting and every task you worked on is slow and easy to forget. 
This skill takes a one-liner - a list of tickets and how long you spent on each - combines it with the meetings on your calendar, and posts the whole 8-hour day to Tempo in one go.

You write what you worked on.
The skill handles the meetings, the math (filling to 8h), and the scheduling (no overlaps, no double-bookings).

## Quick example
```text
/add-tempo AB-1234 1h coding, AB-9999 30 min PR review, AB-5555 3h bugfixes
```

Combined with two calendar meetings (a 30-minute daily and a 1-hour planning call), the skill produces this Tempo log for today:
```
📋 Tempo Log for 2026-05-05
─────────────────────────────────────────────
  Time        │ Ticket   │ Duration │ Description
  09:00-10:30 │ AB-1234  │ 1h 30m   │ coding (grown +30m)
  10:30-11:30 │ AB-9999  │ 1h 0m    │ PR review (grown +30m)
  11:30-12:00 │ AB-1234  │ 0h 30m   │ Daily Standup
  12:00-13:00 │ AB-1234  │ 1h 0m    │ Planning
  13:00-17:00 │ AB-5555  │ 4h 0m    │ bugfixes (grown +1h)
─────────────────────────────────────────────
  Total: 8h 0m / 8h 0m  ✅
```

The original entries totalled 4h 30m of work plus 1h 30m of meetings = 6h, leaving a 2h gap.
The skill walked the entries longest-first - bugfixes (3h) → coding (1h) → PR review (30m) - adding 30m per step and looping back to the top, until the day hit 8h.

The 8-hour total is reached automatically - always exactly 8h, no exceptions.
If your entries (plus meetings and anything already on the day) don't add up to 8h, the skill grows or shrinks your work entries in **30-minute steps**, starting from the longest entry and walking down to the shortest, until the day balances.
Looping back to the top each pass keeps the original proportions roughly intact.
If a leftover gap of less than 30 minutes remains (for example because a 45-minute meeting breaks the 30-minute grid), the skill applies one final **residual** adjustment to the next entry in the walk order - the only non-30 step allowed - so the day always lands on exactly 480 minutes.
Meetings and existing entries are never touched, and no entry is ever shrunk below 30 minutes.

## Setup
You need `curl` and `jq` on your machine, plus the following environment variables exported in your shell:

```bash
# Tempo
export TEMPO_API_TOKEN="your-tempo-api-token"
export TEMPO_MEETING_TICKET="AB-1234"   # Ticket key for which all meetings will be logged

# Jira (used to look up your account ID and ticket internal IDs)
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

Your Jira **account ID** is fetched automatically - you don't need to export it.

## Installation
```bash
./install.sh add-tempo
```

## Usage
Basic shape:
```text
/add-tempo [DATE] <TICKET> <DURATION> [DESCRIPTION], <TICKET> <DURATION> [DESCRIPTION], ...
```

Examples:
```text
/add-tempo AB-1234 1 hour, AB-9999 30 min, AB-5555 3h
/add-tempo AB-1234 1 hour coding, AB-9999 30 min PR review, AB-5555 3h bugfixes
/add-tempo yesterday AB-1234 2h code review
/add-tempo 2026-04-01 AB-1234 1h
```

Notes on the input format:
- **Ticket** - any Jira key like `AB-1234`. The same key may appear multiple times; each comma-separated entry is its own record.
- **Duration** - flexible: `1 hour`, `1h`, `30 min`, `30m`, `1.5h`, `90 min`. Each entry must be at least 30 minutes.
- **Description** - everything after the duration. Optional. If left out, defaults to "Work on `<TICKET>`".
- **Date prefix** - optional. Without it, the skill targets **today**. With it, you can pass `today`, `yesterday`, `2026-04-01`, `april 1`, `last monday`, etc. (Same flexible date handling as `fill-tempo-meetings`.)

## What happens when you run it
1. The skill reads your Outlook calendar for the target day, your existing Tempo entries for that day, and looks up the internal IDs for every ticket you mentioned - all in parallel.
2. **Meetings**: every real work meeting on the calendar gets a planned entry under your meeting ticket. Lunches, gym, declined meetings, and anything cancelled are skipped. Meetings that already exist as Tempo entries are not duplicated.
3. **Your work entries**: parsed from your one-liner, in order.
4. **The 8-hour rule**: existing entries + new meetings + your work entries always equal exactly 8 hours. If the day is short, the skill adds 30 minutes to your work entries one at a time, starting with the longest and cycling back to the top until the next +30 would overshoot. If the day is over, it subtracts 30 minutes the same way (longest first, never below 30 minutes). Any leftover gap of less than 30 minutes (e.g. from a 45-minute meeting) is closed by a single non-30 residual step on the next entry in the walk order, so the day always lands on 480 minutes exactly. Meetings and existing entries are never touched.
5. **Scheduling**: the day is laid out starting at 09:00. Each work entry is placed in the next gap that fits it whole - entries are never split across meetings. Existing entries on the day are treated as immovable, just like meetings.
6. **Posting**: every new record (meetings + work entries) is sent to Tempo in one parallel batch. Existing entries are never re-posted, modified, or deleted.
7. You get a final table showing every record on the day, marking which ones are new vs already there.

## Safety guarantees
- Existing Tempo entries are read-only - never edited, moved, or deleted.
- Meetings already logged for the day are not duplicated.
- Each user entry is exactly one Tempo record (never split across meeting gaps).
- Every new record is at least 30 minutes.
- Time slots are never double-booked.
- Calendar events are taken as-is; nothing is fabricated.
- If a Tempo POST fails, you see the error and the run stops - nothing is silently skipped.
