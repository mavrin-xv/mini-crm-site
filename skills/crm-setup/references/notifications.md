# Notifications

The Worker saves the lead first, answers the visitor, and only then sends alerts inside `ctx.waitUntil`. A dead bot never loses a lead. Every attempt is logged in `lead_events` as `notify_ok` or `notify_fail` with the error text, visible in the lead's event log on the board.

## Telegram
1. In Telegram, open `@BotFather`, send `/newbot`, pick a name. It replies with a token. That is `TG_BOT_TOKEN`.
2. Send any message to your new bot from the account (or group) that should receive leads. A bot cannot write to someone who never started it.
3. Open `https://api.telegram.org/bot<TOKEN>/getUpdates` in a browser. Find `"chat":{"id": ...}`. That number is `TG_CHAT_ID`. Group ids are negative; keep the minus sign.
4. For a group: add the bot to the group, send a message there, read `getUpdates` again.
5. Test before deploying:
   ```bash
   curl -s "https://api.telegram.org/bot<TOKEN>/sendMessage" -d chat_id=<CHAT_ID> -d text=test
   ```
   `"ok":true` means it works.

Messages use `parse_mode: HTML`. Every value from the form goes through `escapeHtml` in `src/lib.js`. If you add a field to the message, escape it too, or a `<` in a customer's message makes Telegram reject the whole alert.

Treat the bot token like a password. Anyone with it can read what the bot receives and send as the bot. If it leaks, `/revoke` in BotFather and set the new one with `wrangler secret put`.

## Webhook (Slack, Discord, anything else)
Set `NOTIFY_WEBHOOK_URL`. The Worker POSTs JSON `{"text": "...", "content": "..."}` with the same message: Slack reads `text`, Discord reads `content`. Formatting is plain text with HTML tags stripped.

## What gets sent
| When | Message |
|---|---|
| New lead | Name, phone, service, date, area, message, source, link to the board |
| Lead still "new" after `FIRST_CONTACT_SLA_MIN` (15) minutes, inside `WORK_HOURS` | "Not called yet" list, once per lead |
| Daily at `DIGEST_HOUR` local time | Counts by status, follow-ups due today, leads nobody called |

Outside work hours late-lead alerts wait until the morning. The digest covers them.

## Debug order
1. Board, open the lead, read the event log: `notify_fail` shows the error.
2. `npx wrangler tail` while sending a test lead.
3. Run the curl test above with the same token and chat id.
