# Project conventions for Claude Code

## Markdown writing style

In every Markdown file in this repo (top-level `README.md`, every `skills/*/README.md`, and any other docs), put **one sentence per line** in prose paragraphs.

If a paragraph contains more than one sentence, the second and later sentences must start on a new line.

Apply this rule when creating or editing any Markdown file in the repo.

### Yes
```
The argument is optional.
Anything you type after the command is treated as additional context.
```

### No
```
The argument is optional. Anything you type after the command is treated as additional context.
```

### Scope and exceptions
- Applies to prose paragraphs only.
- Do **not** split sentences inside fenced code blocks (``` ... ```) - keep code/output verbatim.
- Do **not** split inside table rows, headings, or list items that are themselves a single line - leave their formatting intact.
- Abbreviations like `e.g.`, `i.e.`, `etc.`, version numbers (`1.5h`), and decimals are not sentence boundaries; do not split on them.
- Trailing whitespace at end of lines is fine; do not add or strip it just to satisfy this rule.
