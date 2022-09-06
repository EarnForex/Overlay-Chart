//+------------------------------------------------------------------+
//|                                                 OverlayChart.mq5 |
//|                               Copyright 2014-2022, EarnForex.com |
//|                                        https://www.earnforex.com |
//|               Converted from MT4 version by http://www.irxfx.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2014-2022, EarnForex.com"
#property link      "https://www.earnforex.com/forum/threads/overlay-chart.8939/"
#property version   "1.03"

#property description "Adds overlay chart of another symbol (subsymbol) to the current one."
#property description "If subsymbol chart has more bars, it will skip them."
#property description "If subsymbol chart has fewer bars, it will sync them by time leaving gaps in the host chart."

#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   1
#property indicator_type1  DRAW_COLOR_BARS
#property indicator_color1 clrMediumSeaGreen, clrOrange
#property indicator_width1 1

enum enum_screen_side
{
    Left,
    Right
};

// Indicator parameters:
input string SubSymbol = "CHFJPY";
input bool Mirroring = false;
input ENUM_DRAW_TYPE DrawType = DRAW_COLOR_BARS;
input color GridColor = clrWhite;
input enum_screen_side ScaleSide = Left; // Subsymbol Y-scale side of screen

// Indicator buffers:
double O[];
double H[];
double L[];
double C[];
double Color[];

// Global variables:
double SubOpen[];
double SubHigh[];
double SubLow[];
double SubClose[];
datetime SubTime[];
string Prefix = "OverlayChart"; // Indicator prefix.
int Grid = 10; // Grid lines.
int SnapPips = 10;  // Snap pips for grid lines.
double prev_SubRangeCenter = 0;
double prev_GridPips = 0;
ulong LastRecalculationTime = 0;

int OnInit()
{
    IndicatorSetString(INDICATOR_SHORTNAME, "OverLay Chart (" + SubSymbol + ")");

    if (DrawType == DRAW_LINE)
    {
        SetIndexBuffer(0, C, INDICATOR_DATA);
        // Thsee won't be used, but need them as buffers to avoid array out of range errors:
        SetIndexBuffer(1, H, INDICATOR_DATA);
        SetIndexBuffer(2, L, INDICATOR_DATA);
        SetIndexBuffer(3, O, INDICATOR_DATA);
    }
    else
    {
        SetIndexBuffer(0, O, INDICATOR_DATA);
        SetIndexBuffer(1, H, INDICATOR_DATA);
        SetIndexBuffer(2, L, INDICATOR_DATA);
        SetIndexBuffer(3, C, INDICATOR_DATA);
    }
    SetIndexBuffer(4, Color, INDICATOR_COLOR_INDEX);

    ArraySetAsSeries(O, true);
    ArraySetAsSeries(H, true);
    ArraySetAsSeries(L, true);
    ArraySetAsSeries(C, true);
    ArraySetAsSeries(Color, true);

    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0);
    PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DrawType);
    
    Comment(SubSymbol + " Overlay");
    
    EventSetTimer(1);

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    ObjectsDeleteAll(0, Prefix);
    Comment("");
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime & Time[],
                const double & Open[],
                const double & High[],
                const double & Low[],
                const double & Close[],
                const long & tick_volume[],
                const long & volume[],
                const int &spread[])
{
    ArraySetAsSeries(Open, true);
    ArraySetAsSeries(High, true);
    ArraySetAsSeries(Low, true);
    ArraySetAsSeries(Close, true);
    ArraySetAsSeries(Time, true);

    return Recalc(rates_total, Time, Open, High, Low, Close);
}

int Recalc(int rates_total, const datetime& Time[], const double& Open[], const double& High[], const double& Low[], const double& Close[])
{
    int _BarsCount;
    double _CurRangeHigh, _CurRangeLow, _CurRangeCenter;
    double _SubRangeHigh, _SubRangeLow, _SubRangeCenter;
    double _SubPoint;
    int _SubDigit;
    double _SubOpen, _SubHigh, _SubLow, _SubClose;
    double _PipsRatio;
    double _GridPips, _GridPrice;
    int _i;

    // Calculate visible bars.
    _BarsCount = (int)ChartGetInteger(0, CHART_VISIBLE_BARS) + 1;
    int _FirstBar = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
    int _LastBar = _FirstBar - _BarsCount + 1;
    if ( _LastBar < 0 )
    {
        _LastBar = 0;
        _BarsCount = _FirstBar + 1;
    }
    if (MathAbs(_FirstBar - _LastBar) <= 1) return rates_total;
    // Time of the first and last bars to copy the timeseries values.
    datetime stop_time = Time[_FirstBar];
    datetime start_time = Time[_LastBar];

    //Calculate chart ratio.
    _CurRangeHigh = High[ArrayMaximum(High, _LastBar, _BarsCount)];
    _CurRangeLow = Low[ArrayMinimum(Low, _LastBar, _BarsCount)];
    _CurRangeCenter = (_CurRangeHigh + _CurRangeLow) / 2;

    int n;
    n = CopyOpen(SubSymbol, Period(), start_time, stop_time, SubOpen);
    if (n <= 0)
    {
        Print("Waiting for ", SubSymbol, " data to load...");
        return rates_total;
    }
    n = CopyHigh(SubSymbol, Period(), start_time, stop_time, SubHigh);
    if (n <= 0) return rates_total;
    n = CopyLow(SubSymbol, Period(), start_time, stop_time, SubLow);
    if (n <= 0) return rates_total;
    n = CopyClose(SubSymbol, Period(), start_time, stop_time, SubClose);
    if (n <= 0) return rates_total;
    n = CopyTime(SubSymbol, Period(), start_time, stop_time, SubTime);
    if (n <= 0) return rates_total;

    double SubMax = SubHigh[ArrayMaximum(SubHigh)];
    double SubMin = SubLow[ArrayMinimum(SubLow)];

    if (Mirroring)
    {
        _SubRangeHigh = SubMin;
        _SubRangeLow = SubMax;
    }
    else
    {
        _SubRangeHigh = SubMax;
        _SubRangeLow = SubMin;
    }

    _SubRangeCenter = (_SubRangeHigh + _SubRangeLow) / 2;
    _SubPoint = SymbolInfoDouble(SubSymbol, SYMBOL_POINT);
    _SubDigit = (int)SymbolInfoInteger(SubSymbol, SYMBOL_DIGITS);

    if (_SubRangeHigh - _SubRangeLow == 0) return rates_total;

    _PipsRatio = (_CurRangeHigh - _CurRangeLow) / (_SubRangeHigh - _SubRangeLow);

    _GridPips = (_SubRangeHigh - _SubRangeLow) / Grid;
    _GridPips = MathRound((_SubRangeHigh - _SubRangeLow) / Grid / (_SubPoint * SnapPips)) * (_SubPoint * SnapPips);

    bool skipped = false; // To remember that some subsymbol bars have been skipped and display a relevant message.
    bool not_enough = false; // To remember that there weren't enough subsymbol bars to fill all host chart bars. A relevant message should be displayed.
    int i;

    ArrayInitialize(O, 0);
    ArrayInitialize(H, 0);
    ArrayInitialize(L, 0);
    ArrayInitialize(C, 0);

    // Draw candlesticks.
    for (_i = _LastBar, i = n - 1; (_i < _LastBar + _BarsCount) && (i >= 0); _i++, i--)
    {
        // Loading bars that are more frequent than host chart.
        if (Time[_i] < SubTime[i])
        {
            while (Time[_i] < SubTime[i])
            {
                skipped = true;
                i--;
                // Out of range.
                if (i >= n) break;
            }
        }
        // Loading bars that are less frequent than host chart.
        else if (Time[_i] > SubTime[i])
        {
            while (Time[_i] > SubTime[i])
            {
                not_enough = true;
                _i++;
                // Out of range.
                if (_i >= _LastBar + _BarsCount) break;
            }
        }
        // Failed to sync time.
        if ((_i >= _LastBar + _BarsCount) || (i >= n) || (Time[_i] != SubTime[i])) continue;

        _SubOpen = SubOpen[i] - _SubRangeCenter;
        _SubHigh = SubHigh[i] - _SubRangeCenter;
        _SubLow = SubLow[i] - _SubRangeCenter;
        _SubClose = SubClose[i] - _SubRangeCenter;

        if (Mirroring)
        {
            if (_SubOpen < _SubClose)
            {
                H[_i] = _CurRangeCenter + _SubHigh * _PipsRatio;
                L[_i] = _CurRangeCenter + _SubLow * _PipsRatio;
                Color[_i] = 0;
            }
            else
            {
                L[_i] = _CurRangeCenter + _SubLow * _PipsRatio;
                H[_i] = _CurRangeCenter + _SubHigh * _PipsRatio;
                Color[_i] = 1;
            }
            C[_i] = _CurRangeCenter + _SubClose * _PipsRatio;
            O[_i] = _CurRangeCenter + _SubOpen * _PipsRatio;
        }
        else
        {
            if (_SubOpen < _SubClose)
            {
                H[_i] = _CurRangeCenter + _SubHigh * _PipsRatio;
                L[_i] = _CurRangeCenter + _SubLow * _PipsRatio;
                Color[_i] = 0;
            }
            else
            {
                L[_i] = _CurRangeCenter + _SubLow * _PipsRatio;
                H[_i] = _CurRangeCenter + _SubHigh * _PipsRatio;
                Color[_i] = 1;
            }
            C[_i] = _CurRangeCenter + _SubClose * _PipsRatio;
            O[_i] = _CurRangeCenter + _SubOpen * _PipsRatio;
        }
    }

    // Don't redraw grid if nothing changed.
    if ((prev_SubRangeCenter != _SubRangeCenter) || (prev_GridPips != _GridPips))
    {
        for (_i = 1; _i <= Grid; _i ++)
        {
            _GridPrice = MathRound(_SubRangeCenter / (_SubPoint * SnapPips)) * (_SubPoint * SnapPips);
            _GridPrice = ((_GridPrice + _GridPips / 2) + _GridPips * (Grid / 2 - 1)) - (_GridPips * (_i - 1));

            string grid_string = Prefix + "Grid" + IntegerToString(_i);
            if (ObjectFind(0, grid_string) < 0)
            {
                ObjectCreate(0, grid_string, OBJ_TREND, 0, 0, 0);
                ObjectSetInteger(0, grid_string, OBJPROP_COLOR, GridColor);
                ObjectSetInteger(0, grid_string, OBJPROP_STYLE, STYLE_DOT);
                ObjectSetInteger(0, grid_string, OBJPROP_WIDTH, 1);
                ObjectSetInteger(0, grid_string, OBJPROP_RAY_RIGHT, true);
            }

            ObjectSetInteger(0, grid_string, OBJPROP_TIME, 0, Time[_FirstBar]);
            ObjectSetDouble(0, grid_string, OBJPROP_PRICE, 0, _CurRangeCenter + (_GridPrice - _SubRangeCenter) * _PipsRatio);
            ObjectSetInteger(0, grid_string, OBJPROP_TIME, 1, Time[_LastBar]);
            ObjectSetDouble(0, grid_string, OBJPROP_PRICE, 1, _CurRangeCenter + (_GridPrice - _SubRangeCenter) * _PipsRatio);

            grid_string = Prefix + "Price" + IntegerToString(_i);
            if (ObjectFind(0, grid_string) < 0)
            {
                ObjectCreate(0, grid_string, OBJ_TEXT, 0, 0, 0);
                ObjectSetInteger(0, grid_string, OBJPROP_COLOR, GridColor);
            }
            //ObjectSetInteger(0, grid_string, OBJPROP_TIME, 0, Time[_FirstBar - _BarsCount / 10]);
            if (ScaleSide == Left)
            {
                ObjectSetInteger(0, grid_string, OBJPROP_ANCHOR, 0, ANCHOR_LEFT_LOWER);
                if (_FirstBar > 0) ObjectSetInteger(0, grid_string, OBJPROP_TIME, 0, Time[_FirstBar - 1]);
                else ObjectSetInteger(0, grid_string, OBJPROP_TIME, 0, Time[_FirstBar]);
            }
            else // Right:
            {
                ObjectSetInteger(0, grid_string, OBJPROP_ANCHOR, 0, ANCHOR_RIGHT_LOWER);
                ObjectSetInteger(0, grid_string, OBJPROP_TIME, 0, Time[_LastBar]);
            }
            ObjectSetDouble(0, grid_string, OBJPROP_PRICE, 0, _CurRangeCenter + (_GridPrice - _SubRangeCenter) * _PipsRatio);
            ObjectSetString(0, grid_string, OBJPROP_TEXT, DoubleToString(_GridPrice, _SubDigit));

            prev_SubRangeCenter = _SubRangeCenter;
            prev_GridPips = _GridPips;
        }
    }

    string skipped_label = Prefix + "Skipped";
    if (skipped)
    {
        if (ObjectFind(0, skipped_label) < 0)
        {
            ObjectCreate(0, skipped_label, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, skipped_label, OBJPROP_XDISTANCE, 20);
            ObjectSetInteger(0, skipped_label, OBJPROP_YDISTANCE, 20);
            ObjectSetInteger(0, skipped_label, OBJPROP_CORNER, CORNER_LEFT_LOWER);
            ObjectSetInteger(0, skipped_label, OBJPROP_COLOR, GridColor);
            ObjectSetString(0, skipped_label, OBJPROP_TEXT, "Some of the loaded bars have been skipped.");
        }
    }
    else // Remove message if it is no longer needed.
    {
        ObjectDelete(0, skipped_label);
    }

    string not_enough_label = Prefix + "NotEnough";
    if (not_enough)
    {
        if (ObjectFind(0, not_enough_label) < 0)
        {
            ObjectCreate(0, not_enough_label, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, not_enough_label, OBJPROP_XDISTANCE, 20);
            ObjectSetInteger(0, not_enough_label, OBJPROP_YDISTANCE, 40);
            ObjectSetInteger(0, not_enough_label, OBJPROP_CORNER, CORNER_LEFT_LOWER);
            ObjectSetInteger(0, not_enough_label, OBJPROP_COLOR, GridColor);
            ObjectSetString(0, not_enough_label, OBJPROP_TEXT, "At some point, there weren't enough of the loaded bars.");
        }
    }
    else // Remove message if it is no longer needed.
    {
        ObjectDelete(0, not_enough_label);
    }
    
    LastRecalculationTime = GetMicrosecondCount();
    
    return rates_total;
}

void OnTimer()
{
    if (GetMicrosecondCount() - LastRecalculationTime < 1000000) return; // Do not recalculate on timer if less than 1 second passed.

    datetime Time[];
    double Open[], High[], Low[], Close[];

    ArraySetAsSeries(Open, true);
    ArraySetAsSeries(High, true);
    ArraySetAsSeries(Low, true);
    ArraySetAsSeries(Close, true);
    ArraySetAsSeries(Time, true);

    int rates_total = iBars(Symbol(), Period());
    if (rates_total < 1)
    {
        Print("Waiting for ", Symbol(), " data to load in OnTimer()...");
        return;
    }
    int n;
    n = CopyOpen(Symbol(), Period(), 0, rates_total, Open);
    if (n <= 0)
    {
        Print("Waiting for ", Symbol(), " data to load in OnTimer()...");
        return;
    }
    n = CopyHigh(Symbol(), Period(), 0, rates_total, High);
    if (n <= 0) return;
    n = CopyLow(Symbol(), Period(), 0, rates_total, Low);
    if (n <= 0) return;
    n = CopyClose(Symbol(), Period(), 0, rates_total, Close);
    if (n <= 0) return;
    n = CopyTime(Symbol(), Period(), 0, rates_total, Time);
    if (n <= 0) return;

    Recalc(rates_total, Time, Open, High, Low, Close);

    ChartRedraw();
}
//+------------------------------------------------------------------+