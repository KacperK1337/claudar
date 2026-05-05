---
name: jira-bug
description: generate a jira bug ticket title and description from the current conversation.
disable-model-invocation: true
---

You are a senior engineer writing a clear, actionable Jira bug ticket based on the conversation so far.

## Input handling

The raw user input is available as:

`$ARGUMENTS`

This skill does not require a primary argument.

Interpret `$ARGUMENTS` as optional additional context only:

- Additional context may contain spaces, bullets, punctuation, and multiple lines.
- Treat additional context as important user intent that should shape the ticket: emphasis, audience, wording, strictness of acceptance criteria, focus on reproduction steps, focus on user-visible impact, or explicit instructions about what to highlight or de-emphasize.
- If the additional context conflicts with the conversation evidence, call out the conflict implicitly by following the conversation facts and not inventing unsupported details.

Before producing the ticket, briefly summarize any additional context provided. If none was provided, say that none was supplied.

## Step 1: Analyze the conversation

Review the entire conversation history and extract:

1. **The problem** - what was broken, failing, or behaving unexpectedly.
2. **Root cause** - what was identified as the underlying issue (if found).
3. **Affected area** - which files, modules, services, or features are involved.
4. **Steps to reproduce** - how the user encountered or triggered the bug, based on what they described.
5. **Solution applied** - what fix was discussed or implemented (if any).

If any of these are unclear or not present in the conversation, note them as "Unknown" or "N/A" - do not fabricate details.

Apply any additional user context only to shape emphasis, clarity, and structure. Do not let it override the factual record of the conversation.

## Step 2: Produce the ticket

Output the ticket in the following format. Use plain text suitable for pasting directly into Jira.

```text
## Title
<concise, specific title - what's broken and where, max ~80 chars>

## Description

### Summary
<1-2 sentences: what the bug is and its user-visible impact>

### Root Cause
<brief explanation of why it happens, if identified in the conversation>

### Steps to Reproduce
<numbered list of steps to trigger the issue - be specific>

### Expected Behavior
<what should happen>

### Acceptance Criteria
<bulleted list of conditions that must be true when the bug is resolved>
```

---

## Rules

- Be specific and factual. Every detail must come from the conversation - do not invent scenarios or assume details not discussed.
- Keep the title short and scannable. Lead with the symptom, not the cause. Example: "Login fails with 500 when email contains '+'" not "Fix regex in auth service".
- Write for someone who was NOT in this conversation. They should understand the bug without additional context.
- If the conversation didn't cover reproduction steps clearly, write what you can infer and mark gaps with "[needs verification]".
- Do not include internal conversation details, back-and-forth discussion, or meta-commentary. Just the clean ticket.
- Use any additional context only to improve the usefulness of the ticket, not to add unsupported facts.
