//+------------------------------------------------------------------+
//|                                              SignalSenderEA.mq5 |
//|                                    Trade Signal Broadcast System |
//+------------------------------------------------------------------+
#property copyright   "Boss Joel Trading Ecosystem"
#property version     "1.00"
#property description "Broadcasts trade executions to web server via HTTP POST"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\DealInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "=== Server Configuration ==="
input string   InpServerURL      = "https://api.yourdomain.com/signals";
input string   InpAuthToken      = "";
input int      InpTimeout        = 5000;
input int      InpMaxRetries     = 3;

input group "=== Signal Filtering ==="
input int      InpMagicNumber    = 0;
input string   InpSymbolFilter   = "";
input bool     InpSendOpens      = true;
input bool     InpSendCloses     = true;
input bool     InpSendModifies   = true;

input group "=== Account Identification ==="
input string   InpAccountAlias   = "MASTER_001";
input string   InpEAName         = "SignalSender";

input group "=== Periodic Updates ==="
input bool     InpSendHeartbeat  = true;
input int      InpHeartbeatSec   = 60;
input bool     InpSendPositions  = true;
input int      InpPositionSec    = 30;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CDealInfo      g_dealInfo;
CPositionInfo  g_posInfo;

ulong          g_lastDealTicket = 0;
datetime       g_lastHeartbeat = 0;
datetime       g_lastPositionUpdate = 0;
int            g_consecutiveErrors = 0;
int            g_totalSignalsSent = 0;
int            g_totalSignalsFailed = 0;

enum ENUM_SIGNAL_ACTION
{
   SIGNAL_OPEN,
   SIGNAL_CLOSE,
   SIGNAL_MODIFY,
   SIGNAL_HEARTBEAT,
   SIGNAL_POSITION_SNAPSHOT,
   SIGNAL_ACCOUNT_UPDATE
};

struct TradeSignal
{
   ENUM_SIGNAL_ACTION action;
   ulong              ticket;
   string             symbol;
   string             tradeType;
   double             volume;
   double             price;
   double             sl;
   double             tp;
   double             profit;
   long               magic;
   string             comment;
   datetime           timestamp;
   string             dealEntry;
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
   
   if(StringFind(InpServerURL, "https://") != 0 && StringFind(InpServerURL, "http://") != 0)
   {
      Print("ERROR: Server URL must start with http:// or https://");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   Print("==========================================================");
   Print("IMPORTANT: Ensure URL is whitelisted in MT5:");
   Print("Tools -> Options -> Expert Advisors -> Allow WebRequest");
   Print("Add URL: ", InpServerURL);
   Print("==========================================================");
   
   if(HistorySelect(TimeCurrent() - 86400, TimeCurrent()))
   {
      int totalDeals = HistoryDealsTotal();
      if(totalDeals > 0)
      {
         g_lastDealTicket = HistoryDealGetTicket(totalDeals - 1);
         Print("Initialized with last deal ticket: ", g_lastDealTicket);
      }
   }
   
   if(InpSendHeartbeat || InpSendPositions)
   {
      int timerInterval = MathMin(
         InpSendHeartbeat ? InpHeartbeatSec : INT_MAX,
         InpSendPositions ? InpPositionSec : INT_MAX
      );
      EventSetTimer(timerInterval);
   }
   
   if(SendHeartbeat())
      Print("Server connection verified");
   else
      Print("WARNING: Could not reach server. Check URL whitelist.");
   
   Print("Signal Sender EA initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("==========================================================");
   Print("Signal Sender EA shutting down");
   Print("Total Signals Sent: ", g_totalSignalsSent);
   Print("Total Signals Failed: ", g_totalSignalsFailed);
   Print("==========================================================");
}

//+------------------------------------------------------------------+
//| Tick event (required by MT5 EA loader)                           |
//+------------------------------------------------------------------+
void OnTick()
{
   // Intentionally empty.
   // This EA reacts to trade events and timers, not ticks.
}


//+------------------------------------------------------------------+
void OnTrade()
{
   ProcessNewDeals();
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_POSITION && InpSendModifies)
   {
      if(trans.position != 0)
         ProcessPositionModification(trans.position);
   }
}

//+------------------------------------------------------------------+
void OnTimer()
{
   datetime currentTime = TimeCurrent();
   
   if(InpSendHeartbeat && currentTime - g_lastHeartbeat >= InpHeartbeatSec)
   {
      SendHeartbeat();
      g_lastHeartbeat = currentTime;
   }
   
   if(InpSendPositions && currentTime - g_lastPositionUpdate >= InpPositionSec)
   {
      SendPositionSnapshot();
      g_lastPositionUpdate = currentTime;
   }
}

//+------------------------------------------------------------------+
void ProcessNewDeals()
{
   datetime fromTime = TimeCurrent() - 300;
   datetime toTime = TimeCurrent() + 60;
   
   if(!HistorySelect(fromTime, toTime))
   {
      Print("ERROR: HistorySelect failed, error: ", GetLastError());
      return;
   }
   
   int totalDeals = HistoryDealsTotal();
   
   for(int i = 0; i < totalDeals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      
      if(dealTicket <= g_lastDealTicket)
         continue;
      
      if(!HistoryDealSelect(dealTicket))
         continue;
      
      string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
      long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
      ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
      ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      
      if(!PassesFilters(symbol, magic, dealType, dealEntry))
      {
         g_lastDealTicket = dealTicket;
         continue;
      }
      
      TradeSignal signal;
      BuildSignalFromDeal(dealTicket, signal);
      
      if(SendSignalToServer(signal))
      {
         g_totalSignalsSent++;
         g_consecutiveErrors = 0;
         PrintFormat("Signal sent: %s %s %.2f %s @ %.5f",
                     signal.action == SIGNAL_OPEN ? "OPEN" : "CLOSE",
                     signal.tradeType, signal.volume, signal.symbol, signal.price);
      }
      else
      {
         g_totalSignalsFailed++;
         g_consecutiveErrors++;
         if(g_consecutiveErrors >= 5)
            Alert("Signal Sender: ", g_consecutiveErrors, " consecutive failures!");
      }
      
      g_lastDealTicket = dealTicket;
   }
}

//+------------------------------------------------------------------+
bool PassesFilters(string symbol, long magic, ENUM_DEAL_TYPE dealType, ENUM_DEAL_ENTRY dealEntry)
{
   if(InpMagicNumber != 0 && magic != InpMagicNumber)
      return false;
   
   if(StringLen(InpSymbolFilter) > 0 && symbol != InpSymbolFilter)
      return false;
   
   if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL)
      return false;
   
   if(dealEntry == DEAL_ENTRY_IN && !InpSendOpens)
      return false;
   
   if(dealEntry == DEAL_ENTRY_OUT && !InpSendCloses)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
void BuildSignalFromDeal(ulong dealTicket, TradeSignal& signal)
{
   ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   
   signal.action = (dealEntry == DEAL_ENTRY_IN) ? SIGNAL_OPEN : SIGNAL_CLOSE;
   signal.ticket = dealTicket;
   signal.symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   
   ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
   signal.tradeType = (dealType == DEAL_TYPE_BUY) ? "BUY" : "SELL";
   
   signal.volume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
   signal.price = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
   signal.profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   signal.magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   signal.comment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
   signal.timestamp = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
   
   switch(dealEntry)
   {
      case DEAL_ENTRY_IN:    signal.dealEntry = "IN";    break;
      case DEAL_ENTRY_OUT:   signal.dealEntry = "OUT";   break;
      case DEAL_ENTRY_INOUT: signal.dealEntry = "INOUT"; break;
      default:               signal.dealEntry = "UNKNOWN";
   }
   
   signal.sl = 0;
   signal.tp = 0;
   
   if(dealEntry == DEAL_ENTRY_IN)
   {
      ulong positionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      if(PositionSelectByTicket(positionId))
      {
         signal.sl = PositionGetDouble(POSITION_SL);
         signal.tp = PositionGetDouble(POSITION_TP);
      }
   }
}

//+------------------------------------------------------------------+
void ProcessPositionModification(ulong positionTicket)
{
   if(!PositionSelectByTicket(positionTicket))
      return;
   
   string symbol = PositionGetString(POSITION_SYMBOL);
   long magic = PositionGetInteger(POSITION_MAGIC);
   
   if(InpMagicNumber != 0 && magic != InpMagicNumber)
      return;
   
   if(StringLen(InpSymbolFilter) > 0 && symbol != InpSymbolFilter)
      return;
   
   TradeSignal signal;
   signal.action = SIGNAL_MODIFY;
   signal.ticket = positionTicket;
   signal.symbol = symbol;
   signal.tradeType = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? "BUY" : "SELL";
   signal.volume = PositionGetDouble(POSITION_VOLUME);
   signal.price = PositionGetDouble(POSITION_PRICE_OPEN);
   signal.sl = PositionGetDouble(POSITION_SL);
   signal.tp = PositionGetDouble(POSITION_TP);
   signal.profit = PositionGetDouble(POSITION_PROFIT);
   signal.magic = magic;
   signal.comment = PositionGetString(POSITION_COMMENT);
   signal.timestamp = TimeCurrent();
   signal.dealEntry = "MODIFY";
   
   if(SendSignalToServer(signal))
   {
      g_totalSignalsSent++;
      PrintFormat("Modify signal sent: %s SL=%.5f TP=%.5f", signal.symbol, signal.sl, signal.tp);
   }
}

//+------------------------------------------------------------------+
bool SendSignalToServer(const TradeSignal& signal)
{
   string json = BuildSignalJSON(signal);
   
   for(int attempt = 1; attempt <= InpMaxRetries; attempt++)
   {
      int httpCode = SendHTTPPost(InpServerURL, json);
      
      if(httpCode == 200 || httpCode == 201)
         return true;
      
      if(httpCode == 401 || httpCode == 403)
      {
         Print("Authentication error (", httpCode, "). Check auth token.");
         return false;
      }
      
      if(attempt < InpMaxRetries)
      {
         int sleepMs = (int)MathPow(2, attempt) * 500;
         Print("Request failed (", httpCode, "). Retrying in ", sleepMs, "ms...");
         Sleep(sleepMs);
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
string BuildSignalJSON(const TradeSignal& signal)
{
   string actionStr;
   switch(signal.action)
   {
      case SIGNAL_OPEN:              actionStr = "OPEN";              break;
      case SIGNAL_CLOSE:             actionStr = "CLOSE";             break;
      case SIGNAL_MODIFY:            actionStr = "MODIFY";            break;
      case SIGNAL_HEARTBEAT:         actionStr = "HEARTBEAT";         break;
      case SIGNAL_POSITION_SNAPSHOT: actionStr = "POSITION_SNAPSHOT"; break;
      case SIGNAL_ACCOUNT_UPDATE:    actionStr = "ACCOUNT_UPDATE";    break;
      default:                       actionStr = "UNKNOWN";
   }
   
   string json = "{";
   json += "\"type\":\"TRADE_SIGNAL\",";
   json += "\"action\":\"" + actionStr + "\",";
   json += "\"account_id\":\"" + EscapeJSON(InpAccountAlias) + "\",";
   json += "\"ea_name\":\"" + EscapeJSON(InpEAName) + "\",";
   json += "\"timestamp\":\"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\",";
   json += "\"timestamp_utc\":\"" + FormatUTCTimestamp(TimeGMT()) + "\",";
   json += "\"data\":{";
   json += "\"ticket\":" + IntegerToString(signal.ticket) + ",";
   json += "\"symbol\":\"" + signal.symbol + "\",";
   json += "\"type\":\"" + signal.tradeType + "\",";
   json += "\"entry\":\"" + signal.dealEntry + "\",";
   json += "\"volume\":" + DoubleToString(signal.volume, 2) + ",";
   json += "\"price\":" + DoubleToString(signal.price, 5) + ",";
   json += "\"sl\":" + DoubleToString(signal.sl, 5) + ",";
   json += "\"tp\":" + DoubleToString(signal.tp, 5) + ",";
   json += "\"profit\":" + DoubleToString(signal.profit, 2) + ",";
   json += "\"magic\":" + IntegerToString(signal.magic) + ",";
   json += "\"comment\":\"" + EscapeJSON(signal.comment) + "\"";
   json += "}}";
   
   return json;
}

//+------------------------------------------------------------------+
bool SendHeartbeat()
{
   string json = "{";
   json += "\"type\":\"HEARTBEAT\",";
   json += "\"account_id\":\"" + EscapeJSON(InpAccountAlias) + "\",";
   json += "\"ea_name\":\"" + EscapeJSON(InpEAName) + "\",";
   json += "\"timestamp_utc\":\"" + FormatUTCTimestamp(TimeGMT()) + "\",";
   json += "\"data\":{";
   json += "\"balance\":" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + ",";
   json += "\"equity\":" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + ",";
   json += "\"margin\":" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN), 2) + ",";
   json += "\"free_margin\":" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + ",";
   json += "\"profit\":" + DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 2) + ",";
   json += "\"positions_count\":" + IntegerToString(PositionsTotal()) + ",";
   json += "\"server_time\":\"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\"";
   json += "}}";
   
   int httpCode = SendHTTPPost(InpServerURL + "/heartbeat", json);
   return (httpCode == 200 || httpCode == 201);
}

//+------------------------------------------------------------------+
bool SendPositionSnapshot()
{
   string json = "{";
   json += "\"type\":\"POSITION_SNAPSHOT\",";
   json += "\"account_id\":\"" + EscapeJSON(InpAccountAlias) + "\",";
   json += "\"ea_name\":\"" + EscapeJSON(InpEAName) + "\",";
   json += "\"timestamp_utc\":\"" + FormatUTCTimestamp(TimeGMT()) + "\",";
   json += "\"positions\":[";
   
   int total = PositionsTotal();
   int addedCount = 0;
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      
      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);
      
      if(InpMagicNumber != 0 && magic != InpMagicNumber)
         continue;
      
      if(StringLen(InpSymbolFilter) > 0 && symbol != InpSymbolFilter)
         continue;
      
      if(addedCount > 0)
         json += ",";
      
      json += "{";
      json += "\"ticket\":" + IntegerToString(ticket) + ",";
      json += "\"symbol\":\"" + symbol + "\",";
      json += "\"type\":\"" + (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL") + "\",";
      json += "\"volume\":" + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2) + ",";
      json += "\"open_price\":" + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), 5) + ",";
      json += "\"current_price\":" + DoubleToString(PositionGetDouble(POSITION_PRICE_CURRENT), 5) + ",";
      json += "\"sl\":" + DoubleToString(PositionGetDouble(POSITION_SL), 5) + ",";
      json += "\"tp\":" + DoubleToString(PositionGetDouble(POSITION_TP), 5) + ",";
      json += "\"profit\":" + DoubleToString(PositionGetDouble(POSITION_PROFIT), 2) + ",";
      json += "\"swap\":" + DoubleToString(PositionGetDouble(POSITION_SWAP), 2) + ",";
      json += "\"magic\":" + IntegerToString(magic);
      json += "}";
      
      addedCount++;
   }
   
   json += "]}";
   
   int httpCode = SendHTTPPost(InpServerURL + "/positions", json);
   return (httpCode == 200 || httpCode == 201);
}

//+------------------------------------------------------------------+
int SendHTTPPost(string url, string jsonData)
{
   string headers = "Content-Type: application/json\r\n";
   if(StringLen(InpAuthToken) > 0)
      headers += "Authorization: Bearer " + InpAuthToken + "\r\n";
   headers += "X-Account-ID: " + InpAccountAlias + "\r\n";
   
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
   
   if(httpCode == -1)
   {
      int error = GetLastError();
      
      switch(error)
      {
         case 4014:
            Print("ERROR 4014: URL not in allowed list. Add to: Tools -> Options -> Expert Advisors");
            break;
         case 4015:
            Print("ERROR 4015: Connection failed. Check internet/firewall.");
            break;
         case 4016:
            Print("ERROR 4016: Request timed out after ", InpTimeout, "ms");
            break;
         case 5203:
            Print("ERROR 5203: Request execution failed");
            break;
         default:
            Print("WebRequest error: ", error);
      }
      
      return -1;
   }
   
   if(httpCode != 200 && httpCode != 201)
   {
      string response = CharArrayToString(resultData, 0, WHOLE_ARRAY, CP_UTF8);
      Print("HTTP ", httpCode, " Response: ", StringSubstr(response, 0, 200));
   }
   
   return httpCode;
}

//+------------------------------------------------------------------+
string EscapeJSON(string text)
{
   string result = text;
   StringReplace(result, "\\", "\\\\");
   StringReplace(result, "\"", "\\\"");
   StringReplace(result, "\n", "\\n");
   StringReplace(result, "\r", "\\r");
   StringReplace(result, "\t", "\\t");
   return result;
}

//+------------------------------------------------------------------+
string FormatUTCTimestamp(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ",
                       dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
}
//+------------------------------------------------------------------+
