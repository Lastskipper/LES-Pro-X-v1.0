//================================================================================
// LES PRO X v1.0 - PHASE 3: LIQUIDITY ENGINE
// MetaTrader 5 Expert Advisor
// Institutional ICT/SMC System for Gold Day Trading
//
// Phase 3 Deliverables:
// - Liquidity pool detection and tracking
// - Equal Highs/Lows identification
// - Buy-side and sell-side liquidity detection
// - Internal vs external liquidity classification
// - Session-specific liquidity (Asian, London, New York)
// - Resting liquidity identification
// - Liquidity sweep history and cooldown
// - Liquidity pool ranking by strength and probability
// - Sweep event detection and classification
// - Liquidity pool quality scoring
//
// This phase builds on Phases 1-2 and creates the complete liquidity map
//================================================================================

#property copyright "LES Pro X v1.0 - Phase 3"
#property link      "https://github.com/Lastskipper/LES-Pro-X-v1.0"
#property version   "3.00"

//================================================================================
// STRUCTURES - LIQUIDITY ANALYSIS
//================================================================================

/// @enum Liquidity pool types
enum LIQUIDITY_TYPE
{
   LIQ_EQUAL_HIGH      = 1,    // Equal high level
   LIQ_EQUAL_LOW       = 2,    // Equal low level
   LIQ_BUY_SIDE        = 3,    // Buy-side liquidity (stops above high)
   LIQ_SELL_SIDE       = 4,    // Sell-side liquidity (stops below low)
   LIQ_INTERNAL        = 5,    // Internal dealing range liquidity
   LIQ_EXTERNAL        = 6,    // External (major) liquidity
   LIQ_SESSION_HIGH    = 7,    // Session-specific high
   LIQ_SESSION_LOW     = 8,    // Session-specific low
   LIQ_RESTING         = 9     // Generic resting liquidity
};

/// @enum Liquidity sweep state
enum SWEEP_STATE
{
   SWEEP_UNTOUCHED     = 0,    // Never touched/swept
   SWEEP_PARTIAL       = 1,    // Partially swept
   SWEEP_FULLY_SWEPT   = 2,    // Completely swept
   SWEEP_RECLAIMED     = 3,    // Swept but later reclaimed
   SWEEP_ENGINEERED    = 4     // Deliberately built up to be raided
};

/// @struct Liquidity pool details
struct LiquidityPool
{
   int               poolID;              // Unique identifier
   LIQUIDITY_TYPE    type;                // Type of liquidity
   double            price;               // Price level
   double            clusterRange;        // Price range of cluster (e.g., 0.5 for high/low area)
   int               timeframeOrigin;     // Origin timeframe (M5=5, H1=60, D1=1440)
   
   // Time and history
   datetime          creationTime;        // When pool was identified
   datetime          lastTestedTime;      // Last time price approached pool
   int               barsSinceCreation;   // Bars since pool created
   int               barsSinceTested;     // Bars since last test
   
   // Test tracking
   int               testCount;           // How many times tested
   int               rejectCount;         // How many times rejected (touched but bounced)
   
   // Sweep state
   SWEEP_STATE       sweepState;          // Current sweep state
   datetime          lastSweepTime;       // When it was last swept
   int               sweepCooldownBars;   // Bars until re-sweep allowed
   bool              sweepConfirmed;      // Sweep fully confirmed (not just wick)
   
   // Liquidity characteristics
   double            liquiditySize;       // Estimated size/strength (0-100)
   double            clusterTightness;    // How tight the cluster is (0-100)
   int               equalPointCount;    // How many equal highs/lows in cluster
   
   // Ranking and scoring
   double            distanceFromPrice;   // Distance from current price
   double            probabilityScore;    // Probability of being hit (0-100)
   double            strengthScore;       // Liquidity strength (0-100)
   double            relevanceScore;      // Relevance to current trade (0-100)
   double            totalScore;          // Combined score (0-100)
   
   // Classification
   bool              isUnswept;           // Still unswept (highest priority)
   bool              isExternal;          // External (macro) level
   bool              isActive;            // Still relevant to current analysis
   bool              isPaired;            // Part of a pair (high/low pair)
};

/// @struct Sweep event record
struct SweepEvent
{
   int               eventID;             // Unique identifier
   datetime          sweepTime;           // When sweep occurred
   int               barIndex;            // Bar where sweep occurred
   double            sweepPrice;          // Price at sweep
   int               sweepDirection;      // 1 = buy-side raid, -1 = sell-side raid
   double            sweepDepth;          // How deep into liquidity
   int               barsAfterSweep;      // Bars we've tracked after sweep
   
   // Sweep characteristics
   bool              isCleanSweep;        // Clean break vs wick-only
   bool              isMultipleSweep;     // Multiple sweeps at same level
   double            displacementBars;    // Bars of displacement after sweep
   double            sweepStrength;       // Strength of sweep (0-100)
   
   // Follow-up action (what happened after sweep)
   string            followUpAction;      // "Reversal", "Continuation", "Distribution", etc.
   bool              resolved;            // Resolution identified
   int               barsToResolution;    // Bars until resolution identified
};

/// @struct Liquidity level for higher timeframes (session structure)
struct SessionLiquidityLevel
{
   SESSION_TYPE      session;             // Which session
   int               dayOfWeek;           // Day of week (0=Sun, 1=Mon, etc.)
   double            sessionHigh;         // Session high
   double            sessionLow;          // Session low
   double            sessionMid;          // Session midpoint
   double            sessionRange;        // Range size
   int               barsInSession;       // Bars elapsed in session
   
   // Sweep status for session levels
   SWEEP_STATE       highSweepState;      // Sweep state of session high
   SWEEP_STATE       lowSweepState;       // Sweep state of session low
   bool              highSweepConfirmed;  // Session high swept (confirmed)
   bool              lowSweepConfirmed;   // Session low swept (confirmed)
};

//================================================================================
// GLOBAL VARIABLES - LIQUIDITY TRACKING
//================================================================================

// Liquidity pool arrays
LiquidityPool       gLiquidityPools[];           // All tracked liquidity pools
int                 gLiquidityPoolCount;        // Count of active pools

// Sweep event history
SweepEvent          gSweepEvents[];             // History of sweep events
int                 gSweepEventCount;           // Count of sweep events

// Session liquidity levels
SessionLiquidityLevel gSessionLiquidity[];      // Session-specific liquidity
int                 gSessionLiquidityCount;     // Count of session levels

// Liquidity pool ID counter
int                 gNextPoolID = 1;            // Auto-increment pool IDs

// Active sweep cooldown tracking
int                 gSweepCooldownPoolIDs[];    // Pool IDs on cooldown
int                 gSweepCooldownCount;        // Count of cooldown pools

// Ranking cache (frequently accessed)
int                 gBestUnsweptPoolID;         // Best unswept pool (long direction)
int                 gBestBullishPoolID;         // Best bullish pool
int                 gBestBearishPoolID;         // Best bearish pool
double              gBestPoolProbability;       // Probability of best pool

//================================================================================
// FUNCTION: INITIALIZE LIQUIDITY ENGINE
//================================================================================

/// Initialize liquidity tracking arrays
void InitializeLiquidityEngine()
{
   ArrayResize(gLiquidityPools, 0);
   ArrayResize(gSweepEvents, 0);
   ArrayResize(gSessionLiquidity, 0);
   ArrayResize(gSweepCooldownPoolIDs, 0);
   
   gLiquidityPoolCount = 0;
   gSweepEventCount = 0;
   gSessionLiquidityCount = 0;
   gSweepCooldownCount = 0;
   gNextPoolID = 1;
   
   gBestUnsweptPoolID = -1;
   gBestBullishPoolID = -1;
   gBestBearishPoolID = -1;
   gBestPoolProbability = 0;
}

//================================================================================
// FUNCTION: DETECT EQUAL HIGHS
//================================================================================

/// @brief Detect equal high levels (multiple highs at same price)
/// @param tolerance Price tolerance in points
/// @param minEqualCount Minimum number of equal highs to qualify
void DetectEqualHighs(double tolerance = 10, int minEqualCount = 2)
{
   // Scan H1 timeframe for equal highs
   double tolerance_price = tolerance * GetPointValue();
   int lookback = 50; // Bars to check
   
   for(int i = 0; i < lookback; i++) {
      double currentHigh = iHigh(Symbol(), PERIOD_H1, i);
      int equalCount = 1; // Count current bar
      
      // Count how many other bars have similar high
      for(int j = i + 1; j < lookback; j++) {
         double checkHigh = iHigh(Symbol(), PERIOD_H1, j);
         
         if(MathAbs(checkHigh - currentHigh) < tolerance_price) {
            equalCount++;
         }
      }
      
      // If we found equal highs, create a liquidity pool
      if(equalCount >= minEqualCount) {
         double avgPrice = currentHigh; // Use the exact level
         
         // Check if this level already exists in our pool list
         if(FindLiquidityPoolByPrice(avgPrice, tolerance_price * 2) == -1) {
            CreateLiquidityPool(
               LIQ_EQUAL_HIGH,
               avgPrice,
               tolerance_price * 2,
               PERIOD_H1,
               equalCount
            );
         }
      }
   }
}

/// @brief Detect equal low levels (multiple lows at same price)
/// @param tolerance Price tolerance in points
/// @param minEqualCount Minimum number of equal lows to qualify
void DetectEqualLows(double tolerance = 10, int minEqualCount = 2)
{
   double tolerance_price = tolerance * GetPointValue();
   int lookback = 50;
   
   for(int i = 0; i < lookback; i++) {
      double currentLow = iLow(Symbol(), PERIOD_H1, i);
      int equalCount = 1;
      
      for(int j = i + 1; j < lookback; j++) {
         double checkLow = iLow(Symbol(), PERIOD_H1, j);
         
         if(MathAbs(checkLow - currentLow) < tolerance_price) {
            equalCount++;
         }
      }
      
      if(equalCount >= minEqualCount) {
         double avgPrice = currentLow;
         
         if(FindLiquidityPoolByPrice(avgPrice, tolerance_price * 2) == -1) {
            CreateLiquidityPool(
               LIQ_EQUAL_LOW,
               avgPrice,
               tolerance_price * 2,
               PERIOD_H1,
               equalCount
            );
         }
      }
   }
}

//================================================================================
// FUNCTION: DETECT BUY-SIDE & SELL-SIDE LIQUIDITY
//================================================================================

/// @brief Detect buy-side liquidity (stops resting above recent highs)
/// Buy-side = Sell stops above resistance
void DetectBuySideLiquidity()
{
   // Find recent swing highs
   if(gSwingHighCount == 0) return;
   
   double recentHigh = gSwingHighs[gSwingHighCount - 1].price;
   double aboveHigh = recentHigh + (50 * GetPointValue()); // 50 points above
   
   // Create buy-side liquidity pool (stops resting above high)
   CreateLiquidityPool(
      LIQ_BUY_SIDE,
      aboveHigh,
      25 * GetPointValue(),
      PERIOD_H1,
      1
   );
}

/// @brief Detect sell-side liquidity (stops resting below recent lows)
/// Sell-side = Buy stops below support
void DetectSellSideLiquidity()
{
   if(gSwingLowCount == 0) return;
   
   double recentLow = gSwingLows[gSwingLowCount - 1].price;
   double belowLow = recentLow - (50 * GetPointValue()); // 50 points below
   
   CreateLiquidityPool(
      LIQ_SELL_SIDE,
      belowLow,
      25 * GetPointValue(),
      PERIOD_H1,
      1
   );
}

//================================================================================
// FUNCTION: DETECT SESSION LIQUIDITY
//================================================================================

/// @brief Detect Asian session high/low
void DetectAsianSessionLiquidity()
{
   if(gCurrentSession != SESSION_ASIAN) return;
   
   // Find high and low during Asian session (last few hours)
   double sessionHigh = iHigh(Symbol(), PERIOD_H1, 0);
   double sessionLow = iLow(Symbol(), PERIOD_H1, 0);
   
   for(int i = 1; i < 8; i++) { // Last 8 hours (Asian session)
      if(iHigh(Symbol(), PERIOD_H1, i) > sessionHigh) {
         sessionHigh = iHigh(Symbol(), PERIOD_H1, i);
      }
      if(iLow(Symbol(), PERIOD_H1, i) < sessionLow) {
         sessionLow = iLow(Symbol(), PERIOD_H1, i);
      }
   }
   
   // Create liquidity pools for session levels
   CreateLiquidityPool(LIQ_SESSION_HIGH, sessionHigh, 5 * GetPointValue(), PERIOD_H1, 1);
   CreateLiquidityPool(LIQ_SESSION_LOW, sessionLow, 5 * GetPointValue(), PERIOD_H1, 1);
}

/// @brief Detect London session high/low
void DetectLondonSessionLiquidity()
{
   if(gCurrentSession != SESSION_LONDON) return;
   
   double sessionHigh = iHigh(Symbol(), PERIOD_H1, 0);
   double sessionLow = iLow(Symbol(), PERIOD_H1, 0);
   
   for(int i = 1; i < 9; i++) { // London session roughly 9 hours
      if(iHigh(Symbol(), PERIOD_H1, i) > sessionHigh) {
         sessionHigh = iHigh(Symbol(), PERIOD_H1, i);
      }
      if(iLow(Symbol(), PERIOD_H1, i) < sessionLow) {
         sessionLow = iLow(Symbol(), PERIOD_H1, i);
      }
   }
   
   CreateLiquidityPool(LIQ_SESSION_HIGH, sessionHigh, 5 * GetPointValue(), PERIOD_H1, 1);
   CreateLiquidityPool(LIQ_SESSION_LOW, sessionLow, 5 * GetPointValue(), PERIOD_H1, 1);
}

/// @brief Detect New York session high/low
void DetectNewYorkSessionLiquidity()
{
   if(gCurrentSession != SESSION_NEWYORK) return;
   
   double sessionHigh = iHigh(Symbol(), PERIOD_H1, 0);
   double sessionLow = iLow(Symbol(), PERIOD_H1, 0);
   
   for(int i = 1; i < 8; i++) { // NY session roughly 8 hours
      if(iHigh(Symbol(), PERIOD_H1, i) > sessionHigh) {
         sessionHigh = iHigh(Symbol(), PERIOD_H1, i);
      }
      if(iLow(Symbol(), PERIOD_H1, i) < sessionLow) {
         sessionLow = iLow(Symbol(), PERIOD_H1, i);
      }
   }
   
   CreateLiquidityPool(LIQ_SESSION_HIGH, sessionHigh, 5 * GetPointValue(), PERIOD_H1, 1);
   CreateLiquidityPool(LIQ_SESSION_LOW, sessionLow, 5 * GetPointValue(), PERIOD_H1, 1);
}

//================================================================================
// FUNCTION: CREATE LIQUIDITY POOL
//================================================================================

/// @brief Create and add a new liquidity pool to tracking
/// @param type Type of liquidity
/// @param price Price level
/// @param clusterRange Range around price that counts as cluster
/// @param timeframeOrigin Origin timeframe
/// @param equalCount For equal highs/lows, how many equal points
void CreateLiquidityPool(LIQUIDITY_TYPE type, double price, double clusterRange, 
                         int timeframeOrigin, int equalCount = 1)
{
   // Check if pool already exists at this price
   if(FindLiquidityPoolByPrice(price, clusterRange) != -1) {
      return; // Already tracked
   }
   
   ArrayResize(gLiquidityPools, gLiquidityPoolCount + 1);
   
   LiquidityPool newPool;
   newPool.poolID = gNextPoolID++;
   newPool.type = type;
   newPool.price = price;
   newPool.clusterRange = clusterRange;
   newPool.timeframeOrigin = timeframeOrigin;
   
   newPool.creationTime = TimeCurrent();
   newPool.lastTestedTime = TimeCurrent();
   newPool.barsSinceCreation = 0;
   newPool.barsSinceTested = 0;
   
   newPool.testCount = 0;
   newPool.rejectCount = 0;
   
   newPool.sweepState = SWEEP_UNTOUCHED;
   newPool.lastSweepTime = 0;
   newPool.sweepCooldownBars = 0;
   newPool.sweepConfirmed = false;
   
   newPool.liquiditySize = 70;
   newPool.clusterTightness = 70;
   newPool.equalPointCount = equalCount;
   
   newPool.distanceFromPrice = MathAbs(price - GetCurrentAsk());
   newPool.probabilityScore = 50;
   newPool.strengthScore = 70;
   newPool.relevanceScore = 60;
   newPool.totalScore = (newPool.strengthScore + newPool.relevanceScore) / 2;
   
   newPool.isUnswept = (newPool.sweepState == SWEEP_UNTOUCHED);
   newPool.isExternal = (type == LIQ_EXTERNAL || type == LIQ_SESSION_HIGH || type == LIQ_SESSION_LOW);
   newPool.isActive = true;
   newPool.isPaired = false;
   
   gLiquidityPools[gLiquidityPoolCount] = newPool;
   gLiquidityPoolCount++;
}

//================================================================================
// FUNCTION: FIND LIQUIDITY POOL
//================================================================================

/// @brief Find liquidity pool by price (within tolerance)
/// @param price Price to search for
/// @param tolerance Price tolerance
/// @return Pool index or -1 if not found
int FindLiquidityPoolByPrice(double price, double tolerance)
{
   for(int i = 0; i < gLiquidityPoolCount; i++) {
      if(MathAbs(gLiquidityPools[i].price - price) < tolerance) {
         return i;
      }
   }
   return -1;
}

/// @brief Find liquidity pool by ID
/// @param poolID Pool ID to search for
/// @return Pool index or -1 if not found
int FindLiquidityPoolByID(int poolID)
{
   for(int i = 0; i < gLiquidityPoolCount; i++) {
      if(gLiquidityPools[i].poolID == poolID) {
         return i;
      }
   }
   return -1;
}

//================================================================================
// FUNCTION: DETECT LIQUIDITY SWEEP
//================================================================================

/// @brief Detect if a liquidity pool has been swept
/// @param poolIndex Index of pool to check
/// @return True if sweep detected
bool DetectLiquiditySweep(int poolIndex)
{
   if(poolIndex < 0 || poolIndex >= gLiquidityPoolCount) return false;
   if(gLiquidityPools[poolIndex].sweepState != SWEEP_UNTOUCHED) return false;
   
   double poolPrice = gLiquidityPools[poolIndex].price;
   double currentPrice = iClose(Symbol(), PERIOD_M5, 0);
   double previousClose = iClose(Symbol(), PERIOD_M5, 1);
   
   // Sweep = price goes beyond level, then closes back inside
   double wick = iHigh(Symbol(), PERIOD_M5, 0);
   double lowWick = iLow(Symbol(), PERIOD_M5, 0);
   
   // Buy-side sweep (price goes above, closes back below)
   bool buySideSweep = (wick > poolPrice) && (currentPrice < poolPrice) && (previousClose < poolPrice);
   
   // Sell-side sweep (price goes below, closes back above)
   bool sellSideSweep = (lowWick < poolPrice) && (currentPrice > poolPrice) && (previousClose > poolPrice);
   
   return (buySideSweep || sellSideSweep);
}

/// @brief Mark a liquidity pool as swept
/// @param poolIndex Index of pool to mark
void MarkPoolAsSswept(int poolIndex)
{
   if(poolIndex < 0 || poolIndex >= gLiquidityPoolCount) return;
   
   gLiquidityPools[poolIndex].sweepState = SWEEP_FULLY_SWEPT;
   gLiquidityPools[poolIndex].lastSweepTime = TimeCurrent();
   gLiquidityPools[poolIndex].sweepConfirmed = true;
   gLiquidityPools[poolIndex].isUnswept = false;
   
   // Add to cooldown to prevent re-sweep flagging
   ArrayResize(gSweepCooldownPoolIDs, gSweepCooldownCount + 1);
   gSweepCooldownPoolIDs[gSweepCooldownCount] = gLiquidityPools[poolIndex].poolID;
   gSweepCooldownCount++;
   gLiquidityPools[poolIndex].sweepCooldownBars = 5; // 5 bar cooldown
   
   // Record sweep event
   RecordSweepEvent(poolIndex);
}

//================================================================================
// FUNCTION: RECORD SWEEP EVENT
//================================================================================

/// @brief Record a sweep event for statistics and analysis
/// @param poolIndex Index of pool that was swept
void RecordSweepEvent(int poolIndex)
{
   if(poolIndex < 0 || poolIndex >= gLiquidityPoolCount) return;
   
   ArrayResize(gSweepEvents, gSweepEventCount + 1);
   
   SweepEvent newEvent;
   newEvent.eventID = gSweepEventCount;
   newEvent.sweepTime = TimeCurrent();
   newEvent.barIndex = gBarCounter;
   newEvent.sweepPrice = gLiquidityPools[poolIndex].price;
   newEvent.sweepDirection = (iClose(Symbol(), PERIOD_M5, 0) > iClose(Symbol(), PERIOD_M5, 1)) ? 1 : -1;
   newEvent.sweepDepth = MathAbs(iHigh(Symbol(), PERIOD_M5, 0) - gLiquidityPools[poolIndex].price);
   newEvent.barsAfterSweep = 0;
   newEvent.isCleanSweep = true;
   newEvent.isMultipleSweep = false;
   newEvent.displacementBars = 0;
   newEvent.sweepStrength = gLiquidityPools[poolIndex].strengthScore;
   newEvent.followUpAction = "";
   newEvent.resolved = false;
   newEvent.barsToResolution = 0;
   
   gSweepEvents[gSweepEventCount] = newEvent;
   gSweepEventCount++;
}

//================================================================================
// FUNCTION: UPDATE LIQUIDITY POOLS
//================================================================================

/// @brief Update all liquidity pools each bar
void UpdateLiquidityPools()
{
   double currentPrice = iClose(Symbol(), PERIOD_M5, 0);
   
   for(int i = 0; i < gLiquidityPoolCount; i++) {
      if(!gLiquidityPools[i].isActive) continue;
      
      // Update distance from current price
      gLiquidityPools[i].distanceFromPrice = MathAbs(gLiquidityPools[i].price - currentPrice);
      
      // Update age
      long ageSeconds = (TimeCurrent() - gLiquidityPools[i].creationTime);
      gLiquidityPools[i].barsSinceCreation = ageSeconds / 300; // 5-min bars
      
      // Check if price is testing this pool (within 2x cluster range)
      double testRange = gLiquidityPools[i].clusterRange * 2;
      if(MathAbs(iHigh(Symbol(), PERIOD_M5, 0) - gLiquidityPools[i].price) < testRange) {
         gLiquidityPools[i].testCount++;
         gLiquidityPools[i].lastTestedTime = TimeCurrent();
         gLiquidityPools[i].barsSinceTested = 0;
      } else {
         gLiquidityPools[i].barsSinceTested++;
      }
      
      // Check for sweep
      if(gLiquidityPools[i].sweepState == SWEEP_UNTOUCHED) {
         if(DetectLiquiditySweep(i)) {
            MarkPoolAsSswept(i);
         }
      }
      
      // Decrease cooldown
      if(gLiquidityPools[i].sweepCooldownBars > 0) {
         gLiquidityPools[i].sweepCooldownBars--;
      }
      
      // Calculate probability this pool gets hit next
      CalculateLiquidityProbability(i);
      
      // Deactivate very old pools that haven't been tested
      if(gLiquidityPools[i].barsSinceCreation > 100 && gLiquidityPools[i].testCount == 0) {
         gLiquidityPools[i].isActive = false;
      }
   }
}

//================================================================================
// FUNCTION: CALCULATE LIQUIDITY PROBABILITY
//================================================================================

/// @brief Calculate probability that a liquidity pool will be targeted next
/// @param poolIndex Index of pool to score
void CalculateLiquidityProbability(int poolIndex)
{
   if(poolIndex < 0 || poolIndex >= gLiquidityPoolCount) return;
   
   double score = 50; // Base score
   
   // Distance factor: closer = higher probability
   double maxDistance = 200 * GetPointValue(); // 200 points max
   double distanceFactor = MathMax(0, 1.0 - (gLiquidityPools[poolIndex].distanceFromPrice / maxDistance));
   score += distanceFactor * 20;
   
   // Unswept status: very high if untouched
   if(gLiquidityPools[poolIndex].isUnswept) {
      score += 25;
   }
   
   // Test count factor: more tests without sweep = more likely to be swept soon
   if(gLiquidityPools[poolIndex].testCount >= 3) {
      score += 15;
   } else if(gLiquidityPools[poolIndex].testCount >= 1) {
      score += 8;
   }
   
   // Liquidity size factor
   score += (gLiquidityPools[poolIndex].liquiditySize / 100) * 15;
   
   // Strength of cluster
   score += (gLiquidityPools[poolIndex].clusterTightness / 100) * 10;
   
   // Equal points: equal highs/lows very strong
   if(gLiquidityPools[poolIndex].equalPointCount >= 3) {
      score += 15;
   } else if(gLiquidityPools[poolIndex].equalPointCount >= 2) {
      score += 10;
   }
   
   // Timeframe importance (H1 pools stronger than M5)
   if(gLiquidityPools[poolIndex].timeframeOrigin >= 60) {
      score += 10;
   }
   
   // Bias alignment
   if(gMarketStructure.bias == BIAS_BULLISH && gLiquidityPools[poolIndex].price > GetCurrentAsk()) {
      score += 10; // Bullish bias favors higher levels
   }
   if(gMarketStructure.bias == BIAS_BEARISH && gLiquidityPools[poolIndex].price < GetCurrentAsk()) {
      score += 10; // Bearish bias favors lower levels
   }
   
   // Age factor: fresher pools are slightly more relevant
   if(gLiquidityPools[poolIndex].barsSinceCreation < 20) {
      score += 5;
   }
   
   // Cap at 100
   gLiquidityPools[poolIndex].probabilityScore = MathMin(100, score);
   gLiquidityPools[poolIndex].totalScore = (gLiquidityPools[poolIndex].strengthScore + 
                                             gLiquidityPools[poolIndex].probabilityScore) / 2;
}

//================================================================================
// FUNCTION: RANK LIQUIDITY POOLS
//================================================================================

/// @brief Rank all liquidity pools by probability and strength
/// @param direction 1 for long targets, -1 for short targets
/// @return Best pool ID, or -1 if none found
int RankAndSelectBestLiquidityPool(int direction = 1)
{
   int bestPoolIndex = -1;
   double bestScore = -1;
   
   for(int i = 0; i < gLiquidityPoolCount; i++) {
      if(!gLiquidityPools[i].isActive) continue;
      if(!gLiquidityPools[i].isUnswept) continue; // Prefer unswept
      
      // Directional filtering
      if(direction == 1 && gLiquidityPools[i].price < GetCurrentAsk()) continue; // Long = targets above
      if(direction == -1 && gLiquidityPools[i].price > GetCurrentAsk()) continue; // Short = targets below
      
      // Filter by closest unswept in trend direction
      if(gLiquidityPools[i].totalScore > bestScore) {
         bestScore = gLiquidityPools[i].totalScore;
         bestPoolIndex = i;
      }
   }
   
   if(bestPoolIndex >= 0) {
      if(direction == 1) {
         gBestBullishPoolID = gLiquidityPools[bestPoolIndex].poolID;
      } else {
         gBestBearishPoolID = gLiquidityPools[bestPoolIndex].poolID;
      }
      gBestPoolProbability = gLiquidityPools[bestPoolIndex].probabilityScore;
   }
   
   return (bestPoolIndex >= 0) ? gLiquidityPools[bestPoolIndex].poolID : -1;
}

/// @brief Get nearest unswept liquidity target
/// @param direction 1 for long, -1 for short
/// @return Price of target, or 0 if none found
double GetNearestUnsweptTarget(int direction = 1)
{
   int poolID = RankAndSelectBestLiquidityPool(direction);
   if(poolID == -1) return 0;
   
   int poolIndex = FindLiquidityPoolByID(poolID);
   if(poolIndex == -1) return 0;
   
   return gLiquidityPools[poolIndex].price;
}

//================================================================================
// FUNCTION: GET LIQUIDITY STRENGTH SCORE
//================================================================================

/// @brief Get overall liquidity analysis strength (0-100)
/// @return Strength score
double GetLiquidityStrengthScore()
{
   double score = 50; // Base
   
   // Count unswept pools
   int unsweptCount = 0;
   for(int i = 0; i < gLiquidityPoolCount; i++) {
      if(gLiquidityPools[i].isUnswept && gLiquidityPools[i].isActive) {
         unsweptCount++;
      }
   }
   
   // More unswept pools = stronger liquidity map
   if(unsweptCount >= 3) score += 20;
   else if(unsweptCount >= 2) score += 10;
   else if(unsweptCount >= 1) score += 5;
   
   // Clear targeting (best pool has high confidence)
   if(gBestPoolProbability > 75) score += 15;
   else if(gBestPoolProbability > 60) score += 10;
   else if(gBestPoolProbability > 45) score += 5;
   
   // Equal highs/lows present (very strong)
   for(int i = 0; i < gLiquidityPoolCount; i++) {
      if((gLiquidityPools[i].type == LIQ_EQUAL_HIGH || gLiquidityPools[i].type == LIQ_EQUAL_LOW) 
         && gLiquidityPools[i].isActive) {
         score += 10;
         break;
      }
   }
   
   return MathMin(100, score);
}

//================================================================================
// FUNCTION: PRINT LIQUIDITY STATE
//================================================================================

/// Print current liquidity map for debugging
void PrintLiquidityState()
{
   Print("\n=== LIQUIDITY MAP STATE ===");
   Print("Total Pools: ", gLiquidityPoolCount);
   
   int unsweptCount = 0;
   int sweptCount = 0;
   
   for(int i = 0; i < gLiquidityPoolCount; i++) {
      if(gLiquidityPools[i].isActive) {
         if(gLiquidityPools[i].isUnswept) {
            unsweptCount++;
            Print("  [Unswept] Pool #", gLiquidityPools[i].poolID, 
                  " @ ", DoubleToString(gLiquidityPools[i].price, 5),
                  " | Prob: ", DoubleToString(gLiquidityPools[i].probabilityScore, 0),
                  "% | Type: ", (int)gLiquidityPools[i].type);
         } else {
            sweptCount++;
         }
      }
   }
   
   Print("Unswept: ", unsweptCount, " | Swept: ", sweptCount);
   
   if(gBestBullishPoolID > 0) {
      int idx = FindLiquidityPoolByID(gBestBullishPoolID);
      if(idx >= 0) {
         Print("Best Bullish Target: ", DoubleToString(gLiquidityPools[idx].price, 5),
               " | Prob: ", DoubleToString(gBestPoolProbability, 0), "%");
      }
   }
   
   Print("Liquidity Strength: ", DoubleToString(GetLiquidityStrengthScore(), 0));
   Print("Sweep Events: ", gSweepEventCount);
   Print("===========================\n");
}

//================================================================================
// INTEGRATION WITH PREVIOUS PHASES
//================================================================================

/// Enhanced OnTick with liquidity analysis
void OnTickPhase3()
{
   // Check for new bar (from Phase 1)
   gIsNewBar = IsNewBar(Symbol(), PERIOD_CURRENT, gLastBarTime);
   
   if(gIsNewBar) {
      gBarCounter++;
      
      // UPDATE MARKET STRUCTURE (Phase 2)
      UpdateMarketStructure();
      
      // UPDATE LIQUIDITY (Phase 3)
      // Detect new liquidity pools
      DetectEqualHighs(10, 2);
      DetectEqualLows(10, 2);
      DetectBuySideLiquidity();
      DetectSellSideLiquidity();
      DetectAsianSessionLiquidity();
      DetectLondonSessionLiquidity();
      DetectNewYorkSessionLiquidity();
      
      // Update existing pools
      UpdateLiquidityPools();
      
      if(inShowDebugInfo) {
         Print("Bar #", gBarCounter,
               " | Close: ", DoubleToString(iClose(Symbol(), PERIOD_M5, 0), 5),
               " | Swings - H:", gSwingHighCount, " L:", gSwingLowCount,
               " | Liquidity Pools: ", gLiquidityPoolCount,
               " | Best Target: ", DoubleToString(GetNearestUnsweptTarget(1), 5));
      }
      
      // Daily reset (from Phase 1)
      if(IsNewDay()) {
         gAccount.dailyStartBalance = GetAccountBalance();
         gAccount.dailyPnL = 0;
         gDailyLockout = false;
         InitializeStructureArrays();
         InitializeLiquidityEngine();
      }
   }
}

//================================================================================
// END OF PHASE 3: LIQUIDITY ENGINE
//================================================================================
