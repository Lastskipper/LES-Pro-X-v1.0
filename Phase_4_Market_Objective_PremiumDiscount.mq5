//================================================================================
// LES PRO X v1.0 - PHASE 4: MARKET OBJECTIVE & PREMIUM/DISCOUNT
// MetaTrader 5 Expert Advisor
// Institutional ICT/SMC System for Gold Day Trading
//
// Phase 4 Deliverables:
// - Market Objective Engine (identifies where price is trying to go)
// - Daily objective target identification
// - Objective completion tracking
// - Premium/discount zone calculation
// - Equilibrium point detection
// - OTE (Optimal Trade Entry) zone detection
// - Dynamic dealing range logic
// - Range anchor selection (HTF vs session vs expansion)
// - Objective confidence scoring
// - Objective status tracking (pending/partial/completed)
//
// This phase builds on Phases 1-3 and adds high-level market targeting
//================================================================================

#property copyright "LES Pro X v1.0 - Phase 4"
#property link      "https://github.com/Lastskipper/LES-Pro-X-v1.0"
#property version   "4.00"

//================================================================================
// ENUMERATIONS - OBJECTIVE & PREMIUM/DISCOUNT
//================================================================================

/// @enum Market Objective types
enum OBJECTIVE_TYPE
{
   OBJ_PREVIOUS_DAY_HIGH      = 1,
   OBJ_PREVIOUS_DAY_LOW       = 2,
   OBJ_PREVIOUS_WEEK_HIGH     = 3,
   OBJ_PREVIOUS_WEEK_LOW      = 4,
   OBJ_MONTHLY_HIGH           = 5,
   OBJ_MONTHLY_LOW            = 6,
   OBJ_EQUAL_HIGH             = 7,
   OBJ_EQUAL_LOW              = 8,
   OBJ_ASIAN_HIGH             = 9,
   OBJ_ASIAN_LOW              = 10,
   OBJ_LONDON_HIGH            = 11,
   OBJ_LONDON_LOW             = 12,
   OBJ_NEWYORK_HIGH           = 13,
   OBJ_NEWYORK_LOW            = 14,
   OBJ_INTERNAL_LIQUIDITY     = 15,
   OBJ_EXTERNAL_LIQUIDITY     = 16,
   OBJ_UNKNOWN                = 0
};

/// @enum Objective completion status
enum OBJECTIVE_STATUS
{
   OBJ_PENDING                = 1,  // Target not reached yet
   OBJ_PARTIALLY_COMPLETED    = 2,  // Partially reached (within 80%)
   OBJ_COMPLETED              = 3,  // Fully reached and closed beyond
   OBJ_INVALIDATED            = 4   // Became irrelevant/invalidated
};

/// @enum Premium/Discount classification
enum PRICE_LOCATION
{
   LOC_PREMIUM                = 1,  // Upper half of range (expensive)
   LOC_DISCOUNT               = 2,  // Lower half of range (cheap)
   LOC_EQUILIBRIUM            = 3,  // Middle of range (neutral)
   LOC_OTE_PREMIUM            = 4,  // Optimal entry in premium (61.8%-79% from low)
   LOC_OTE_DISCOUNT           = 5,  // Optimal entry in discount (20%-38.2% from low)
   LOC_UNKNOWN                = 0
};

/// @enum Range anchor source
enum RANGE_ANCHOR
{
   ANCHOR_HTF_SWING           = 1,  // H4/D1 swing high/low
   ANCHOR_SESSION_RANGE       = 2,  // Current session structure
   ANCHOR_EXPANSION_MOVE      = 3,  // Last strong expansion leg
   ANCHOR_EXTERNAL_STRUCTURE  = 4,  // External dealing range
   ANCHOR_UNKNOWN             = 0
};

//================================================================================
// STRUCTURES - MARKET OBJECTIVE & LOCATION
//================================================================================

/// @struct Market Objective definition
struct MarketObjective
{
   OBJECTIVE_TYPE   primaryObjective;        // Main target for today
   OBJECTIVE_TYPE   secondaryObjective;      // Secondary target
   double           primaryObjectivePrice;   // Price of primary target
   double           secondaryObjectivePrice; // Price of secondary target
   
   OBJECTIVE_STATUS objectiveStatus;         // Pending/partial/completed
   double           objectiveCompletion;     // Percentage complete (0-100)
   bool             objectiveReached;        // Has objective been touched?
   bool             objectiveCompleted;      // Has objective been definitively completed?
   
   double           objectiveDistance;       // Distance to primary objective
   double           objectiveConfidence;     // Confidence in objective (0-100)
   int              barsToObjective;         // Estimated bars to reach objective
   
   MARKET_BIAS      objectiveDirection;      // Direction objective implies
   
   // Secondary targets
   int              targetCount;             // How many valid targets identified
   double           nearestTarget;           // Nearest valid target
   double           secondaryTarget;         // Second-nearest target
   
   datetime         objectiveSetTime;        // When objective was identified
   int              barsObjectiveActive;     // Bars since objective set
};

/// @struct Premium/Discount zone definition
struct PremiumDiscountZone
{
   double           rangeHigh;               // High of current range
   double           rangeLow;                // Low of current range
   double           rangeSize;               // High - Low
   double           rangeMid;                // Midpoint (equilibrium)
   
   RANGE_ANCHOR     rangeAnchor;             // What anchors this range
   datetime         rangeCreationTime;       // When range was established
   int              barsSinceRangeCreated;   // Age of range
   bool             rangeStale;              // Is range no longer valid?
   
   // Premium zone (upper half)
   double           premiumTop;              // Top of premium (= range high)
   double           premiumBottom;           // Bottom of premium (= mid)
   double           premiumMid;              // Center of premium
   double           premiumPercent;          // How deep into premium is price (0-100)
   
   // Discount zone (lower half)
   double           discountBottom;          // Bottom of discount (= range low)
   double           discountTop;             // Top of discount (= mid)
   double           discountMid;             // Center of discount
   double           discountPercent;         // How deep into discount is price (0-100)
   
   // OTE (Optimal Trade Entry) zones - Fibonacci-based
   double           oteDiscountLow;          // 20% - 38.2% from low
   double           oteDiscountHigh;         // (38.2% level)
   double           otePremiumLow;           // (61.8% level)
   double           otePremiumHigh;          // 61.8% - 79% from low
   
   // Current location
   PRICE_LOCATION   currentLocation;         // Where price is now
   double           locationScore;           // Quality of current location (0-100)
   bool             inOTE;                   // Is price in OTE zone?
   
   // Dealing range tracking
   double           dealingRangeHigh;        // High of current dealing activity
   double           dealingRangeLow;         // Low of current dealing activity
   bool             dealingRangeValid;       // Is there a valid dealing range?
};

/// @struct Historical high/low for previous periods
struct HistoricalLevel
{
   double           highPrice;               // High price
   double           lowPrice;                // Low price
   double           midPrice;                // Midpoint
   double           range;                   // High - Low
   datetime         periodStart;             // Start of period
   datetime         periodEnd;               // End of period
   int              periodType;              // 0=Daily, 1=Weekly, 2=Monthly
};

//================================================================================
// GLOBAL VARIABLES - MARKET OBJECTIVE & PREMIUM/DISCOUNT
//================================================================================

// Market Objective
MarketObjective     gMarketObjective;        // Current market objective
HistoricalLevel     gYesterdayLevel;         // Previous day's high/low
HistoricalLevel     gLastWeekLevel;          // Previous week's high/low
HistoricalLevel     gLastMonthLevel;         // Previous month's high/low

// Premium/Discount zones
PremiumDiscountZone gPremiumDiscount;        // Current P/D zone

// Objective history
double              gObjectiveHistory[];     // Array of recent objectives
int                 gObjectiveHistoryCount;  // Count of recent objectives

// Completion tracking
bool                gObjectiveCompletedToday; // Was objective reached today?
double              gDayCompletionTime;      // Time objective was completed

//================================================================================
// FUNCTION: GET PREVIOUS DAY HIGH/LOW
//================================================================================

/// @brief Get previous day's high and low
/// @param high Output parameter for previous day high
/// @param low Output parameter for previous day low
void GetPreviousDayHighLow(double &high, double &low)
{
   high = 0;
   low = 99999;
   
   // Get previous day's bars (roughly 24 hours = 288 M5 bars)
   int barsPerDay = 288; // 5-minute bars in 24 hours
   
   for(int i = barsPerDay; i < barsPerDay * 2; i++) {
      if(i >= iBars(Symbol(), PERIOD_M5)) break;
      
      double barHigh = iHigh(Symbol(), PERIOD_M5, i);
      double barLow = iLow(Symbol(), PERIOD_M5, i);
      
      if(barHigh > high) high = barHigh;
      if(barLow < low) low = barLow;
   }
   
   // Fallback: use daily timeframe
   if(high == 0 || low == 99999) {
      high = iHigh(Symbol(), PERIOD_D1, 1);
      low = iLow(Symbol(), PERIOD_D1, 1);
   }
}

/// @brief Get previous week's high and low
/// @param high Output parameter for previous week high
/// @param low Output parameter for previous week low
void GetPreviousWeekHighLow(double &high, double &low)
{
   high = 0;
   low = 99999;
   
   // Use weekly timeframe
   int weeksBack = 1;
   
   for(int i = weeksBack; i <= weeksBack; i++) {
      if(i >= iBars(Symbol(), PERIOD_W1)) break;
      
      double weekHigh = iHigh(Symbol(), PERIOD_W1, i);
      double weekLow = iLow(Symbol(), PERIOD_W1, i);
      
      if(weekHigh > high) high = weekHigh;
      if(weekLow < low) low = weekLow;
   }
}

/// @brief Get previous month's high and low
/// @param high Output parameter for previous month high
/// @param low Output parameter for previous month low
void GetPreviousMonthHighLow(double &high, double &low)
{
   high = 0;
   low = 99999;
   
   // Use monthly timeframe
   int monthsBack = 1;
   
   for(int i = monthsBack; i <= monthsBack; i++) {
      if(i >= iBars(Symbol(), PERIOD_MN1)) break;
      
      double monthHigh = iHigh(Symbol(), PERIOD_MN1, i);
      double monthLow = iLow(Symbol(), PERIOD_MN1, i);
      
      if(monthHigh > high) high = monthHigh;
      if(monthLow < low) low = monthLow;
   }
}

//================================================================================
// FUNCTION: IDENTIFY MARKET OBJECTIVE
//================================================================================

/// @brief Identify the primary market objective for today
/// @return Objective type
OBJECTIVE_TYPE IdentifyPrimaryObjective()
{
   double currentPrice = GetCurrentBid();
   OBJECTIVE_TYPE bestObjective = OBJ_UNKNOWN;
   double bestScore = 0;
   
   // Get all candidate levels
   double pdHigh, pdLow, pwHigh, pwLow, pmHigh, pmLow;
   GetPreviousDayHighLow(pdHigh, pdLow);
   GetPreviousWeekHighLow(pwHigh, pwLow);
   GetPreviousMonthHighLow(pmHigh, pmLow);
   
   // Score each candidate
   
   // Previous Day High
   double scoreP dHigh = ScoreObjective(pdHigh, currentPrice, true);
   if(scorePdHigh > bestScore) {
      bestScore = scorePdHigh;
      bestObjective = OBJ_PREVIOUS_DAY_HIGH;
   }
   
   // Previous Day Low
   double scorePdLow = ScoreObjective(pdLow, currentPrice, false);
   if(scorePdLow > bestScore) {
      bestScore = scorePdLow;
      bestObjective = OBJ_PREVIOUS_DAY_LOW;
   }
   
   // Previous Week High
   double scorePwHigh = ScoreObjective(pwHigh, currentPrice, true);
   if(scorePwHigh > bestScore) {
      bestScore = scorePwHigh;
      bestObjective = OBJ_PREVIOUS_WEEK_HIGH;
   }
   
   // Previous Week Low
   double scorePwLow = ScoreObjective(pwLow, currentPrice, false);
   if(scorePwLow > bestScore) {
      bestScore = scorePwLow;
      bestObjective = OBJ_PREVIOUS_WEEK_LOW;
   }
   
   // Nearest unswept liquidity pool (from Phase 3)
   double nearestLiquidityLong = GetNearestUnsweptTarget(1);
   double nearestLiquidityShort = GetNearestUnsweptTarget(-1);
   
   if(nearestLiquidityLong > currentPrice) {
      double scoreLiq = ScoreObjective(nearestLiquidityLong, currentPrice, true);
      if(scoreLiq > bestScore) {
         bestScore = scoreLiq;
         bestObjective = OBJ_EXTERNAL_LIQUIDITY;
      }
   }
   
   if(nearestLiquidityShort < currentPrice) {
      double scoreLiq = ScoreObjective(nearestLiquidityShort, currentPrice, false);
      if(scoreLiq > bestScore) {
         bestScore = scoreLiq;
         bestObjective = OBJ_INTERNAL_LIQUIDITY;
      }
   }
   
   return bestObjective;
}

/// @brief Score an objective based on relevance
/// @param objectivePrice Price of the objective
/// @param currentPrice Current price
/// @param isUpside Is this an upside objective?
/// @return Score (0-100)
double ScoreObjective(double objectivePrice, double currentPrice, bool isUpside)
{
   double score = 50; // Base score
   
   // Distance factor: closer is more relevant (but not too close)
   double distance = MathAbs(objectivePrice - currentPrice);
   double maxDistance = 500 * GetPointValue();
   
   if(distance > maxDistance) return 0; // Too far
   if(distance < GetPointValue() * 5) return 0; // Too close (already touched)
   
   double distanceFactor = 1.0 - (distance / maxDistance);
   score += distanceFactor * 20;
   
   // Direction alignment: does it agree with bias?
   if(isUpside && gMarketStructure.bias == BIAS_BULLISH) {
      score += 20;
   }
   if(!isUpside && gMarketStructure.bias == BIAS_BEARISH) {
      score += 20;
   }
   
   // Timeframe importance (daily highs/lows score higher than intraday)
   // This would be higher for weekly/monthly
   
   // Unswept bonus (if it's an unswept liquidity pool)
   // This is handled implicitly by the liquidity ranking
   
   return MathMin(100, score);
}

/// @brief Get objective price
/// @param objectiveType Type of objective
/// @return Price of objective, or 0 if not found
double GetObjectivePrice(OBJECTIVE_TYPE objectiveType)
{
   double pdHigh, pdLow, pwHigh, pwLow, pmHigh, pmLow;
   GetPreviousDayHighLow(pdHigh, pdLow);
   GetPreviousWeekHighLow(pwHigh, pwLow);
   GetPreviousMonthHighLow(pmHigh, pmLow);
   
   switch(objectiveType) {
      case OBJ_PREVIOUS_DAY_HIGH:      return pdHigh;
      case OBJ_PREVIOUS_DAY_LOW:       return pdLow;
      case OBJ_PREVIOUS_WEEK_HIGH:     return pwHigh;
      case OBJ_PREVIOUS_WEEK_LOW:      return pwLow;
      case OBJ_MONTHLY_HIGH:           return pmHigh;
      case OBJ_MONTHLY_LOW:            return pmLow;
      case OBJ_EXTERNAL_LIQUIDITY:     return GetNearestUnsweptTarget(1);
      case OBJ_INTERNAL_LIQUIDITY:     return GetNearestUnsweptTarget(-1);
      default:                         return 0;
   }
}

//================================================================================
// FUNCTION: UPDATE MARKET OBJECTIVE
//================================================================================

/// @brief Update market objective analysis
void UpdateMarketObjective()
{
   double currentPrice = GetCurrentBid();
   
   // If no objective set, identify one
   if(gMarketObjective.primaryObjective == OBJ_UNKNOWN) {
      gMarketObjective.primaryObjective = IdentifyPrimaryObjective();
      gMarketObjective.primaryObjectivePrice = GetObjectivePrice(gMarketObjective.primaryObjective);
      gMarketObjective.objectiveSetTime = TimeCurrent();
      gMarketObjective.barsObjectiveActive = 0;
   }
   
   // Update objective status
   gMarketObjective.objectiveDistance = MathAbs(gMarketObjective.primaryObjectivePrice - currentPrice);
   gMarketObjective.barsObjectiveActive++;
   
   // Check if objective has been touched
   double touchRange = 20 * GetPointValue();
   if(MathAbs(currentPrice - gMarketObjective.primaryObjectivePrice) < touchRange) {
      gMarketObjective.objectiveReached = true;
      gMarketObjective.objectiveStatus = OBJ_PARTIALLY_COMPLETED;
      gMarketObjective.objectiveCompletion = 80;
   }
   
   // Check if objective has been definitively completed (close beyond it)
   if(gMarketObjective.primaryObjectiveDirection == BIAS_BULLISH && currentPrice > gMarketObjective.primaryObjectivePrice) {
      gMarketObjective.objectiveCompleted = true;
      gMarketObjective.objectiveStatus = OBJ_COMPLETED;
      gMarketObjective.objectiveCompletion = 100;
      gObjectiveCompletedToday = true;
      gDayCompletionTime = TimeCurrent();
   }
   
   if(gMarketObjective.primaryObjectiveDirection == BIAS_BEARISH && currentPrice < gMarketObjective.primaryObjectivePrice) {
      gMarketObjective.objectiveCompleted = true;
      gMarketObjective.objectiveStatus = OBJ_COMPLETED;
      gMarketObjective.objectiveCompletion = 100;
      gObjectiveCompletedToday = true;
      gDayCompletionTime = TimeCurrent();
   }
   
   // Calculate confidence
   gMarketObjective.objectiveConfidence = 60;
   if(gMarketObjective.primaryObjective != OBJ_UNKNOWN) {
      gMarketObjective.objectiveConfidence = 75;
   }
}

//================================================================================
// FUNCTION: CALCULATE PREMIUM/DISCOUNT ZONES
//================================================================================

/// @brief Calculate premium/discount zones based on current dealing range
void CalculatePremiumDiscountZones()
{
   // Determine range anchor
   SelectRangeAnchor();
   
   // Get current dealing range
   double currentHigh = iHigh(Symbol(), PERIOD_M5, 0);
   double currentLow = iLow(Symbol(), PERIOD_M5, 0);
   
   // Look back for recent swing high/low
   if(gSwingHighCount > 0) {
      currentHigh = MathMax(currentHigh, gSwingHighs[gSwingHighCount - 1].price);
   }
   if(gSwingLowCount > 0) {
      currentLow = MathMin(currentLow, gSwingLows[gSwingLowCount - 1].price);
   }
   
   // Calculate zone boundaries
   gPremiumDiscount.rangeHigh = currentHigh;
   gPremiumDiscount.rangeLow = currentLow;
   gPremiumDiscount.rangeSize = gPremiumDiscount.rangeHigh - gPremiumDiscount.rangeLow;
   gPremiumDiscount.rangeMid = (gPremiumDiscount.rangeHigh + gPremiumDiscount.rangeLow) / 2.0;
   
   // Premium zone (upper half)
   gPremiumDiscount.premiumTop = gPremiumDiscount.rangeHigh;
   gPremiumDiscount.premiumBottom = gPremiumDiscount.rangeMid;
   gPremiumDiscount.premiumMid = (gPremiumDiscount.premiumTop + gPremiumDiscount.premiumBottom) / 2.0;
   
   // Discount zone (lower half)
   gPremiumDiscount.discountBottom = gPremiumDiscount.rangeLow;
   gPremiumDiscount.discountTop = gPremiumDiscount.rangeMid;
   gPremiumDiscount.discountMid = (gPremiumDiscount.discountTop + gPremiumDiscount.discountBottom) / 2.0;
   
   // OTE zones (Fibonacci-based optimal entry areas)
   // Discount OTE: 20% - 38.2% from low
   gPremiumDiscount.oteDiscountLow = gPremiumDiscount.rangeLow + (gPremiumDiscount.rangeSize * 0.20);
   gPremiumDiscount.oteDiscountHigh = gPremiumDiscount.rangeLow + (gPremiumDiscount.rangeSize * 0.382);
   
   // Premium OTE: 61.8% - 79% from low
   gPremiumDiscount.otePremiumLow = gPremiumDiscount.rangeLow + (gPremiumDiscount.rangeSize * 0.618);
   gPremiumDiscount.otePremiumHigh = gPremiumDiscount.rangeLow + (gPremiumDiscount.rangeSize * 0.79);
   
   // Determine current price location
   double currentPrice = GetCurrentBid();
   UpdatePriceLocation(currentPrice);
}

/// @brief Determine current price location (premium/discount/OTE)
/// @param currentPrice Current bid price
void UpdatePriceLocation(double currentPrice)
{
   // Check OTE zones first (highest priority)
   if(currentPrice >= gPremiumDiscount.oteDiscountLow && 
      currentPrice <= gPremiumDiscount.oteDiscountHigh) {
      gPremiumDiscount.currentLocation = LOC_OTE_DISCOUNT;
      gPremiumDiscount.inOTE = true;
      gPremiumDiscount.locationScore = 85;
      return;
   }
   
   if(currentPrice >= gPremiumDiscount.otePremiumLow && 
      currentPrice <= gPremiumDiscount.otePremiumHigh) {
      gPremiumDiscount.currentLocation = LOC_OTE_PREMIUM;
      gPremiumDiscount.inOTE = true;
      gPremiumDiscount.locationScore = 85;
      return;
   }
   
   gPremiumDiscount.inOTE = false;
   
   // Check premium/discount
   if(currentPrice > gPremiumDiscount.rangeMid) {
      gPremiumDiscount.currentLocation = LOC_PREMIUM;
      double premiumPercent = (currentPrice - gPremiumDiscount.premiumBottom) / 
                             (gPremiumDiscount.premiumTop - gPremiumDiscount.premiumBottom);
      gPremiumDiscount.premiumPercent = premiumPercent * 100;
      gPremiumDiscount.locationScore = 60;
   }
   else if(currentPrice < gPremiumDiscount.rangeMid) {
      gPremiumDiscount.currentLocation = LOC_DISCOUNT;
      double discountPercent = (currentPrice - gPremiumDiscount.discountBottom) / 
                              (gPremiumDiscount.discountTop - gPremiumDiscount.discountBottom);
      gPremiumDiscount.discountPercent = discountPercent * 100;
      gPremiumDiscount.locationScore = 60;
   }
   else {
      gPremiumDiscount.currentLocation = LOC_EQUILIBRIUM;
      gPremiumDiscount.locationScore = 50;
   }
}

//================================================================================
// FUNCTION: SELECT RANGE ANCHOR
//================================================================================

/// @brief Determine which range anchor to use (HTF, session, expansion, or external)
void SelectRangeAnchor()
{
   // Priority order:
   // 1. Recent expansion move (if strong displacement exists)
   // 2. Session structure (if current session has valid structure)
   // 3. External/HTF swings (if they're still protected)
   // 4. Fallback to H4 swing range
   
   if(gLastDisplacementCandle.is_displacement && gLastDisplacementCandle.barTime > (TimeCurrent() - 3600)) {
      gPremiumDiscount.rangeAnchor = ANCHOR_EXPANSION_MOVE;
      return;
   }
   
   if(gSessionHigh > 0 && gSessionLow > 0) {
      gPremiumDiscount.rangeAnchor = ANCHOR_SESSION_RANGE;
      return;
   }
   
   if(gSwingHighCount > 0 && gSwingLowCount > 0) {
      if(gSwingHighs[gSwingHighCount - 1].is_external) {
         gPremiumDiscount.rangeAnchor = ANCHOR_EXTERNAL_STRUCTURE;
         return;
      }
   }
   
   gPremiumDiscount.rangeAnchor = ANCHOR_HTF_SWING;
}

//================================================================================
// FUNCTION: GET OBJECTIVE STRING
//================================================================================

/// @brief Convert objective type to string
/// @param objType Objective type
/// @return String name
string ObjectiveTypeToString(OBJECTIVE_TYPE objType)
{
   switch(objType) {
      case OBJ_PREVIOUS_DAY_HIGH:      return "PDH (Previous Day High)";
      case OBJ_PREVIOUS_DAY_LOW:       return "PDL (Previous Day Low)";
      case OBJ_PREVIOUS_WEEK_HIGH:     return "PWH (Previous Week High)";
      case OBJ_PREVIOUS_WEEK_LOW:      return "PWL (Previous Week Low)";
      case OBJ_MONTHLY_HIGH:           return "MH (Monthly High)";
      case OBJ_MONTHLY_LOW:            return "ML (Monthly Low)";
      case OBJ_EQUAL_HIGH:             return "EQH (Equal High)";
      case OBJ_EQUAL_LOW:              return "EQL (Equal Low)";
      case OBJ_ASIAN_HIGH:             return "AH (Asian High)";
      case OBJ_ASIAN_LOW:              return "AL (Asian Low)";
      case OBJ_LONDON_HIGH:            return "LH (London High)";
      case OBJ_LONDON_LOW:             return "LL (London Low)";
      case OBJ_NEWYORK_HIGH:           return "NYH (NY High)";
      case OBJ_NEWYORK_LOW:            return "NYL (NY Low)";
      case OBJ_INTERNAL_LIQUIDITY:     return "IL (Internal Liquidity)";
      case OBJ_EXTERNAL_LIQUIDITY:     return "EL (External Liquidity)";
      default:                         return "Unknown";
   }
}

/// @brief Convert price location to string
/// @param location Price location
/// @return String name
string PriceLocationToString(PRICE_LOCATION location)
{
   switch(location) {
      case LOC_PREMIUM:         return "PREMIUM";
      case LOC_DISCOUNT:        return "DISCOUNT";
      case LOC_EQUILIBRIUM:     return "EQUILIBRIUM";
      case LOC_OTE_PREMIUM:     return "OTE PREMIUM";
      case LOC_OTE_DISCOUNT:    return "OTE DISCOUNT";
      default:                  return "UNKNOWN";
   }
}

//================================================================================
// FUNCTION: GET LOCATION QUALITY SCORE
//================================================================================

/// @brief Get quality score for current location
/// @param direction 1 for long, -1 for short
/// @return Quality score (0-100)
double GetLocationQualityScore(int direction = 1)
{
   double score = 0;
   
   if(direction == 1) { // Long
      // Discount is best for longs
      if(gPremiumDiscount.currentLocation == LOC_OTE_DISCOUNT) {
         score = 90; // Optimal
      }
      else if(gPremiumDiscount.currentLocation == LOC_DISCOUNT) {
         score = 75; // Good
      }
      else if(gPremiumDiscount.currentLocation == LOC_EQUILIBRIUM) {
         score = 50; // Neutral
      }
      else {
         score = 30; // Poor (in premium)
      }
   }
   else { // Short
      // Premium is best for shorts
      if(gPremiumDiscount.currentLocation == LOC_OTE_PREMIUM) {
         score = 90;
      }
      else if(gPremiumDiscount.currentLocation == LOC_PREMIUM) {
         score = 75;
      }
      else if(gPremiumDiscount.currentLocation == LOC_EQUILIBRIUM) {
         score = 50;
      }
      else {
         score = 30; // Poor (in discount)
      }
   }
   
   return score;
}

//================================================================================
// FUNCTION: PRINT OBJECTIVE STATE
//================================================================================

/// Print current objective and premium/discount state
void PrintObjectiveState()
{
   Print("\n=== MARKET OBJECTIVE & LOCATION ===");
   Print("Primary Objective: ", ObjectiveTypeToString(gMarketObjective.primaryObjective));
   Print("Objective Price: ", DoubleToString(gMarketObjective.primaryObjectivePrice, 5));
   Print("Distance: ", DoubleToString(gMarketObjective.objectiveDistance, 5));
   Print("Status: ", 
      (gMarketObjective.objectiveStatus == OBJ_PENDING ? "PENDING" :
       gMarketObjective.objectiveStatus == OBJ_PARTIALLY_COMPLETED ? "PARTIAL" :
       gMarketObjective.objectiveStatus == OBJ_COMPLETED ? "COMPLETED" : "UNKNOWN"));
   Print("Confidence: ", DoubleToString(gMarketObjective.objectiveConfidence, 0), "%");
   
   Print("\n--- Premium/Discount ---");
   Print("Range: ", DoubleToString(gPremiumDiscount.rangeLow, 5), 
         " to ", DoubleToString(gPremiumDiscount.rangeHigh, 5));
   Print("Equilibrium: ", DoubleToString(gPremiumDiscount.rangeMid, 5));
   Print("Current Location: ", PriceLocationToString(gPremiumDiscount.currentLocation));
   Print("In OTE: ", (gPremiumDiscount.inOTE ? "YES" : "NO"));
   Print("Location Score: ", DoubleToString(gPremiumDiscount.locationScore, 0));
   
   Print("=====================================\n");
}

//================================================================================
// INTEGRATION WITH PREVIOUS PHASES
//================================================================================

/// Enhanced OnTick with objective and location analysis
void OnTickPhase4()
{
   // Check for new bar (from Phase 1)
   gIsNewBar = IsNewBar(Symbol(), PERIOD_CURRENT, gLastBarTime);
   
   if(gIsNewBar) {
      gBarCounter++;
      
      // UPDATE MARKET STRUCTURE (Phase 2)
      UpdateMarketStructure();
      
      // UPDATE LIQUIDITY (Phase 3)
      DetectEqualHighs(10, 2);
      DetectEqualLows(10, 2);
      DetectBuySideLiquidity();
      DetectSellSideLiquidity();
      DetectAsianSessionLiquidity();
      DetectLondonSessionLiquidity();
      DetectNewYorkSessionLiquidity();
      UpdateLiquidityPools();
      
      // UPDATE OBJECTIVE & LOCATION (Phase 4)
      UpdateMarketObjective();
      CalculatePremiumDiscountZones();
      
      if(inShowDebugInfo) {
         Print("Bar #", gBarCounter,
               " | Close: ", DoubleToString(iClose(Symbol(), PERIOD_M5, 0), 5),
               " | Objective: ", ObjectiveTypeToString(gMarketObjective.primaryObjective),
               " | Location: ", PriceLocationToString(gPremiumDiscount.currentLocation),
               " | Obj Status: ", (gMarketObjective.objectiveStatus == OBJ_COMPLETED ? "COMPLETE" : "PENDING"));
      }
      
      // Daily reset (from Phase 1)
      if(IsNewDay()) {
         gAccount.dailyStartBalance = GetAccountBalance();
         gAccount.dailyPnL = 0;
         gDailyLockout = false;
         gObjectiveCompletedToday = false;
         InitializeStructureArrays();
         InitializeLiquidityEngine();
      }
   }
}

//================================================================================
// END OF PHASE 4: MARKET OBJECTIVE & PREMIUM/DISCOUNT
//================================================================================
