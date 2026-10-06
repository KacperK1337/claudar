# jira-bug
Turn a debugging conversation into a paste-ready Jira bug ticket.

## Why use it
After you've spent an hour digging through logs and stack traces with Claude, the last thing you want to do is rewrite the whole story into a Jira ticket. 
This skill reads the conversation that just happened, pulls out the problem, the root cause, the steps to reproduce, and the fix, and gives you a structured ticket you can drop straight into Jira.
It uses only what was actually discussed - no guessing, no padding.

## Quick example
After debugging an intermittent 500 error with Claude, run:
```text
/jira-bug
```

You get back something like:
```
## Title
Intermittent 500 on POST /orders when cart contains a discounted item

## Description

### Summary
Placing an order right after creating a cart with a discounted item fails with a 500 about 1 time in 5.

### Root Cause
Discount lookup races with cart serialization; null is read before the discount worker finishes writing.

### Steps to Reproduce
1. Create a cart with a single discounted item.
2. Submit POST /orders within ~50 ms of cart creation.
3. Observe 500 in 1-3 attempts out of 10.

### Expected Behavior
Order creation succeeds and the discount is applied.

### Acceptance Criteria
- Order creation never returns 500 due to discount race.
- Existing happy-path orders are unaffected.
- Regression test added covering the timing window.
```

You can sharpen the output by adding context after the command:
```text
/jira-bug focus on the user-visible impact
/jira-bug write this for the backend team and emphasize reproduction steps
```

## Setup
No external tools or environment variables needed.
The skill works entirely off the current Claude Code conversation.

## Installation
```bash
./install.sh jira-bug
```

## Usage
Basic shape:
```text
/jira-bug [additional context]
```

The argument is optional.
Anything you type after `/jira-bug` becomes guidance for shaping the ticket - audience, emphasis, level of detail.

Multiline context works too:
```text
/jira-bug
make the acceptance criteria strict
highlight that this is intermittent
call out that the root cause is still unconfirmed if needed
```

## What happens when you run it
1. The skill reads the full conversation history in the current session.
2. It pulls out the bug-relevant pieces: what broke, what was expected, what was tried, what worked.
3. Any context you passed with the command shapes the wording, audience, or focus areas.
4. It produces a structured ticket with: title, summary, root cause, steps to reproduce, expected behavior, and acceptance criteria.
5. It checks the ticket before sending: title length, all sections present, nothing invented, no conversation chatter.
If a check fails, it fixes the ticket and checks again.
6. The output is plain text, ready to paste into Jira.

## Safety guarantees
- Only uses information present in the current conversation - no fabrication, no general advice.
- If the root cause is unconfirmed, the ticket says so rather than guessing.
- No external services are contacted; nothing leaves your machine.
- No files are read or written.
