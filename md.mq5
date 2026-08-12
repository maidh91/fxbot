//+------------------------------------------------------------------+
//| SetSLTP_Panel.mq5                                                |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade trade;

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