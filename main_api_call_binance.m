%% main function to binance web calls
%
%

function [response,status] = main_api_call_binance(method, params)
    default_method_names={'time', 'klines', 'symbols', 'account_info'};
    default_method_types={@binance_time, @binance_klines, @binance_symbols, @binance_account_info};
    method_select=find(strcmp(method,default_method_names), 1);
    if isempty(method_select)
        disp('main_api_call_binance::wrong method name for binance, please try: '); disp(default_method_names);
        response='';
        status='';
    else
        [response, status]=default_method_types{method_select}(params);
    end
end

%% function to get binance server time
% inputs:
%       adTime: numerical in milli secs, adds an offset to the returned
%       time from server. If no param given then msecs from 1970 will be
%       added
% outputs:
%       server_time: string of millisecs returned from exchange
%       sever_time_formated: string with format dd-mm-yy hh:MM:ss
function [server_time, sever_time_formated] = binance_time(~)
    %if nargin<1
        adTime = datenum(1970,1,1); %milliseconds
    %end
    global platform_URL;
    server_time = 0;
    sever_time_formated = '';
    options = weboptions('UserAgent', 'Mozilla/5.0 (Windows NT 5.1; rv:19.0) Gecko/20100101 Firefox/19.0');

    try
        % check if platform is online, read time
        web_ret = webread([platform_URL '/api/v3/time'], options);
    catch ME    
        fprintf('binance_time::Connection to binance server failed with error->%s\n', ME.identifier);
        return;
    end
    
    tm = web_ret.serverTime;
    server_time = num2str(tm);
    sever_time_formated = datestr(tm/86400/1000 + datenum(1970,1,1));
end

%% function to get exchangeInfo like symbols, symbol info, trading rules  
% inputs: ~
%
% outputs:
%       symbols: 20x1 struct with symbol infos
function [symbols, ret] = binance_symbols(~)
   global platform_URL;
   ret = 0;
   try
        % check if platform is online, read time
        web_ret = webread([platform_URL '/api/v3/exchangeInfo']);
    catch ME    
        fprintf('binance_symbols::Connection to binance server failed with error->%s\n', ME.identifier);
        symbols = 0;
        return;
   end
    options = weboptions('UserAgent', 'Mozilla/5.0 (Windows NT 5.1; rv:19.0) Gecko/20100101 Firefox/19.0');
    web_ret = webread([platform_URL '/api/v3/exchangeInfo'], options);
    symbols = web_ret.symbols;
end

%% function to get klines/candles from binance
% inputs:
%       traiding_pair: string with supported traiding pair. Check if
%                       traiding pair is supported by the exchange first ... 
%                       before you request candles/klines
%       interval: string of time period for each candle ['1m', '5m', '15m', ...
%                '30m', '1h', '3h', '6h', '12h', '1D', '7D', '14D', '1M']
%       limit: double, number of last klines/candles to be retrieved
% outputs: time_table_klines
% The response storage in data contains a timetable matrix of 9 columns and 
% number of ticks defined in limit variable, 
% with the information of the : datetime(date'), open, high, low, close, 
% vol, Quote_asset_volume, num_trades, Taker_buy_quote_asset_volume. This information is more useful in
% a timetable object, which allows a more handy way of manipulating the data, 
% like sorting using the Time column. The following function can be used to 
% obtain the timetable object with the lastest price action of the indicated 
% market ("BTCUSD" for example) and desired interval ("1h" for example).
% if reading from exchange failed then function returns 0. 
% Terminology:
% $\textit{base}$ asset refers to the asset that is the $\textit{quantity}$ of a 
%    symbol. For the symbol BTCUSDT, BTC would be the $\textit{base asset}$.
% $\textit{quote}$ asset refers to the asset that is the $\textit{price}$ of a
%    symbol. For the symbol BTCUSDT, USDT would be the $\textit{quote asset}$.

function [time_table_klines, ret] = binance_klines(params)
    global platform_URL;
    tt = 0;
    ret = 0;
    if size(params)~= 3
        disp('binance_klines::not enough arguments');
    end
    traidingpair = params(1);
    interval = params(2);
    limit = params(3);

    urlTemp = sprintf('%s%s',platform_URL, '/api/v3/klines');
    options = weboptions('UserAgent', 'Mozilla/5.0 (Windows NT 5.1; rv:19.0) Gecko/20100101 Firefox/19.0');
    try
        data = webread(urlTemp,'symbol', traidingpair, 'interval', interval, 'limit', limit, options);
    catch ME    
        fprintf('binance_klines::Retreiving traiding pair data from Binance failed with->%s\n', ME.identifier);
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
        tt = timetable(datetime(date'), open, high, low, close, vol, Quote_asset_volume, num_trades, Taker_buy_quote_asset_volume);
        tt = sortrows(tt, 'Time');
        tt = unique(tt);
        fprintf('binance_klines::Number of candles received->%i\n', i);
    catch ME
        disp('binance_klines::Processing of traiding pair data failed with stack dump:');
        ME.stack
    end
    time_table_klines = tt;
end

%% function to get personal account info 
% inputs:
%
% outputs:
%       account_info: struct with:
% {
%   "makerCommission": 15,
%   "takerCommission": 15,
%   "buyerCommission": 0,
%   "sellerCommission": 0,
%   "canTrade": true,
%   "canWithdraw": true,
%   "canDeposit": true,
%   "updateTime": 123456789,
%   "accountType": "SPOT",
%   "balances": [
%     {
%       "asset": "BTC",
%       "free": "4723846.89208129",
%       "locked": "0.00000000"
%     },
%     {
%       "asset": "LTC",
%       "free": "4763368.68006011",
%       "locked": "0.00000000"
%     }
%   ],
%     "permissions": [
%     "SPOT"
%   ]
% }
function [account_info, ret] = binance_account_info(~)
    global spotAPI_URL;
    ret = 0;
    recvwindow = 5000; % 5 secs windows signature to be valid

    %urlTemp = sprintf('%s%s',spotAPI_URL, '/api/v3/account');
    
    [server_time, ~] = binance_time();
    fprintf('binance_account_info::server time in ms->%s\n', server_time);
    if server_time == 0
        account_info = 0;
        disp('binance_account_info::No server time retrieved->exiting');
        return;
    end
    
    [key, secret] = key_secret('binance');
    if key == 0
        disp('binance_account_info::exiting\n');
        return;
    end
    
    query_string = ['recvWindow=' num2str(recvwindow) '&timestamp=' server_time];
    signature = char(crypto(query_string, secret, 'HmacSHA256'));
    url_ext = [ query_string '&signature=' signature];
    %urlTemp = [spotAPI_URL '/api/v3/account?' url_ext];
    urlTemp = [spotAPI_URL '/api/v3/account'];
    options = weboptions('HeaderFields',{'X-MBX-APIKEY' key}, 'ArrayFormat','json', 'UserAgent', 'Mozilla/5.0 (Windows NT 5.1; rv:19.0) Gecko/20100101 Firefox/19.0');
    % options = weboptions('ArrayFormat','json', 'UserAgent', 'AlgoTrader');
    try
        data = webread(urlTemp,'recvWindow', num2str(recvwindow),'timestamp', ...
            server_time, 'signature', signature, options);
        account_info = data;
    catch ME    
        fprintf('binance_klines::Retreiving traiding pair data from Binance failed with->%s\n', ME.identifier);
        ME
        account_info = 0;
        return;
    end
end