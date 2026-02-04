# Telegram Bot Setup

Telegram is the **fallback** channel for OpenClaw. Slack is primary. Telegram activates when Slack is unavailable or for mobile notifications.

## 1. Create Bot via @BotFather

1. Open Telegram, search for `@BotFather`
2. Send `/newbot`
3. Choose a display name (e.g., `OpenClaw Bot`)
4. Choose a username (must end in `bot`, e.g., `openclaw_prod_bot`)
5. BotFather returns a **bot token** — save this

## 2. Save Bot Token

```bash
# Replace with the token from BotFather
echo "123456:ABC-DEF..." > secrets/telegram_token.txt
chmod 600 secrets/telegram_token.txt
```

The token is mounted into the openclaw container as a Docker secret at `/run/secrets/telegram_token`.

## 3. Get Your Chat ID

1. Send any message to your new bot in Telegram
2. Run:
   ```bash
   curl -s "https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates" | jq '.result[0].message.chat.id'
   ```
3. Copy the numeric chat ID

## 4. Configure channels.json

The chat ID and bot token are referenced in `config/channels.json`:

```json
{
  "channels": {
    "telegram": {
      "enabled": true,
      "primary": false,
      "botToken": "${TELEGRAM_BOT_TOKEN}",
      "chatId": "${TELEGRAM_ADMIN_CHAT_ID}",
      "webhookUrl": "https://openclaw.yourdomain.com/webhook/telegram",
      "allowedUsers": ["${TELEGRAM_ADMIN_USER_ID}"]
    }
  }
}
```

- `primary: false` — Telegram is fallback only; Slack is primary
- `webhookUrl` — Replace `yourdomain.com` with your actual domain
- `allowedUsers` — Restrict who can interact with the bot

## 5. Set Webhook URL

After deploying with Cloudflare Tunnel, set the webhook so Telegram sends updates to your server:

```bash
curl -X POST "https://api.telegram.org/bot<YOUR_TOKEN>/setWebhook" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://openclaw.yourdomain.com/webhook/telegram"}'
```

Verify webhook is set:

```bash
curl -s "https://api.telegram.org/bot<YOUR_TOKEN>/getWebhookInfo" | jq .
```

## 6. Agent Binding

Telegram is **not** bound to any agent by default. The only default binding is:

| Channel | Agent | Role |
|---------|-------|------|
| Slack `#openclaw` | magnifico | Primary Interface |

Telegram is used by the rescue bot for emergency fallback notifications (see `config/rescue-bot-setup.md`).

## Verification

```bash
# Token secret exists
cat secrets/telegram_token.txt

# Secret is in docker-compose.yml
docker compose config | grep telegram_token

# Webhook URL in channels.json
python3 -c "import json; ch=json.load(open('config/channels.json')); print(ch['channels']['telegram']['webhookUrl'])"
```
