//+------------------------------------------------------------------+
//|  XAUUSD M15 Scalper EA v5.0                                      |
//|  Strategy: ADX+EMA+RSI+BB+H4 Double Confirm | ATR SL            |
//+------------------------------------------------------------------+
#property copyright "Trading Nova"
#property version   "5.00"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
CTrade trade;
CPositionInfo posInfo;
input group "=== TREND M15 ==="
input int    InpEMA_Fast=21;
input int    InpEMA_Slow=50;
input group "=== H4 BIAS ==="
input int    InpH4_EMA_Fast=50;
input int    InpH4_EMA_Slow=200;
input group "=== ADX ==="
input int    InpADX_Period=14;
input double InpADX_Min=30.0;
input group "=== RSI ==="
input int    InpRSI_Period=14;
input double InpRSI_BuyMin=45.0;
input double InpRSI_BuyMax=65.0;
input double InpRSI_SellMin=35.0;
input double InpRSI_SellMax=55.0;
input group "=== BB ==="
input int    InpBB_Period=20;
input double InpBB_Dev=2.0;
input group "=== ATR RISK ==="
input int    InpATR_Period=14;
input double InpATR_SL_Mult=1.5;
input double InpATR_TP1_Mult=1.5;
input double InpATR_TP2_Mult=3.0;
input double InpRiskPercent=1.0;
input bool   InpUseTrailing=true;
input bool   InpUseTP1=true;
input double InpTP1_ClosePC=50.0;
input group "=== FILTERS ==="
input double InpMaxSpread=60.0;
input int    InpMaxTrades=2;
input int    InpStartHour=8;
input int    InpEndHour=20;
input bool   InpSkipFriday=true;
input int    InpCooldownHours=2;
int handleEMA_Fast,handleEMA_Slow,handleH4_Fast,handleH4_Slow;
int handleRSI,handleADX,handleBB,handleATR;
double emaFast[],emaSlow[],h4Fast[],h4Slow[];
double rsiVal[],adxVal[],adxPlus[],adxMinus[];
double bbUpper[],bbMiddle[],bbLower[],atrVal[];
datetime lastBuyTime=0,lastSellTime=0;
int OnInit()
{
   trade.SetExpertMagicNumber(20250628);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   handleEMA_Fast=iMA(_Symbol,PERIOD_M15,InpEMA_Fast,0,MODE_EMA,PRICE_CLOSE);
   handleEMA_Slow=iMA(_Symbol,PERIOD_M15,InpEMA_Slow,0,MODE_EMA,PRICE_CLOSE);
   handleH4_Fast =iMA(_Symbol,PERIOD_H4,InpH4_EMA_Fast,0,MODE_EMA,PRICE_CLOSE);
   handleH4_Slow =iMA(_Symbol,PERIOD_H4,InpH4_EMA_Slow,0,MODE_EMA,PRICE_CLOSE);
   handleRSI=iRSI(_Symbol,PERIOD_M15,InpRSI_Period,PRICE_CLOSE);
   handleADX=iADX(_Symbol,PERIOD_M15,InpADX_Period);
   handleBB =iBands(_Symbol,PERIOD_M15,InpBB_Period,0,InpBB_Dev,PRICE_CLOSE);
   handleATR=iATR(_Symbol,PERIOD_M15,InpATR_Period);
   if(handleEMA_Fast==INVALID_HANDLE||handleRSI==INVALID_HANDLE||
      handleADX==INVALID_HANDLE||handleBB==INVALID_HANDLE||handleATR==INVALID_HANDLE)
   {Print("ERROR: handles failed");return INIT_FAILED;}
   ArraySetAsSeries(emaFast,true);ArraySetAsSeries(emaSlow,true);
   ArraySetAsSeries(h4Fast,true);ArraySetAsSeries(h4Slow,true);
   ArraySetAsSeries(rsiVal,true);ArraySetAsSeries(adxVal,true);
   ArraySetAsSeries(adxPlus,true);ArraySetAsSeries(adxMinus,true);
   ArraySetAsSeries(bbUpper,true);ArraySetAsSeries(bbMiddle,true);
   ArraySetAsSeries(bbLower,true);ArraySetAsSeries(atrVal,true);
   Print("XAUUSD M15 EA v5.0 OK");
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   IndicatorRelease(handleEMA_Fast);IndicatorRelease(handleEMA_Slow);
   IndicatorRelease(handleH4_Fast);IndicatorRelease(handleH4_Slow);
   IndicatorRelease(handleRSI);IndicatorRelease(handleADX);
   IndicatorRelease(handleBB);IndicatorRelease(handleATR);
}
bool RefreshBuffers()
{
   if(CopyBuffer(handleEMA_Fast,0,0,5,emaFast)<5) return false;
   if(CopyBuffer(handleEMA_Slow,0,0,5,emaSlow)<5) return false;
   if(CopyBuffer(handleH4_Fast,0,0,3,h4Fast)<3) return false;
   if(CopyBuffer(handleH4_Slow,0,0,3,h4Slow)<3) return false;
   if(CopyBuffer(handleRSI,0,0,5,rsiVal)<5) return false;
   if(CopyBuffer(handleADX,0,0,5,adxVal)<5) return false;
   if(CopyBuffer(handleADX,1,0,5,adxPlus)<5) return false;
   if(CopyBuffer(handleADX,2,0,5,adxMinus)<5) return false;
   if(CopyBuffer(handleBB,0,0,5,bbMiddle)<5) return false;
   if(CopyBuffer(handleBB,1,0,5,bbUpper)<5) return false;
   if(CopyBuffer(handleBB,2,0,5,bbLower)<5) return false;
   if(CopyBuffer(handleATR,0,0,5,atrVal)<5) return false;
   return true;
}
bool IsTradingHours()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(),dt);
   if(dt.day_of_week==0||dt.day_of_week==6) return false;
   if(InpSkipFriday&&dt.day_of_week==5&&dt.hour>=17) return false;
   if(dt.hour<InpStartHour||dt.hour>=InpEndHour) return false;
   return true;
}
int CountMyTrades()
{
   int c=0;
   for(int i=0;i<PositionsTotal();i++)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic()==20250628&&posInfo.Symbol()==_Symbol) c++;
   return c;
}
bool HasOpenBuy()
{
   for(int i=0;i<PositionsTotal();i++)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic()==20250628&&posInfo.Symbol()==_Symbol&&
            posInfo.PositionType()==POSITION_TYPE_BUY) return true;
   return false;
}
bool HasOpenSell()
{
   for(int i=0;i<PositionsTotal();i++)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic()==20250628&&posInfo.Symbol()==_Symbol&&
            posInfo.PositionType()==POSITION_TYPE_SELL) return true;
   return false;
}
bool IsCooldownOK(int direction)
{
   datetime cd=(datetime)(InpCooldownHours*3600);
   if(direction==1 &&lastBuyTime >0&&(TimeGMT()-lastBuyTime) <cd) return false;
   if(direction==-1&&lastSellTime>0&&(TimeGMT()-lastSellTime)<cd) return false;
   return true;
}
bool IsBullishCandle(int shift)
{
   double o=iOpen(_Symbol,PERIOD_M15,shift),c=iClose(_Symbol,PERIOD_M15,shift);
   double body=MathAbs(c-o),range=iHigh(_Symbol,PERIOD_M15,shift)-iLow(_Symbol,PERIOD_M15,shift);
   return(c>o)&&(range>0)&&(body/range>=0.40);
}
bool IsBearishCandle(int shift)
{
   double o=iOpen(_Symbol,PERIOD_M15,shift),c=iClose(_Symbol,PERIOD_M15,shift);
   double body=MathAbs(c-o),range=iHigh(_Symbol,PERIOD_M15,shift)-iLow(_Symbol,PERIOD_M15,shift);
   return(c<o)&&(range>0)&&(body/range>=0.40);
}
int GetSignal()
{
   double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ema21=emaFast[1],ema50=emaSlow[1];
   double rsi=rsiVal[1];
   double adx=adxVal[1],diPlus=adxPlus[1],diMinus=adxMinus[1];
   double bbMid=bbMiddle[1];
   // H4 double confirmation
   bool h4Bullish=(h4Fast[0]>h4Slow[0])&&(price>h4Slow[0]);
   bool h4Bearish=(h4Fast[0]<h4Slow[0])&&(price<h4Slow[0]);
   if(adx<InpADX_Min) return 0;
   // BUY: H4 bullish + M15 uptrend + momentum + candle
   if(h4Bullish&&ema21>ema50&&rsi>InpRSI_BuyMin&&rsi<InpRSI_BuyMax&&
      diPlus>diMinus&&price>bbMid&&IsBullishCandle(1)&&IsCooldownOK(1)) return 1;
   // SELL: H4 bearish + M15 downtrend + momentum + candle
   if(h4Bearish&&ema21<ema50&&rsi>InpRSI_SellMin&&rsi<InpRSI_SellMax&&
      diMinus>diPlus&&price<bbMid&&IsBearishCandle(1)&&IsCooldownOK(-1)) return -1;
   return 0;
}
double CalcLotSize(double slDist)
{
   if(slDist<=0) return SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double risk=eq*(InpRiskPercent/100.0);
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double ls=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(ts<=0||tv<=0) return mn;
   double vpl=(slDist/ts)*tv;
   if(vpl<=0) return mn;
   double lots=MathFloor((risk/vpl)/ls)*ls;
   return NormalizeDouble(MathMax(mn,MathMin(mx,lots)),2);
}
void OpenBuy()
{
   double atr=atrVal[1];
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double sl =NormalizeDouble(ask-(atr*InpATR_SL_Mult),_Digits);
   double tp2=NormalizeDouble(ask+(atr*InpATR_TP2_Mult),_Digits);
   double lots=CalcLotSize(ask-sl);
   if(lots<=0) return;
   if(!trade.Buy(lots,_Symbol,ask,sl,tp2,"XAUUSD_BUY_v5"))
      Print("BUY failed: ",trade.ResultRetcodeDescription());
   else{lastBuyTime=TimeGMT();
      Print("BUY v5 | Lots:",lots," SL:",sl," TP:",tp2," ATR:",atrVal[1]);}
}
void OpenSell()
{
   double atr=atrVal[1];
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl =NormalizeDouble(bid+(atr*InpATR_SL_Mult),_Digits);
   double tp2=NormalizeDouble(bid-(atr*InpATR_TP2_Mult),_Digits);
   double lots=CalcLotSize(sl-bid);
   if(lots<=0) return;
   if(!trade.Sell(lots,_Symbol,bid,sl,tp2,"XAUUSD_SELL_v5"))
      Print("SELL failed: ",trade.ResultRetcodeDescription());
   else{lastSellTime=TimeGMT();
      Print("SELL v5 | Lots:",lots," SL:",sl," TP:",tp2," ATR:",atrVal[1]);}
}
void ManagePositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=20250628||posInfo.Symbol()!=_Symbol) continue;
      double op=posInfo.PriceOpen(),sl=posInfo.StopLoss(),tp=posInfo.TakeProfit();
      double atr=atrVal[0],dist=MathAbs(op-sl);
      if(posInfo.PositionType()==POSITION_TYPE_BUY)
      {
         double tp1=NormalizeDouble(op+(dist*InpATR_TP1_Mult),_Digits);
         double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
         if(InpUseTP1&&bid>=tp1)
         {
            double ls=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
            double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
            double cv=NormalizeDouble(posInfo.Volume()*(InpTP1_ClosePC/100.0),2);
            cv=MathMax(mn,MathFloor(cv/ls)*ls);
            if(cv<posInfo.Volume()) trade.PositionClosePartial(posInfo.Ticket(),cv);
         }
         if(InpUseTrailing&&bid>=tp1)
         {
            double nsl=NormalizeDouble(op+_Point,_Digits);
            if(nsl>sl+_Point) trade.PositionModify(posInfo.Ticket(),nsl,tp);
         }
      }
      if(posInfo.PositionType()==POSITION_TYPE_SELL)
      {
         double tp1=NormalizeDouble(op-(dist*InpATR_TP1_Mult),_Digits);
         double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         if(InpUseTP1&&ask<=tp1)
         {
            double ls=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
            double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
            double cv=NormalizeDouble(posInfo.Volume()*(InpTP1_ClosePC/100.0),2);
            cv=MathMax(mn,MathFloor(cv/ls)*ls);
            if(cv<posInfo.Volume()) trade.PositionClosePartial(posInfo.Ticket(),cv);
         }
         if(InpUseTrailing&&ask<=tp1)
         {
            double nsl=NormalizeDouble(op-_Point,_Digits);
            if(nsl<sl-_Point) trade.PositionModify(posInfo.Ticket(),nsl,tp);
         }
      }
   }
}
void OnTick()
{
   static datetime lastBar=0;
   datetime cur=iTime(_Symbol,PERIOD_M15,0);
   if(cur==lastBar) return;
   lastBar=cur;
   if(!RefreshBuffers()) return;
   if(!IsTradingHours()) return;
   double spread=SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*_Point;
   if(spread>InpMaxSpread*_Point) return;
   ManagePositions();
   if(CountMyTrades()>=InpMaxTrades) return;
   int sig=GetSignal();
   if(sig==1&&!HasOpenBuy())   OpenBuy();
   if(sig==-1&&!HasOpenSell()) OpenSell();
}
