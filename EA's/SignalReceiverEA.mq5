//+------------------------------------------------------------------+
//|                                            SignalReceiverEA.mq5 |
//|                                    Trade Signal Execution System |
//+------------------------------------------------------------------+
#property copyright   "Boss Joel Trading Ecosystem"
#property version     "1.00"
#property description "Receives trade signals from web server and executes trades"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "=== Server Configuration ==="
input string   InpServerURL       = "https://api.yourdomain.com/signals/pending";
input string   InpAckURL          = "https://api.yourdomain.com/signals/ack";
input string   InpAuthToken       = "";
input int      InpTimeout         = 5000;
input int      InpPollInterval    = 1000;

input group "=== Account Identification ==="
input string   InpAccountAlias    = "SLAVE_001";
input int      InpMagicNumber     = 999001;

input group "=== Execution Settings ==="
input double   InpLotMultiplier   = 1.0;
input double   InpMaxLotSize      = 10.0;
input int      InpMaxSlippage     = 30;
input int      InpMaxSpread       = 50;
input int      InpSignalExpirySec = 60;

input group "=== Risk Management ==="
input bool     InpEnableTrading   = true;
input double   InpMinMarginLevel  = 100.0;
input int      InpMaxPositions    = 10;
input bool     InpValidateSymbol  = true;

input group "=== Symbol Mapping ==="
input string   InpSymbolSuffix    = "";
input string   InpSymbolPrefix    = "";

//+------------------------------------------------------------------+
//| GLOBAL OBJECTS                                                    |
//+------------------------------------------------------------------+
CTrade         g_trade;
CSymbolInfo    g_symbolInfo;
CAccountInfo   g_accountInfo;
CPositionInfo  g_positionInfo;

bool           g_isInitialized = false;
datetime       g_lastPollTime = 0;
int            g_consecutiveErrors = 0;
string         g_lastProcessedSignalId = "";

int            g_signalsReceived = 0;
int            g_signalsExecuted = 0;
int            g_signalsFailed = 0;
int            g_signalsSkipped = 0;

//+------------------------------------------------------------------+
//| STRUCTURE: Received Signal                                        |
//+------------------------------------------------------------------+
struct ReceivedSignal
{
   string   signalId;
   string   action;
   string   symbol;
   string   tradeType;
   double   volume;
   double   price;
   double   sl;
   double   tp;
   long     magic;
   ulong    masterTicket;
   datetime timestamp;
   string   comment;
};

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   if(StringLen(InpServerURL) == 0)
   {
      Print("ERROR: Server URL is not configured");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   Print("==========================================================");
   Print("IMPORTANT: Ensure URLs are whitelisted in MT5:");
   Print("Tools → Options → Expert Advisors → Allow WebRequest");
   Print("Signal URL: ", InpServerURL);
   Print("Ack URL: ", InpAckURL);
   Print("==========================================================");
   
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpMaxSlippage);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   g_trade.SetAsyncMode(false);
   
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   {
      Print("ERROR: Trading not allowed on this account");
      return INIT_FAILED;
   }
   
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Print("ERROR: Trading not allowed in terminal (check AutoTrading button)");
      return INIT_FAILED;
   }
   
   if(!EventSetMillisecondTimer(InpPollInterval))
   {
      Print("ERROR: Failed to set timer, error: ", GetLastError());
      return INIT_FAILED;
   }
   
   Print("Testing server connection...");
   if(TestServerConnection())
      Print("✓ Server connection verified");
   else
      Print("⚠ WARNING: Could not reach server. Will retry when signals are polled.");
   
   g_isInitialized = true;
   
   Print("Signal Receiver EA initialized successfully");
   Print("Account: ", InpAccountAlias, " | Magic: ", InpMagicNumber);
   Print("Execution: ", InpEnableTrading ? "ENABLED" : "SIMULATION ONLY");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("==========================================================");
   Print("Signal Receiver EA shutting down");
   Print("Signals Received: ", g_signalsReceived);
   Print("Signals Executed: ", g_signalsExecuted);
   Print("Signals Failed: ", g_signalsFailed);
   Print("Signals Skipped: ", g_signalsSkipped);
   Print("==========================================================");
}

//+------------------------------------------------------------------+
//| Timer event - Poll server for signals                            |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!g_isInitialized)
      return;
   
   PollForSignals();
}

//+------------------------------------------------------------------+
//| Poll server for pending signals                                  |
//+------------------------------------------------------------------+
void PollForSignals()
{
   string response = "";
   int httpCode = SendHTTPGet(InpServerURL, response);
   
   if(httpCode != 200)
   {
      g_consecutiveErrors++;
      if(g_consecutiveErrors >= 5 && g_consecutiveErrors % 10 == 0)
         Print("WARNING: ", g_consecutiveErrors, " consecutive poll failures");
      return;
   }
   
   g_consecutiveErrors = 0;
   ProcessSignalResponse(response);
}

//+------------------------------------------------------------------+
//| Process JSON response containing signals                         |
//+------------------------------------------------------------------+
void ProcessSignalResponse(string jsonResponse)
{
   if(StringLen(jsonResponse) < 10)
      return;
   
   int signalsStart = StringFind(jsonResponse, "\"signals\"");
   if(signalsStart < 0)
   {
      ReceivedSignal signal;
      if(ParseSingleSignal(jsonResponse, signal))
         ProcessSignal(signal);
      return;
   }
   
   int arrayStart = StringFind(jsonResponse, "[", signalsStart);
   int arrayEnd = StringFind(jsonResponse, "]", arrayStart);
   
   if(arrayStart < 0 || arrayEnd < 0)
      return;
   
   string arrayContent = StringSubstr(jsonResponse, arrayStart + 1, arrayEnd - arrayStart - 1);
   
   string signals[];
   int count = SplitJSONArray(arrayContent, signals);
   
   for(int i = 0; i < count; i++)
   {
      ReceivedSignal signal;
      if(ParseSingleSignal(signals[i], signal))
         ProcessSignal(signal);
   }
}

//+------------------------------------------------------------------+
//| Parse single signal from JSON object                              |
//+------------------------------------------------------------------+
bool ParseSingleSignal(string json, ReceivedSignal& signal)
{
   signal.signalId = ExtractJSONString(json, "signal_id");
   if(signal.signalId == "") 
      signal.signalId = ExtractJSONString(json, "id");
   
   signal.action = ExtractJSONString(json, "action");
   signal.symbol = ExtractJSONString(json, "symbol");
   signal.tradeType = ExtractJSONString(json, "type");
   signal.volume = ExtractJSONDouble(json, "volume");
   signal.price = ExtractJSONDouble(json, "price");
   signal.sl = ExtractJSONDouble(json, "sl");
   signal.tp = ExtractJSONDouble(json, "tp");
   signal.magic = (long)ExtractJSONDouble(json, "magic");
   signal.masterTicket = (ulong)ExtractJSONDouble(json, "ticket");
   signal.comment = ExtractJSONString(json, "comment");
   
   string timestampStr = ExtractJSONString(json, "timestamp_utc");
   if(timestampStr == "")
      timestampStr = ExtractJSONString(json, "timestamp");
   
   signal.timestamp = ParseISOTimestamp(timestampStr);
   if(signal.timestamp == 0)
      signal.timestamp = TimeCurrent();
   
   if(signal.action == "" || signal.symbol == "" || signal.tradeType == "")
   {
      Print("Invalid signal: missing required fields");
      return false;
   }
   
   if(signal.volume <= 0)
   {
      Print("Invalid signal: volume must be positive");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Process a validated signal                                        |
//+------------------------------------------------------------------+
void ProcessSignal(ReceivedSignal& signal)
{
   g_signalsReceived++;
   
   if(signal.signalId == g_lastProcessedSignalId && signal.signalId != "")
   {
      Print("Skipping duplicate signal: ", signal.signalId);
      return;
   }
   
   datetime currentGMT = TimeGMT();
   if(signal.timestamp > 0 && currentGMT - signal.timestamp > InpSignalExpirySec)
   {
      PrintFormat("Signal expired: %s (age: %d sec)", signal.signalId, currentGMT - signal.timestamp);
      g_signalsSkipped++;
      SendAcknowledgment(signal.signalId, "EXPIRED");
      return;
   }
   
   string tradingSymbol = MapSymbol(signal.symbol);
   
   if(InpValidateSymbol && !ValidateSymbol(tradingSymbol))
   {
      PrintFormat("Invalid symbol: %s (mapped from %s)", tradingSymbol, signal.symbol);
      g_signalsSkipped++;
      SendAcknowledgment(signal.signalId, "INVALID_SYMBOL");
      return;
   }
   
   string rejectReason = "";
   if(!ValidateTradingConditions(tradingSymbol, signal.volume, rejectReason))
   {
      PrintFormat("Trading conditions not met: %s - %s", signal.symbol, rejectReason);
      g_signalsSkipped++;
      SendAcknowledgment(signal.signalId, "REJECTED:" + rejectReason);
      return;
   }
   
   bool success = false;
   
   if(signal.action == "OPEN")
      success = ExecuteOpenSignal(signal, tradingSymbol);
   else if(signal.action == "CLOSE")
      success = ExecuteCloseSignal(signal, tradingSymbol);
   else if(signal.action == "MODIFY")
      success = ExecuteModifySignal(signal, tradingSymbol);
   else
   {
      Print("Unknown action: ", signal.action);
      g_signalsSkipped++;
   }
   
   if(success)
   {
      g_signalsExecuted++;
      g_lastProcessedSignalId = signal.signalId;
      SendAcknowledgment(signal.signalId, "EXECUTED");
   }
   else
   {
      g_signalsFailed++;
      SendAcknowledgment(signal.signalId, "FAILED:" + IntegerToString(GetLastError()));
   }
}

//+------------------------------------------------------------------+
//| Execute OPEN signal                                               |
//+------------------------------------------------------------------+
bool ExecuteOpenSignal(const ReceivedSignal& signal, string symbol)
{
   if(!InpEnableTrading)
   {
      PrintFormat("[SIMULATION] Would open %s %s %.2f lots @ %.5f SL=%.5f TP=%.5f",
                  signal.tradeType, symbol, signal.volume * InpLotMultiplier,
                  signal.price, signal.sl, signal.tp);
      return true;
   }
   
   double lotSize = NormalizeLotSize(symbol, signal.volume * InpLotMultiplier);
   if(lotSize <= 0)
   {
      Print("Invalid lot size after normalization");
      return false;
   }
   
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   
   double sl = (signal.sl > 0) ? NormalizeDouble(signal.sl, digits) : 0;
   double tp = (signal.tp > 0) ? NormalizeDouble(signal.tp, digits) : 0;
   
   string comment = StringFormat("Sig:%s", signal.signalId);
   if(StringLen(comment) > 31)
      comment = StringSubstr(comment, 0, 31);
   
   bool result = false;
   
   if(signal.tradeType == "BUY")
      result = g_trade.Buy(lotSize, symbol, ask, sl, tp, comment);
   else if(signal.tradeType == "SELL")
      result = g_trade.Sell(lotSize, symbol, bid, sl, tp, comment);
   
   if(result)
   {
      uint retcode = g_trade.ResultRetcode();
      
      if(retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_PLACED)
      {
         ulong deal = g_trade.ResultDeal();
         double price = g_trade.ResultPrice();
         PrintFormat("✓ OPENED %s %s %.2f @ %.5f [Deal: %I64u]",
                     signal.tradeType, symbol, lotSize, price, deal);
         return true;
      }
      else
      {
         PrintFormat("✗ Trade rejected: %d - %s", retcode, GetRetcodeDescription(retcode));
         return false;
      }
   }
   else
   {
      PrintFormat("✗ Trade failed: %d", GetLastError());
      return false;
   }
}

//+------------------------------------------------------------------+
//| Execute CLOSE signal                                              |
//+------------------------------------------------------------------+
bool ExecuteCloseSignal(const ReceivedSignal& signal, string symbol)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      bool directionMatch = false;
      
      if(signal.tradeType == "BUY" && posType == POSITION_TYPE_BUY)
         directionMatch = true;
      else if(signal.tradeType == "SELL" && posType == POSITION_TYPE_SELL)
         directionMatch = true;
      
      string comment = PositionGetString(POSITION_COMMENT);
      if(signal.masterTicket > 0 && StringFind(comment, IntegerToString(signal.masterTicket)) >= 0)
         directionMatch = true;
      
      if(!directionMatch)
         continue;
      
      if(!InpEnableTrading)
      {
         PrintFormat("[SIMULATION] Would close %s ticket %I64u", symbol, ticket);
         return true;
      }
      
      if(g_trade.PositionClose(ticket, InpMaxSlippage))
      {
         uint retcode = g_trade.ResultRetcode();
         if(retcode == TRADE_RETCODE_DONE)
         {
            PrintFormat("✓ CLOSED %s [Ticket: %I64u]", symbol, ticket);
            return true;
         }
         else
            PrintFormat("✗ Close rejected: %d - %s", retcode, GetRetcodeDescription(retcode));
      }
      else
         Print("✗ Close failed: ", GetLastError());
   }
   
   Print("No matching position found for close signal");
   return false;
}

//+------------------------------------------------------------------+
//| Execute MODIFY signal                                             |
//+------------------------------------------------------------------+
bool ExecuteModifySignal(const ReceivedSignal& signal, string symbol)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double newSL = (signal.sl > 0) ? NormalizeDouble(signal.sl, digits) : PositionGetDouble(POSITION_SL);
      double newTP = (signal.tp > 0) ? NormalizeDouble(signal.tp, digits) : PositionGetDouble(POSITION_TP);
      
      if(!InpEnableTrading)
      {
         PrintFormat("[SIMULATION] Would modify %s SL=%.5f TP=%.5f", symbol, newSL, newTP);
         return true;
      }
      
      if(g_trade.PositionModify(ticket, newSL, newTP))
      {
         uint retcode = g_trade.ResultRetcode();
         if(retcode == TRADE_RETCODE_DONE)
         {
            PrintFormat("✓ MODIFIED %s SL=%.5f TP=%.5f", symbol, newSL, newTP);
            return true;
         }
      }
      
      Print("✗ Modify failed: ", GetLastError());
      return false;
   }
   
   Print("No matching position found for modify signal");
   return false;
}

//+------------------------------------------------------------------+
//| Validate trading conditions before execution                      |
//+------------------------------------------------------------------+
bool ValidateTradingConditions(string symbol, double volume, string& rejectReason)
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      rejectReason = "AutoTrading disabled";
      return false;
   }
   
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   {
      rejectReason = "Account trading disabled";
      return false;
   }
   
   if(CountOwnPositions() >= InpMaxPositions)
   {
      rejectReason = "Max positions reached";
      return false;
   }
   
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(marginLevel > 0 && marginLevel < InpMinMarginLevel)
   {
      rejectReason = StringFormat("Margin level %.1f%% < %.1f%%", marginLevel, InpMinMarginLevel);
      return false;
   }
   
   int spread = (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread)
   {
      rejectReason = StringFormat("Spread %d > %d", spread, InpMaxSpread);
      return false;
   }
   
   ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
   {
      rejectReason = "Symbol trading disabled";
      return false;
   }
   
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double adjustedVolume = volume * InpLotMultiplier;
   
   if(adjustedVolume < minLot)
   {
      rejectReason = StringFormat("Volume %.2f < min %.2f", adjustedVolume, minLot);
      return false;
   }
   
   if(adjustedVolume > maxLot || adjustedVolume > InpMaxLotSize)
   {
      rejectReason = StringFormat("Volume %.2f > max %.2f", adjustedVolume, MathMin(maxLot, InpMaxLotSize));
      return false;
   }
   
   double requiredMargin = 0;
   double price = SymbolInfoDouble(symbol, SYMBOL_ASK);
   
   if(!OrderCalcMargin(ORDER_TYPE_BUY, symbol, adjustedVolume, price, requiredMargin))
   {
      rejectReason = "Cannot calculate margin";
      return false;
   }
   
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(requiredMargin > freeMargin)
   {
      rejectReason = StringFormat("Insufficient margin: need %.2f, have %.2f", requiredMargin, freeMargin);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Validate symbol exists and is tradeable                           |
//+------------------------------------------------------------------+
bool ValidateSymbol(string symbol)
{
   if(!SymbolInfoInteger(symbol, SYMBOL_EXIST))
   {
      if(!SymbolSelect(symbol, true))
         return false;
   }
   
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   
   if(bid <= 0 || ask <= 0)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Apply symbol prefix/suffix mapping                                |
//+------------------------------------------------------------------+
string MapSymbol(string symbol)
{
   string result = symbol;
   
   if(StringLen(InpSymbolPrefix) > 0)
      result = InpSymbolPrefix + result;
   
   if(StringLen(InpSymbolSuffix) > 0)
      result = result + InpSymbolSuffix;
   
   return result;
}

//+------------------------------------------------------------------+
//| Normalize lot size to broker specifications                       |
//+------------------------------------------------------------------+
double NormalizeLotSize(string symbol, double requestedLots)
{
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   double lots = MathMin(requestedLots, maxLot);
   lots = MathMin(lots, InpMaxLotSize);
   lots = MathMax(lots, minLot);
   
   lots = MathFloor(lots / lotStep) * lotStep;
   
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Count positions opened by this EA                                 |
//+------------------------------------------------------------------+
int CountOwnPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Send acknowledgment to server                                     |
//+------------------------------------------------------------------+
void SendAcknowledgment(string signalId, string status)
{
   if(StringLen(InpAckURL) == 0)
      return;
   
   string json = "{";
   json += "\"signal_id\":\"" + signalId + "\",";
   json += "\"account_id\":\"" + InpAccountAlias + "\",";
   json += "\"status\":\"" + status + "\",";
   json += "\"timestamp\":\"" + FormatUTCTimestamp(TimeGMT()) + "\"";
   json += "}";
   
   string response;
   SendHTTPPost(InpAckURL, json, response);
}

//+------------------------------------------------------------------+
//| HTTP GET implementation                                           |
//+------------------------------------------------------------------+
int SendHTTPGet(string url, string& response)
{
   string headers = "Accept: application/json\r\n";
   if(StringLen(InpAuthToken) > 0)
      headers += "Authorization: Bearer " + InpAuthToken + "\r\n";
   headers += "X-Account-ID: " + InpAccountAlias + "\r\n";
   
   char postData[];
   char resultData[];
   string resultHeaders;
   
   ResetLastError();
   
   int httpCode = WebRequest(
      "GET",
      url,
      headers,
      InpTimeout,
      postData,
      resultData,
      resultHeaders
   );
   
   if(httpCode == -1)
   {
      int error = GetLastError();
      if(error == 4014)
         Print("ERROR: URL not whitelisted in MT5: ", url);
      return -1;
   }
   
   response = CharArrayToString(resultData, 0, WHOLE_ARRAY, CP_UTF8);
   return httpCode;
}

//+------------------------------------------------------------------+
//| HTTP POST implementation                                          |
//+------------------------------------------------------------------+
int SendHTTPPost(string url, string jsonData, string& response)
{
   string headers = "Content-Type: application/json\r\n";
   if(StringLen(InpAuthToken) > 0)
      headers += "Authorization: Bearer " + InpAuthToken + "\r\n";
   
   char postData[];
   char resultData[];
   string resultHeaders;
   
   StringToCharArray(jsonData, postData, 0, WHOLE_ARRAY, CP_UTF8);
   int dataSize = ArraySize(postData) - 1;
   if(dataSize < 0) dataSize = 0;
   
   ResetLastError();
   
   int httpCode = WebRequest(
      "POST",
      url,
      headers,
      InpTimeout,
      postData,
      resultData,
      resultHeaders
   );
   
   if(httpCode > 0)
      response = CharArrayToString(resultData, 0, WHOLE_ARRAY, CP_UTF8);
   
   return httpCode;
}

//+------------------------------------------------------------------+
//| Test server connection                                            |
//+------------------------------------------------------------------+
bool TestServerConnection()
{
   string response;
   int httpCode = SendHTTPGet(InpServerURL, response);
   return (httpCode == 200 || httpCode == 204);
}

//+------------------------------------------------------------------+
//| JSON Parsing Helper Functions                                     |
//+------------------------------------------------------------------+
string ExtractJSONString(string json, string key)
{
   string searchKey = "\"" + key + "\"";
   int keyPos = StringFind(json, searchKey);
   if(keyPos < 0)
      return "";
   
   int colonPos = StringFind(json, ":", keyPos);
   if(colonPos < 0)
      return "";
   
   int startQuote = StringFind(json, "\"", colonPos);
   if(startQuote < 0)
      return "";
   
   int endQuote = StringFind(json, "\"", startQuote + 1);
   if(endQuote < 0)
      return "";
   
   return StringSubstr(json, startQuote + 1, endQuote - startQuote - 1);
}

double ExtractJSONDouble(string json, string key)
{
   string searchKey = "\"" + key + "\"";
   int keyPos = StringFind(json, searchKey);
   if(keyPos < 0)
      return 0;
   
   int colonPos = StringFind(json, ":", keyPos);
   if(colonPos < 0)
      return 0;
   
   int startPos = colonPos + 1;
   int len = StringLen(json);
   
   while(startPos < len)
   {
      ushort ch = StringGetCharacter(json, startPos);
      if(ch != ' ' && ch != '\t' && ch != '\n' && ch != '\r')
         break;
      startPos++;
   }
   
   if(StringGetCharacter(json, startPos) == 'n')
      return 0;
   
   int endPos = startPos;
   while(endPos < len)
   {
      ushort ch = StringGetCharacter(json, endPos);
      if((ch >= '0' && ch <= '9') || ch == '.' || ch == '-' || ch == '+')
         endPos++;
      else
         break;
   }
   
   string numStr = StringSubstr(json, startPos, endPos - startPos);
   return StringToDouble(numStr);
}

int SplitJSONArray(string arrayContent, string& elements[])
{
   ArrayResize(elements, 0);
   
   int braceCount = 0;
   int elementStart = 0;
   int count = 0;
   
   for(int i = 0; i < StringLen(arrayContent); i++)
   {
      ushort ch = StringGetCharacter(arrayContent, i);
      
      if(ch == '{')
      {
         if(braceCount == 0)
            elementStart = i;
         braceCount++;
      }
      else if(ch == '}')
      {
         braceCount--;
         if(braceCount == 0)
         {
            string element = StringSubstr(arrayContent, elementStart, i - elementStart + 1);
            ArrayResize(elements, count + 1);
            elements[count] = element;
            count++;
         }
      }
   }
   
   return count;
}

datetime ParseISOTimestamp(string isoTime)
{
   if(StringLen(isoTime) < 19)
      return 0;
   
   int year = (int)StringToInteger(StringSubstr(isoTime, 0, 4));
   int month = (int)StringToInteger(StringSubstr(isoTime, 5, 2));
   int day = (int)StringToInteger(StringSubstr(isoTime, 8, 2));
   int hour = (int)StringToInteger(StringSubstr(isoTime, 11, 2));
   int minute = (int)StringToInteger(StringSubstr(isoTime, 14, 2));
   int second = (int)StringToInteger(StringSubstr(isoTime, 17, 2));
   
   MqlDateTime dt;
   dt.year = year;
   dt.mon = month;
   dt.day = day;
   dt.hour = hour;
   dt.min = minute;
   dt.sec = second;
   
   return StructToTime(dt);
}

string FormatUTCTimestamp(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ",
                       dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
}

string GetRetcodeDescription(uint retcode)
{
   switch(retcode)
   {
      case TRADE_RETCODE_REQUOTE:         return "Requote";
      case TRADE_RETCODE_REJECT:          return "Request rejected";
      case TRADE_RETCODE_CANCEL:          return "Request canceled";
      case TRADE_RETCODE_PLACED:          return "Order placed";
      case TRADE_RETCODE_DONE:            return "Request completed";
      case TRADE_RETCODE_DONE_PARTIAL:    return "Partial execution";
      case TRADE_RETCODE_ERROR:           return "Request processing error";
      case TRADE_RETCODE_TIMEOUT:         return "Request timeout";
      case TRADE_RETCODE_INVALID:         return "Invalid request";
      case TRADE_RETCODE_INVALID_VOLUME:  return "Invalid volume";
      case TRADE_RETCODE_INVALID_PRICE:   return "Invalid price";
      case TRADE_RETCODE_INVALID_STOPS:   return "Invalid stops";
      case TRADE_RETCODE_TRADE_DISABLED:  return "Trading disabled";
      case TRADE_RETCODE_MARKET_CLOSED:   return "Market closed";
      case TRADE_RETCODE_NO_MONEY:        return "Insufficient funds";
      case TRADE_RETCODE_PRICE_CHANGED:   return "Price changed";
      case TRADE_RETCODE_PRICE_OFF:       return "No quotes";
      case TRADE_RETCODE_INVALID_FILL:    return "Invalid fill type";
      case TRADE_RETCODE_CONNECTION:      return "No connection";
      default:                            return "Unknown (" + IntegerToString(retcode) + ")";
   }
}
//+------------------------------------------------------------------+
