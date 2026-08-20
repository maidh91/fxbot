# md.mq5

## Setup

1. Allow the Telegram API URL: **Tools > Options > Expert Advisors** → check
   "Allow WebRequest for listed URL" → add `https://api.telegram.org`.
2. Put your Telegram credentials in `MQL5/Files/.env` (same folder as this
   repo's parent `Files/` dir):

   ```
   TELEGRAM_BOT_TOKEN=<your bot token>
   TELEGRAM_CHAT_ID=<your chat id>
   ```
