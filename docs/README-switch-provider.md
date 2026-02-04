# claude-provider-switch

A simple Bash script to quickly switch between Claude API providers (Claude MAX / Official Anthropic vs z.ai) while preserving OAuth authentication.

## Features

- 🔄 **Quick Switching**: Toggle between Claude MAX and z.ai API with one command
- 🔐 **OAuth Support**: Preserves your OAuth token across providers
- 💾 **Automatic Backups**: Creates timestamped backups before each switch
- 📊 **Status Check**: See which provider is currently active
- ✅ **Safe**: Only modifies the `ANTHROPIC_BASE_URL` setting

## Installation

1. Clone or download `switch-provider.sh`
2. Make it executable:
   ```bash
   chmod +x switch-provider.sh
   ```

3. (Optional) Add to your PATH for global access:
   ```bash
   sudo cp switch-provider.sh /usr/local/bin/claude-provider
   ```

## Usage

### Switch to Claude MAX (Official Anthropic API)
```bash
./switch-provider.sh claude
# or
./switch-provider.sh max
# or
./switch-provider.sh official
```

### Switch to z.ai API
```bash
./switch-provider.sh zai
# or
./switch-provider.sh z.ai
```

### Check Current Provider
```bash
./switch-provider.sh status
```

### Help
```bash
./switch-provider.sh help
```

## Requirements

- Bash shell
- `jq` (JSON processor) - Install via:
  - macOS: `brew install jq`
  - Linux: `sudo apt-get install jq` or `sudo yum install jq`
- Claude Code CLI installed
- OAuth token configured in `~/.claude/settings.json`

## How It Works

The script modifies `~/.claude/settings.json`:

**Claude MAX (Official):**
- Removes `ANTHROPIC_BASE_URL` → uses default Anthropic API
- Keeps your OAuth token intact

**z.ai API:**
- Sets `ANTHROPIC_BASE_URL` to `https://api.z.ai/api/anthropic`
- Keeps your OAuth token intact

## Example Output

```bash
$ ./switch-provider.sh claude
🔄 Switching to Claude MAX (Official Anthropic API)...
✅ Now using: Claude MAX (Official Anthropic API)
   OAuth Token: 103fb7dcae63463b8aba...
   Backup saved: /Users/user/.claude/settings.json.backup.20250130_175924

$ ./switch-provider.sh status
📊 Current Provider Configuration:
─────────────────────────────────
Base URL: default (Anthropic Official)
OAuth Token: 103fb7dcae63463b8aba...

✅ Using: Claude MAX (Official Anthropic)
```

## Use Cases

- **Claude MAX Subscription**: Use official Anthropic API with your MAX benefits
- **z.ai Alternative**: Switch to z.ai for cost-effective GLM Coding Plan access
- **Testing**: Compare responses between providers
- **Development**: Use different providers for different projects

## Backups

Every switch creates a backup:
```
~/.claude/settings.json.backup.20250130_175924
```

Restore a backup if needed:
```bash
cp ~/.claude/settings.json.backup.20250130_175924 ~/.claude/settings.json
```

## Troubleshooting

### `jq: command not found`
Install jq JSON processor:
```bash
brew install jq  # macOS
```

### Permission denied
Make script executable:
```bash
chmod +x switch-provider.sh
```

### Settings file not found
Ensure Claude Code CLI is installed and has been run at least once to create the settings file.

## License

MIT License - Feel free to use, modify, and distribute

## Contributing

Contributions welcome! Feel free to submit issues or pull requests.

## Disclaimer

This tool is not officially affiliated with Anthropic or z.ai. Use at your own risk.
