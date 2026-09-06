//================================================================================
// LES PRO X v1.0 - PHASE 2: MARKET STRUCTURE & BIAS
// MetaTrader 5 Expert Advisor
// Institutional ICT/SMC System for Gold Day Trading
//
// Phase 2 Deliverables:
// - Swing high/low detection (internal and external)
// - Bullish/bearish/neutral bias determination
// - Break of Structure (BOS) detection
// - Change of Character (CHoCH) identification
// - Market Structure Shift (MSS) confirmation
// - Displacement candle detection
// - Pullback zone logic
// - Confirmation candle detection
// - Protected highs/lows tracking
// - Structure quality scoring
//
// This phase builds on Phase 1 and adds market foundation analysis
//================================================================================

#property copyright "LES Pro X v1.0 - Phase 2"
#property link      "https://github.com/Lastskipper/LES-Pro-X-v1.0"
#property version   "2.00"

//================================================================================
// STRUCTURES - MARKET STRUCTURE ANALYSIS
//================================================================================

/// @struct Swing point in market
struct SwingPoint
{
   int      barIndex;              // Bar where swing formed
   datetime barTime;               // Time of swing formation
   double   price;                 // Price level of swing
   int      type;                  // 1 = High, -1 = Low
   double   strength;              // Strength score (0-100)
   int      bars_formed;           // Bars it took to form this swing
   bool     is_protected;          // Is this swing protected (not yet broken)
   bool     is_external;           // Is this swing external (dealing range defining)
   int      test_count;            // How many times price tested this level
   double   quality_score;         // Overall quality (0-100)
};

/// @struct Break of Structure event
struct StructureBreak
{
   int      barIndex;              // Bar where break occurred
   datetime barTime;               // Time of break
   double   breakLevel;            // Price level that was broken
   int      direction;             // 1 = Bullish break, -1 = Bearish break
   double   displacement;          // Distance moved after break (in points)
   int      bars_until_reclaim;    // Bars until level retest/reclaim
   bool     reclaimed;             // Was the break reclaimed (failed)
   double   strength;              // Break strength score (0-100)
   string   break_type;            // "BOS" or "MSS" or "CHoCH"
};

/// @struct Market structure state
struct MarketStructure
{
   MARKET_BIAS bias;               // Current bias: bullish, bearish, neutral
   double   bias_strength;         // Strength of bias (0-100)
   
   SwingPoint last_swing_high;     // Most recent swing high
   SwingPoint last_swing_low;      // Most recent swing low
   
   double   protected_high;        // Protected high level
   double   protected_low;         // Protected low level
   
   int      higher_high_count;     // Consecutive higher highs
   int      higher_low_count;      // Consecutive higher lows
   int      lower_high_count;      // Consecutive lower highs
   int      lower_low_count;       // Consecutive lower lows
   
   bool     structure_bullish;     // Structure confirms uptrend
   bool     structure_bearish;     // Structure confirms downtrend
   bool     structure_neutral;     // Structure unclear/conflicted
   
   StructureBreak last_bos;        // Last break of structure
   StructureBreak last_mss;        // Last market structure shift
   StructureBreak last_choch;      // Last change of character
   
   double   internal_range_high;   // Internal dealing range high
   double   internal_range_low;    // Internal dealing range low
   double   external_range_high;   // External dealing range high
   double   external_range_low;    // External dealing range low
   
   datetime last_update;           // Last time structure was updated
   int      bars_since_break;      // Bars since last significant break
   double   structure_confidence;  // Confidence in current structure (0-100)
};

/// @struct Displacement candle characteristics
struct DisplacementCandle
{
   int      barIndex;              // Bar index
   datetime barTime;               // Bar time
   double   open_price;            // Open
   double   close_price;           // Close
   double   high_price;            // High
   double   low_price;             // Low
   double   body_size;             // Candle body size
   double   range_size;            // High-low range
   double   displacement_speed;    // How far/fast it moved (range / time)
   bool     is_displacement;       // Is this a displacement candle
   int      direction;             // 1 = bullish, -1 = bearish
   double   strength;              // Displacement strength (0-100)
};

/// @struct Pullback zone definition
struct PullbackZone
{
   double   zone_high;             // Upper boundary of pullback zone
   double   zone_low;              // Lower boundary of pullback zone
   double   zone_mid;              // Midpoint of zone
   int      bars_in_zone;          // How many bars price spent in zone
   bool     valid;                 // Is pullback zone still valid
   datetime formed_time;           // When pullback formed
   int      formation_bars;        // Bars it took to form
   double   quality_score;         // Quality of pullback (0-100)
};

//================================================================================
// GLOBAL VARIABLES - MARKET STRUCTURE
//================================================================================

// Structure tracking arrays
SwingPoint          gSwingHighs[];              // Array of swing highs
SwingPoint          gSwingLows[];               // Array of swing lows
StructureBreak      gStructureBreaks[];         // Array of structure breaks

// Current market structure state
MarketStructure     gMarketStructure;           // Current market structure

// Candle analysis
DisplacementCandle  gCurrentCandle;             // Current bar's candle analysis
DisplacementCandle  gLastDisplacementCandle;    // Last confirmed displacement

// Pullback tracking
PullbackZone        gCurrentPullback;           // Active pullback zone

// Counters and trackers
int                 gSwingHighCount;            // Number of tracked swing highs
int                 gSwingLowCount;             // Number of tracked swing lows
int                 gStructureBreakCount;       // Number of tracked breaks
int                 gLastSwingUpdate;           // Bar index of last swing update
bool                gNeedsStructureRefresh;     // Flag: recalculate structure

//================================================================================
// HELPER FUNCTION - ARRAY INITIALIZATION
//================================================================================

/// Initialize dynamic arrays for structure tracking
void InitializeStructureArrays()
{
   ArrayResize(gSwingHighs, 0);
   ArrayResize(gSwingLows, 0);
   ArrayResize(gStructureBreaks, 0);
   
   gSwingHighCount = 0;
   gSwingLowCount = 0;
   gStructureBreakCount = 0;
   gNeedsStructureRefresh = true;
}

//================================================================================
// FUNCTION: SWING DETECTION - INTERNAL SWINGS
//================================================================================

/// @brief Detect internal swing highs (within current dealing range)
/// @param lookback Number of bars to look back
/// @return True if swing high found
bool DetectInternalSwingHigh(int lookback = 5)
{
   int currentBar = 0;
   
   // A swing high needs at least lookback bars before and after
   if(lookback < 3) return false;
   
   double centerPrice = iHigh(Symbol(), PERIOD_M5, currentBar);
   
   // Check if center bar is higher than surrounding bars
   for(int i = 1; i <= lookback; i++) {
      double leftPrice = iHigh(Symbol(), PERIOD_M5, currentBar + i);
      double rightPrice = (currentBar - i >= 0) ? iHigh(Symbol(), PERIOD_M5, currentBar - i) : 0;
      
      // Left side check
      if(leftPrice > centerPrice) return false;
      
      // Right side check (if we have future bars)
      if(rightPrice > 0 && rightPrice >= centerPrice) return false;
   }
   
   return true;
}

/// @brief Detect internal swing lows (within current dealing range)
/// @param lookback Number of bars to look back
/// @return True if swing low found
bool DetectInternalSwingLow(int lookback = 5)
{
   int currentBar = 0;
   
   if(lookback < 3) return false;
   
   double centerPrice = iLow(Symbol(), PERIOD_M5, currentBar);
   
   for(int i = 1; i <= lookback; i++) {
      double leftPrice = iLow(Symbol(), PERIOD_M5, currentBar + i);
      double rightPrice = (currentBar - i >= 0) ? iLow(Symbol(), PERIOD_M5, currentBar - i) : 0;
      
      if(leftPrice < centerPrice) return false;
      if(rightPrice > 0 && rightPrice <= centerPrice) return false;
   }
   
   return true;
}

//================================================================================
// FUNCTION: SWING DETECTION - EXTERNAL SWINGS
//================================================================================

/// @brief Detect external swing highs (dealing range defining)
/// @param lookback Number of bars to analyze
/// @return True if external swing high found
bool DetectExternalSwingHigh(int lookback = 20)
{
   double highest = iHigh(Symbol(), PERIOD_H1, 0);
   int highBar = 0;
   
   // Find highest point in lookback period
   for(int i = 0; i < lookback; i++) {
      double currentHigh = iHigh(Symbol(), PERIOD_H1, i);
      if(currentHigh > highest) {
         highest = currentHigh;
         highBar = i;
      }
   }
   
   // Check if it has been tested multiple times without being broken
   int testCount = 0;
   for(int i = highBar - 1; i >= 0; i--) {
      double currentHigh = iHigh(Symbol(), PERIOD_H1, i);
      if(currentHigh >= (highest - GetPointValue() * 5)) { // Within 5 points
         testCount++;
      }
   }
   
   return (testCount >= 2); // At least 2 tests = valid external high
}

/// @brief Detect external swing lows (dealing range defining)
/// @param lookback Number of bars to analyze
/// @return True if external swing low found
bool DetectExternalSwingLow(int lookback = 20)
{
   double lowest = iLow(Symbol(), PERIOD_H1, 0);
   int lowBar = 0;
   
   for(int i = 0; i < lookback; i++) {
      double currentLow = iLow(Symbol(), PERIOD_H1, i);
      if(currentLow < lowest) {
         lowest = currentLow;
         lowBar = i;
      }
   }
   
   int testCount = 0;
   for(int i = lowBar - 1; i >= 0; i--) {
      double currentLow = iLow(Symbol(), PERIOD_H1, i);
      if(currentLow <= (lowest + GetPointValue() * 5)) {
         testCount++;
      }
   }
   
   return (testCount >= 2);
}

//================================================================================
// FUNCTION: SWING TRACKING - ADD & UPDATE
//================================================================================

/// @brief Add a swing high to tracking array
/// @param barIndex Bar index where swing formed
/// @param price Swing high price
/// @param isExternal Is this an external (dealing range) swing
void AddSwingHigh(int barIndex, double price, bool isExternal = false)
{
   ArrayResize(gSwingHighs, gSwingHighCount + 1);
   
   SwingPoint newSwing;
   newSwing.barIndex = barIndex;
   newSwing.barTime = iTime(Symbol(), PERIOD_M5, barIndex);
   newSwing.price = price;
   newSwing.type = 1; // High
   newSwing.strength = 0;
   newSwing.bars_formed = 0;
   newSwing.is_protected = true;
   newSwing.is_external = isExternal;
   newSwing.test_count = 0;
   newSwing.quality_score = 50;
   
   gSwingHighs[gSwingHighCount] = newSwing;
   gSwingHighCount++;
}

/// @brief Add a swing low to tracking array
/// @param barIndex Bar index where swing formed
/// @param price Swing low price
/// @param isExternal Is this an external (dealing range) swing
void AddSwingLow(int barIndex, double price, bool isExternal = false)
{
   ArrayResize(gSwingLows, gSwingLowCount + 1);
   
   SwingPoint newSwing;
   newSwing.barIndex = barIndex;
   newSwing.barTime = iTime(Symbol(), PERIOD_M5, barIndex);
   newSwing.price = price;
   newSwing.type = -1; // Low
   newSwing.strength = 0;
   newSwing.bars_formed = 0;
   newSwing.is_protected = true;
   newSwing.is_external = isExternal;
   newSwing.test_count = 0;
   newSwing.quality_score = 50;
   
   gSwingLows[gSwingLowCount] = newSwing;
   gSwingLowCount++;
}

/// @brief Update protection status of swings
void UpdateSwingProtectionStatus()
{
   double currentHigh = iHigh(Symbol(), PERIOD_M5, 0);
   double currentLow = iLow(Symbol(), PERIOD_M5, 0);
   
   // Check swing highs
   for(int i = 0; i < gSwingHighCount; i++) {
      if(currentHigh > gSwingHighs[i].price) {
         gSwingHighs[i].is_protected = false; // High broken
      }
      
      // Count tests of this level
      if(currentHigh >= (gSwingHighs[i].price - GetPointValue() * 10)) {
         gSwingHighs[i].test_count++;
      }
   }
   
   // Check swing lows
   for(int i = 0; i < gSwingLowCount; i++) {
      if(currentLow < gSwingLows[i].price) {
         gSwingLows[i].is_protected = false; // Low broken
      }
      
      if(currentLow <= (gSwingLows[i].price + GetPointValue() * 10)) {
         gSwingLows[i].test_count++;
      }
   }
}

//================================================================================
// FUNCTION: BREAK OF STRUCTURE DETECTION
//================================================================================

/// @brief Detect bullish Break of Structure (break of a swing low)
/// @return True if bullish BOS detected
bool DetectBullishBOS()
{
   if(gSwingLowCount == 0) return false;
   
   double lastSwingLow = gSwingLows[gSwingLowCount - 1].price;
   double currentLow = iLow(Symbol(), PERIOD_M5, 0);
   double previousClose = iClose(Symbol(), PERIOD_M5, 1);
   
   // Price must close below previous swing low (wick OK, but close must confirm)
   bool breakDetected = (currentLow < lastSwingLow) && (previousClose < lastSwingLow);
   
   // Optional: require displacement after the break
   if(breakDetected) {
      double displacement = currentLow - lastSwingLow;
      if(displacement < GetPointValue() * 2) return false; // Too small
   }
   
   return breakDetected;
}

/// @brief Detect bearish Break of Structure (break of a swing high)
/// @return True if bearish BOS detected
bool DetectBearishBOS()
{
   if(gSwingHighCount == 0) return false;
   
   double lastSwingHigh = gSwingHighs[gSwingHighCount - 1].price;
   double currentHigh = iHigh(Symbol(), PERIOD_M5, 0);
   double previousClose = iClose(Symbol(), PERIOD_M5, 1);
   
   bool breakDetected = (currentHigh > lastSwingHigh) && (previousClose > lastSwingHigh);
   
   if(breakDetected) {
      double displacement = currentHigh - lastSwingHigh;
      if(displacement < GetPointValue() * 2) return false;
   }
   
   return breakDetected;
}

//================================================================================
// FUNCTION: MARKET STRUCTURE SHIFT DETECTION
//================================================================================

/// @brief Detect bullish Market Structure Shift (MSS)
/// A bullish MSS requires: prior lower low intact, then a break and reclaim
/// @return True if bullish MSS detected
bool DetectBullishMSS()
{
   if(gSwingLowCount < 2) return false;
   
   // Need at least 2 lows to detect a shift
   double priorLow = gSwingLows[gSwingLowCount - 2].price;
   double lastLow = gSwingLows[gSwingLowCount - 1].price;
   double currentPrice = iClose(Symbol(), PERIOD_M5, 0);
   
   // Bullish MSS: lower low is intact, and we've now broken above recent high
   bool priorLowIntact = (iLow(Symbol(), PERIOD_M5, 0) > priorLow);
   bool breakAboveRecent = (currentPrice > iHigh(Symbol(), PERIOD_M5, 5));
   
   return (priorLowIntact && breakAboveRecent);
}

/// @brief Detect bearish Market Structure Shift (MSS)
/// @return True if bearish MSS detected
bool DetectBearishMSS()
{
   if(gSwingHighCount < 2) return false;
   
   double priorHigh = gSwingHighs[gSwingHighCount - 2].price;
   double lastHigh = gSwingHighs[gSwingHighCount - 1].price;
   double currentPrice = iClose(Symbol(), PERIOD_M5, 0);
   
   bool priorHighIntact = (iHigh(Symbol(), PERIOD_M5, 0) < priorHigh);
   bool breakBelowRecent = (currentPrice < iLow(Symbol(), PERIOD_M5, 5));
   
   return (priorHighIntact && breakBelowRecent);
}

//================================================================================
// FUNCTION: CHANGE OF CHARACTER DETECTION
//================================================================================

/// @brief Detect bullish Change of Character (CHoCH)
/// First sign that bearish trend might be reversing
/// @return True if bullish CHoCH detected
bool DetectBullishCHoCH()
{
   if(gSwingLowCount < 2) return false;
   
   // CHoCH: new lower low created where we previously had higher lows
   double lastLow = gSwingLows[gSwingLowCount - 1].price;
   double previousLow = (gSwingLowCount >= 2) ? gSwingLows[gSwingLowCount - 2].price : 0;
   
   // Signal: lower low than the previous low
   if(lastLow >= previousLow) return false;
   
   // But structure begins to shift after
   double currentClose = iClose(Symbol(), PERIOD_M5, 0);
   if(currentClose <= lastLow) return false; // Too early
   
   return true;
}

/// @brief Detect bearish Change of Character (CHoCH)
/// @return True if bearish CHoCH detected
bool DetectBearishCHoCH()
{
   if(gSwingHighCount < 2) return false;
   
   double lastHigh = gSwingHighs[gSwingHighCount - 1].price;
   double previousHigh = (gSwingHighCount >= 2) ? gSwingHighs[gSwingHighCount - 2].price : 0;
   
   if(lastHigh <= previousHigh) return false;
   
   double currentClose = iClose(Symbol(), PERIOD_M5, 0);
   if(currentClose >= lastHigh) return false;
   
   return true;
}

//================================================================================
// FUNCTION: DISPLACEMENT CANDLE DETECTION
//================================================================================

/// @brief Analyze current candle for displacement characteristics
/// @return Displacement strength (0-100)
double AnalyzeDisplacementCandle()
{
   int current = 0;
   
   double open = iOpen(Symbol(), PERIOD_M5, current);
   double close = iClose(Symbol(), PERIOD_M5, current);
   double high = iHigh(Symbol(), PERIOD_M5, current);
   double low = iLow(Symbol(), PERIOD_M5, current);
   
   double bodySize = MathAbs(close - open);
   double rangeSize = high - low;
   double displacement = MathAbs(close - open); // Body movement
   
   // Get previous candle for comparison
   double prevClose = iClose(Symbol(), PERIOD_M5, 1);
   double prevHigh = iHigh(Symbol(), PERIOD_M5, 1);
   double prevLow = iLow(Symbol(), PERIOD_M5, 1);
   double prevRange = prevHigh - prevLow;
   
   // Displacement score based on:
   // 1. Large body relative to previous
   // 2. Small wicks relative to body
   // 3. Clear directional commitment
   
   double bodyRatio = (prevRange > 0) ? (bodySize / prevRange) : 0;
   double wickSize = MathMin(high - close, close - low);
   double wickRatio = (rangeSize > 0) ? (wickSize / rangeSize) : 0;
   
   double score = 0;
   
   // Large body scores well
   if(bodyRatio > 1.5) score += 40;
   else if(bodyRatio > 1.0) score += 25;
   else if(bodyRatio > 0.7) score += 15;
   
   // Small wicks score well
   if(wickRatio < 0.1) score += 30;
   else if(wickRatio < 0.2) score += 20;
   else if(wickRatio < 0.3) score += 10;
   
   // Directional consistency
   if(close > open && close > prevClose) score += 20; // Bullish follow-through
   if(close < open && close < prevClose) score += 20; // Bearish follow-through
   
   return MathMin(100, score);
}

//================================================================================
// FUNCTION: PULLBACK ZONE DETECTION
//================================================================================

/// @brief Detect pullback zone (retracement area within trend)
/// @return True if valid pullback zone found
bool DetectPullbackZone()
{
   if(gSwingHighCount == 0 || gSwingLowCount == 0) return false;
   
   double rangeHigh = gSwingHighs[gSwingHighCount - 1].price;
   double rangeLow = gSwingLows[gSwingLowCount - 1].price;
   double rangeSize = rangeHigh - rangeLow;
   
   if(rangeSize <= 0) return false;
   
   // Pullback zone is typically 38.2% - 61.8% retracement
   double fib382 = rangeLow + (rangeSize * 0.382);
   double fib618 = rangeLow + (rangeSize * 0.618);
   
   double currentPrice = iClose(Symbol(), PERIOD_M5, 0);
   
   // If price is in pullback zone
   if(currentPrice >= fib382 && currentPrice <= fib618) {
      gCurrentPullback.zone_high = fib618;
      gCurrentPullback.zone_low = fib382;
      gCurrentPullback.zone_mid = (fib382 + fib618) / 2.0;
      gCurrentPullback.valid = true;
      gCurrentPullback.formed_time = TimeCurrent();
      
      return true;
   }
   
   return false;
}

//================================================================================
// FUNCTION: CONFIRMATION CANDLE DETECTION
//================================================================================

/// @brief Detect confirmation candle (candle that confirms structure)
/// @param direction 1 = bullish confirmation, -1 = bearish confirmation
/// @return True if confirmation candle found
bool DetectConfirmationCandle(int direction)
{
   int current = 0;
   int previous = 1;
   
   double currentOpen = iOpen(Symbol(), PERIOD_M5, current);
   double currentClose = iClose(Symbol(), PERIOD_M5, current);
   double currentHigh = iHigh(Symbol(), PERIOD_M5, current);
   double currentLow = iLow(Symbol(), PERIOD_M5, current);
   
   double previousClose = iClose(Symbol(), PERIOD_M5, previous);
   double previousHigh = iHigh(Symbol(), PERIOD_M5, previous);
   double previousLow = iLow(Symbol(), PERIOD_M5, previous);
   
   if(direction == 1) { // Bullish confirmation
      // Current candle closes higher than previous
      // Current close is near current high (bullish conviction)
      double closeRatio = (currentClose - currentLow) / (currentHigh - currentLow);
      
      bool closeAbovePrevious = (currentClose > previousClose);
      bool bullishBody = (currentClose > currentOpen);
      bool bullishConviction = (closeRatio > 0.7); // Close in upper portion
      
      return (closeAbovePrevious && bullishBody && bullishConviction);
   }
   else { // Bearish confirmation
      double closeRatio = (currentHigh - currentClose) / (currentHigh - currentLow);
      
      bool closeBelowPrevious = (currentClose < previousClose);
      bool bearishBody = (currentClose < currentOpen);
      bool bearishConviction = (closeRatio > 0.7);
      
      return (closeBelowPrevious && bearishBody && bearishConviction);
   }
}

//================================================================================
// FUNCTION: MARKET BIAS CALCULATION
//================================================================================

/// @brief Calculate current market bias based on structure
/// @return Market bias (BIAS_BULLISH, BIAS_BEARISH, BIAS_NEUTRAL)
MARKET_BIAS CalculateMarketBias()
{
   if(gSwingHighCount == 0 || gSwingLowCount == 0) return BIAS_NEUTRAL;
   
   // Get recent swings
   double lastSwingHigh = gSwingHighs[gSwingHighCount - 1].price;
   double lastSwingLow = gSwingLows[gSwingLowCount - 1].price;
   
   // Count consecutive higher highs and higher lows (bullish)
   int higherHighs = 0;
   int higherLows = 0;
   
   for(int i = 1; i < gSwingHighCount && i < 5; i++) {
      if(gSwingHighs[gSwingHighCount - i].price > gSwingHighs[gSwingHighCount - i - 1].price) {
         higherHighs++;
      }
   }
   
   for(int i = 1; i < gSwingLowCount && i < 5; i++) {
      if(gSwingLows[gSwingLowCount - i].price > gSwingLows[gSwingLowCount - i - 1].price) {
         higherLows++;
      }
   }
   
   // Count consecutive lower highs and lower lows (bearish)
   int lowerHighs = 0;
   int lowerLows = 0;
   
   for(int i = 1; i < gSwingHighCount && i < 5; i++) {
      if(gSwingHighs[gSwingHighCount - i].price < gSwingHighs[gSwingHighCount - i - 1].price) {
         lowerHighs++;
      }
   }
   
   for(int i = 1; i < gSwingLowCount && i < 5; i++) {
      if(gSwingLows[gSwingLowCount - i].price < gSwingLows[gSwingLowCount - i - 1].price) {
         lowerLows++;
      }
   }
   
   // Determine bias
   if(higherHighs >= 2 && higherLows >= 2) {
      gMarketStructure.bias = BIAS_BULLISH;
      gMarketStructure.bias_strength = 75;
      return BIAS_BULLISH;
   }
   
   if(lowerHighs >= 2 && lowerLows >= 2) {
      gMarketStructure.bias = BIAS_BEARISH;
      gMarketStructure.bias_strength = 75;
      return BIAS_BEARISH;
   }
   
   // Mixed or unclear
   gMarketStructure.bias = BIAS_NEUTRAL;
   gMarketStructure.bias_strength = 40;
   return BIAS_NEUTRAL;
}

//================================================================================
// FUNCTION: UPDATE MARKET STRUCTURE
//================================================================================

/// @brief Update entire market structure analysis (call each new bar)
void UpdateMarketStructure()
{
   // Detect new swings
   if(DetectInternalSwingHigh(5)) {
      AddSwingHigh(0, iHigh(Symbol(), PERIOD_M5, 0), false);
   }
   
   if(DetectInternalSwingLow(5)) {
      AddSwingLow(0, iLow(Symbol(), PERIOD_M5, 0), false);
   }
   
   // Update protection status
   UpdateSwingProtectionStatus();
   
   // Calculate bias
   MARKET_BIAS newBias = CalculateMarketBias();
   
   // Detect structure breaks
   if(DetectBullishBOS()) {
      gMarketStructure.structure_bullish = true;
      gMarketStructure.structure_bearish = false;
   }
   
   if(DetectBearishBOS()) {
      gMarketStructure.structure_bearish = true;
      gMarketStructure.structure_bullish = false;
   }
   
   // Detect structure shifts
   if(DetectBullishMSS()) {
      gMarketStructure.structure_bullish = true;
      gMarketStructure.structure_bearish = false;
   }
   
   if(DetectBearishMSS()) {
      gMarketStructure.structure_bearish = true;
      gMarketStructure.structure_bullish = false;
   }
   
   // Update displacement analysis
   double displacement = AnalyzeDisplacementCandle();
   if(displacement > 60) {
      gLastDisplacementCandle.is_displacement = true;
      gLastDisplacementCandle.strength = displacement;
      gLastDisplacementCandle.barTime = TimeCurrent();
   }
   
   // Update pullback zone
   DetectPullbackZone();
   
   // Set protected levels
   if(gSwingHighCount > 0) {
      gMarketStructure.protected_high = gSwingHighs[gSwingHighCount - 1].price;
   }
   
   if(gSwingLowCount > 0) {
      gMarketStructure.protected_low = gSwingLows[gSwingLowCount - 1].price;
   }
   
   // Update timestamp
   gMarketStructure.last_update = TimeCurrent();
}

//================================================================================
// FUNCTION: GET STRUCTURE QUALITY SCORE
//================================================================================

/// @brief Get overall structure quality score
/// @return Quality score (0-100)
double GetStructureQualityScore()
{
   double score = 50; // Base score
   
   // Higher highs/lows pattern adds confidence
   if(gMarketStructure.bias == BIAS_BULLISH) {
      score += 15;
   }
   else if(gMarketStructure.bias == BIAS_BEARISH) {
      score += 15;
   }
   
   // Recent displacement adds confidence
   if(gLastDisplacementCandle.is_displacement) {
      long barsSinceDisplacement = (TimeCurrent() - gLastDisplacementCandle.barTime) / 300; // 5-min bars
      if(barsSinceDisplacement < 5) {
         score += MathMin(20, (20 * (1 - (double)barsSinceDisplacement / 5)));
      }
   }
   
   // Protected levels validity
   if(gMarketStructure.protected_high > 0 && gMarketStructure.protected_low > 0) {
      double protectionRange = gMarketStructure.protected_high - gMarketStructure.protected_low;
      if(protectionRange > 0) score += 10;
   }
   
   // BOS/MSS confirmation
   if(gMarketStructure.structure_bullish || gMarketStructure.structure_bearish) {
      score += 10;
   }
   
   return MathMin(100, score);
}

//================================================================================
// HELPER FUNCTION: PRINT STRUCTURE STATE
//================================================================================

/// Print current market structure for debugging
void PrintMarketStructureState()
{
   Print("\n=== MARKET STRUCTURE STATE ===");
   Print("Bias: ", 
      (gMarketStructure.bias == BIAS_BULLISH ? "BULLISH" :
       gMarketStructure.bias == BIAS_BEARISH ? "BEARISH" : "NEUTRAL"),
      " (Strength: ", DoubleToString(gMarketStructure.bias_strength, 0), ")");
   
   Print("Swing Highs: ", gSwingHighCount, " | Swing Lows: ", gSwingLowCount);
   
   if(gSwingHighCount > 0) {
      Print("Recent High: ", DoubleToString(gSwingHighs[gSwingHighCount - 1].price, 5),
            " | Protected: ", (gSwingHighs[gSwingHighCount - 1].is_protected ? "YES" : "NO"));
   }
   
   if(gSwingLowCount > 0) {
      Print("Recent Low: ", DoubleToString(gSwingLows[gSwingLowCount - 1].price, 5),
            " | Protected: ", (gSwingLows[gSwingLowCount - 1].is_protected ? "YES" : "NO"));
   }
   
   Print("Structure Bullish: ", (gMarketStructure.structure_bullish ? "YES" : "NO"));
   Print("Structure Bearish: ", (gMarketStructure.structure_bearish ? "YES" : "NO"));
   
   if(gLastDisplacementCandle.is_displacement) {
      Print("Last Displacement: ", DoubleToString(gLastDisplacementCandle.strength, 0), "%");
   }
   
   Print("Quality Score: ", DoubleToString(GetStructureQualityScore(), 0));
   Print("==============================\n");
}

//================================================================================
// INTEGRATION WITH PHASE 1 - UPDATE OnTick
//================================================================================

/// Enhanced OnTick with structure analysis
void OnTickPhase2()
{
   // Check for new bar (from Phase 1)
   gIsNewBar = IsNewBar(Symbol(), PERIOD_CURRENT, gLastBarTime);
   
   if(gIsNewBar) {
      gBarCounter++;
      
      // UPDATE MARKET STRUCTURE
      UpdateMarketStructure();
      
      if(inShowDebugInfo) {
         Print("Bar #", gBarCounter,
               " | Close: ", DoubleToString(iClose(Symbol(), PERIOD_M5, 0), 5),
               " | Bias: ", (gMarketStructure.bias == BIAS_BULLISH ? "BULL" :
                             gMarketStructure.bias == BIAS_BEARISH ? "BEAR" : "NEUTRAL"),
               " | Swings - H:", gSwingHighCount, " L:", gSwingLowCount,
               " | Quality: ", DoubleToString(GetStructureQualityScore(), 0));
      }
      
      // Daily/weekly reset logic (from Phase 1)
      if(IsNewDay()) {
         gAccount.dailyStartBalance = GetAccountBalance();
         gAccount.dailyPnL = 0;
         gDailyLockout = false;
         InitializeStructureArrays(); // Reset swings daily
      }
      
      // Account state update (from Phase 1)
      gAccount.currentBalance = GetAccountBalance();
      gAccount.currentDrawdown = GetDrawdownPercent();
   }
}

//================================================================================
// END OF PHASE 2: MARKET STRUCTURE & BIAS
//================================================================================
