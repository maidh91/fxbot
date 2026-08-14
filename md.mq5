//+------------------------------------------------------------------+
//| SetSLTP_Panel.mq5                                                |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade trade;

input string InpTelegramEnvFile      = ".env"; // Env file (in MQL5\Files)
input bool   InpTelegramAlerts       = true;    // Alert on position open/close
input double InpReportIntervalHours  = 4;       // Periodic position report (hours, 0=off)

string   g_telegramBotToken = "";
string   g_telegramChatID   = "";
datetime g_lastReportTime   = 0;

#define EDIT_SL        "sltp_edit_sl"
#define EDIT_TP        "sltp_edit_tp"
#define BTN_SL         "sltp_btn_sl"
#define BTN_TP         "sltp_btn_tp"
#define LBL_SL         "sltp_lbl_sl"
#define LBL_TP         "sltp_lbl_tp"
#define BTN_CLOSE      "sltp_btn_close"
#define BTN_CLOSE_BUY  "sltp_btn_close_buy"
#define BTN_CLOSE_SELL "sltp_btn_close_sell"
#define LBL_POS        "sltp_lbl_pos"
#define LBL_SELLS      "sltp_lbl_sells"
#define LBL_BUYS       "sltp_lbl_buys"
#define LBL_RISK       "sltp_lbl_risk"
#define LBL_REWARD     "sltp_lbl_reward"

// layout
#define X0      20
#define Y0      30
#define EDIT_W  120
#define BTN_W   90
#define GAP     6
#define ROW_H   40
#define CTRL_H  34
#define PANEL_W (EDIT_W + GAP + BTN_W)
#define INFO_H  26

// close confirm state ("" = nothing armed)
string   g_armedBtn     = "";
datetime g_closeArmedAt = 0;
datetime g_lastUiUpdate = 0;
#define  CONFIRM_WINDOW 4   // seconds to confirm

// snapshot of the open positions, refreshed for the info section
struct PosStats
{
   int    total;
   int    buyCount;
   double buyVolume;
   int    sellCount;
   double sellVolume;
   int    withSL;
   double slTotal;
   int    withTP;
   double tpTotal;
};

//+------------------------------------------------------------------+
int OnInit()
{
   LoadTelegramEnv();

   int rowClose = Y0;
   int rowBuy   = Y0 + ROW_H;
   int rowSell  = Y0 + ROW_H * 2;
   int row1     = Y0 + ROW_H * 3;
   int row2     = Y0 + ROW_H * 4;
   int rowInfo  = Y0 + ROW_H * 5;
   int btnX = X0 + EDIT_W + GAP;
   int lblX = btnX + BTN_W + GAP;

   // full-width rows: a half-width button clips "CLOSE SELL"
   CreateButton(BTN_CLOSE, X0, rowClose, PANEL_W, CTRL_H,
                BtnLabel(BTN_CLOSE), BtnColor(BTN_CLOSE));
   CreateButton(BTN_CLOSE_BUY, X0, rowBuy, PANEL_W, CTRL_H,
                BtnLabel(BTN_CLOSE_BUY), BtnColor(BTN_CLOSE_BUY));
   CreateButton(BTN_CLOSE_SELL, X0, rowSell, PANEL_W, CTRL_H,
                BtnLabel(BTN_CLOSE_SELL), BtnColor(BTN_CLOSE_SELL));

   CreateEdit(EDIT_SL, X0,   row1, EDIT_W, CTRL_H, "0.0");
   CreateButton(BTN_SL, btnX, row1, BTN_W, CTRL_H, "SL", clrTomato);
   CreateLabel(LBL_SL, lblX, row1 + 10, "-");

   CreateEdit(EDIT_TP, X0,   row2, EDIT_W, CTRL_H, "0.0");
   CreateButton(BTN_TP, btnX, row2, BTN_W, CTRL_H, "TP", clrMediumSeaGreen);
   CreateLabel(LBL_TP, lblX, row2 + 10, "-");

   CreateLabel(LBL_POS,    X0, rowInfo,              "-", clrGold);
   CreateLabel(LBL_SELLS,  X0, rowInfo + INFO_H,     "-", clrTomato);
   CreateLabel(LBL_BUYS,   X0, rowInfo + INFO_H * 2, "-", clrMediumSeaGreen);
   CreateLabel(LBL_RISK,   X0, rowInfo + INFO_H * 3, "-", clrTomato);
   CreateLabel(LBL_REWARD, X0, rowInfo + INFO_H * 4, "-", clrMediumSeaGreen);

   UpdateLabels();
   ChartRedraw();

   PrintFormat("OnInit: %d open position(s)", PositionsTotal());
   SendPositionsSnapshot("ℹ️ Bot started");
   g_lastReportTime = TimeCurrent();

   EventSetTimer(60);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();

   ObjectDelete(0, EDIT_SL);
   ObjectDelete(0, EDIT_TP);
   ObjectDelete(0, BTN_SL);
   ObjectDelete(0, BTN_TP);
   ObjectDelete(0, LBL_SL);
   ObjectDelete(0, LBL_TP);
   ObjectDelete(0, BTN_CLOSE);
   ObjectDelete(0, BTN_CLOSE_BUY);
   ObjectDelete(0, BTN_CLOSE_SELL);
   ObjectDelete(0, LBL_POS);
   ObjectDelete(0, LBL_SELLS);
   ObjectDelete(0, LBL_BUYS);
   ObjectDelete(0, LBL_RISK);
   ObjectDelete(0, LBL_REWARD);
   ChartRedraw();
}

void OnTick()
{
   // auto-disarm close button if confirm window elapsed
   if(g_armedBtn != "" && TimeCurrent() - g_closeArmedAt > CONFIRM_WINDOW)
      DisarmClose();

   // refresh the info section at most once per second
   if(TimeCurrent() != g_lastUiUpdate)
   {
      g_lastUiUpdate = TimeCurrent();
      UpdateLabels();
      ChartRedraw();
   }
}

void OnTimer()
{
   UpdateLabels();
   ChartRedraw();

   if(InpReportIntervalHours <= 0) return;

   if(TimeCurrent() - g_lastReportTime >= InpReportIntervalHours * 3600)
   {
      SendPositionsSnapshot("ℹ️ Periodic report");
      g_lastReportTime = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == BTN_CLOSE || sparam == BTN_CLOSE_BUY || sparam == BTN_CLOSE_SELL)
      {
         if(g_armedBtn != sparam)
            ArmClose(sparam);
         else
         {
            if(sparam == BTN_CLOSE)           { ClosePositions(-1); DeletePendingOrders(); }
            else if(sparam == BTN_CLOSE_BUY)    ClosePositions(POSITION_TYPE_BUY);
            else                                ClosePositions(POSITION_TYPE_SELL);
            DisarmClose();
         }
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
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
   // any trade activity can change the position list, so refresh the
   // info section here rather than waiting for the next tick / timer
   UpdateLabels();
   ChartRedraw();
   g_lastUiUpdate = TimeCurrent();

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

   int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(digits <= 0) digits = 5;
   string priceStr = DoubleToString(price, digits);

   if(entry == DEAL_ENTRY_IN)
   {
      string msg = StringFormat("🟢 Position OPENED\n%s %s\nVolume: %.2f\nPrice: %s",
                                 symbol, dir, volume, priceStr);
      SendTelegramMessage(msg);
   }
   else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
   {
      // the closing deal is the opposite side of the position it closed
      string posDir  = (type == DEAL_TYPE_BUY) ? "SELL" : "BUY";
      string plEmoji = (profit > 0) ? "💰" : (profit < 0) ? "🔥" : "";
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);

      string msg = StringFormat("🔴 Position CLOSED\n%s %s\nVolume: %.2f\nPrice: %s\nP/L: %.2f %s\nBalance: %.2f",
                                 symbol, posDir, volume, priceStr, profit, plEmoji, balance);
      SendTelegramMessage(msg);
   }
}

//+------------------------------------------------------------------+
//| Telegram snapshot of all open positions (on start + periodic)    |
//+------------------------------------------------------------------+
void SendPositionsSnapshot(string header = "ℹ️ Position report")
{
   if(!InpTelegramAlerts) return;

   int total = PositionsTotal();
   if(total == 0)
   {
      SendTelegramMessage(StringFormat("%s. No open positions.\nBalance: %.2f",
                                       header, AccountInfoDouble(ACCOUNT_BALANCE)));
      return;
   }

   string msg = StringFormat("%s. Open positions (%d):", header, total);
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
      string dir      = (type == POSITION_TYPE_BUY) ? "🟢 BUY" : "🔴 SELL";
      string plEmoji  = (profit > 0) ? "💰" : (profit < 0) ? "🔥" : "";

      totalProfit += profit;

      msg += StringFormat("\n\n%s %s %.2f\nOpen: %.5f  SL: %s  TP: %s\nP/L: %.2f %s",
                           symbol, dir, volume, open,
                           (sl > 0 ? DoubleToString(sl, 5) : "-"),
                           (tp > 0 ? DoubleToString(tp, 5) : "-"),
                           profit, plEmoji);
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
string BtnLabel(const string name)
{
   if(name == BTN_CLOSE)     return "CLOSE ALL";
   if(name == BTN_CLOSE_BUY) return "CLOSE BUY";
   return "CLOSE SELL";
}

color BtnColor(const string name)
{
   if(name == BTN_CLOSE)     return clrDimGray;
   if(name == BTN_CLOSE_BUY) return clrSeaGreen;
   return clrIndianRed;
}

void ArmClose(const string name)
{
   if(g_armedBtn != "" && g_armedBtn != name)
      DisarmClose();                       // only one button armed at a time

   g_armedBtn     = name;
   g_closeArmedAt = TimeCurrent();
   ObjectSetString (0, name, OBJPROP_TEXT, "CONFIRM?");
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrRed);
}

void DisarmClose()
{
   if(g_armedBtn == "") return;

   ObjectSetString (0, g_armedBtn, OBJPROP_TEXT, BtnLabel(g_armedBtn));
   ObjectSetInteger(0, g_armedBtn, OBJPROP_BGCOLOR, BtnColor(g_armedBtn));
   g_armedBtn = "";
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Close positions: posType = -1 for every position, or             |
//| POSITION_TYPE_BUY / POSITION_TYPE_SELL for one side only         |
//+------------------------------------------------------------------+
void ClosePositions(const int posType)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(posType >= 0 && (int)PositionGetInteger(POSITION_TYPE) != posType)
         continue;

      if(!trade.PositionClose(ticket))
         PrintFormat("Close pos failed %I64u: %d", ticket, trade.ResultRetcode());
      else
         PrintFormat("Closed pos %I64u", ticket);
   }
}

void DeletePendingOrders()
{
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

   PosStats s;
   CollectStats(s);

   ObjectSetString(0, LBL_POS,   OBJPROP_TEXT,
                   StringFormat("Positions: %d", s.total));
   ObjectSetString(0, LBL_SELLS, OBJPROP_TEXT,
                   StringFormat("SELL: %d   vol %.2f", s.sellCount, s.sellVolume));
   ObjectSetString(0, LBL_BUYS,  OBJPROP_TEXT,
                   StringFormat("BUY:  %d   vol %.2f", s.buyCount, s.buyVolume));

   ObjectSetString(0, LBL_RISK,   OBJPROP_TEXT,
                   "SL total: " + FormatLevelTotal(s.slTotal, balance, s.withSL, s.total));
   ObjectSetString(0, LBL_REWARD, OBJPROP_TEXT,
                   "TP total: " + FormatLevelTotal(s.tpTotal, balance, s.withTP, s.total));
}

string FormatMoneyPct(double money, double balance)
{
   if(money <= 0) return "-";
   double pct = (balance > 0) ? money / balance * 100.0 : 0;
   return StringFormat("%.2f (%.1f%%)", money, pct);
}

string FormatLevelTotal(double money, double balance, int withLevel, int totalPos)
{
   if(totalPos == 0)  return "no positions";
   if(withLevel == 0) return StringFormat("none set (0/%d)", totalPos);

   double pct = (balance > 0) ? money / balance * 100.0 : 0;
   string s   = StringFormat("%+.2f (%+.1f%%)", money, pct);
   if(withLevel < totalPos)
      s += StringFormat("   %d/%d set", withLevel, totalPos);
   return s;
}

//+------------------------------------------------------------------+
//| P/L of the currently selected position if closed at `price`      |
//+------------------------------------------------------------------+
double PositionPLAt(const double price)
{
   string symbol = PositionGetString(POSITION_SYMBOL);
   long   type   = PositionGetInteger(POSITION_TYPE);
   double open   = PositionGetDouble(POSITION_PRICE_OPEN);
   double volume = PositionGetDouble(POSITION_VOLUME);
   double swap   = PositionGetDouble(POSITION_SWAP);

   double mpp = MoneyPerPrice(symbol, volume);
   if(mpp <= 0) return 0;

   double diff = (type == POSITION_TYPE_BUY) ? (price - open) : (open - price);
   return diff * mpp + swap;
}

//+------------------------------------------------------------------+
//| One pass over the open positions for everything the info         |
//| section shows: counts, volume per side, and the P/L each side    |
//| would realise at its own SL / TP levels.                         |
//+------------------------------------------------------------------+
void CollectStats(PosStats &s)
{
   ZeroMemory(s);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;

      s.total++;

      double volume = PositionGetDouble(POSITION_VOLUME);
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         s.buyCount++;
         s.buyVolume += volume;
      }
      else
      {
         s.sellCount++;
         s.sellVolume += volume;
      }

      double sl = PositionGetDouble(POSITION_SL);
      if(sl > 0)
      {
         s.withSL++;
         s.slTotal += PositionPLAt(sl);
      }

      double tp = PositionGetDouble(POSITION_TP);
      if(tp > 0)
      {
         s.withTP++;
         s.tpTotal += PositionPLAt(tp);
      }
   }
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

void CreateLabel(string name, int x, int y, string text, color clr = clrBlack)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}