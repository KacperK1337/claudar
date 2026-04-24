# jira-bug
Generate a Jira bug ticket title and description from the current conversation.

## Requirements
- No external tools required

## Installation
```bash
./install.sh jira-bug
```

## Usage
After debugging an issue in Claude Code, run:
```text
/jira-bug [additional context]
```
This command does not require a primary argument. Any text written after `/jira-bug` is treated as optional additional context and should be used to sharpen the generated ticket.

Examples:
```text
/jira-bug
/jira-bug focus on the user-visible impact
/jira-bug write this for the backend team and emphasize reproduction steps
```

You can also provide multiline context, for example:
```text
/jira-bug
make the acceptance criteria strict
highlight that this is intermittent
call out that the root cause is still unconfirmed if needed
```

## What it does
1. Analyzes the full conversation history to extract the bug context
2. Identifies the problem, root cause, affected area, reproduction steps, and any fix applied
3. Uses any additional context provided with the command to shape emphasis, wording, or level of detail
4. Outputs a structured bug ticket ready to paste into Jira

The output covers: summary, root cause, steps to reproduce, expected behavior, and acceptance criteria — all based strictly on what was discussed in the conversation.
