# fill-tempo-meetings
Backfill missing Tempo logs for past calendar meetings only.
Logging meetings under specific ticket from Tempo UI is hard. This skill focus on automating that process.

## Requirements

### CMD tools
- `curl` installed
- `jq` installed

### Environment Variables
```bash
# Tempo:
export TEMPO_API_TOKEN="your-tempo-api-token"
export TEMPO_MEETING_TICKET="AB-1234"

# Jira, used only to resolve your account ID and the meeting ticket issue ID:
export JIRA_ORG="your-org"
export JIRA_EMAIL="you@company.com"
export JIRA_API_TOKEN="your-atlassian-api-token"

# Outlook Calendar:
export OUTLOOK_ICS_URL="url.ics"
```

Here's how to get each of those:
- `TEMPO_API_TOKEN`: Tempo -> Settings -> API Integration -> create a new token.
- `TEMPO_MEETING_TICKET`: the Jira ticket key you use to log meetings under, e.g. `ABC-1234`.
- `JIRA_ORG`: the slug in your Jira URL `https://<org>.atlassian.net`.
- `JIRA_EMAIL`: the email tied to your Atlassian account.
- `JIRA_API_TOKEN`: create at https://id.atlassian.com/manage-profile/security/api-tokens.
- `OUTLOOK_ICS_URL`: Outlook -> Calendar -> Share -> Publish a calendar -> copy the ICS link.

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
```

The date argument is flexible:
- `april 1` -> April 1st of the current year
- `january 2026` -> January 1st, 2026 (missing day defaults to the 1st)
- `2026` -> January 1st, 2026
- `2026-04-01`, `04/01/2026`, `last monday`, `3 weeks ago` all work too

Whatever you pass, the skill backfills every workday from that date through **yesterday**. Today is never touched.

## What it does
1. Builds a list of workdays from the provided start date to yesterday.
2. Fetches your Outlook ICS calendar once.
3. Fetches existing Tempo worklogs for the full date range.
4. For each workday:
   - Extracts real calendar meetings from Outlook ICS.
   - Skips non-work events, cancelled meetings, declined meetings, all-day events, and meetings under 30 minutes.
   - Handles common recurring meetings, `EXDATE`, and cancelled recurrence overrides.
   - Skips meetings already covered by existing meeting worklogs.
   - Treats meeting times as authoritative.
   - Moves existing non-meeting Tempo records when they conflict with meeting windows.
   - Shortens existing non-meeting records if adding meetings would push the day above 8h.
   - Logs each remaining meeting under `TEMPO_MEETING_TICKET` with the real meeting duration.
5. Prints a one-line result for each day and a grand total at the end.

## Safety rules
- Meetings only.
- One Tempo record per meeting.
- Every record is at least 30 minutes.
- Meeting durations are never trimmed.
- Existing non-meeting records can be moved or shortened to make room for meetings.
- The final day is kept at or below 8h total logged time when safely possible.
- Already-covered meetings are skipped.
- Weekends and today are skipped.
