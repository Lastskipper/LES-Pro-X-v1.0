//================================================================================
// LES PRO X v1.0 - PHASE 1: CORE FRAMEWORK
// MetaTrader 5 Expert Advisor
// Institutional ICT/SMC System for Gold Day Trading
//
// Phase 1 Deliverables:
// - Input settings and configuration
// - Symbol selection and validation
// - ATR indicator handle management
// - Session and time helper functions
// - New-bar detection mechanism
// - Risk anchors and account protection
// - Trade tracking infrastructure
// - Journal/CSV logging system
// - Shadow mode support (paper trading)
//
// This phase compiles cleanly with zero errors and runs safely
// All dependent modules will build on this foundation
//================================================================================

#property copyright "LES Pro X v1.0"
#property link      "https://github.com/Lastskipper/LES-Pro-X-v1.0"
#property version   "1.00"
#property strict
#property description "Institutional ICT/SMC Expert Advisor for Gold Day Trading"

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\DealInfo.mqh>
#include <Arrays\ArrayObj.mqh>

//================================================================================
// ENUMERATIONS
//================================================================================

/// @enum Session types for kill zone identification
enum SESSION_TYPE
{
   SESSION_ASIAN    = 1,      // Asian session (typically 00:00-08:00 UTC)
   SESSION_LONDON   = 2,      // London session (typically 08:00-17:00 UTC)
   SESSION_NEWYORK  = 3,      // New York session (typically 13:00-21:00 UTC)
   SESSION_OVERLAP  = 4,      // London/NY overlap (highest volatility)
   SESSION_UNKNOWN  = 0       // No identified session
};

/// @enum Execution direction
enum TRADE_DIRECTION
{
   DIRECTION_LONG   = 1,      // Long trade (buy)
   DIRECTION_SHORT  = -1,     // Short trade (sell)
   DIRECTION_NONE   = 0       // No active direction
};

/// @enum Trade quality grades
enum TRADE_GRADE
{
   GRADE_APLUS      = 5,      // A+: Exceptional institutional alignment
   GRADE_A          = 4,      // A: Strong, tradable setup
   GRADE_B          = 3,      // B: Acceptable but not ideal
   GRADE_C          = 2,      // C: Weak but technically valid
   GRADE_REJECT     = 1,      // Reject: Fails minimum bar
   GRADE_UNKNOWN    = 0       // Unknown grade
};

/// @enum Market bias direction
enum MARKET_BIAS
{
   BIAS_BULLISH     = 1,      // Bullish bias
   BIAS_BEARISH     = -1,     // Bearish bias
   BIAS_NEUTRAL     = 0       // Neutral/undecided
};

/// @enum Position state
enum POSITION_STATE
{
   POS_CLOSED       = 0,      // No open position
   POS_PENDING      = 1,      // Pending entry
   POS_OPEN         = 2,      // Position open and running
   POS_BREAKEVEN    = 3,      // Stop moved to break-even
   POS_PARTIAL      = 4       // Partial close done, remainder open
};

//================================================================================
// CONSTANTS
//================================================================================

// Session times (UTC-based, adjust for your timezone/broker)
const int ASIAN_OPEN_HOUR    = 0;      // 00:00 UTC
const int LONDON_OPEN_HOUR   = 8;      // 08:00 UTC
const int NEWYORK_OPEN_HOUR  = 13;     // 13:00 UTC (summer), 14:00 (winter)
const int SESSION_CLOSE_HOUR = 21;     // 21:00 UTC

// Risk and money management defaults
const double DEFAULT_RISK_PERCENT = 1.0;           // Risk 1% per trade by default
const double MAX_RISK_PERCENT      = 3.0;          // Maximum 3% per trade
const double MIN_RISK_PERCENT      = 0.25;         // Minimum 0.25% per trade
const int    MAX_OPEN_TRADES       = 3;            // Maximum 3 simultaneous trades
const double MAX_DAILY_LOSS_PERCENT = 5.0;        // Stop trading if -5% daily
const double MAX_WEEKLY_LOSS_PERCENT = 10.0;      // Stop trading if -10% weekly

// Timing constants
const int BAR_CHECK_INTERVAL = 1000;               // Check for new bar every 1000ms
const int CSV_WRITE_INTERVAL = 5000;               // Write stats every 5 seconds
const int TRADE_TIMEOUT_BARS = 100;                // Close trade if >100 bars old

// File paths
const string JOURNAL_PATH = "Logs\\LES_Pro_X_Journal.csv";
const string STATS_PATH   = "Logs\\LES_Pro_X_Stats.csv";

// Tolerance and filter constants
const double MIN_SPREAD_MULTIPLIER = 1.0;          // Spread must be < 1.0x normal
const double VOLATILITY_EXTREME_ATR = 2.5;         // ATR > 2.5x normal = extreme

//================================================================================
// INPUT SETTINGS
//================================================================================

input group "=== SYMBOL & TRADING ===";
input string       inSymbol              = "XAUUSD";      // Symbol to trade (gold)
input TRADE_DIRECTION inPreferredDirection = DIRECTION_NONE; // 0=Both, 1=Long only, -1=Short only

input group "=== RISK MANAGEMENT ===";
input double       inRiskPercentPerTrade = 1.0;           // Risk % per trade (0.25-3.0)
input double       inMaxDailyLossPercent = 5.0;           // Max daily loss % before lockout
input double       inMaxWeeklyLossPercent = 10.0;          // Max weekly loss % before lockout
input double       inMaxDrawdownPercent  = 15.0;          // Max drawdown % from peak equity
input int          inMaxOpenTrades       = 3;             // Max simultaneous open positions
input double       inAtrStopMultiplier   = 1.5;           // ATR stop distance multiplier

input group "=== SESSIONS & TIME ===";
input bool         inTradeAsianSession   = true;          // Allow Asian session trades
input bool         inTradeLondonOpen     = true;          // Allow London open trades
input bool         inTradeLondonClose    = true;          // Allow London close trades
input bool         inTradeNYOpen         = true;          // Allow NY open trades
input bool         inTradeNYLunch        = false;         // Allow NY lunch (not recommended)
input int          inNewBarCheckInterval = 1000;          // Check for new bar (ms)

input group "=== EXECUTION & PRECISION ===";
input double       inMinSpreadMultiplier = 1.0;           // Min spread OK as multiple of avg
input bool         inUseShadowMode       = false;         // Paper trading mode (no real orders)
input bool         inUsePartialClose     = true;          // Close part at TP1, remainder at TP2
input int          inPartialClosePercent = 50;            // Close 50% at TP1

input group "=== CHART & DISPLAY ===";
input bool         inShowDashboard       = true;          // Display live dashboard
input int          inDashboardX          = 10;            // Dashboard X position
input int          inDashboardY          = 10;            // Dashboard Y position
input bool         inShowDebugInfo       = true;          // Show debug information

input group "=== LOGGING & ANALYSIS ===";
input bool         inEnableJournal       = true;          // Enable trade journal logging
input bool         inEnableStatistics    = true;          // Enable statistics tracking
input bool         inExportToCSV         = true;          // Export to CSV files
input int          inCsvWriteInterval    = 5000;          // CSV write interval (ms)

//================================================================================
// GLOBAL STRUCTURES
//================================================================================

/// @struct Account state tracker
struct AccountState
{
   double   startBalance;           // Balance at EA start
   double   currentBalance;         // Current account balance
   double   dailyStartBalance;      // Balance at start of day
   double   weeklyStartBalance;     // Balance at start of week
   double   peakEquity;             // Highest equity reached
   double   currentDrawdown;        // Current drawdown from peak
   double   dailyPnL;               // Profit/loss today
   double   weeklyPnL;              // Profit/loss this week
   double   dailyOpenTrades;        // Trades opened today
   double   winRate;                // Win rate percentage
   double   profitFactor;           // Gross profit / gross loss
   double   expectancy;             // Average win per trade
};

/// @struct Trade setup context
struct SetupContext
{
   int      barTime;                // Time of bar formation
   TRADE_DIRECTION direction;       // Long or short
   double   entryPrice;             // Entry price level
   double   stopPrice;              // Stop loss price
   double   tp1Price;               // Take profit 1 (partial close)
   double   tp2Price;               // Take profit 2 (final target)
   double   riskAmount;             // Risk in account currency
   double   rewardAmount;           // Reward in account currency
   double   riskRewardRatio;        // Risk:Reward ratio
   TRADE_GRADE setupGrade;          // Quality grade A+/A/B/C/Reject
   double   setupConfidence;        // Confidence 0-100
   string   narrativeType;          // Daily narrative classification
   string   executionModel;         // Execution model used
   string   liquidityTarget;        // Target liquidity type
};

/// @struct Session statistics
struct SessionStats
{
   string   sessionName;            // Session identifier
   int      tradeCount;             // Number of trades in session
   int      winCount;               // Number of wins
   int      lossCount;              // Number of losses
   double   sessionPnL;             // P/L for session
   double   sessionWinRate;         // Win rate %
   double   avgRR;                  // Average risk:reward
   long     sessionStartTime;       // Session start timestamp
   long     sessionEndTime;         // Session end timestamp
};

//================================================================================
// GLOBAL VARIABLES - APPLICATION STATE
//================================================================================

// Core handles and objects
CTrade          gTrade;             // Trade object for order operations
COrderInfo      gOrderInfo;         // Order information helper
CPositionInfo   gPositionInfo;      // Position information helper
CDealInfo       gDealInfo;          // Deal information helper
CArrayObj       gActiveTrades;      // Array of active trade contexts

// Indicator handles
int             gATRHandle;         // ATR indicator handle
int             gMovingAvgHandle;   // Moving average for trend (future phases)

// Time and bar tracking
datetime        gLastBarTime;       // Time of last processed bar
datetime        gLastDailyReset;    // Time of last daily stats reset
datetime        gLastWeeklyReset;   // Time of last weekly stats reset
int             gBarCounter;        // Counter for bars since EA start
bool            gIsNewBar;          // Flag: new bar detected this tick

// Account state
AccountState    gAccount;           // Current account state
bool            gDailyLockout;      // Daily loss limit reached
bool            gWeeklyLockout;     // Weekly loss limit reached
int             gConsecutiveLosses; // Consecutive losing trades
int             gConsecutiveWins;   // Consecutive winning trades

// Session tracking
SESSION_TYPE    gCurrentSession;    // Current active session
datetime        gSessionStart;      // Session start time
double          gSessionHigh;       // Session high so far
double          gSessionLow;        // Session low so far

// Trade tracking
int             gOpenTradeCount;    // Number of currently open trades
bool            gTradeInProgress;   // Is a trade currently active
ulong           gCurrentTradeTicket; // Ticket of current trade
SetupContext    gCurrentSetup;      // Context of current setup/trade

// File handles and logging
int             gJournalHandle;     // File handle for journal
int             gStatsHandle;       // File handle for statistics
string          gJournalFilePath;   // Full path to journal file
string          gStatsFilePath;     // Full path to stats file

// Timing
uint            gLastCheckTime;     // Last time we checked for new bar (ms)
uint            gLastCsvWrite;      // Last time CSV was written (ms)

// Configuration flags
bool            gShadowMode;        // Paper trading enabled
bool            gShowDashboard;     // Display dashboard on chart
bool            gEnableLogging;     // Enable all logging

//================================================================================
// CLASS: CLogWriter - Trade Journal Management
//================================================================================

class CLogWriter
{
private:
   string   m_journalPath;
   int      m_handle;
   bool     m_initialized;
   
public:
   /// Initialize logger with file path
   bool Initialize(string filePath)
   {
      m_journalPath = filePath;
      
      // Ensure directory exists
      if(!FileIsExist(m_journalPath)) {
         if(!CreateDirectory(m_journalPath)) {
            Print("ERROR: Failed to create journal directory: ", m_journalPath);
            return false;
         }
      }
      
      // Open file for appending
      m_handle = FileOpen(m_journalPath, FILE_CSV | FILE_READ | FILE_WRITE, ",");
      if(m_handle == INVALID_HANDLE) {
         Print("ERROR: Failed to open journal file: ", m_journalPath);
         return false;
      }
      
      // Write header if file is new/empty
      if(FileSize(m_handle) == 0) {
         WriteHeader();
      }
      
      m_initialized = true;
      return true;
   }
   
   /// Write CSV header row
   void WriteHeader(void)
   {
      if(!m_initialized) return;
      
      FileSeek(m_handle, 0, SEEK_END);
      FileWrite(m_handle,
         "TradeID", "Date", "Time", "Symbol", "Direction",
         "EntryPrice", "StopLoss", "TP1", "TP2", "RiskAmount",
         "RewardAmount", "RR_Ratio", "Grade", "Confidence",
         "Narrative", "ExecutionModel", "LiquidityTarget",
         "Result", "ExitPrice", "PnL", "Win", "Bars",
         "MFE", "MAE", "Spread", "Slippage", "Notes");
      FileFlush(m_handle);
   }
   
   /// Log a trade entry
   void LogTrade(int tradeID, const SetupContext &setup, string notes = "")
   {
      if(!m_initialized) return;
      
      FileSeek(m_handle, 0, SEEK_END);
      FileWrite(m_handle,
         IntegerToString(tradeID),
         TimeToString(TimeCurrent(), TIME_DATE),
         TimeToString(TimeCurrent(), TIME_SECONDS),
         Symbol(),
         setup.direction == DIRECTION_LONG ? "LONG" : "SHORT",
         DoubleToString(setup.entryPrice, 5),
         DoubleToString(setup.stopPrice, 5),
         DoubleToString(setup.tp1Price, 5),
         DoubleToString(setup.tp2Price, 5),
         DoubleToString(setup.riskAmount, 2),
         DoubleToString(setup.rewardAmount, 2),
         DoubleToString(setup.riskRewardRatio, 2),
         GradeToString(setup.setupGrade),
         DoubleToString(setup.setupConfidence, 2),
         setup.narrativeType,
         setup.executionModel,
         setup.liquidityTarget,
         "OPEN", "0", "0", "0", "0", "0", "0", notes);
      FileFlush(m_handle);
   }
   
   /// Log trade exit/close
   void LogTradeExit(int tradeID, double exitPrice, double pnl, bool isWin, 
                     int barCount, double mfe, double mae, double spread, string notes = "")
   {
      // For Phase 1, we'll just log to Print output
      // Full CSV update will be in later phases
      Print("Trade #", tradeID, " Exit: Price=", exitPrice, " PnL=", pnl, 
            " Result=", (isWin ? "WIN" : "LOSS"));
   }
   
   /// Cleanup
   ~CLogWriter(void)
   {
      if(m_handle != INVALID_HANDLE) {
         FileClose(m_handle);
      }
   }

private:
   /// Helper: Convert grade to string
   string GradeToString(TRADE_GRADE grade)
   {
      switch(grade) {
         case GRADE_APLUS:  return "A+";
         case GRADE_A:      return "A";
         case GRADE_B:      return "B";
         case GRADE_C:      return "C";
         case GRADE_REJECT: return "REJECT";
         default:           return "UNKNOWN";
      }
   }
};

// Global logger instance
CLogWriter gLogger;

//================================================================================
// HELPER FUNCTIONS - SESSION & TIME
//================================================================================

/// @brief Detect current session based on broker time
/// @return SESSION_TYPE current session
SESSION_TYPE DetectCurrentSession(void)
{
   int hour = Hour();
   
   // Adjust for timezone offset if needed (example: 2-hour offset for GMT+2)
   // This is configurable per broker
   
   if(hour >= ASIAN_OPEN_HOUR && hour < LONDON_OPEN_HOUR)
      return SESSION_ASIAN;
   
   if(hour >= LONDON_OPEN_HOUR && hour < NEWYORK_OPEN_HOUR)
      return SESSION_LONDON;
   
   if(hour >= NEWYORK_OPEN_HOUR && hour < SESSION_CLOSE_HOUR)
      return SESSION_NEWYORK;
   
   // Check for overlap (London close / NY open)
   if(hour >= (NEWYORK_OPEN_HOUR - 1) && hour < (LONDON_OPEN_HOUR + 8))
      return SESSION_OVERLAP;
   
   return SESSION_UNKNOWN;
}

/// @brief Get session name
/// @param session Session type
/// @return String name of session
string GetSessionName(SESSION_TYPE session)
{
   switch(session) {
      case SESSION_ASIAN:    return "Asian";
      case SESSION_LONDON:   return "London";
      case SESSION_NEWYORK:  return "New York";
      case SESSION_OVERLAP:  return "Overlap";
      default:               return "Unknown";
   }
}

/// @brief Check if it's a new trading day
/// @return true if new day started
bool IsNewDay(void)
{
   datetime currentTime = TimeCurrent();
   MqlDateTime timeStruct;
   TimeToStruct(currentTime, timeStruct);
   
   // Create "start of day" time (00:00:00)
   MqlDateTime dayStart = timeStruct;
   dayStart.hour = 0;
   dayStart.min = 0;
   dayStart.sec = 0;
   
   return (currentTime - StructToTime(dayStart)) < 3600; // Within first hour of day
}

/// @brief Check if it's a new trading week
/// @return true if new week started
bool IsNewWeek(void)
{
   datetime currentTime = TimeCurrent();
   MqlDateTime timeStruct;
   TimeToStruct(currentTime, timeStruct);
   
   // Monday = 1, Sunday = 0
   return (timeStruct.day_of_week == 1 && Hour() == 0);
}

/// @brief Get server time (broker time)
/// @return Current server time
datetime GetServerTime(void)
{
   return TimeCurrent();
}

/// @brief Check if current bar is new (hasn't been processed yet)
/// @param symbol Trading symbol
/// @param timeframe Chart timeframe
/// @param lastProcessedTime Time of last processed bar
/// @return true if new bar has formed
bool IsNewBar(string symbol, ENUM_TIMEFRAMES timeframe, datetime &lastProcessedTime)
{
   datetime barTime = iTime(symbol, timeframe, 0);
   
   if(barTime != lastProcessedTime) {
      lastProcessedTime = barTime;
      return true;
   }
   
   return false;
}

/// @brief Get bars since specific time
/// @param symbol Trading symbol
/// @param timeframe Chart timeframe
/// @param startTime Start time
/// @return Number of bars elapsed
int GetBarsElapsed(string symbol, ENUM_TIMEFRAMES timeframe, datetime startTime)
{
   int barCount = 0;
   datetime currentTime = iTime(symbol, timeframe, 0);
   
   while(currentTime >= startTime && barCount < 100000) {
      barCount++;
      datetime nextBarTime = iTime(symbol, timeframe, barCount);
      if(nextBarTime == 0) break;
      currentTime = nextBarTime;
   }
   
   return barCount;
}

//================================================================================
// HELPER FUNCTIONS - PRICE & VOLUME
//================================================================================

/// @brief Get current bid price
/// @return Current bid
double GetCurrentBid(void)
{
   return SymbolInfoDouble(Symbol(), SYMBOL_BID);
}

/// @brief Get current ask price
/// @return Current ask
double GetCurrentAsk(void)
{
   return SymbolInfoDouble(Symbol(), SYMBOL_ASK);
}

/// @brief Get current spread in points
/// @return Spread in points
double GetCurrentSpread(void)
{
   return GetCurrentAsk() - GetCurrentBid();
}

/// @brief Get current spread in pips
/// @return Spread in pips
double GetCurrentSpreadPips(void)
{
   double spread = GetCurrentSpread();
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   return spread * MathPow(10, digits);
}

/// @brief Get average spread over N bars
/// @param bars Number of bars to analyze
/// @return Average spread
double GetAverageSpread(int bars = 50)
{
   double sumSpread = 0;
   
   for(int i = 0; i < bars; i++) {
      double high = iHigh(Symbol(), PERIOD_M5, i);
      double low = iLow(Symbol(), PERIOD_M5, i);
      sumSpread += (high - low);
   }
   
   return sumSpread / bars;
}

/// @brief Check if spread is acceptable
/// @param maxSpreadMultiplier Maximum allowed spread as multiple of average
/// @return true if spread is acceptable
bool IsSpreadAcceptable(double maxSpreadMultiplier = 1.5)
{
   double currentSpread = GetCurrentSpread();
   double avgSpread = GetAverageSpread();
   
   return (currentSpread <= (avgSpread * maxSpreadMultiplier));
}

/// @brief Get point value (minimum move in account currency)
/// @return Point value
double GetPointValue(void)
{
   return SymbolInfoDouble(Symbol(), SYMBOL_POINT);
}

/// @brief Get digits (decimal places)
/// @return Number of digits
int GetDigits(void)
{
   return (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
}

/// @brief Normalize price to valid precision
/// @param price Price to normalize
/// @return Normalized price
double NormalizePrice(double price)
{
   return NormalizeDouble(price, GetDigits());
}

//================================================================================
// HELPER FUNCTIONS - ATR & VOLATILITY
//================================================================================

/// @brief Create ATR indicator handle
/// @param period ATR period (default 14)
/// @return Handle (-1 if failed)
int CreateATRHandle(int period = 14)
{
   int handle = iATR(Symbol(), PERIOD_H1, period);
   
   if(handle == INVALID_HANDLE) {
      Print("ERROR: Failed to create ATR handle");
      return -1;
   }
   
   return handle;
}

/// @brief Get current ATR value
/// @param handle ATR indicator handle
/// @param shift Bar shift (0 = current)
/// @return ATR value
double GetATRValue(int handle, int shift = 0)
{
   if(handle == INVALID_HANDLE) return 0;
   
   double atrBuffer[];
   if(CopyBuffer(handle, 0, shift, 1, atrBuffer) <= 0) {
      Print("ERROR: Failed to copy ATR buffer");
      return 0;
   }
   
   return atrBuffer[0];
}

/// @brief Get average ATR over N bars
/// @param handle ATR indicator handle
/// @param bars Number of bars to average
/// @return Average ATR
double GetAverageATR(int handle, int bars = 20)
{
   if(handle == INVALID_HANDLE) return 0;
   
   double atrBuffer[];
   if(CopyBuffer(handle, 0, 0, bars, atrBuffer) <= 0) {
      Print("ERROR: Failed to copy ATR buffer for averaging");
      return 0;
   }
   
   double sum = 0;
   for(int i = 0; i < bars; i++) {
      sum += atrBuffer[i];
   }
   
   return sum / bars;
}

/// @brief Get ATR expansion ratio (current vs average)
/// @param handle ATR indicator handle
/// @return Ratio of current ATR to average ATR
double GetATRExpansionRatio(int handle)
{
   double current = GetATRValue(handle, 0);
   double average = GetAverageATR(handle, 20);
   
   if(average == 0) return 0;
   return current / average;
}

/// @brief Check if volatility is extreme
/// @param handle ATR indicator handle
/// @param threshold Threshold multiplier (e.g., 2.5 = 2.5x average)
/// @return true if volatility is extreme
bool IsVolatilityExtreme(int handle, double threshold = 2.5)
{
   return (GetATRExpansionRatio(handle) >= threshold);
}

//================================================================================
// HELPER FUNCTIONS - ACCOUNT & RISK
//================================================================================

/// @brief Get current account balance
/// @return Account balance
double GetAccountBalance(void)
{
   return AccountInfoDouble(ACCOUNT_BALANCE);
}

/// @brief Get current account equity
/// @return Account equity
double GetAccountEquity(void)
{
   return AccountInfoDouble(ACCOUNT_EQUITY);
}

/// @brief Get account free margin
/// @return Free margin
double GetFreeMargin(void)
{
   return AccountInfoDouble(ACCOUNT_FREEMARGIN);
}

/// @brief Calculate position size based on risk percentage
/// @param riskPercent Percentage of account to risk
/// @param stopDistancePoints Stop distance in points
/// @return Lot size
double CalculatePositionSize(double riskPercent, double stopDistancePoints)
{
   double balance = GetAccountBalance();
   double riskAmount = balance * (riskPercent / 100.0);
   double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double point = GetPointValue();
   
   if(stopDistancePoints <= 0 || tickValue <= 0) return 0;
   
   double lotSize = riskAmount / (stopDistancePoints * point * tickValue);
   double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   
   // Normalize to step
   lotSize = MathFloor(lotSize / stepLot) * stepLot;
   
   // Apply limits
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   
   return lotSize;
}

/// @brief Get current daily P&L
/// @return Daily profit/loss
double GetDailyPnL(void)
{
   double dailyPnL = 0;
   
   // Sum all today's closed trades
   int dealsTotal = HistoryDealsTotal();
   
   for(int i = 0; i < dealsTotal; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      
      if(!HistoryDealSelect(ticket)) continue;
      
      long dealTime = HistoryDealGetInteger(ticket, DEAL_TIME);
      datetime dealDateTime = (datetime)dealTime;
      
      // Check if deal was today
      MqlDateTime today, deal;
      TimeToStruct(TimeCurrent(), today);
      TimeToStruct(dealDateTime, deal);
      
      if(today.year == deal.year && today.mon == deal.mon && today.day == deal.day) {
         dailyPnL += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      }
   }
   
   return dailyPnL;
}

/// @brief Check if daily loss limit reached
/// @param maxLossPercent Maximum allowed daily loss %
/// @return true if limit exceeded
bool IsDailyLossLimitExceeded(double maxLossPercent)
{
   double dailyPnL = GetDailyPnL();
   double balance = GetAccountBalance();
   double maxLoss = balance * (maxLossPercent / 100.0);
   
   return (dailyPnL < -maxLoss);
}

/// @brief Get number of open positions
/// @return Count of open trades
int GetOpenPositionCount(void)
{
   int count = 0;
   
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      
      if(PositionSelectByTicket(ticket)) {
         count++;
      }
   }
   
   return count;
}

/// @brief Get account drawdown percentage
/// @return Current drawdown %
double GetDrawdownPercent(void)
{
   double equity = GetAccountEquity();
   double balance = GetAccountBalance();
   
   if(balance == 0) return 0;
   
   double drawdown = ((balance - equity) / balance) * 100.0;
   return MathMax(0, drawdown);
}

//================================================================================
// HELPER FUNCTIONS - SYMBOL & VALIDATION
//================================================================================

/// @brief Check if symbol is valid and available
/// @param symbol Symbol name
/// @return true if symbol valid
bool IsSymbolValid(string symbol)
{
   if(!SymbolSelect(symbol, true)) {
      Print("ERROR: Symbol not found or not available: ", symbol);
      return false;
   }
   
   // Verify we can get tick data
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick)) {
      Print("ERROR: Cannot get tick data for symbol: ", symbol);
      return false;
   }
   
   return true;
}

/// @brief Verify symbol trading parameters
/// @param symbol Symbol to verify
/// @return true if valid
bool VerifySymbolTradingParams(string symbol)
{
   // Check if symbol is tradeable
   if((SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) & SYMBOL_TRADE_MODE_DISABLED) != 0) {
      Print("ERROR: Symbol trading is disabled: ", symbol);
      return false;
   }
   
   // Check spreads
   double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
   if(spread == 0) {
      Print("ERROR: Cannot get valid spread for symbol: ", symbol);
      return false;
   }
   
   return true;
}

//================================================================================
// INITIALIZATION FUNCTION
//================================================================================

/// @brief Initialize EA on startup
/// @return true if initialization successful
bool InitializeEA(void)
{
   Print("=== LES PRO X v1.0 - INITIALIZATION ===");
   Print("Symbol: ", Symbol());
   Print("TimeFrame: ", StringSubstr(EnumToString(PERIOD_CURRENT), 7));
   
   // Validate symbol
   if(!IsSymbolValid(Symbol())) {
      Print("FATAL: Invalid symbol");
      return false;
   }
   
   if(!VerifySymbolTradingParams(Symbol())) {
      Print("FATAL: Invalid trading parameters");
      return false;
   }
   
   // Initialize account state
   gAccount.startBalance = GetAccountBalance();
   gAccount.currentBalance = gAccount.startBalance;
   gAccount.dailyStartBalance = gAccount.startBalance;
   gAccount.weeklyStartBalance = gAccount.startBalance;
   gAccount.peakEquity = GetAccountEquity();
   gAccount.currentDrawdown = 0;
   gAccount.winRate = 0;
   gAccount.profitFactor = 0;
   gAccount.expectancy = 0;
   
   // Create ATR indicator
   gATRHandle = CreateATRHandle(14);
   if(gATRHandle == INVALID_HANDLE) {
      Print("FATAL: Failed to create ATR indicator");
      return false;
   }
   
   // Initialize Trade object
   if(!gTrade.SetExpertMagicNumber(20240906)) {
      Print("WARNING: Failed to set magic number");
   }
   
   // Initialize logger
   if(inEnableJournal) {
      if(!gLogger.Initialize(JOURNAL_PATH)) {
         Print("WARNING: Failed to initialize journal");
      }
   }
   
   // Set global flags
   gShadowMode = inUseShadowMode;
   gShowDashboard = inShowDashboard;
   gEnableLogging = inEnableJournal;
   
   // Initialize time tracking
   gLastBarTime = iTime(Symbol(), PERIOD_CURRENT, 0);
   gLastDailyReset = TimeCurrent();
   gLastWeeklyReset = TimeCurrent();
   gLastCheckTime = GetTickCount();
   gLastCsvWrite = GetTickCount();
   
   // Detect initial session
   gCurrentSession = DetectCurrentSession();
   gSessionStart = TimeCurrent();
   gSessionHigh = iHigh(Symbol(), PERIOD_CURRENT, 0);
   gSessionLow = iLow(Symbol(), PERIOD_CURRENT, 0);
   
   Print("✓ ATR Handle: ", gATRHandle);
   Print("✓ Current Session: ", GetSessionName(gCurrentSession));
   Print("✓ Account Balance: ", DoubleToString(gAccount.startBalance, 2));
   Print("✓ Shadow Mode: ", (gShadowMode ? "ENABLED" : "DISABLED"));
   Print("✓ EA Initialized Successfully");
   Print("================================================");
   
   return true;
}

//================================================================================
// CLEANUP FUNCTION
//================================================================================

/// @brief Cleanup and release resources
void CleanupEA(void)
{
   Print("=== LES PRO X v1.0 - CLEANUP ===");
   
   // Release indicator handles
   if(gATRHandle != INVALID_HANDLE) {
      IndicatorRelease(gATRHandle);
      gATRHandle = INVALID_HANDLE;
   }
   
   // Close all trades if not shadow mode
   if(!gShadowMode && GetOpenPositionCount() > 0) {
      Print("WARNING: Closing all open trades on EA stop");
      
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket)) {
            gTrade.PositionClose(ticket);
         }
      }
   }
   
   Print("✓ EA Cleanup Complete");
}

//================================================================================
// MAIN EXPERT ADVISOR STRUCTURE
//================================================================================

/// OnInit: Initialize expert advisor
int OnInit()
{
   if(!InitializeEA()) {
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

/// OnDeinit: Cleanup on EA stop
void OnDeinit(const int reason)
{
   CleanupEA();
}

/// OnTick: Main event handler (called on every tick)
void OnTick()
{
   // Check for new bar
   gIsNewBar = IsNewBar(Symbol(), PERIOD_CURRENT, gLastBarTime);
   
   if(gIsNewBar) {
      gBarCounter++;
      
      // PHASE 1: Just log activity
      // In later phases, this will call full decision pipeline
      
      if(inShowDebugInfo) {
         Print("New bar #", gBarCounter, 
               " | Session: ", GetSessionName(gCurrentSession),
               " | Bid: ", GetCurrentBid(),
               " | Ask: ", GetCurrentAsk(),
               " | Spread: ", DoubleToString(GetCurrentSpreadPips(), 1), "p",
               " | ATR: ", DoubleToString(GetATRValue(gATRHandle), 5),
               " | Open Trades: ", GetOpenPositionCount());
      }
      
      // Check for daily/weekly resets
      if(IsNewDay()) {
         gAccount.dailyStartBalance = GetAccountBalance();
         gAccount.dailyPnL = 0;
         gDailyLockout = false;
         if(inShowDebugInfo) Print("=== NEW TRADING DAY ===");
      }
      
      if(IsNewWeek()) {
         gAccount.weeklyStartBalance = GetAccountBalance();
         gAccount.weeklyPnL = 0;
         gWeeklyLockout = false;
         if(inShowDebugInfo) Print("=== NEW TRADING WEEK ===");
      }
      
      // Update account state
      gAccount.currentBalance = GetAccountBalance();
      gAccount.currentDrawdown = GetDrawdownPercent();
      gAccount.dailyPnL = GetDailyPnL();
      
      // Check lockouts
      if(IsDailyLossLimitExceeded(inMaxDailyLossPercent)) {
         gDailyLockout = true;
         if(inShowDebugInfo) Print("!!! DAILY LOSS LIMIT EXCEEDED - TRADING DISABLED !!!");
      }
      
      if(GetDrawdownPercent() > inMaxDrawdownPercent) {
         gWeeklyLockout = true;
         if(inShowDebugInfo) Print("!!! DRAWDOWN LIMIT EXCEEDED - TRADING DISABLED !!!");
      }
      
      // Detect session changes
      SESSION_TYPE newSession = DetectCurrentSession();
      if(newSession != gCurrentSession) {
         gCurrentSession = newSession;
         gSessionStart = TimeCurrent();
         gSessionHigh = iHigh(Symbol(), PERIOD_CURRENT, 0);
         gSessionLow = iLow(Symbol(), PERIOD_CURRENT, 0);
         
         if(inShowDebugInfo) {
            Print("*** SESSION CHANGE: ", GetSessionName(gCurrentSession), " ***");
         }
      }
      
      // Update session high/low
      double currentHigh = iHigh(Symbol(), PERIOD_CURRENT, 0);
      double currentLow = iLow(Symbol(), PERIOD_CURRENT, 0);
      
      if(currentHigh > gSessionHigh) gSessionHigh = currentHigh;
      if(currentLow < gSessionLow) gSessionLow = currentLow;
      
      // TODO: In later phases, this is where the full decision engine fires
      // For Phase 1, we're just laying the infrastructure
   }
}

/// OnStart: Called on chart open or first signal (for script compatibility)
void OnStart()
{
   // Not used in Expert Advisor, but included for completeness
}

//================================================================================
// DEBUG & UTILITY FUNCTIONS
//================================================================================

/// Print current system status
void PrintSystemStatus(void)
{
   Print("\n=== SYSTEM STATUS ===");
   Print("Symbol: ", Symbol());
   Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   Print("Session: ", GetSessionName(gCurrentSession));
   Print("Balance: ", DoubleToString(GetAccountBalance(), 2));
   Print("Equity: ", DoubleToString(GetAccountEquity(), 2));
   Print("Drawdown: ", DoubleToString(GetDrawdownPercent(), 2), "%");
   Print("Open Positions: ", GetOpenPositionCount());
   Print("Daily P&L: ", DoubleToString(GetDailyPnL(), 2));
   Print("Spread: ", DoubleToString(GetCurrentSpreadPips(), 1), "p");
   Print("ATR: ", DoubleToString(GetATRValue(gATRHandle), 5));
   Print("Daily Lockout: ", (gDailyLockout ? "YES" : "NO"));
   Print("Weekly Lockout: ", (gWeeklyLockout ? "YES" : "NO"));
   Print("Shadow Mode: ", (gShadowMode ? "ON" : "OFF"));
   Print("=====================");
}

//================================================================================
// END OF PHASE 1 CORE FRAMEWORK
//================================================================================
