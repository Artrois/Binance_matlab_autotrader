%% Algorithmic Trading in Matlab
%

%% start function
%
%

function start()

trading_pair = "BTCUSD";%BTCUSD for Bitfinex
trading_pair = "BTCUSDT";%BTCUSDT for Binance

%spotAPI_URL = 'https://api.binance.com';
%spotAPI1_URL = 'https://api1.binance.com';
%spotAPI_TestNet_URL = 'https://testnet.binance.vision';
%platform_URL = spotAPI_URL;

% we create instance of binance_settings and give parameter true that will
% select settings for binance test net
binance_settings_instance = binance_settings(true);
binance_api_instance = binance_api(binance_settings_instance);

control_GUI = GUI();

tiledlayout(3, 1) % we use three subplots
% Top plot
nexttile

% check if platform is online, read time
[sever_time, sever_time_formated] = binance_api_instance.get_time();
if sever_time == 0
    disp('No time retreived->exiting');
    return;
end

disp(['Binance server online with time->' sever_time_formated]);

% check if symbol pair of interest is supported by the exchange
[binance_symbols] =  binance_api_instance.get_symbols();
if ~size(binance_symbols) 
    disp('No symbols retrieved from exchange->exiting');
    return;
end
found = 0;
for i=1:size(binance_symbols,1)
    if binance_symbols(i).symbol == trading_pair, found = 1; end
end
if ~found
    fprintf('Traiding %s pair not supported\n',trading_pair);
    return;
end

% get account details
[account_info, my_balances] = binance_api_instance.get_account_info();
if ~isstruct(account_info)
    disp('Account info not retrieved->exiting');
    return;
end
ret = size(my_balances);
fprintf('Account info retrieved with %i balances \n', ret(1));


%   8×3 cell array of balances
%       asset           balance             locked
%     {'BNB' }    {'1000.00000000'  }    {'0.00000000'}
%     {'BTC' }    {'1.00000000'     }    {'0.00000000'}
%     {'BUSD'}    {'10000.00000000' }    {'0.00000000'}
%     {'ETH' }    {'100.00000000'   }    {'0.00000000'}
%     {'LTC' }    {'500.00000000'   }    {'0.00000000'}
%     {'TRX' }    {'500000.00000000'}    {'0.00000000'}
%     {'USDT'}    {'10000.00000000' }    {'0.00000000'}
%     {'XRP' }    {'50000.00000000' }    {'0.00000000'}

% update asset table
set(control_GUI.UItblAssets, 'ColumnName', {'Asset', 'Free', 'Locked'});
set(control_GUI.UItblAssets, 'Data', my_balances); %, 'ColumnWidth','auto');

%This information can be easily plot in as candles, which indicates the open, 
%high, low and close price of each tick. The following code shows the hourly 
%price of the last week (24*7 1h).
global asset;
% asset = getPriceActionBitfinex(trading_pair, "1h", 24*7);
% asset = getPriceActionBinance(trading_pair, "1h", 24*7);
asset = binance_api_instance.get_klines(trading_pair, '1h', 24*7);
if ~istimetable(asset)
    return;
end

uiAxesObj = control_GUI.UIAxesCandles;
hold(uiAxesObj,'on')
candle(uiAxesObj, asset) %plot candle sticks

%now create bollinger bands
[middle,upper,lower]= bollinger(asset);
CloseBolling = [middle.Close, upper.Close, lower.Close];
plot(uiAxesObj, middle.Time,CloseBolling)
title(trading_pair + " candles")
hold(uiAxesObj,'off')

% find local minima and maxima using thresholds. Take peaks which are
% higher then neighbors by 1% of the last crypto close price
[peaks, locs] = findpeaks(asset.close , 'Threshold', ceil(asset.close(end) * 0.001)); %local max
[~, rlocs] = findpeaks(-asset.close , 'Threshold', ceil(asset.close(end) * 0.004)); %local min

%if ~isempty(locs), plot(btc.Time(locs), btc.close(locs), 'rv', 'MarkerFaceColor', 'r'), end
%if ~isempty(rlocs), plot(btc.Time(rlocs), btc.close(rlocs), 'g^', 'MarkerFaceColor', 'g'), end

% use Savitzky-Golay smoothing filter to smooth the closing prices. 
cubicMA = sgolayfilt(asset.close, 3, 7);
plot(asset.Time, cubicMA);


%Using the close price, we can calculate the return of each tick. This indicates 
%the percent of change with regard the previous tick, which represent the theoretical 
%gain (or loss) obtained if holding the assets for each tick. And the cumulative 
%sum of these returns would represent the buy and hold strategy return over the time.
asset.tickRet = [0; (asset.close(2:end)- asset.close(1:end-1))./asset.close(1:end-1)];
%asset = btc;

%calculate slope/gradient from row price and use 60mins as interval to make slope relative
%to 60minutes duration betweek candle sticks
raw_derivative = [0; diff(asset.close)./60]; % [0; (btc.close(2:end)- btc.close(1:end-1))./btc.close(1:end-1)];

% calculate slope/gradient from cubicMA smoothed signal and use 60mins as interval to make slope relative
% to 60minutes duration betweek candle sticks
cubicMA_derivative = [0; diff(cubicMA)./60];

%calculate 2nd order sope/gradient/derivative from cubicMA
cubicMA_2nd_order_derivative = abs([0; diff(cubicMA_derivative)] ./ [1; cubicMA_derivative(2); cubicMA_derivative(3:end)]);

% find zero-crossings in cubicMA_derivative signal with positive slope and plot on graph
% here we check current value >0 but previous value < 0. This means we
% crossed zero and would be in positive slope 
% TODO: consider to filter only those local extrema which have high slope.
% basically use a threshold to select only those extrema which have high
% slope: (cubicMA_derivative(3:end) - cubicMA_derivative(2:end-1)) > XY
% XY := threshold
relative_threshold_to_filter_extrema = 3;
cubicMA_derivative_zero_crossing_min = [ false; false; cubicMA_derivative(3:end) > 0 ... 
    & cubicMA_derivative(2:end-1) < 0  ]; % & cubicMA_2nd_order_derivative(3:end) > relative_threshold_to_filter_extrema ]; 

   
cubicMA_derivative_zero_crossing_max = [ false; false; cubicMA_derivative(3:end) < 0 ...
    & cubicMA_derivative(2:end-1) > 0  ]; % & cubicMA_2nd_order_derivative(3:end) > relative_threshold_to_filter_extrema ];

sum(cubicMA_derivative_zero_crossing_min)
sum(cubicMA_derivative_zero_crossing_max)

% calc RSI
rsi_index = rsindex(asset.close);
% loc minima where RSI <50, if RSI>50 then we are overbought and the min should not be taken
filtered_loc_min = (rsi_index < 40) & cubicMA_derivative_zero_crossing_min;

% plot markers where cubicMA slope crossed zero line, this equals a local
% minima of a smoothed close price after applied Savitzky-Golay smoothing filter
%plot(btc.Time(cubicMA_derivative_zero_crossing_min), btc.close(cubicMA_derivative_zero_crossing_min), 'go'); % loc minima
plot(asset.Time(filtered_loc_min), asset.close(filtered_loc_min), 'go'); 
plot(asset.Time(cubicMA_derivative_zero_crossing_max), asset.close(cubicMA_derivative_zero_crossing_max), 'ro'); % loc maxima

hold off
grid on

% gradient plot
nexttile;
hold on

plot(asset.Time, raw_derivative);


plot(asset.Time, cubicMA_derivative);
plot(asset.Time(cubicMA_derivative_zero_crossing_min), cubicMA_derivative(cubicMA_derivative_zero_crossing_min), 'go'); % loc minima
plot(asset.Time(cubicMA_derivative_zero_crossing_max), cubicMA_derivative(cubicMA_derivative_zero_crossing_max), 'ro'); % loc maxima
plot(asset.Time, rsi_index); %plot RSI

hold off
legend('raw gradient', 'cubicMA gradient', 'local min', 'local max', 'RSI');
grid on

% Bottom plot
nexttile
%figure % open new plot window for multiple line plotting
hold on
plot(asset.Time, asset.tickRet)         % TickReturns
plot(asset.Time, cumsum(asset.tickRet)) % BuyAndHold


SMA_str = SMA_strategy(20); %20=lagging, 3=leading moving average
SMA_cumret = evaluateStrategy(SMA_str, 0.001); %taker fee being 0.001
plot(asset.Time, SMA_cumret);


legend('TickReturns', 'BuyAndHold', 'SMA returns');
hold off

title(trading_pair + " strategies")
grid on;

% optimization
%%aisearch = PSO(@fitnessFunction, 13);
%aisearch = PSO(@fitnessFunction, 9);
%aisearch.sizePopulation = 100;
%aisearch.maxNoIterations = 100;
%aisearch.start();

delete(binance_settings_instance);
delete(binance_api_instance);
end

%% Get prices from Binance Exchange
% The response storage in data contains a matrix of 6 columns and 1000 days, 
% with the information of the date; low, high, open and close price of such 
% day and amount of volume trade over it. This information is more useful in
% a timetable object, which allows a more handy way of manipulating the data, 
% like sorting using the Time column. The following function can be used to 
% obtain the timetable object with the lastest price action of the indicated 
% market ("BTCUSD" for example) and desired interval ("1h" for example).

function tt = getPriceActionBinance(traidingpair, interval, limit)
    global platform_URL;
    tt = 0;
 
    % check if platform is online, read time
    [sever_time, sever_time_formated] = time;
    if sever_time == 0
        return;
    end

    disp(['Platform online with server time->' sever_time_formated]);

    %check traiding pair is supported
    symbols = binance_symbols();
    if symbols == 0
        return;
    end
    found = 0;
    for i=1:size(symbols,1)
        if symbols(i).symbol == traidingpair, found = 1; end
    end
    if ~found
        fprintf('Traiding %s pair not supported by %s\n',traidingpair, platform_URL);
        return
    end
    
    urlTemp = sprintf('%s%s',platform_URL, '/api/v3/klines');
    try
        data = webread(urlTemp,'symbol', traidingpair, 'interval', interval, 'limit', limit);
    catch ME    
        disp('Retreiving traiding pair data from Binance failed with->' + ME.identifier);
        return;
    end
    sz = size(data);
    date = datetime.empty(sz(1), 0);open = zeros(sz(1), 1); close = zeros(sz(1), 1);high = zeros(sz(1), 1);
    low = zeros(sz(1), 1);vol = zeros(sz(1), 1);Quote_asset_volume = zeros(sz(1), 1);
    num_trades = zeros(sz(1), 1); Taker_buy_quote_asset_volume = zeros(sz(1), 1);
    try
        for i = 1:sz(1)
            tmp = data{i};
            date(i) = datetime(datestr(tmp{7}/86400/1000 + datenum(1970,1,1)));
            open(i) = str2double(tmp{2});
            close(i) = str2double(tmp{5});
            high(i) = str2double(tmp{3});
            low(i) = str2double(tmp{4});
            vol(i) = str2double(tmp{6});
            Quote_asset_volume(i) = str2double(tmp{8});
            num_trades(i) = tmp{9};
            Taker_buy_quote_asset_volume(i) = str2double(tmp{11});
        end
        %date = datetime(datestr(data(:,1)/86400/1000 + datenum(1970,1,1)));
        %open = data(:,2);
        %close = data(:,3);
        %high = data(:,4);
        %low = data(:,5);
        %vol = data(:,6);
        tt = timetable(datetime(date'), open, high, low, close, vol);
        tt = sortrows(tt, 'Time');
        tt = unique(tt);
    catch ME
        disp('Processing of traiding pair data failed with stack dump:');
        ME.stack
    end
    
end


%% Get prices from Bitfinex Exchange
% The response storage in data contains a matrix of 6 columns and 1000 days, 
% with the information of the date; low, high, open and close price of such 
% day and amount of volume trade over it. This information is more useful in
% a timetable object, which allows a more handy way of manipulating the data, 
% like sorting using the Time column. The following function can be used to 
% obtain the timetable object with the lastest price action of the indicated 
% market ("BTCUSD" for example) and desired interval ("1h" for example).

function tt = getPriceActionBitfinex(traidingpair, interval, limit)
    platformStatus = webread('https://api-pub.bitfinex.com/v2/platform/status');
    if platformStatus 
        disp('Platform online');
    else
        fprintf('Platform offline/in maintenance. Exiting...\n');
        tt = 0;
        return;
    end
        
    urlTemp = sprintf('https://api-pub.bitfinex.com/v2/candles/trade:%s:t%s/hist', interval, traidingpair);
    data = webread(urlTemp, 'limit', limit, 'sort', -1);
    date = datetime(datestr(data(:,1)/86400/1000 + datenum(1970,1,1)));
    open = data(:,2);
    close = data(:,3);
    high = data(:,4);
    low = data(:,5);
    vol = data(:,6);
    tt = timetable(datetime(date), open, high, low, close, vol);
    tt = sortrows(tt, 'Time');
    tt = unique(tt);
end


%% Evaluate Strategy perfomrance
%With this information, any strategy can be applied over the tick returns by 
%multiplying a vector that selects the ticks on which the strategy is long 
%with a value of 1, short with a value of −1 or without a position with 
%a value of 0. Then by using the cumulative sum of this multiplication 
%(cumsum(strategy .* btc.tickRet)) the return over time of such strategy 
%can be obtained. However, this do not reflect the fees expended every time 
%an order is executed, which can be included by substracting the difference 
%of the strategy vector.

function cumret = evaluateStrategy(strategy, fees)
    global asset;
    orders = [0; diff(strategy)];                   % Change of position
    %tickRet = [0; (asset.close(2:end) - asset.close(1:end-1))./asset.close(1:end-1)];
    %strategyRet = tickRet .* strategy;              % Strategy Tick Returns
    strategyRet = asset.tickRet .* strategy;        % Strategy Tick Returns
    strategyRet = strategyRet - abs(orders) * fees; % Add fees
    cumret = cumprod(1 + strategyRet) - 1;              % Strategy Cumulative Returns
end



%% mixStrategies function
% Although these three strategies can be optimized individually with a good 
% computer and a couple hours, when a more sophisticated mixture of strategies 
% is intended to be implemented execution time of brute force is unpractical. 
% One approach could be to use the individual best parameters of these strategies
% and then optimize the mixture weights between them. Splitting the complexity 
% overall optimization, but resulting in sub-optimal solutions, due to different
% parameters might result optimal when a combination of strategies is intended 
% as opposite of their individual strategy behavior. Although, several ways 
% of mixing these strategies can be formulated, a simple weighted sum can be 
% implemented as follows. 
% This function considers that when the sum of the strategies positions is 
% higher than 1, then the long positions is confirmed, or lower than -1 
% indicates a short one. Also, when the sum results is between the range 
% $[−1,1]$, no consensus is reached, therefore no positions is advised:
%

function newStrat = mixStrategies(strats)
    sumStrat = sum(strats, 2);
    newStrat = zeros(size(strats, 1), 1);
    newStrat(sumStrat >= 1) = 1;
    newStrat(sumStrat <= -1) = -1;
end

%% Fitness function
% Given the higher number of parameters in a mixture of strategies, other 
% optimization methods can be applied to find efficient solutions quickly. 
% Previous works have make use of Metaheuristics Algorithms to find sub-optimal 
% parameters for single strategies, such as the moving average in (Lee et al. 2005), 
% or a mixture of them in (S.Tawfik, Badr, and Abdel-Rahman 2013) 
% (Contreras, Hidalgo, and Núñez-Letamendia 2013) (Stasinakis et al. 2016) (Hu et al. 2015). 
% Metaheuristics Algorithms are designed to operate as black boxes, in such 
% way that their application results relatively easy. In this case, the open 
% source AISearch toolbox(Reyna-Orta 2019) (https://github.com/aeroreyna/AISearchMatlab) 
% provides the Metaheuristics implementation. 
% For the case of the application of trading strategy optimization, these can 
% be applied by selecting the dimensionality of the problem as the number of 
% parameters to be adjusted, a function that transform each dimensionality 
% between the desired boundaries and a fitness function that evaluates the 
% solutions offers by the algorithm. If the MA, DEMA, MACD and RSI strategies 
% are considered, then there is 2, 3, 4, and 4 parameters to be found respectively, 
% considering the weight of the strategy as well. Therefore, the dimensionality 
% of the problem becomes 13, and each dimension is manipulated to belong between 
% the boundaries of each strategy. The following function shows an implementation 
% of the designed fitness function, which calculates the strategy of each indicator 
% and their weighted mixture. This mix strategy is evaluated against the 
% historical data, and the final return is used as fitness value.
%
function y = fitnessFunction(x)
  global asset;
  %bounds = [1000, 1000, 1000, 500, 500, 50, 50, 50, 500, 1, 1, 1, 1];
  bounds = [1000, 1000, 1000, 500, 500, 50, 1, 1, 1];
  MA_Strategy = SMA_strategy(asset, ceil(x(1)));
  DMA_Strategy = dualMovingAverageStrategy(asset, ceil(x(2)), ceil(x(3)));
  MACD_Strategy = MACDStrategy(asset, ceil(x(4)), ceil(x(5)), ceil(x(6)));
  %RSI_Strategy = rsiStrategy(asset, ceil(x(7)), 100 - ceil(x(8)), ceil(x(9)));
  Mix_Strategy = mixStrategies(x(end-2:end).*[MA_Strategy, DMA_Strategy, MACD_Strategy]);
  Mix_cumret = evaluateStrategy(asset, Mix_Strategy, 0.001);
  y = Mix_cumret(end);
end


%% A simple moving average (SMA) strategy
% 
% Finally, it is important to remember that any strategy we use has to be formulated 
% by considering only the previous price values of each tick. This means, that 
% no future price value can be known beforehand, and as we're considering the 
% close price of each tick, the current index is unknown until the tick ends, 
% or the new one starts. As an example, a simple strategy can be formulated 
% using the Moving Average (MA), which calculates the average price over a 
% certain window length $L$ of ticks, filtering the signal into a smoother 
% representation. A possible rule for this strategy is to buy every time the 
% tick close price cross over the MA line, and sell when it cross under it. 
% A simple moving average (SMA) strategy can be implemented as follows:
% ${MA}^{Strategy}_{i}(L) = \Biggm{\lbrace} \begin{array}{@{}ll@{}} 0, \quad i < L \\ 
% 1, \quad {MA}_{i-1}(L) > close_{i-1} \\ 
% -1, \quad otherwise \end{array}$

% parameters of the function:
% @asset = timeseries with close price
% @sliding_window = type of MOVAVG with [20 = lagging indicator, 3 = leading indicator]
%
function strategy = SMA_strategy(sliding_window)
global asset;
movAvg = movavg(asset.close, 'linear', sliding_window);
strategy = asset.close > movAvg;
% Correct that we bought when the day closes, so that day return
% is not counted and selling is apply on the close price of each day
strategy = [0; strategy(1:end-1)];
strategy(strategy==0) = -1;        % Use Short Orders

% Wait until %sliding_window ticks before starting. this is to allow MA to 
% calculate over the perior as defined in sliding_window variable
strategy(1:sliding_window) = 0;                 
                                                
end

%% Dual moving average
%
% using a Double Exponential Moving Average (DEMA) strategy requires at 
% least two parameters, being the window length of both EMAs. This strategy 
% considers a fast $(EMA(L_{fast}))$ and slow $(EMA(L_{slow}))$ signal, on which
% $L_{slow} > L_{fast}$ and positions are made when these price lines crosses 
% each other. This is strategy can be codified as follows:
% ${EMA}^{Strategy}_{i}(L) = \Biggm{\lbrace} \begin{array}{@{}ll@{}} 0, \quad i < L_{slow} \\ 
% 1, \quad {EMA}_{i-1}(L_{slow}) \geq EMA_{i-1}(L_{fast}) \\ 
% -1, \quad otherwise \end{array}$
%
function strategy = dualMovingAverageStrategy(slowWindow, fastWindow)
    global asset;
    slowMovAvg = movavg(asset.close, 'exponential', slowWindow);
    fastMovAvg = movavg(asset.close, 'exponential', fastWindow);
    strategy = slowMovAvg > fastMovAvg;
    strategy = [0; strategy(1:end-1)];
    strategy(strategy==0) = -1;
    strategy(1:slowWindow) = 0;
end

%% MACD
%
% MACD strategy requires at least three parameters, two exponential moving 
% averages window length of the asset price, and one for the difference between
% the first two EMAs. This strategy open a long position every time that the 
% MACD Line crosses the MACD Signal Line and the value of the MACD Line is 
% positive, and a short one when the opposite happens. Therefore, it does not 
% always has an active position like MA and DEMA. This behavior is intended 
% to avoid to open short positions on a bullish trend as explained in 
% https://tradingsim.com/blog/macd/
%
function strategy = MACDStrategy(slowMA, fastMA, ma)
    global asset;
    emaSlow = movavg(asset.close,'exponential', fastMA);
    emaFast = movavg(asset.close,'exponential', slowMA);
    MACDLine = emaFast - emaSlow;
    MACDSignalLine = movavg(MACDLine,'exponential', ma);
    MACDbars = MACDLine - MACDSignalLine;
    strategy = zeros(size(asset.close));
    strategy(MACDbars > 0 & MACDLine > 0) = 1;
    strategy(MACDbars < 0 & MACDLine < 0) = -1;
    strategy = [0; strategy(1:end-1)];
end

%%Local minima and maxima strategy
%
%
%
function strategy = MinMaxStrategy()
    global asset;

end
