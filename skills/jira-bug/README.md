# jira-bug
Generate a Jira bug ticket title and description from the current conversation.

## Requirements
- No external tools required

## Installation
```
./install.sh jira-bug
```

## Usage
After debugging an issue in Claude Code, run:
```
/jira-bug
```

## What it does
1. Analyzes the full conversation history to extract the bug context
2. Identifies the problem, root cause, affected area, reproduction steps, and any fix applied
3. Suggests a priority level (Critical / Major / Minor / Trivial)
4. Outputs a structured bug ticket ready to paste into Jira

The output covers: summary, steps to reproduce, expected vs actual behavior, root cause, affected components, and fix details — all based strictly on what was discussed in the conversation.
