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
3. Outputs a structured bug ticket ready to paste into Jira

The output covers: summary, root cause, steps to reproduce, expected behavior, and acceptance criteria — all based strictly on what was discussed in the conversation.
