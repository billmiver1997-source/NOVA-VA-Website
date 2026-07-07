//+------------------------------------------------------------------+
//|  XAUUSD M15 Active Scalper v9                                    |
//|  Απλή, γρήγορη στρατηγική — trades κάθε μέρα                   |
//|                                                                   |
//|  BUY:  EMA21>EMA50 + Stoch cross up από <35 + bullish bar       |
//|  SELL: EMA21<EMA50 + Stoch cross dn από >65 + bearish bar       |
//|  SL: 1.0×ATR | TP: 1.5×ATR | Risk: 1% | Cooldown: 30min        |
//+------------------------------------------------------------------+
#property copyright "Trading Nova"
#property version   "9.00"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
CTrade trade;
CPositionInfo pos;

input group "=== TREND ==="
input int    InpFast    = 21;
input int    InpSlow    = 50;

input group "=== STOCHASTIC ==="
input int    InpStochK  = 14;
input int    InpStochD  = 3;
input int    InpStochSl = 3;
input double InpOversold    = 35.0;
input double InpOverbought  = 65.0;

input group "=== RISK ==="
input int    InpATR     = 14;
input double InpSL      = 1.0;
input double InpTP      = 1.5;
input double InpRisk    = 1.0;
input double InpMaxDD   = 5.0;   // stop day if down 5%

input group "=== FILTERS ==="
input double InpMaxSpread  = 60.0;
input int    InpMaxTrades  = 2;
input int    InpCooldownMin= 30;
input int    InpStartHour  = 9;   // 09:00 EET
input int    InpEndHour    = 23;  // 23:00 EET
input int    InpTZOffset   = 3;

int hFast, hSlow, hStoch, hATR;
double eFast[], eSlow[], sk[], sd[], atr_v[];
datetime lastTrade=0;
double   dayEq=0; int lastDay=-1;

int OnInit()
{
   trade.SetExpertMagicNumber(20250709);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   hFast  = iMA(_Symbol,PERIOD_M15,InpFast, 0,MODE_EMA,PRICE_CLOSE);
   hSlow  = iMA(_Symbol,PERIOD_M15,InpSlow, 0,MODE_EMA,PRICE_CLOSE);
   hStoch = iStochastic(_Symbol,PERIOD_M15,InpStochK,InpStochD,InpStochSl,MODE_SMA,STO_LOWHIGH);
   hATR   = iATR(_Symbol,PERIOD_M15,InpATR);
   if(hFast==INVALID_HANDLE||hSlow==INVALID_HANDLE||hStoch==INVALID_HANDLE||hATR==INVALID_HANDLE)
   { Print("Init failed"); return INIT_FAILED; }
   ArraySetAsSeries(eFast,true); ArraySetAsSeries(eSlow,true);
   ArraySetAsSeries(sk,true);    ArraySetAsSeries(sd,true);
   ArraySetAsSeries(atr_v,true);
   Print("XAUUSD v9 Active Scalper OK | EMA21/50 + Stoch35/65 | 1%risk");
   return INIT_SUCCEEDED;
}
void OnDeinit(const int r)
{
   IndicatorRelease(hFast); IndicatorRelease(hSlow);
   IndicatorRelease(hStoch); IndicatorRelease(hATR);
}
bool Refresh()
{
   return CopyBuffer(hFast, 0,0,4,eFast)  >=4
       && CopyBuffer(hSlow, 0,0,4,eSlow)  >=4
       && CopyBuffer(hStoch,0,0,4,sk)     >=4
       && CopyBuffer(hStoch,1,0,4,sd)     >=4
       && CopyBuffer(hATR,  0,0,4,atr_v)  >=4;
}
bool InSession()
{
   MqlDateTime dt;
   datetime eet=TimeGMT()+(datetime)(InpTZOffset*3600);
   TimeToStruct(eet,dt);
   if(dt.day_of_week==0||dt.day_of_week==6) return false;
   if(dt.day_of_week==5 && dt.hour>=22) return false;
   return dt.hour>=InpStartHour && dt.hour<InpEndHour;
}
int CountMine()
{
   int c=0;
   for(int i=0;i<PositionsTotal();i++)
      if(pos.SelectByIndex(i)&&pos.Magic()==20250709&&pos.Symbol()==_Symbol) c++;
   return c;
}
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
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic()!=20250709||pos.Symbol()!=_Symbol) continue;
      double op=pos.PriceOpen(),sl=pos.StopLoss(),tp=pos.TakeProfit(),av=atr_v[0];
      if(pos.PositionType()==POSITION_TYPE_BUY)
      {
         double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
         if(bid>=op+av*0.7 && sl<op)
            trade.PositionModify(pos.Ticket(),NormalizeDouble(op+_Point,_Digits),tp);
      }
      else
      {
         double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         if(ask<=op-av*0.7 && sl>op)
            trade.PositionModify(pos.Ticket(),NormalizeDouble(op-_Point,_Digits),tp);
      }
   }
}
void OnTick()
{
   static datetime lastBar=0;
   datetime cur=iTime(_Symbol,PERIOD_M15,0);
   if(cur==lastBar) return; lastBar=cur;
   if(!Refresh()) return;

   MqlDateTime dt; TimeToStruct(TimeGMT(),dt);
   if(dt.day!=lastDay){ dayEq=AccountInfoDouble(ACCOUNT_EQUITY); lastDay=dt.day; }

   TrailStop();

   if(!InSession()){ return; }

   double spread=SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*_Point;
   if(spread>InpMaxSpread*_Point){ Print("SKIP spread=",DoubleToString(spread/_Point,0)); return; }

   // Daily DD guard
   if(InpMaxDD>0 && dayEq>0 && AccountInfoDouble(ACCOUNT_EQUITY)<dayEq*(1-InpMaxDD/100))
   { Print("STOP: daily DD limit"); return; }

   if(CountMine()>=InpMaxTrades) return;
   if(lastTrade>0 && (TimeCurrent()-lastTrade)<(datetime)(InpCooldownMin*60)) return;

   // Signal
   bool crossUp = sk[1]>sd[1] && sk[2]<=sd[2];
   bool crossDn = sk[1]<sd[1] && sk[2]>=sd[2];
   double cC=iClose(_Symbol,PERIOD_M15,0), cO=iOpen(_Symbol,PERIOD_M15,0);

   Print("SCAN | EMA21=",DoubleToString(eFast[1],1)," EMA50=",DoubleToString(eSlow[1],1),
         " K=",DoubleToString(sk[1],1)," D=",DoubleToString(sd[1],1),
         " Cross=",crossUp?"UP":crossDn?"DN":"–",
         " Trend=",eFast[1]>eSlow[1]?"UP":"DN");

   double av=atr_v[1];
   if(eFast[1]>eSlow[1] && crossUp && sk[1]<InpOversold && cC>cO)
   {
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double sl=NormalizeDouble(ask-av*InpSL,_Digits);
      double tp=NormalizeDouble(ask+av*InpTP,_Digits);
      double lots=Lots(ask-sl);
      if(trade.Buy(lots,_Symbol,ask,sl,tp,"v9_BUY"))
      { lastTrade=TimeCurrent(); Print("BUY v9 | lots=",lots," sl=",sl," tp=",tp," K=",DoubleToString(sk[1],1)); }
   }
   else if(eFast[1]<eSlow[1] && crossDn && sk[1]>InpOverbought && cC<cO)
   {
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double sl=NormalizeDouble(bid+av*InpSL,_Digits);
      double tp=NormalizeDouble(bid-av*InpTP,_Digits);
      double lots=Lots(sl-bid);
      if(trade.Sell(lots,_Symbol,bid,sl,tp,"v9_SELL"))
      { lastTrade=TimeCurrent(); Print("SELL v9 | lots=",lots," sl=",sl," tp=",tp," K=",DoubleToString(sk[1],1)); }
   }
}
