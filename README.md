# claudar
A collection of Claude Code skills ready to install and use.

Current available skills can be checked in [skills](skills) directory.
For each there is a README.md with details on what it does and which tools it requires (claude is required by default and not listed).

## Installation
Clone the repo and run the `install.sh` script with the skill you want to install:
```bash
git clone git@github.com:KacperK1337/claudar.git
cd claudar
./install.sh <skill-name>
```

The script will check if required tools for selected skill are installed, 
then it will copy the skill to `~/.claude/skills/` so it's available globally.

## Uninstalling
Remove the skill directory from `~/.claude/skills/`:
```bash
rm -rf ~/.claude/skills/<skill-name>
```

## Contributing
To add a skill create a directory with the name for it under [skills](skills) with:
- `SKILL.md` — the skill definition (see [Claude Code docs](https://docs.anthropic.com/en/docs/claude-code) for correct format)
- `requirements.txt` — one CLI tool per line that must be available for the skill to work (leave empty if there are none)
- `README.md` — description of the skill, its requirements, usage, examples, what it does (see existing skills for examples)
