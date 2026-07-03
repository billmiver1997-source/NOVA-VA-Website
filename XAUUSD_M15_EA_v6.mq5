//+------------------------------------------------------------------+
//|  XAUUSD M15 Mean-Reversion Scalper EA v6.0                       |
//|  Strategy: Buy oversold bounces at BB lower, sell overbought      |
//|  at BB upper. Trades AGAINST short-term extremes, not trend.      |
//|                                                                    |
//|  BUY:  price <= BB lower + RSI < 38 + bullish candle + ADX<30   |
//|  SELL: price >= BB upper + RSI > 62 + bearish candle + ADX<30   |
//|  TP: Bollinger Band middle (the mean we're reverting to)          |
//|  SL: 1.5x ATR beyond entry                                        |
//+------------------------------------------------------------------+
#property copyright "Trading Nova"
#property version   "6.00"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
CTrade trade;
CPositionInfo posInfo;

input group "=== BOLLINGER BANDS ==="
input int    InpBB_Period = 20;
input double InpBB_Dev    = 2.0;

input group "=== RSI ==="
input int    InpRSI_Period  = 14;
input double InpRSI_OversoldMax  = 38.0;   // BUY when RSI below this
input double InpRSI_OverboughtMin= 62.0;   // SELL when RSI above this

input group "=== ADX (range filter) ==="
input int    InpADX_Period = 14;
input double InpADX_Max    = 30.0;         // No trade when trending too hard

input group "=== ATR RISK ==="
input int    InpATR_Period    = 14;
input double InpATR_SL_Mult   = 1.5;       // SL distance
input double InpRiskPercent   = 1.0;       // % equity per trade
input bool   InpUsePartial    = true;
input double InpPartialPC     = 50.0;      // % of position to close at partial
input double InpBE_ATR_Mult   = 0.5;       // Move to breakeven at this profit

input group "=== RISK GUARD ==="
input double InpMaxDailyLossPC = 3.0;

input group "=== FILTERS ==="
input double InpMaxSpread    = 60.0;
input int    InpMaxTrades    = 2;
input int    InpTimezoneOffset = 3;        // EET (UTC+3 summer)
input int    InpStartHour    = 11;         // 11:00 EET = London open
input int    InpEndHour      = 23;         // 23:00 EET
input bool   InpSkipFriday   = true;
input int    InpCooldownMins = 45;

int handleBB, handleRSI, handleADX, handleATR;
double bbUpper[], bbMiddle[], bbLower[];
double rsiVal[], adxVal[], atrVal[];
datetime lastBuyTime = 0, lastSellTime = 0;
double   dailyEquityOpen = 0;
int      lastTradeDay    = -1;

int OnInit()
{
   trade.SetExpertMagicNumber(20250703);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   handleBB  = iBands(_Symbol, PERIOD_M15, InpBB_Period, 0, InpBB_Dev, PRICE_CLOSE);
   handleRSI = iRSI(_Symbol, PERIOD_M15, InpRSI_Period, PRICE_CLOSE);
   handleADX = iADX(_Symbol, PERIOD_M15, InpADX_Period);
   handleATR = iATR(_Symbol, PERIOD_M15, InpATR_Period);
   if(handleBB==INVALID_HANDLE || handleRSI==INVALID_HANDLE ||
      handleADX==INVALID_HANDLE || handleATR==INVALID_HANDLE)
   { Print("ERROR: indicator handles failed"); return INIT_FAILED; }
   ArraySetAsSeries(bbUpper, true); ArraySetAsSeries(bbMiddle, true);
   ArraySetAsSeries(bbLower, true); ArraySetAsSeries(rsiVal, true);
   ArraySetAsSeries(adxVal,  true); ArraySetAsSeries(atrVal,  true);
   Print("XAUUSD M15 EA v6.0 OK — Mean-Reversion");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(handleBB);  IndicatorRelease(handleRSI);
   IndicatorRelease(handleADX); IndicatorRelease(handleATR);
}

bool RefreshBuffers()
{
   if(CopyBuffer(handleBB,  0, 0, 5, bbMiddle) < 5) return false;
   if(CopyBuffer(handleBB,  1, 0, 5, bbUpper)  < 5) return false;
   if(CopyBuffer(handleBB,  2, 0, 5, bbLower)  < 5) return false;
   if(CopyBuffer(handleRSI, 0, 0, 5, rsiVal)   < 5) return false;
   if(CopyBuffer(handleADX, 0, 0, 5, adxVal)   < 5) return false;
   if(CopyBuffer(handleATR, 0, 0, 5, atrVal)   < 5) return false;
   return true;
}

bool IsTradingHours()
{
   MqlDateTime dt;
   datetime eetTime = TimeGMT() + (datetime)(InpTimezoneOffset * 3600);
   TimeToStruct(eetTime, dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false;
   if(InpSkipFriday && dt.day_of_week == 5 && dt.hour >= 20) return false;
   if(dt.hour < InpStartHour || dt.hour >= InpEndHour) return false;
   return true;
}

int CountMyTrades()
{
   int c = 0;
   for(int i = 0; i < PositionsTotal(); i++)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic() == 20250703 && posInfo.Symbol() == _Symbol) c++;
   return c;
}

bool HasOpenBuy()
{
   for(int i = 0; i < PositionsTotal(); i++)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic()==20250703 && posInfo.Symbol()==_Symbol &&
            posInfo.PositionType()==POSITION_TYPE_BUY) return true;
   return false;
}

bool HasOpenSell()
{
   for(int i = 0; i < PositionsTotal(); i++)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic()==20250703 && posInfo.Symbol()==_Symbol &&
            posInfo.PositionType()==POSITION_TYPE_SELL) return true;
   return false;
}

bool IsCooldownOK(int direction)
{
   datetime cd = (datetime)(InpCooldownMins * 60);
   if(direction ==  1 && lastBuyTime  > 0 && (TimeGMT()-lastBuyTime)  < cd) return false;
   if(direction == -1 && lastSellTime > 0 && (TimeGMT()-lastSellTime) < cd) return false;
   return true;
}

bool IsBullishCandle(int shift)
{
   double o = iOpen(_Symbol, PERIOD_M15, shift), c = iClose(_Symbol, PERIOD_M15, shift);
   double body = MathAbs(c - o), range = iHigh(_Symbol,PERIOD_M15,shift) - iLow(_Symbol,PERIOD_M15,shift);
   return (c > o) && (range > 0) && (body / range >= 0.25);
}

bool IsBearishCandle(int shift)
{
   double o = iOpen(_Symbol, PERIOD_M15, shift), c = iClose(_Symbol, PERIOD_M15, shift);
   double body = MathAbs(c - o), range = iHigh(_Symbol,PERIOD_M15,shift) - iLow(_Symbol,PERIOD_M15,shift);
   return (c < o) && (range > 0) && (body / range >= 0.25);
}

// Returns +1 (BUY), -1 (SELL), 0 (no signal)
int GetSignal()
{
   double price  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double rsi    = rsiVal[1];
   double adx    = adxVal[1];
   double bbLow  = bbLower[1], bbMid = bbMiddle[1], bbUp = bbUpper[1];

   // In strong trends mean-reversion fails — stay out
   if(adx > InpADX_Max) return 0;

   // BUY: price touched or crossed below lower band, RSI oversold, bullish reversal candle
   if(iLow(_Symbol,PERIOD_M15,1) <= bbLow &&
      rsi < InpRSI_OversoldMax &&
      IsBullishCandle(1) &&
      IsCooldownOK(1)) return 1;

   // SELL: price touched or crossed above upper band, RSI overbought, bearish reversal candle
   if(iHigh(_Symbol,PERIOD_M15,1) >= bbUp &&
      rsi > InpRSI_OverboughtMin &&
      IsBearishCandle(1) &&
      IsCooldownOK(-1)) return -1;

   return 0;
}

double CalcLotSize(double slDist)
{
   if(slDist <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk = eq * (InpRiskPercent / 100.0);
   double tv  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double ls  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mn  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(ts <= 0 || tv <= 0) return mn;
   double vpl = (slDist / ts) * tv;
   if(vpl <= 0) return mn;
   double lots = MathFloor((risk / vpl) / ls) * ls;
   return NormalizeDouble(MathMax(mn, MathMin(mx, lots)), 2);
}

void OpenBuy()
{
   double atr  = atrVal[1];
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl   = NormalizeDouble(ask - atr * InpATR_SL_Mult, _Digits);
   double tp   = NormalizeDouble(bbMiddle[1], _Digits);   // TP = BB middle (the mean)
   double lots = CalcLotSize(ask - sl);
   if(lots <= 0) return;
   if(!trade.Buy(lots, _Symbol, ask, sl, tp, "MR_BUY_v6"))
      Print("BUY failed: ", trade.ResultRetcodeDescription());
   else {
      lastBuyTime = TimeGMT();
      Print("BUY v6 | Lots:", lots, " Entry:", ask, " SL:", sl, " TP(BBmid):", tp,
            " RSI:", DoubleToString(rsiVal[1],1), " ATR:", DoubleToString(atr,2));
   }
}

void OpenSell()
{
   double atr  = atrVal[1];
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl   = NormalizeDouble(bid + atr * InpATR_SL_Mult, _Digits);
   double tp   = NormalizeDouble(bbMiddle[1], _Digits);   // TP = BB middle (the mean)
   double lots = CalcLotSize(sl - bid);
   if(lots <= 0) return;
   if(!trade.Sell(lots, _Symbol, bid, sl, tp, "MR_SELL_v6"))
      Print("SELL failed: ", trade.ResultRetcodeDescription());
   else {
      lastSellTime = TimeGMT();
      Print("SELL v6 | Lots:", lots, " Entry:", bid, " SL:", sl, " TP(BBmid):", tp,
            " RSI:", DoubleToString(rsiVal[1],1), " ATR:", DoubleToString(atr,2));
   }
}

void ManagePositions()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic() != 20250703 || posInfo.Symbol() != _Symbol) continue;

      double op  = posInfo.PriceOpen();
      double sl  = posInfo.StopLoss();
      double tp  = posInfo.TakeProfit();
      double atr = atrVal[0];

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double beTrigger = NormalizeDouble(op + atr * InpBE_ATR_Mult, _Digits);

         // Move to breakeven
         if(bid >= beTrigger && sl < op)
         {
            double nsl = NormalizeDouble(op + _Point, _Digits);
            trade.PositionModify(posInfo.Ticket(), nsl, tp);
         }
         // Partial close at halfway to TP
         if(InpUsePartial && tp > op)
         {
            double half = NormalizeDouble(op + (tp - op) * 0.5, _Digits);
            if(bid >= half && sl <= op + _Point)
            {
               double ls = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
               double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
               double cv = NormalizeDouble(posInfo.Volume() * (InpPartialPC / 100.0), 2);
               cv = MathMax(mn, MathFloor(cv / ls) * ls);
               if(cv < posInfo.Volume()) trade.PositionClosePartial(posInfo.Ticket(), cv);
            }
         }
      }

      if(posInfo.PositionType() == POSITION_TYPE_SELL)
      {
         double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double beTrigger = NormalizeDouble(op - atr * InpBE_ATR_Mult, _Digits);

         // Move to breakeven
         if(ask <= beTrigger && sl > op)
         {
            double nsl = NormalizeDouble(op - _Point, _Digits);
            trade.PositionModify(posInfo.Ticket(), nsl, tp);
         }
         // Partial close at halfway to TP
         if(InpUsePartial && tp < op)
         {
            double half = NormalizeDouble(op - (op - tp) * 0.5, _Digits);
            if(ask <= half && sl >= op - _Point)
            {
               double ls = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
               double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
               double cv = NormalizeDouble(posInfo.Volume() * (InpPartialPC / 100.0), 2);
               cv = MathMax(mn, MathFloor(cv / ls) * ls);
               if(cv < posInfo.Volume()) trade.PositionClosePartial(posInfo.Ticket(), cv);
            }
         }
      }
   }
}

void OnTick()
{
   static datetime lastBar = 0;
   datetime cur = iTime(_Symbol, PERIOD_M15, 0);
   if(cur == lastBar) return;
   lastBar = cur;
   if(!RefreshBuffers()) return;

   // Daily equity reset
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   if(dt.day != lastTradeDay)
   {
      dailyEquityOpen = AccountInfoDouble(ACCOUNT_EQUITY);
      lastTradeDay    = dt.day;
   }

   if(!IsTradingHours())
   {
      datetime eetNow = TimeGMT() + (datetime)(InpTimezoneOffset * 3600);
      MqlDateTime eet; TimeToStruct(eetNow, eet);
      Print("SKIP: outside hours (EET ", eet.hour, ":", eet.min, ")");
      return;
   }

   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   if(spread > InpMaxSpread * _Point)
   { Print("SKIP: spread ", DoubleToString(spread/_Point,0), " > ", InpMaxSpread); return; }

   ManagePositions();

   if(InpMaxDailyLossPC > 0)
   {
      double curEq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(curEq < dailyEquityOpen * (1.0 - InpMaxDailyLossPC / 100.0))
      { Print("SKIP: daily loss limit hit"); return; }
   }

   if(CountMyTrades() >= InpMaxTrades)
   { Print("SKIP: max trades (", InpMaxTrades, ")"); return; }

   // Diagnostic log every bar
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double adx   = adxVal[1], rsi = rsiVal[1];
   Print("SCAN | Price:", DoubleToString(price,2),
         " BBlow:", DoubleToString(bbLower[1],2),
         " BBup:", DoubleToString(bbUpper[1],2),
         " RSI:", DoubleToString(rsi,1),
         " ADX:", DoubleToString(adx,1),
         adx > InpADX_Max ? " [TREND-SKIP]" : "");

   int sig = GetSignal();
   if(sig ==  1 && !HasOpenBuy())  OpenBuy();
   if(sig == -1 && !HasOpenSell()) OpenSell();
}
