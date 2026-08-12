//+------------------------------------------------------------------+
//| SetSLTP_Panel.mq5                                                |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade trade;

input string InpTelegramEnvFile  = ".env"; // Env file (in MQL5\Files)
input bool   InpTelegramAlerts   = true;     // Alert on position open/close

string g_telegramBotToken = "";
string g_telegramChatID   = "";

#define EDIT_SL   "sltp_edit_sl"
#define EDIT_TP   "sltp_edit_tp"
#define BTN_SL    "sltp_btn_sl"
#define BTN_TP    "sltp_btn_tp"
#define LBL_SL    "sltp_lbl_sl"
#define LBL_TP    "sltp_lbl_tp"
#define BTN_CLOSE "sltp_btn_close"

// layout
#define X0     20
#define Y0     30
#define EDIT_W 120
#define BTN_W  90
#define GAP    6
#define ROW_H  40
#define CTRL_H 34

// close-all confirm state
bool     g_closeArmed = false;
datetime g_closeArmedAt = 0;
#define  CONFIRM_WINDOW 4   // seconds to confirm

//+------------------------------------------------------------------+
int OnInit()
{
   LoadTelegramEnv();

   int rowClose = Y0;
   int row1     = Y0 + ROW_H;
   int row2     = Y0 + ROW_H * 2;
   int btnX = X0 + EDIT_W + GAP;
   int lblX = btnX + BTN_W + GAP;

   CreateButton(BTN_CLOSE, X0, rowClose, EDIT_W + GAP + BTN_W, CTRL_H,
                "CLOSE ALL", clrDimGray);

   CreateEdit(EDIT_SL, X0,   row1, EDIT_W, CTRL_H, "0.0");
   CreateButton(BTN_SL, btnX, row1, BTN_W, CTRL_H, "SL", clrTomato);
   CreateLabel(LBL_SL, lblX, row1 + 10, "-");

   CreateEdit(EDIT_TP, X0,   row2, EDIT_W, CTRL_H, "0.0");
   CreateButton(BTN_TP, btnX, row2, BTN_W, CTRL_H, "TP", clrMediumSeaGreen);
   CreateLabel(LBL_TP, lblX, row2 + 10, "-");

   UpdateLabels();
   ChartRedraw();

   PrintFormat("OnInit: %d open position(s)", PositionsTotal());
   SendPositionsSnapshot();

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ObjectDelete(0, EDIT_SL);
   ObjectDelete(0, EDIT_TP);
   ObjectDelete(0, BTN_SL);
   ObjectDelete(0, BTN_TP);
   ObjectDelete(0, LBL_SL);
   ObjectDelete(0, LBL_TP);
   ObjectDelete(0, BTN_CLOSE);
   ChartRedraw();
}

void OnTick()
{
   // auto-disarm close button if confirm window elapsed
   if(g_closeArmed && TimeCurrent() - g_closeArmedAt > CONFIRM_WINDOW)
      DisarmClose();
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == BTN_CLOSE)
      {
         if(!g_closeArmed) ArmClose();
         else              { CloseAll(); DisarmClose(); }
         ObjectSetInteger(0, BTN_CLOSE, OBJPROP_STATE, false);
         UpdateLabels();
         ChartRedraw();
         return;
      }

      if(sparam == BTN_SL || sparam == BTN_TP)
      {
         bool   isSL     = (sparam == BTN_SL);
         string editName = isSL ? EDIT_SL : EDIT_TP;
         double price    = StringToDouble(ObjectGetString(0, editName, OBJPROP_TEXT));

         if(price <= 0)
            Print("Enter a valid price first.");
         else
            ApplyToAll(price, isSL);

         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         UpdateLabels();
         ChartRedraw();
      }
      return;
   }

   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(sparam == EDIT_SL || sparam == EDIT_TP)
      {
         UpdateLabels();
         ChartRedraw();
      }
   }
}

//+------------------------------------------------------------------+
//| Telegram alerts on position open/close                           |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong dealTicket = trans.deal;
   if(!HistoryDealSelect(dealTicket))
      return;

   long type = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
   if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
      return; // ignore balance/credit/etc.

   long   entry  = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   double volume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
   double price  = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
   double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                 + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                 + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
   string dir    = (type == DEAL_TYPE_BUY) ? "BUY" : "SELL";

   if(entry == DEAL_ENTRY_IN)
   {
      string msg = StringFormat("\U0001F7E2 Position OPENED\n%s %s\nVolume: %.2f\nPrice: %.5f",
                                 symbol, dir, volume, price);
      SendTelegramMessage(msg);
   }
   else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
   {
      string msg = StringFormat("\U0001F534 Position CLOSED\n%s %s\nVolume: %.2f\nPrice: %.5f\nP/L: %.2f",
                                 symbol, dir, volume, price, profit);
      SendTelegramMessage(msg);
   }
}

//+------------------------------------------------------------------+
//| Telegram snapshot of all open positions (sent once on start)     |
//+------------------------------------------------------------------+
void SendPositionsSnapshot()
{
   if(!InpTelegramAlerts) return;

   int total = PositionsTotal();
   if(total == 0)
   {
      SendTelegramMessage("ℹ️ Bot started. No open positions.");
      return;
   }

   string msg = StringFormat("ℹ️ Bot started. Open positions (%d):", total);
   double totalProfit = 0;

   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long   type   = PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);
      double profit = PositionGetDouble(POSITION_PROFIT)
                     + PositionGetDouble(POSITION_SWAP);
      string dir    = (type == POSITION_TYPE_BUY) ? "BUY" : "SELL";

      totalProfit += profit;

      msg += StringFormat("\n\n%s %s %.2f\nOpen: %.5f  SL: %s  TP: %s\nP/L: %.2f",
                           symbol, dir, volume, open,
                           (sl > 0 ? DoubleToString(sl, 5) : "-"),
                           (tp > 0 ? DoubleToString(tp, 5) : "-"),
                           profit);
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double pct     = (balance > 0) ? totalProfit / balance * 100.0 : 0;
   msg += StringFormat("\n\nTotal P/L: %.2f (%.1f%%)\nBalance: %.2f",
                        totalProfit, pct, balance);
   SendTelegramMessage(msg);
}

void LoadTelegramEnv()
{
   g_telegramBotToken = "";
   g_telegramChatID   = "";

   if(!FileIsExist(InpTelegramEnvFile))
   {
      PrintFormat("Telegram env file not found: MQL5\\Files\\%s (create it with TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID)",
                  InpTelegramEnvFile);
      return;
   }

   int handle = FileOpen(InpTelegramEnvFile, FILE_READ | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("Failed to open %s: %d", InpTelegramEnvFile, GetLastError());
      return;
   }

   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(line == "" || StringGetCharacter(line, 0) == '#')
         continue;

      int eq = StringFind(line, "=");
      if(eq <= 0)
         continue;

      string key = line;
      StringSetLength(key, eq);
      string value = StringSubstr(line, eq + 1);

      if(key == "TELEGRAM_BOT_TOKEN")
         g_telegramBotToken = value;
      else if(key == "TELEGRAM_CHAT_ID")
         g_telegramChatID = value;
   }
   FileClose(handle);
}

void SendTelegramMessage(string text)
{
   if(!InpTelegramAlerts || g_telegramBotToken == "" || g_telegramChatID == "")
      return;

   string url  = "https://api.telegram.org/bot" + g_telegramBotToken + "/sendMessage";
   string body = "chat_id=" + g_telegramChatID + "&text=" + UrlEncode(text);

   char   post[];
   int    bodyLen = StringToCharArray(body, post, 0, StringLen(body)) - 1;
   ArrayResize(post, bodyLen);

   char   response[];
   string responseHeaders;
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";

   ResetLastError();
   int res = WebRequest("POST", url, headers, 5000, post, response, responseHeaders);
   if(res == -1)
      PrintFormat("Telegram WebRequest failed (%d). Add %s to allowed URLs: Tools > Options > Expert Advisors.",
                  GetLastError(), "https://api.telegram.org");
   else if(res != 200)
      PrintFormat("Telegram send failed, HTTP %d: %s", res, CharArrayToString(response));
}

string UrlEncode(const string text)
{
   uchar utf8[];
   int   len = StringToCharArray(text, utf8, 0, -1, CP_UTF8) - 1; // drop trailing null
   if(len < 0) len = 0;

   string result = "";
   uchar  ch[1];

   for(int i = 0; i < len; i++)
   {
      uchar c = utf8[i];
      if((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
         c == '-' || c == '_' || c == '.' || c == '~')
      {
         ch[0] = c;
         result += CharArrayToString(ch, 0, 1);
      }
      else if(c == '\n')
         result += "%0A";
      else if(c == ' ')
         result += "+";
      else
         result += StringFormat("%%%02X", c);
   }
   return result;
}

//+------------------------------------------------------------------+
//| Close-all arm / disarm                                           |
//+------------------------------------------------------------------+
void ArmClose()
{
   g_closeArmed   = true;
   g_closeArmedAt = TimeCurrent();
   ObjectSetString (0, BTN_CLOSE, OBJPROP_TEXT, "CONFIRM?");
   ObjectSetInteger(0, BTN_CLOSE, OBJPROP_BGCOLOR, clrRed);
}

void DisarmClose()
{
   g_closeArmed = false;
   ObjectSetString (0, BTN_CLOSE, OBJPROP_TEXT, "CLOSE ALL");
   ObjectSetInteger(0, BTN_CLOSE, OBJPROP_BGCOLOR, clrDimGray);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Close every position, delete every pending order                 |
//+------------------------------------------------------------------+
void CloseAll()
{
   // positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!trade.PositionClose(ticket))
         PrintFormat("Close pos failed %I64u: %d", ticket, trade.ResultRetcode());
      else
         PrintFormat("Closed pos %I64u", ticket);
   }

   // pending orders
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!trade.OrderDelete(ticket))
         PrintFormat("Delete order failed %I64u: %d", ticket, trade.ResultRetcode());
      else
         PrintFormat("Deleted order %I64u", ticket);
   }
}

//+------------------------------------------------------------------+
double MoneyPerPrice(string symbol, double volume)
{
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickValue <= 0 || volume <= 0) return 0;
   return (tickValue / tickSize) * volume;
}

double TotalMoney(double price)
{
   if(price <= 0) return 0;
   double total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double volume = PositionGetDouble(POSITION_VOLUME);

      double mpp  = MoneyPerPrice(symbol, volume);
      if(mpp <= 0) continue;

      total += MathAbs(price - open) * mpp;
   }
   return total;
}

void UpdateLabels()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double slPrice = StringToDouble(ObjectGetString(0, EDIT_SL, OBJPROP_TEXT));
   double tpPrice = StringToDouble(ObjectGetString(0, EDIT_TP, OBJPROP_TEXT));

   ObjectSetString(0, LBL_SL, OBJPROP_TEXT, FormatMoneyPct(TotalMoney(slPrice), balance));
   ObjectSetString(0, LBL_TP, OBJPROP_TEXT, FormatMoneyPct(TotalMoney(tpPrice), balance));
}

string FormatMoneyPct(double money, double balance)
{
   if(money <= 0) return "-";
   double pct = (balance > 0) ? money / balance * 100.0 : 0;
   return StringFormat("%.2f (%.1f%%)", money, pct);
}

//+------------------------------------------------------------------+
void ApplyToAll(double price, bool isSL)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);
      double np     = NormalizeDouble(price, digits);

      if(isSL) sl = np; else tp = np;

      if(!trade.PositionModify(ticket, sl, tp))
         PrintFormat("Modify failed %I64u (%s): %d",
                     ticket, symbol, trade.ResultRetcode());
      else
         PrintFormat("OK %I64u (%s) SL=%.5f TP=%.5f", ticket, symbol, sl, tp);
   }
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
void CreateEdit(string name, int x, int y, int w, int h, string text)
{
   ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_LEFT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void CreateButton(string name, int x, int y, int w, int h, string text, color bg)
{
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void CreateLabel(string name, int x, int y, string text)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}