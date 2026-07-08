//+------------------------------------------------------------------+
//|  NAS100 M5 Mean-Reversion Scalper v3                             |
//|  Αγόρασε oversold, πούλα overbought — χωρίς trend filter        |
//|  BUY:  K crosses D από <25 + bullish bar + RSI>15               |
//|  SELL: K crosses D από >75 + bearish bar + RSI<85               |
//|  SL: 0.6×ATR | TP: 1.0×ATR | Risk: 1% | Max 4 trades/day        |
//+------------------------------------------------------------------+
#property copyright "Trading Nova"
#property version   "3.00"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
CTrade trade;
CPositionInfo pos;

input group "=== STOCHASTIC ==="
input int    InpStochK  = 8;
input int    InpStochD  = 3;
input int    InpStochSl = 3;
input double InpOversold  = 40.0;
input double InpOverbought= 60.0;

input group "=== RSI (anti-crash filter) ==="
input int    InpRSI     = 14;
input double InpRSImin  = 15.0;  // no buy if RSI below this (free-fall)
input double InpRSImax  = 85.0;  // no sell if RSI above this (parabola)

input group "=== RISK ==="
input int    InpATR     = 10;
input double InpSL      = 0.6;
input double InpTP      = 1.0;
input double InpRisk    = 1.0;
input double InpMaxDD   = 4.0;

input group "=== FILTERS ==="
input double InpMaxSpread  = 200.0;
input int    InpMaxTrades  = 4;
input int    InpCooldownMin= 10;
input int    InpStartHour  = 13;
input int    InpEndHour    = 22;

int hStoch, hRSI, hATR;
double sk[], sd[], rsi[], atr_v[];
datetime lastTrade=0;
double   dayEq=0; int lastDay=-1;
int      dayTrades=0;

int OnInit()
{
   trade.SetExpertMagicNumber(20250708);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   hStoch = iStochastic(_Symbol,PERIOD_M5,InpStochK,InpStochD,InpStochSl,MODE_SMA,STO_LOWHIGH);
   hRSI   = iRSI(_Symbol,PERIOD_M5,InpRSI,PRICE_CLOSE);
   hATR   = iATR(_Symbol,PERIOD_M5,InpATR);
   if(hStoch==INVALID_HANDLE||hRSI==INVALID_HANDLE||hATR==INVALID_HANDLE)
   { Print("Init failed"); return INIT_FAILED; }
   ArraySetAsSeries(sk,true); ArraySetAsSeries(sd,true);
   ArraySetAsSeries(rsi,true); ArraySetAsSeries(atr_v,true);
   Print("NAS100 v3 MeanReversion OK | Stoch25/75 | 4x/day | 10min cd");
   return INIT_SUCCEEDED;
}
void OnDeinit(const int r){ IndicatorRelease(hStoch); IndicatorRelease(hRSI); IndicatorRelease(hATR); }
bool Refresh()
{
   return CopyBuffer(hStoch,0,0,4,sk)    >=4
       && CopyBuffer(hStoch,1,0,4,sd)    >=4
       && CopyBuffer(hRSI,  0,0,4,rsi)   >=4
       && CopyBuffer(hATR,  0,0,4,atr_v) >=4;
}
bool InSession()
{
   MqlDateTime dt; TimeToStruct(TimeGMT(),dt);
   if(dt.day_of_week==0||dt.day_of_week==6) return false;
   if(dt.day_of_week==5 && dt.hour>=22) return false;
   return dt.hour>=InpStartHour && dt.hour<InpEndHour;
}
int CountMine()
{
   int c=0;
   for(int i=0;i<PositionsTotal();i++)
      if(pos.SelectByIndex(i)&&pos.Magic()==20250708&&pos.Symbol()==_Symbol) c++;
   return c;
}
bool HasBuy(){ for(int i=0;i<PositionsTotal();i++) if(pos.SelectByIndex(i)&&pos.Magic()==20250708&&pos.Symbol()==_Symbol&&pos.PositionType()==POSITION_TYPE_BUY) return true; return false; }
bool HasSell(){ for(int i=0;i<PositionsTotal();i++) if(pos.SelectByIndex(i)&&pos.Magic()==20250708&&pos.Symbol()==_Symbol&&pos.PositionType()==POSITION_TYPE_SELL) return true; return false; }
double Lots(double slD)
{
   if(slD<=0) return SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double risk=AccountInfoDouble(ACCOUNT_EQUITY)*(InpRisk/100.0);
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double ls=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(ts<=0||tv<=0) return mn;
   double vpl=(slD/ts)*tv; if(vpl<=0) return mn;
   return NormalizeDouble(MathMax(mn,MathMin(mx,MathFloor((risk/vpl)/ls)*ls)),2);
}
void TrailStop()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!pos.SelectByIndex(i)||pos.Magic()!=20250708||pos.Symbol()!=_Symbol) continue;
      double op=pos.PriceOpen(),sl=pos.StopLoss(),tp=pos.TakeProfit(),av=atr_v[0];
      if(pos.PositionType()==POSITION_TYPE_BUY)
      { double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
        if(bid>=op+av*0.4 && sl<op) trade.PositionModify(pos.Ticket(),NormalizeDouble(op+_Point,_Digits),tp); }
      else
      { double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
        if(ask<=op-av*0.4 && sl>op) trade.PositionModify(pos.Ticket(),NormalizeDouble(op-_Point,_Digits),tp); }
   }
}
void OnTick()
{
   static datetime lastBar=0;
   datetime cur=iTime(_Symbol,PERIOD_M5,0);
   if(cur==lastBar) return; lastBar=cur;
   if(!Refresh()) return;

   MqlDateTime dt; TimeToStruct(TimeGMT(),dt);
   if(dt.day!=lastDay){ dayEq=AccountInfoDouble(ACCOUNT_EQUITY); lastDay=dt.day; dayTrades=0; }

   TrailStop();

   if(!InSession()) return;

   double spread=SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*_Point;
   if(spread>InpMaxSpread*_Point) return;

   if(InpMaxDD>0 && dayEq>0 && AccountInfoDouble(ACCOUNT_EQUITY)<dayEq*(1-InpMaxDD/100))
   { Print("STOP: daily DD limit"); return; }

   if(dayTrades>=InpMaxTrades) return;
   if(lastTrade>0 && (TimeCurrent()-lastTrade)<(datetime)(InpCooldownMin*60)) return;

   bool crossUp = sk[1]>sd[1] && sk[2]<=sd[2] && sk[1]<InpOversold;
   bool crossDn = sk[1]<sd[1] && sk[2]>=sd[2] && sk[1]>InpOverbought;

   Print("SCAN | K=",DoubleToString(sk[1],1)," D=",DoubleToString(sd[1],1),
         " RSI=",DoubleToString(rsi[1],1),
         " Cross=",crossUp?"BUY↑":crossDn?"SELL↓":"–",
         " Day=",dayTrades,"/",InpMaxTrades);

   double av=atr_v[1];

   if(crossUp && rsi[1]>InpRSImin && !HasBuy())
   {
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double sl=NormalizeDouble(ask-av*InpSL,_Digits);
      double tp=NormalizeDouble(ask+av*InpTP,_Digits);
      double lots=Lots(ask-sl);
      if(trade.Buy(lots,_Symbol,ask,sl,tp,"NAS_BUY"))
      { lastTrade=TimeCurrent(); dayTrades++;
        Print(">>> BUY | lots=",lots," K=",DoubleToString(sk[1],1)," RSI=",DoubleToString(rsi[1],1)); }
   }
   else if(crossDn && rsi[1]<InpRSImax && !HasSell())
   {
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double sl=NormalizeDouble(bid+av*InpSL,_Digits);
      double tp=NormalizeDouble(bid-av*InpTP,_Digits);
      double lots=Lots(sl-bid);
      if(trade.Sell(lots,_Symbol,bid,sl,tp,"NAS_SELL"))
      { lastTrade=TimeCurrent(); dayTrades++;
        Print(">>> SELL | lots=",lots," K=",DoubleToString(sk[1],1)," RSI=",DoubleToString(rsi[1],1)); }
   }
}
