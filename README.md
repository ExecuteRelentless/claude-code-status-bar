# Claude Code Status Bar

A status line script for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows live usage data, git status, and conversation context at a glance.

![Status Bar Example](screenshot.png)

## What it shows

```
Opus 4.6 (1M) | 📁my-project | 🔀main (2 files uncommitted, synced 3m ago) | Session 20% resets at 10:00 PM | Week 11% resets Wed 8:00 PM
💬 last user message preview
```

- **Model** - Current model name
- **Directory** - Working directory name
- **Git branch** - Branch name, uncommitted file count, sync status (ahead/behind/synced), last fetch time
- **Session usage** - 5-hour window utilization % and reset time (local timezone)
- **Weekly usage** - 7-day window utilization % and reset time (local timezone)
- **Last message** - Preview of your last message in the conversation (second line)

## Requirements

- `jq` - JSON processor (`brew install jq` on macOS)
- `git` - For git status features (optional, gracefully skipped if not in a repo)

## Installation

1. Download the script:

```bash
mkdir -p ~/.claude/scripts
curl -o ~/.claude/scripts/context-bar.sh \
  https://raw.githubusercontent.com/ExecuteRelentless/claude-code-status-bar/main/context-bar.sh
chmod +x ~/.claude/scripts/context-bar.sh
```

2. Add to your Claude Code settings (`~/.claude/settings.json`):

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/scripts/context-bar.sh"
  }
}
```

3. Restart Claude Code. The status bar appears at the bottom of the terminal.

## How it works

Claude Code pipes a JSON object to the status line command's stdin on every render. This JSON includes:

- `.model.display_name` - Current model
- `.cwd` - Working directory
- `.transcript_path` - Path to conversation transcript
- `.rate_limits.five_hour.used_percentage` / `.rate_limits.five_hour.resets_at` - Session usage
- `.rate_limits.seven_day.used_percentage` / `.rate_limits.seven_day.resets_at` - Weekly usage

The script reads this input directly - no API calls, no caching, no authentication needed. Usage numbers update live on every render.

### Why not use the API?

An earlier version fetched usage from `https://api.anthropic.com/api/oauth/usage`, but that endpoint returns 429 (rate limited) while a Claude Code session is active. Reading from the input JSON is instant and always up to date.

## Customization

The script is a single bash file - edit it to add/remove sections or change formatting. Some ideas:

- Remove the git section if you don't need it
- Remove the last message line if you prefer a single-line status bar
- Change the emoji icons
- Add additional data from the input JSON

## Platform support

- **macOS** - Fully supported (uses `stat -f`, `date -r`, macOS `date -j`)
- **Linux** - Supported with fallbacks (uses `stat -c`, `date -d`)

## License

MIT
