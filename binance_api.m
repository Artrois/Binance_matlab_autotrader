%% Matlab class with functions to access Binance API
% Copyright by Paul Wulf (paul.wulf@web.de)
% Reference API https://binance-docs.github.io/apidocs/spot/en/
% 
% Terminology:
% base asset refers to the asset that is the quantity of a symbol. For the symbol BTCUSDT, BTC would be the base asset.
% quote asset refers to the asset that is the price of a symbol. For the symbol BTCUSDT, USDT would be the quote asset.
classdef binance_api < handle 
    % we use handle as supercalls since the instance will be passed as a pointer/reference to a variable.
    % there two types of in-built superclasses: handle, value. Value is
    % default. For handle you need to excplicitley mention it for a new
    % class defintion to inherit from handle. 
    
    properties (Access = private)
        settings; % shall be instance of class binance_settings
        
        % containers.Map
        % map of SimpleClient instances. use keys(websocket_clients) to retrieve keys associated with client instances
        % usually a traidingpair STRING is used as a map key e.g. BTCUSDT
        websocket_clients; 
        
        % containers.Map
        % map of timetables with klines. Candles can have different intervals which
        % will be defined first time the get_klines function is called.
        % usually a traidingpair STRING is used as a map key e.g. BTCUSDT
        time_table_klines;
        
        % containers.Map
        % map of kline intervals, STRING
        % usually a traidingpair STRING is used as a map key e.g. BTCUSDT
        kline_intervals;
        
        % containers.Map
        % timetable with ticks within given interval. when subscribed to
        % websocket for klines update, it sends every 2secs an update of a
        % current kline. This table holds all ticks per 2 secs until the
        % current kline within kline_interval is closed and transferrred to
        % time_table_klines. We use the 2secs ticks to implement
        % strategies which shall detect short term spikes and whale trades
        % which would occur within min kline limit (means <1m kline limit).
        % usually a traidingpair STRING is used as a map key e.g. BTCUSDT.
        time_table_intra_kline_ticks;
        
        % containers.Map
        % map of callback functions for kline timetable updates.
        % Callbackfunction and callbackID will be stored in a map
        % as a struct.{clbFunc, parentObj}
        callback_kline_func_map;
        
    end
    
    properties (Constant)
       %***side
        BUY = 'BUY'
        SELL = 'SELL'
        
        %***%order type
        MARKET = 'MARKET'
            %additional mandatory paramenters for market order
            quantity = 'quantity'
            %or
            quoteOrderQty = 'quoteOrderQty'
        LIMIT = 'LIMIT'
            %additional mandatory paramenters for limit order
            %quantity = 'quantity'
            timeInForce = 'timeInForce'
            price = 'price'
        %will execute a market sell order 
        STOP_LOSS = 'STOP_LOSS'
            %additional mandatory paramenters 
            %quantity = 'quantity'
            stopPrice = 'stopPrice'
        %will execute a market order. Dont forget to define side = [SELL | BUY] 
        TAKE_PROFIT = 'TAKE_PROFIT'
            %additional mandatory paramenters 
            %quantity = 'quantity'
            %stopPrice = 'stopPrice'            
    end
    
    methods (Access = private)
        
        %% kline callback function for websocket client
        % receives kline updates every 2secs = intra-klines.
        % it keep updating 
        function processWSSklineMessage(parentObj, msg)
            % This function simply displays the message received
            fprintf('%s binance_api::processWSSklineMessage(): Message received:\n%s\n',datetime('now'), msg);
            try
                klines_struct = jsondecode(msg);
                symbol = string(klines_struct.s);
                intrakline_time = datetime(datestr(klines_struct.E/86400/1000 + datenum(1970,1,1)));
                kline_close_time = datetime(datestr(klines_struct.k.T/86400/1000 + datenum(1970,1,1)));
                %return % the below portion not yet finished
                
                Open = klines_struct.k.o;
                High = klines_struct.k.h;
                Low = klines_struct.k.l;
                Close = klines_struct.k.c;
                vol = klines_struct.k.v;
                Quote_asset_volume = klines_struct.k.q;
                num_trades = klines_struct.k.n;
                Taker_buy_quote_asset_volume = klines_struct.k.Q;
                tt = timetable(intrakline_time, Open, High, Low, Close, vol, Quote_asset_volume, num_trades, Taker_buy_quote_asset_volume);
                        
                % check if intra-kline is closed/reached limit time
                % for us it means we start new intra kline collection of
                % intra kline ticks
                if klines_struct.k.x
                    % remove timetable for intr-klines
                    tt_intraklines = parentObj.time_table_intra_kline_ticks(symbol);
                    tt_intraklines(:,:) = [];
                    parentObj.time_table_intra_kline_ticks(symbol) = tt_intraklines;
                    % add same entry to time_table_klines

                    if ~isempty(parentObj.time_table_klines)
                        % indexing timetable
                        tt_klines = parentObj.time_table_klines(symbol);
                        tt_klines(kline_close_time, :) = {Open, High, Low, Close, vol, Quote_asset_volume, num_trades, Taker_buy_quote_asset_volume};
                        tt_klines = sortrows(tt_klines, 'Time');
                        tt_klines = unique(tt_klines);
                        parentObj.time_table_klines(symbol) = tt_klines;
                    else
                        % TODO: need to handle a situation where no klines
                        % received and websocket gets its first intra-kline
                        % that is at the same time also closed and shall go
                        % into time_table_klines. Eventually you would need
                        % to run unique(tt) when next time a new tick is
                        % added.
                        parentObj.time_table_klines(symbol) = tt;
                    end
                    
                    % trigger callback functions to notify an update in
                    % klines
                    parentObj.notifyKlineCallbacks(parentObj);
                else
                
                    % check if we first time received intra-kline tick
                    if ~isKey(parentObj.time_table_intra_kline_ticks, symbol)
                        % add new tick
                        parentObj.time_table_intra_kline_ticks(symbol) = tt;
    %                     intrakline_time = datetime(datestr(klines_struct.E/86400/1000 + datenum(1970,1,1)));
    %                     tt = timetable(datetime(date'), open, high, low, close, vol, Quote_asset_volume, num_trades, Taker_buy_quote_asset_volume);
    %                     tt = sortrows(tt, 'Time');
    %                     tt = unique(tt);
                    else
                        % append new tick
                        % indexing timetable
                        tt_klines = parentObj.time_table_intra_kline_ticks(symbol);
                        tt_klines(intrakline_time, :) = {Open, High, Low, Close, vol, Quote_asset_volume, num_trades, Taker_buy_quote_asset_volume};
                        tt_klines = sortrows(tt_klines, 'Time');
                        tt_klines = unique(tt_klines);
                        parentObj.time_table_intra_kline_ticks(symbol) = tt_klines;
                    end
                    
                end
                

            catch ME    
                fprintf('binance_api::processWSSklineMessage: processing of websocket message failed with error ->%s\n received msg: %s\n', ME.identifier, msg);
            end

        end
        
        %% Register a call back function for kline timetable updates
        % Call back function will be executed once kline timetable is
        % updated. Callbackfunction and callbackID will be stored in a map
        % as a struct.{clbFunc, parentObj}
        % inputs:
        %       clbFunc: MANDATORY (function_handle) will be invoked as clbFunc(parent, kline_cell_array)
        %       clbFuncID: MANDATORY (STRING) unique ID to identify the call back function
        %       parent: MANDATORY parent object that will be passed to the clbFunc
        %       along with the received message
        %
        function setCallBackKlines(self, clbFuncID, clbFunc, parent)
            if nargin < 4
                warning('binance_api::setCallBackKlines(): not enough arguments');
                return 
            end
            clbStruct.clbFunc = clbFunc;
            clbStruct.parentObj = parent;
            if isKey(self.callback_kline_func_map, clbFuncID)
                fprintf('binance_api::setCallBackKlines(): callback with ID %s already exist => replacing with new one \n', clbFuncID);
            end
            self.callback_kline_func_map(clbFuncID) = clbStruct;
        end
        
        %% De-register a callback function from kline timetable updates
        % inputs:
        %       clbFuncID: MANDATORY (STRING) unique ID to identify the call back function
        % 
        function unsetCallBackKlines(self, clbFuncID)
            if nargin < 2
                warning('binance_api::unsetCallBackKlines(): not enough arguments');
                return 
            end
            if isKey(self.callback_kline_func_map, clbFuncID)
                remove(self.callback_kline_func_map, clbFuncID);
            else
                fprintf('binance_api::unsetCallBackKlines(): callback ID %s not found\n', clbFuncID);
            end
        end
        
        %% function usually called to notify callback functions about updated klines
        % see processWSSklineMessage()
        function notifyKlineCallbacks(self)
            valueSet = values(self.callback_kline_func_map);
            for i=1:size(self.callback_kline_func_map, 1)
                clbStruct = valueSet{1, i};
                clbStruct.clbFunc(clbStruct.parentObj);
            end
        end
    end
    
    methods
        %% destructor
        % deletes objects/websockets
        function delete(obj)
            obj.close_WSS_client();
        end
        
        %% function to close specific web socket and to delete it from the map container
        % inputs:
        %       key: string with unique key to the WSS client to be closed
        %           if key is empty all websockets will be closed
        %           you will need to create new WSS clients once
        %           closed/deleted. Key is usually a crypto trainding pair e.g. BTCUSDT
        function close_WSS_client(self, key)
            if ~isa(self.websocket_clients, 'containers.Map')
                warning('binance_api::close_WSS_socket(): binance_api::websocket_clients not an instance of containers.Map -> abort');
                return
            end
            if size(self.websocket_clients,1) == 0
                disp('binance_api::close_WSS_socket(): no WSS Clients to close');
                return
            end
            if  nargin < 2
                array_of_keys = keys(self.websocket_clients);
                for i = 1:size(self.websocket_clients,1)
                    wss_client = self.websocket_clients(array_of_keys{i});
                    delete(wss_client);
                    remove(self.websocket_clients, array_of_keys{i});
                end
                
            else
                wss_client = self.websocket_clients(key);
                delete(wss_client); 
                remove(self.websocket_clients, key);
            end
        end
        
        %% function to get a list of client names/keys
        % inputs:
        %       
        % outputs:
        %       list_of_client_keys: cell array of key/client names 
        function [list_of_client_keys] = list_WSS_clients(self)
            if ~isa(self.websocket_clients, 'containers.Map')
                warning('binance_api::close_WSS_socket(): binance_api::websocket_clients not an instance of containers.Map -> abort');
                return
            end
            list_of_client_keys = keys(self.websocket_clients);
        end
        
        %% binance_api constructor
        % gets parameter as instance of binance_settings
        function self = binance_api(settings_object)
            %BINANCE_API Construct an instance of this class
            %   Detailed explanation goes here
            if isa(settings_object, "binance_settings")
                self.settings = settings_object;
                self.websocket_clients = containers.Map;
                self.kline_intervals = containers.Map;
                self.time_table_klines = containers.Map;
                self.time_table_intra_kline_ticks = containers.Map;
                self.callback_kline_func_map = containers.Map;
            else
                ME = MException('binance_api:noSuchObject', ...
                        'Passed object not instance of binance_settings');
                throw(ME)
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
        function [server_time, sever_time_formated] = get_time(self)
            %if nargin<1
                adTime = datenum(1970,1,1); %milliseconds
            %end
            platform_URL = self.settings.get_API_URL();
            server_time = 0;
            sever_time_formated = '';
            options = weboptions('UserAgent', 'Mozilla/5.0 (Windows NT 5.1; rv:19.0) Gecko/20100101 Firefox/19.0');

            try
                % check if platform is online, read time
                web_ret = webread([platform_URL '/api/v3/time'], options);
            catch ME    
                fprintf('get_time::Connection to binance server failed with error->%s\n', ME.identifier);
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
        %       symbols: array of structs
        %     [
        %       "symbol": "ETHBTC",
        %       "status": "TRADING",
        %       "baseAsset": "ETH",
        %       "baseAssetPrecision": 8,
        %       "quoteAsset": "BTC",
        %       "quotePrecision": 8,
        %       "quoteAssetPrecision": 8,
        %       "orderTypes": [
        %         "LIMIT",
        %         "LIMIT_MAKER",
        %         "MARKET",
        %         "STOP_LOSS",
        %         "STOP_LOSS_LIMIT",
        %         "TAKE_PROFIT",
        %         "TAKE_PROFIT_LIMIT"
        %       ]

        function [symbols] = get_symbols(self)
           platform_URL = self.settings.get_API_URL();

           try
                options = weboptions('UserAgent', 'Mozilla/5.0 (Windows NT 5.1; rv:19.0) Gecko/20100101 Firefox/19.0');
                %/api/v3/ticker/price
                %endpoint /api/v3/exchangeInfo provides limited list of
                %symbols. Hence we need to use ticker/price endpoint
                web_ret = webread([platform_URL '/api/v3/exchangeInfo'], options);
                symbols = web_ret.symbols;
            catch ME    
                fprintf('get_symbols::Connection to binance server failed with error->%s\n', ME.identifier);
                symbols = 0;
                return;
           end

        end
        
                
        
        %% function to convert interval value e.g. '1m', '5m', '15m', '30m', 
        % '1h', '3h', '6h', '12h', '1D', '1W', '14D', '1M'
        % to epoch consumable values in milliseconds
        function [interval_millisecs] = limit_to_millisecs(self, interval)
            interval_millisecs = double(60 * 1000);
            switch interval
               case '1m'
                  interval_millisecs = 60 * 1000;
               case '5m'
                  interval_millisecs = 5 * 60 * 1000;
               case '15m'
                  interval_millisecs = 15 * 60 * 1000;
               case '30m'
                  interval_millisecs = 30 * 60 * 1000;
               case '1h'
                  interval_millisecs = 60 * 60 * 1000;
               case '3h'
                  interval_millisecs = 3 * 60 * 60 * 1000;
               case '6h'
                  interval_millisecs = 6 * 60 * 60 * 1000;
               case '12h'
                  interval_millisecs = 12 * 60 * 60 * 1000;
               case '1D'
                  interval_millisecs = 24 * 60 * 60 * 1000;
               case '1W'
                  interval_millisecs = 7 * 24 * 60 * 60 * 1000;
               case '14D'
                  interval_millisecs = 14 * 24 * 60 * 60 * 1000;
               case '1M'
                  interval_millisecs = 4 * 7 * 24 * 60 * 60 * 1000;            
                otherwise
                  interval_millisecs = 60 * 1000;
                  warning('bitfinex_api::limit_to_millisecs(): interval ' + interval + ' not supported. Return default 1m');
            end
        end
        
        %% function to convert datetime to epoch
        % epoch time is "Number of milliseconds since 1-Jan-1970 00:00:00 UTC"
        % inputs date_time: 25-Mar-2019 12:48:59
        %
        % outputs:
        %       epoch_time: milliseconds(date_time - datetime(1970,1,1))
        function [epoch_time] = datetime_to_epoch(self, date_time)
            epoch_time = milliseconds(date_time - datetime(1970,1,1));
        end
        
        %% function to convert epoch to datetime
        % epoch time is "Number of milliseconds since 1-Jan-1970 00:00:00 UTC"
        % inputs epoch_time: in milliseconds since 1-Jan-1970 00:00:00 UTC
        %
        % outputs:
        %       date_time: 25-Mar-2019 12:48:59
        function [date_time] = epoch_to_datetime(self, epoch_time)
            %dnow = datetime('now');
            date_time = datetime(epoch_time,'ConvertFrom','epochtime','TicksPerSecond',1000);
        end
     
        
        %% function to get klines/candles from binance
        % inputs:
        %       traiding_pair: string with supported traiding pair. Check if
        %                       traiding pair is supported by the exchange first ... 
        %                       before you request candles/klines
        %       interval: string of time period for each candle ['1m', '5m', '15m', ...
        %                '30m', '1h', '3h', '6h', '12h', '1D', '7D', '14D', '1M']
        %       start: double, epoch time to start retrieving klines in
        %               millisecs
        %       end: double, time to start retrieving klines in millisecs
        %       limit: double, number of last klines/candles to be
        %               retrieved. If not set 600 will be taken. Max is
        %               1000
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

        function [time_table_klines] = get_klines(self, traiding_pair, interv, start, ende, limt)
            platform_URL = self.settings.get_API_URL();
            platform_URL = 'https://api.binance.com';
            tt = 0;
            if nargin < 3
                disp('binance_api::get_klines(): not enough arguments');
            end
            params = {'symbol', char(traiding_pair), 'interval', char(interv)};
            
            if nargin == 4
                error("binance_api::get_klines(): not enough arguments");
            end

            if (nargin == 5) || (nargin == 6)
                params = {params{:}, 'startTime', num2str(start)};%, 'endTime', num2str(ende)};
            end
            if nargin == 6
                if limt > 1000, warning("binance_api::get_klines(): limit >1k, set to 1k");limt=1000; end
                params = {params{:}, 'limit', num2str(limt)};
            end
                    
            %traidingpair = char(traiding_pair);
            %interval = char(interv);
            
            % check if klines for same interval and same traiding pair
            % already requested and available in local variable self.time_table_klines
            % if available then dont request klines from exchange and
            % return stored klines (self.time_table_klines).
            if isKey(self.kline_intervals, traiding_pair)
                stored_interval = self.kline_intervals(traiding_pair);
            else
                stored_interval = "";
            end
            if isKey(self.time_table_klines, traiding_pair) && strcmp(stored_interval, interv)
                % if TRUE then we have the pair and interval already
                % stored. Just return it as parameter
                time_table_klines = self.time_table_klines(traiding_pair);
                %return % not nice, but should be fine for now. we can optimize later
            else          
                urlTemp = sprintf('%s%s',platform_URL, '/api/v3/klines');
                options = weboptions('UserAgent', 'Mozilla/5.0 (Windows NT 5.1; rv:19.0) Gecko/20100101 Firefox/19.0');
                try
                    data = webread(urlTemp, params{:}, options);
                catch ME    
                    fprintf('get_klines::Retreiving traiding pair data from Binance failed with->%s\n', ME.identifier);
                    %q = string({urlTemp, params{:}});a = strjoin(q, {'?', '=', '&', '=', '&', '='})
                    return;
                end
                sz = size(data);
                date = datetime.empty(sz(1), 0);Open = zeros(sz(1), 1); Close = zeros(sz(1), 1);High = zeros(sz(1), 1);
                Low = zeros(sz(1), 1);vol = zeros(sz(1), 1);Quote_asset_volume = zeros(sz(1), 1);
                num_trades = zeros(sz(1), 1); Taker_buy_quote_asset_volume = zeros(sz(1), 1);
                try
                    for i = 1:sz(1)
                        tmp = data{i};
                        date(i) = datetime(datestr(tmp{7}/86400/1000 + datenum(1970,1,1)));
                        Open(i) = str2double(tmp{2});
                        Close(i) = str2double(tmp{5});
                        High(i) = str2double(tmp{3});
                        Low(i) = str2double(tmp{4});
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
                    tt = timetable(datetime(date'), Open, High, Low, Close, vol, Quote_asset_volume, num_trades, Taker_buy_quote_asset_volume);
                    tt = sortrows(tt, 'Time');
                    tt = unique(tt);

                    % save the data linked to the traidingpair
                    self.kline_intervals(traiding_pair) = interv;
                    self.time_table_klines(traiding_pair) = tt;
                    
                    % if neither klines for traiding pair nor the suitable interval is avialable then
                    % we initiate websocket client and start receiving 2sec
                    % kline updates and to start filling self.time_table_intra_kline_ticks
                    % and we proceed to receive klines from the exchange
                    %%%%%% self.ws_get_klines(traiding_pair, interv);

                    fprintf('get_klines::Number of candles received->%i\n', i);
                catch ME
                    disp('get_klines::Processing of traiding pair data failed with stack dump:');
                    ME.stack
                end
                time_table_klines = tt;
            end
        end
        
        %% function to open websocket to klines/candles on binance
        % inputs:
        %       traiding_pair: string with supported traiding pair. Check if
        %                       traiding pair is supported by the exchange first ... 
        %                       before you request candles/klines
        %       interval: string of time period for each candle ['1m', '5m', '15m', ...
        %                '30m', '1h', '3h', '6h', '12h', '1D', '7D', '14D', '1M']
        % outputs: ~
        % update speed: 2000ms
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
        % Received json stream will be decoded to cell array using
        % jsondecode():
        % {
        %   "e": "kline",     // Event type
        %   "E": 123456789,   // Event time
        %   "s": "BNBBTC",    // Symbol
        %   "k": {
        %     "t": 123400000, // Kline start time
        %     "T": 123460000, // Kline close time
        %     "s": "BNBBTC",  // Symbol
        %     "i": "1m",      // Interval
        %     "f": 100,       // First trade ID
        %     "L": 200,       // Last trade ID
        %     "o": "0.0010",  // Open price
        %     "c": "0.0020",  // Close price
        %     "h": "0.0025",  // High price
        %     "l": "0.0015",  // Low price
        %     "v": "1000",    // Base asset volume
        %     "n": 100,       // Number of trades
        %     "x": false,     // Is this kline closed?
        %     "q": "1.0000",  // Quote asset volume
        %     "V": "500",     // Taker buy base asset volume
        %     "Q": "0.500",   // Taker buy quote asset volume
        %     "B": "123456"   // Ignore
        %   }
        % }
        function [] = ws_get_klines(self, traiding_pair, interv)
            platform_URL = self.settings.get_websocket_URL();

            if nargin < 3
                disp('get_klines::not enough arguments');
            end
            traidingpair = lower(traiding_pair);
            interval = interv;

            urlTemp = sprintf('%s/%s@kline_%s',platform_URL, traidingpair, interval);
            if isKey(self.websocket_clients, traiding_pair)
                fprintf('binance_api::ws_get_klines(): WSS client for traiding pair %s already exist -> replace with new one\n', traiding_pair);
                wss_client = self.websocket_clients(traiding_pair);
                delete(wss_client);
            end
            
            try
                % wss_client = SimpleClient('wss://stream.binance.com:9443/ws/btcusdt@kline_15m');
                wss_client = SimpleClient(urlTemp);
                self.websocket_clients(traiding_pair) = wss_client;
                wss_client.setCallBack(@processWSSklineMessage, self); % register call back func
                wss_client.open(); % connect to server
              
            catch ME    
                fprintf('ws_get_klines::Creating websocket client failed with->%s\n', ME.identifier);
                return;
            end
            
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
        %           balances: 8x3 cell array of balances with:
        %       asset           balance             locked
        %     {'BNB' }    {'1000.00000000'  }    {'0.00000000'}
        %     {'BTC' }    {'1.00000000'     }    {'0.00000000'}
        %     {'BUSD'}    {'10000.00000000' }    {'0.00000000'}
        %     {'ETH' }    {'100.00000000'   }    {'0.00000000'}
        %     {'LTC' }    {'500.00000000'   }    {'0.00000000'}
        %     {'TRX' }    {'500000.00000000'}    {'0.00000000'}
        %     {'USDT'}    {'10000.00000000' }    {'0.00000000'}
        %     {'XRP' }    {'50000.00000000' }    {'0.00000000'}       
        function [account_info, balances] = get_account_info(self)
            spotAPI_URL = self.settings.get_API_URL();
            ret = 0;
            recvwindow = 5000; % 5 secs windows signature to be valid

            %urlTemp = sprintf('%s%s',spotAPI_URL, '/api/v3/account');

            [server_time, ~] = self.get_time();
            fprintf('get_account_info::server time in ms->%s\n', server_time);
            if server_time == 0
                account_info = 0;
                disp('get_account_info::No server time retrieved->exiting');
                return;
            end

            secret = self.settings.get_secret();
            key = self.settings.get_key();

            query_string = ['recvWindow=' num2str(recvwindow) '&timestamp=' server_time];
            signature = char(Message_Authentication_Code(query_string, secret, 'HmacSHA256'));
            url_ext = [ query_string '&signature=' signature];
            %urlTemp = [spotAPI_URL '/api/v3/account?' url_ext];
            urlTemp = [spotAPI_URL '/api/v3/account'];
            options = weboptions('HeaderFields',{'X-MBX-APIKEY' key}, 'ArrayFormat','json', 'UserAgent', 'Mozilla/5.0 (Windows NT 5.1; rv:19.0) Gecko/20100101 Firefox/19.0');
            % options = weboptions('ArrayFormat','json', 'UserAgent', 'AlgoTrader');
            try
                data = webread(urlTemp,'recvWindow', num2str(recvwindow),'timestamp', ...
                    server_time, 'signature', signature, options);
                account_info = data;
                balances = struct2cell(data.balances)';
            catch ME    
                fprintf('get_account_info::Retreiving traiding pair data from Binance failed with->%s\n', ME.identifier);
                ME
                account_info = 0;
                return;
            end
        end
        
        %% function to get list of my trades for a specific symbol
        % If fromId is set, it will get id >= that fromId. Otherwise most recent trades are returned.
        % inputs:
        %       symbol (MANDATORY): string with traiding pair
        %       startTime: long, time stamp starting with which to collect
        %                   the trades
        %       end Time: long, time until when to collect the trades
        %       fromId:   long, TradeId to fetch from. Default gets most recent trades.
        %       limit: int, Default 500; max 1000
        % you can omit optional inputs by using [] or '' as input parameter
        % to pass an empty parameter
        % outputs:
        %       myTrades: struct with:
        %  [
        %   {
        %     "symbol": "BNBBTC",
        %     "id": 28457,
        %     "orderId": 100234,
        %     "orderListId": -1, //Unless OCO, the value will always be -1
        %     "price": "4.00000100",
        %     "qty": "12.00000000",
        %     "quoteQty": "48.000012",
        %     "commission": "10.10000000",
        %     "commissionAsset": "BNB",
        %     "time": 1499865549590,
        %     "isBuyer": true,
        %     "isMaker": false,
        %     "isBestMatch": true
        %   }
        % ]   
        %       returns empty array [] if no trades or in case of an error.
        %       Use isempty() to check if there are returns
        function [trade_list] = get_my_account_trade_list(self, symbol, startTime, endTime, fromID, limit)
            spotAPI_URL = self.settings.get_API_URL();
            
            recvwindow = 5000; % 5 secs windows signature to be valid
            query_string_from_inputs = '';
            
            %process inputs
            switch nargin
                case 1
                    query_string_from_inputs = '';
                    warning('binance_api::get_my_account_trade_list(): symbol pair not set ->exit');
                    return
                case 2
                    % i kept two strings. One to calculate HMAC SHA256
                    % signature
                    if isempty(symbol)
                       warning('binance_api::get_my_account_trade_list(): symbol pair is empty ->exit');
                       return
                    end
                    query_string_from_inputs = ['symbol=' char(symbol) '&'];
                    query_str_tmp = {'symbol', char(symbol)};
                case 3
                    warning('binance_api::get_my_account_trade_list(): endTime argument not set->exit');
                    return
                case 4
                    if isempty(symbol)
                       warning('binance_api::get_my_account_trade_list(): symbol pair is empty ->exit');
                       return
                    end
                    query_string_from_inputs = ['symbol=' char(symbol) '&'];
                    query_str_tmp = {'symbol', char(symbol)};
                    % make sure endTime and startTime are double
                    if ~isempty(startTime) && ~isempty(endTime)
                        query_string_from_inputs = [query_string_from_inputs 'startTime=' num2str(startTime) '&endTime=' num2str(endTime) '&'];
                        query_str_tmp = {query_str_tmp{:}, 'startTime', num2str(startTime), 'endTime', num2str(endTime)};
                    else
                         warning('binance_api::get_my_account_trade_list(): endTime or startTime argument not double->skipping the arguments');
                    end                
                case 5
                    if isempty(symbol)
                       warning('binance_api::get_my_account_trade_list(): symbol pair is empty ->exit');
                       return
                    end
                    query_string_from_inputs = ['symbol=' char(symbol) '&'];
                    query_str_tmp = {'symbol', char(symbol)};
                    % make sure endTime and startTime are double
                    if ~isempty(startTime) && ~isempty(endTime)
                        query_string_from_inputs = [query_string_from_inputs 'startTime=' num2str(startTime) '&endTime=' num2str(endTime) '&'];
                        query_str_tmp = {query_str_tmp{:}, 'startTime', num2str(startTime), 'endTime', num2str(endTime)};
                    else
                         warning('binance_api::get_my_account_trade_list(): endTime or startTime argument not double->skipping the arguments');
                    end 
                    if ~isempty(fromID)
                        query_string_from_inputs = [query_string_from_inputs 'fromID=' num2str(fromID) '&'];
                        query_str_tmp = {query_str_tmp{:}, 'fromID', num2str(fromID)};
                    else
                         warning('binance_api::get_my_account_trade_list(): endTime or startTime argument not double->skipping the arguments');
                    end 
                case 6
                    if isempty(symbol)
                       warning('binance_api::get_my_account_trade_list(): symbol pair is empty ->exit');
                       return
                    end
                    query_string_from_inputs = ['symbol=' char(symbol) '&'];
                    query_str_tmp = {'symbol', char(symbol)};
                    % make sure endTime and startTime are double
                    if ~isempty(startTime) && ~isempty(endTime)
                        query_string_from_inputs = [query_string_from_inputs 'startTime=' num2str(startTime) '&endTime=' num2str(endTime) '&'];
                        query_str_tmp = {query_str_tmp{:}, 'startTime', num2str(startTime), 'endTime', num2str(endTime)};
                    else
                         warning('binance_api::get_my_account_trade_list(): endTime or startTime argument not double->skipping the arguments');
                    end 
                    if ~isempty(fromID)
                        query_string_from_inputs = [query_string_from_inputs 'fromID=' num2str(fromID) '&'];
                        query_str_tmp = {query_str_tmp{:}, 'fromID', num2str(fromID)};
                    else
                         warning('binance_api::get_my_account_trade_list(): endTime or startTime argument not double->skipping the arguments');
                    end 
                    if ~isempty(limit)
                        query_string_from_inputs = [query_string_from_inputs 'limit=' num2str(limit) '&'];
                        query_str_tmp = {query_str_tmp{:}, 'limit', num2str(limit)};
                    else
                         warning('binance_api::get_my_account_trade_list(): limit argument not double->skipping the argument');
                    end                     
                otherwise
                    warning('binance_api::get_my_account_trade_list(): too many arguments->skipping all of them');
                    %return
            end
            
            %urlTemp = sprintf('%s%s',spotAPI_URL, '/api/v3/account');

            [server_time, ~] = self.get_time();
            fprintf('get_my_account_trade_list::server time in ms->%s\n', server_time);
            if server_time == 0
                trade_list = 0;
                disp('get_my_account_trade_list::No server time retrieved->exiting');
                return;
            end

            secret = self.settings.get_secret();
            key = self.settings.get_key();

            query_string = [query_string_from_inputs 'recvWindow=' num2str(recvwindow) '&timestamp=' server_time];
            signature = char(Message_Authentication_Code(query_string, secret, 'HmacSHA256'));

            query_str_final = {query_str_tmp{:}, 'recvWindow', num2str(recvwindow),'timestamp', ...
                    server_time, 'signature', signature};
            urlTemp = [spotAPI_URL '/api/v3/myTrades'];
            options = weboptions('HeaderFields',{'X-MBX-APIKEY' key}, 'ArrayFormat','json', 'UserAgent', 'Mozilla/5.0 (Windows NT 5.1; rv:19.0) Gecko/20100101 Firefox/19.0');
            try
                data = webread(urlTemp, query_str_final{:}, options);
                trade_list = data;
            catch ME    
                fprintf('get_my_account_trade_list::Retreiving traiding pair data from Binance failed with->%s\n', ME.identifier);
                ME
                trade_list = [];
                return;
            end
        end       
 
        %% function to get list of my orders for a specific symbol
        % Get all account orders; active, canceled, or filled.
        % This shows the orders you placed to the market and the final
        % result/quoted value. It does not show partial fills. For partial
        % fills executed by the exchange/matching machine refer to Account
        % Trade List.
        % If fromId is set, it will get id >= that fromId. Otherwise most recent trades are returned.
        % inputs:
        %       symbol (MANDATORY): string with traiding pair
        %       startTime: long, time stamp starting with which to collect
        %                   the trades
        %       end Time: long, time until when to collect the trades
        %       fromId:   long, TradeId to fetch from. Default gets most recent trades.
        %       limit: int, Default 500; max 1000
        % you can omit optional inputs by using [] or '' as input parameter
        % to pass an empty parameter
        % outputs:
        %       all orders: struct with:
        % [
        %   {
        %     "symbol": "LTCBTC",
        %     "orderId": 1,
        %     "orderListId": -1, //Unless OCO, the value will always be -1
        %     "clientOrderId": "myOrder1",
        %     "price": "0.1",
        %     "origQty": "1.0",
        %     "executedQty": "0.0",
        %     "cummulativeQuoteQty": "0.0",
        %     "status": "NEW",
        %     "timeInForce": "GTC",
        %     "type": "LIMIT",
        %     "side": "BUY",
        %     "stopPrice": "0.0",
        %     "icebergQty": "0.0",
        %     "time": 1499827319559,
        %     "updateTime": 1499827319559,
        %     "isWorking": true,
        %     "origQuoteOrderQty": "0.000000"
        %   }
        % ]   
        % possible status values:
        % NEW                 The order has been accepted by the engine.
        % PARTIALLY_FILLED	A part of the order has been filled.
        % FILLED              The order has been completed.
        % CANCELED            The order has been canceled by the user.
        % PENDING_CANCEL      Currently unused
        % REJECTED            The order was not accepted by the engine and not processed.
        % EXPIRED             The order was canceled according to the order type's rules 
        %                     (e.g. LIMIT FOK orders with no fill, LIMIT IOC or MARKET 
        %                     orders that partially fill) or by the exchange, (e.g. orders 
        %                     canceled during liquidation, orders canceled during maintenance)        
        %
        %       returns empty array [] if no trades or in case of an error.
        %       Use isempty() to check if there are returns
        function [order_list] = get_all_my_orders(self, symbol, startTime, endTime, fromID, limit)
            spotAPI_URL = self.settings.get_API_URL();
            
            recvwindow = 5000; % 5 secs windows signature to be valid
            query_string_from_inputs = '';
            
            %process inputs
            switch nargin
                case 1
                    query_string_from_inputs = '';
                    warning('binance_api::get_all_my_orders(): symbol pair not set ->exit');
                    return
                case 2
                    % i kept two strings. One to calculate HMAC SHA256
                    % signature
                    if isempty(symbol)
                       warning('binance_api::get_all_my_orders(): symbol pair is empty ->exit');
                       return
                    end
                    query_string_from_inputs = ['symbol=' char(symbol) '&'];
                    query_str_tmp = {'symbol', char(symbol)};
                case 3
                    warning('binance_api::get_all_my_orders(): endTime argument not set->exit');
                    return
                case 4
                    if isempty(symbol)
                       warning('binance_api::get_all_my_orders(): symbol pair is empty ->exit');
                       return
                    end
                    query_string_from_inputs = ['symbol=' char(symbol) '&'];
                    query_str_tmp = {'symbol', char(symbol)};
                    % make sure endTime and startTime are double
                    if ~isempty(startTime) || ~isempty(endTime)
                        query_string_from_inputs = [query_string_from_inputs 'startTime=' num2str(startTime) '&endTime=' num2str(endTime) '&'];
                        query_str_tmp = {query_str_tmp{:}, 'startTime', num2str(startTime), 'endTime', num2str(endTime)};
                    else
                         warning('binance_api::get_all_my_orders(): endTime or startTime argument not double->skipping the arguments');
                    end                
                case 5
                    if isempty(symbol)
                       warning('binance_api::get_all_my_orders(): symbol pair is empty ->exit');
                       return
                    end
                    query_string_from_inputs = ['symbol=' char(symbol) '&'];
                    query_str_tmp = {'symbol', char(symbol)};
                    % make sure endTime and startTime are double
                    if ~isempty(startTime) || ~isempty(endTime)
                        query_string_from_inputs = [query_string_from_inputs 'startTime=' num2str(startTime) '&endTime=' num2str(endTime) '&'];
                        query_str_tmp = {query_str_tmp{:}, 'startTime', num2str(startTime), 'endTime', num2str(endTime)};
                    else
                         warning('binance_api::get_all_my_orders(): endTime or startTime argument not double->skipping the arguments');
                    end 
                    if ~isempty(fromID)
                        query_string_from_inputs = [query_string_from_inputs 'fromID=' num2str(fromID) '&'];
                        query_str_tmp = {query_str_tmp{:}, 'fromID', num2str(fromID)};
                    else
                         warning('binance_api::get_all_my_orders(): endTime or startTime argument not double->skipping the arguments');
                    end 
                case 6
                    if isempty(symbol)
                       warning('binance_api::get_all_my_orders(): symbol pair is empty ->exit');
                       return
                    end
                    query_string_from_inputs = ['symbol=' char(symbol) '&'];
                    query_str_tmp = {'symbol', char(symbol)};
                    % make sure endTime and startTime are double
                    if ~isempty(startTime) || ~isempty(endTime)
                        query_string_from_inputs = [query_string_from_inputs 'startTime=' num2str(startTime) '&endTime=' num2str(endTime) '&'];
                        query_str_tmp = {query_str_tmp{:}, 'startTime', num2str(startTime), 'endTime', num2str(endTime)};
                    else
                         warning('binance_api::get_all_my_orders(): endTime or startTime argument not double->skipping the arguments');
                    end 
                    if ~isempty(fromID)
                        query_string_from_inputs = [query_string_from_inputs 'fromID=' num2str(fromID) '&'];
                        query_str_tmp = {query_str_tmp{:}, 'fromID', num2str(fromID)};
                    else
                         warning('binance_api::get_all_my_orders(): endTime or startTime argument not double->skipping the arguments');
                    end 
                    if ~isempty(limit)
                        query_string_from_inputs = [query_string_from_inputs 'limit=' num2str(limit) '&'];
                        query_str_tmp = {query_str_tmp{:}, 'limit', num2str(limit)};
                    else
                         warning('binance_api::get_all_my_orders(): limit argument not double->skipping the argument');
                    end                     
                otherwise
                    warning('binance_api::get_all_my_orders(): too many arguments->skipping all of them');
                    %return
            end
            
            %urlTemp = sprintf('%s%s',spotAPI_URL, '/api/v3/account');

            [server_time, ~] = self.get_time();
            fprintf('get_all_my_orders::server time in ms->%s\n', server_time);
            if server_time == 0
                order_list = 0;
                disp('get_all_my_orders::No server time retrieved->exiting');
                return;
            end

            secret = self.settings.get_secret();
            key = self.settings.get_key();

            query_string = [query_string_from_inputs 'recvWindow=' num2str(recvwindow) '&timestamp=' server_time];
            signature = char(Message_Authentication_Code(query_string, secret, 'HmacSHA256'));

            query_str_final = {query_str_tmp{:}, 'recvWindow', num2str(recvwindow),'timestamp', ...
                    server_time, 'signature', signature};
            urlTemp = [spotAPI_URL '/api/v3/allOrders'];
            options = weboptions('HeaderFields',{'X-MBX-APIKEY' key}, 'ArrayFormat','json', 'UserAgent', 'Mozilla/5.0 (Windows NT 5.1; rv:19.0) Gecko/20100101 Firefox/19.0');
            try
                data = webread(urlTemp, query_str_final{:}, options);
                % change time stamp format to datetime
                for i=1:size(data, 1)
                    data(i, 1).time = datetime(datestr(data(i, 1).time/86400/1000 + datenum(1970,1,1)));
                    data(i, 1).updateTime = datetime(datestr(data(i, 1).updateTime/86400/1000 + datenum(1970,1,1)));
                end
                order_list = data;
            catch ME    
                fprintf('get_all_my_orders::Retreiving traiding pair data from Binance failed with->%s\n', ME.identifier);
                ME
                order_list = [];
                return;
            end
        end       
        
        
        %% function to get order book (also known as order depth) from binance
        % inputs:
        %       traiding_pair: string with supported traiding pair. Check if
        %                       traiding pair is supported by the exchange first ... 
        %                       before you request order book
        %       limit: double, quantity of orders in the order book to be returned, ...
        %               Default 100; max 5000. Valid limits:[5, 10, 20, 50, 100, 500, 1000, 5000]
        % outputs: 
        % {
        %   "lastUpdateId": 1027024,
        %   "bids": [
        %    [
        %       "4.00000000",     // PRICE
        %       "431.00000000"    // QTY
        %     ]
        %   ],
        %   "asks": [
        %     [
        %       "4.00000200",
        %       "12.00000000"
        %     ]
        %   ]
        % }
        function [order_book] = get_depth(self, traiding_pair, limit)
           platform_URL = self.settings.get_API_URL();
           urlTmp = [platform_URL '/api/v3/depth'];
           try
                options = weboptions('UserAgent', 'Mozilla/5.0 (Windows NT 5.1; rv:19.0) Gecko/20100101 Firefox/19.0');
                web_ret = webread(urlTmp, 'symbol', traiding_pair, 'limit', limit, options);
                order_book = web_ret;
            catch ME    
                fprintf('get_depth::Connection to binance server failed with error->%s\n', ME.identifier);
                order_book = 0;
                return;
           end
        end
        
        %% function to get Best price/qty on the order book for a symbol or symbols.
        % Best price/qty on the order book for a symbol or symbols.
        % inputs:
        %       symbol: string with supported traiding pair. Check if
        %                       traiding pair is supported by the exchange first ... 
        %                       before you place a request
        %       If the symbol is not sent, prices for all symbols will be returned in an array.
        % outputs: 
        % {
        %   "symbol": "LTCBTC",
        %   "bidPrice": "4.00000000",
        %   "bidQty": "431.00000000",
        %   "askPrice": "4.00000200",
        %   "askQty": "9.00000000"
        % }
        function [best_price] = get_best_price(self, traiding_pair)
           platform_URL = self.settings.get_API_URL();
           urlTmp = [platform_URL '/api/v3/ticker/bookTicker'];
           try
                options = weboptions('UserAgent', 'Mozilla/5.0 (Windows NT 5.1; rv:19.0) Gecko/20100101 Firefox/19.0');
                web_ret = webread(urlTmp, 'symbol', traiding_pair, options);
                best_price = web_ret;
            catch ME    
                fprintf('get_best_price::Connection to binance server failed with error->%s\n', ME.identifier);
                best_price = 0;
                return;
           end
        end
        
        %% function to get symbol price ticker
        % Latest price for a symbol or symbols
        % inputs:
        %       symbol: string with supported traiding pair. Check if
        %                       traiding pair is supported by the exchange first ... 
        %                       before you place a request
        %       If the symbol is not sent, prices for all symbols will be returned in an array.
        % outputs: 
        % {
        %   "symbol": "LTCBTC",
        %   "price": "4.00000200"
        % }
        function [latest_price] = get_price_ticker(self, traiding_pair)
           platform_URL = self.settings.get_API_URL();
           urlTmp = [platform_URL '/api/v3/ticker/price'];
           if nargin<2
               traiding_pair = '';
           end

           try
                options = weboptions('UserAgent', 'Mozilla/5.0 (Windows NT 5.1; rv:19.0) Gecko/20100101 Firefox/19.0');
               if ~isempty(traiding_pair)
                    queryParam = {'symbol', traiding_pair};
                    web_ret = webread(urlTmp, queryParam{:}, options);
               else
                    web_ret = webread(urlTmp, options);
               end

                latest_price = web_ret;
            catch ME    
                fprintf('get_price_ticker::Connection to binance server failed with error->%s\n', ME.identifier);
                latest_price = 0;
                return;
           end
        end

        %% function to place a new order
        % Send a new order to the exchange. Dont use it directly but rather 
        % implement dedicated frontrunner functions such as BUY/SELL which will call this function.
        % inputs:
        %       symbol (MANDATORY): string with traiding pair
        %       side   (MANDATORY): ENUM {BUY, SELL}
        %       type   (MANDATORY): ENUM {          
        %                      (type)               (additional mandatory params)
        %                       LIMIT               timeInForce, quantity, price
        %                       MARKET              quantity or quoteOrderQty
        %                       STOP_LOSS           quantity, stopPrice
        %                       STOP_LOSS_LIMIT     timeInForce, quantity, price, stopPrice
        %                       TAKE_PROFIT         quantity, stopPrice
        %                       TAKE_PROFIT_LIMIT	timeInForce, quantity, price, stopPrice
        %                       LIMIT_MAKER         quantity, price
        %                               }
        %       newClientOrderId:	STRING	A unique id among open orders.
        %                           newClientOrderId shall be of format:
        %                           [STRATEGYID_SYMBOL_timestamp]
        %                           Define it to allow later identification
        %                           of used strategy. 
        %
        %       (other intputs which you can pass in a cell array. The function
        %       will assemble them to a POST query. You need to send {param1, value1, param2, value2}. The array will be assembled to:
        %       param1=value1&param2=value2)
        %        timeInForce	ENUM	Valid values are GTC/FOK/IOC
        %                       {
        %                       GTC	Good Till Canceled, an order will be on the book unless the order is canceled.
        %                       IOC	Immediate Or Cancel, an order will try to fill the order as much as it can before the order expires.
        %                       FOK	Fill or Kill, An order will expire if the full order cannot be filled upon execution.
        %                       }
        %
        %        quantity	DECIMAL		quantity of base asset for BTCUSDT it is BTC
        %        quoteOrderQty	DECIMAL	for BUY side, the order will buy as many BTC as quoteOrderQty USDT can	
        %                               for SELL side, SELL side, the order will sell as much BTC needed to receive quoteOrderQty USDT
        %        price	DECIMAL	
        %        stopPrice	DECIMAL	Used with STOP_LOSS, STOP_LOSS_LIMIT, TAKE_PROFIT, and TAKE_PROFIT_LIMIT orders.
        % outputs:
        %       FULL_RESPONSE: struct with:
        % {
        %   "symbol": "BTCUSDT",
        %   "orderId": 28,
        %   "orderListId": -1, //Unless OCO, value will be -1
        %   "clientOrderId": "6gCrw2kRUAF9CvJDGP16IP",
        %   "transactTime": 1507725176595,
        %   "price": "0.00000000",
        %   "origQty": "10.00000000",
        %   "executedQty": "10.00000000",
        %   "cummulativeQuoteQty": "10.00000000",
        %   "status": "FILLED",
        %   "timeInForce": "GTC",
        %   "type": "MARKET",
        %   "side": "SELL",
        %   "fills": [
        %     {
        %       "price": "4000.00000000",
        %       "qty": "1.00000000",
        %       "commission": "4.00000000",
        %       "commissionAsset": "USDT"
        %     },
        %     {
        %       "price": "3999.00000000",
        %       "qty": "5.00000000",
        %       "commission": "19.99500000",
        %       "commissionAsset": "USDT"
        %     },
        %     {
        %       "price": "3998.00000000",
        %       "qty": "2.00000000",
        %       "commission": "7.99600000",
        %       "commissionAsset": "USDT"
        %     },
        %     {
        %       "price": "3997.00000000",
        %       "qty": "1.00000000",
        %       "commission": "3.99700000",
        %       "commissionAsset": "USDT"
        %     },
        %     {
        %       "price": "3995.00000000",
        %       "qty": "1.00000000",
        %       "commission": "3.99500000",
        %       "commissionAsset": "USDT"
        %     }
        %   ]
        % }
        %       returns empty array [] if no trades or in case of an error.
        %       Use isempty() to check if there are returns
        function [new_order_details] = place_new_order(self, symbol, side, type, newClientOrderId, cell_array_of_params)
            spotAPI_URL = self.settings.get_API_URL();
            
            recvwindow = 5000; % 5 secs windows signature to be valid
            query_string_from_inputs = '';
            
            %process inputs
            switch nargin
                case 1:4
                    new_order_details = [];
                    warning('binance_api::place_new_order(): not enough arguments passed ->exit');
                    return
                case 5
                    % i kept two strings. One to calculate HMAC SHA256
                    % signature
                    if (isempty(symbol) || isempty(side) || isempty(type) || isempty(newClientOrderId)) 
                       new_order_details = [];
                       warning('binance_api::place_new_order(): one or more input parameters are empty ->exit');
                       return
                    end
                    query_string_from_inputs = ['symbol=' char(symbol) '&side=' char(side) '&type=' char(type) '&newClientOrderId=' char(newClientOrderId)];
                    query_str_tmp = {'symbol', char(symbol), 'side', char(side), 'type', char(type), 'newClientOrderId', char(newClientOrderId)};
                case 6
                    % i kept two strings. One to calculate HMAC SHA256
                    % signature
                    if (isempty(symbol) || isempty(side) || isempty(type) || isempty(newClientOrderId)) 
                       new_order_details = [];
                       warning('binance_api::place_new_order(): one or more input parameters are empty ->exit');
                       return
                    end
                    query_string_from_inputs = ['symbol=' char(symbol) '&side=' char(side) '&type=' char(type) '&newClientOrderId=' char(newClientOrderId) '&'];
                    query_str_tmp = {'symbol', char(symbol), 'side', char(side), 'type', char(type), 'newClientOrderId', char(newClientOrderId)};
                    if ~isa(cell_array_of_params, 'cell')
                        warning('binance_api::place_new_order(): last argument is passed to func but it is not a cell array ->exit');
                        return
                    end
                    if size(cell_array_of_params, 2) < 2
                        warning('binance_api::place_new_order(): last argument is passed to func but its size < 2 ->exit');
                        return                        
                    end
                    
                    % assemble the arrays for signature and for the API
                    % query
                    query_str_tmp = {query_str_tmp{:}, cell_array_of_params{:}};
                    for i=1:2:size(cell_array_of_params, 2)
                        query_string_from_inputs = sprintf('%s%s=%s&', query_string_from_inputs, cell_array_of_params{i}, cell_array_of_params{i+1});
                    end
                               
                otherwise
                    new_order_details = [];
                    warning('binance_api::place_new_order(): too many arguments, expected 5 arguments ->exit');
                    return
            end
            

            [server_time, ~] = self.get_time();
            fprintf('binance_api::place_new_order(): server time in ms->%s\n', server_time);
            if server_time == 0
                new_order_details = 0;
                disp('binance_api::place_new_order(): No server time retrieved->exiting');
                return;
            end

            secret = self.settings.get_secret();
            key = self.settings.get_key();

            query_string = [query_string_from_inputs 'recvWindow=' num2str(recvwindow) '&timestamp=' server_time];
            signature = char(Message_Authentication_Code(query_string, secret, 'HmacSHA256'));

            query_str_final = {query_str_tmp{:}, 'recvWindow', num2str(recvwindow),'timestamp', ...
                    server_time, 'signature', signature};
            urlTemp = [spotAPI_URL '/api/v3/order']; % /api/v3/order/test
            options = weboptions('HeaderFields',{'X-MBX-APIKEY' key}, 'ArrayFormat','json', 'UserAgent', 'Mozilla/5.0 (Windows NT 5.1; rv:19.0) Gecko/20100101 Firefox/19.0');
            try
                % data = webwrite(urlTemp, query_str_final{:}, options);
                data = webwrite(urlTemp, [query_string, '&signature=', signature], options);
                new_order_details = data;
            catch ME    
                fprintf('binance_api::place_new_order(): Placing new order failed with->%s\n', ME.identifier);
                ME
                disp('parameter dump:');
                fprintf('%s&%s\n', urlTemp, [query_string, '&signature=', signature]);
                new_order_details = [];
                return;
            end
        end 
        
        %% place market buy order with timeInForce=GTC and with quoteAssetQuantity
        % will buy as much base asset as quoteAssetQuantity will allow
        % e.g. symbol=BTCUSDT, quoteAssetQuantity=200, we try to buy as
        % much BTC as possible for 200USDT
        % inputs:
        %       symbol              CHAR crypto asset pair
        %       newClientOrderId    CHAR unique ID to mark the order
        %                           shall be of format:
        %                           [STRATEGYID_SYMBOL]. This function will
        %                           attach a timestamp to the clientOrderID
        %                           before it sends order to binance: [STRATEGYID_SYMBOL_timestamp]
        %       quoteAssetQuantity  LONG decimal value of quote asset
        % outputs: (same as for place_new_order())
        %       returns empty array [] if no trades or in case of an error.
        %       Use isempty() to check if there are returns
        function [new_order_details] = place_new_market_buy_order(self, symbol, newClientOrderId, quoteAssetQuantity)
            % use datetime(now,'ConvertFrom','datenum') to reconstruct from
            % now
            % create clientOrderID and add timestamp: [STRATEGYID_SYMBOL_timestamp]
            clientOrderID = sprintf('%s_%s', newClientOrderId, num2str(ceil(now)));
            params = {'quoteOrderQty', num2str(quoteAssetQuantity)};
            new_order_details = place_new_order(self, symbol, 'BUY', 'MARKET', clientOrderID, params);
        end
        
        %% place market sell order with timeInForce=GTC and with baseAssetQuantity
        % will sell all base assets as defined in baseAssetQuantity
        % e.g. symbol=BTCUSDT, baseAssetQuantity=0.5, we push exchange to
        % sell as much as possible of 0.5BTC at current best market quote
        % inputs:
        %       symbol              CHAR crypto asset pair
        %       newClientOrderId    CHAR unique ID to mark the order
        %                           shall be of format:
        %                           [STRATEGYID_SYMBOL]. This function will
        %                           attach a timestamp to the clientOrderID
        %                           before it sends order to binance: [STRATEGYID_SYMBOL_timestamp]
        %       baseeAssetQuantity  LONG decimal value of base asset
        % outputs: (same as for place_new_order())
        %       returns empty array [] if no trades or in case of an error.
        %       Use isempty() to check if there are returns
        function [new_order_details] = place_new_market_sell_order(self,  symbol, newClientOrderId, baseAssetQuantity)
            % use datetime(now,'ConvertFrom','datenum') to reconstruct from
            % now
            % create clientOrderID and add timestamp: [STRATEGYID_SYMBOL_timestamp]
            clientOrderID = sprintf('%s_%s', newClientOrderId, num2str(ceil(now)));
            params = {'quantity', num2str(baseAssetQuantity)};
            new_order_details = place_new_order(self, symbol, 'SELL', 'MARKET', clientOrderID, params);
        end
        
        %%
        %
        function [new_order_details] = place_new_limit_buy_order(self, symbol, side, type, newClientOrderId, cell_array_of_params)
            warning('binance_api::place_new_limit_buy_order(): not implemented yet');
        end
        
        %%
        %
        function [new_order_details] = place_new_limit_sell_order(self, symbol, side, type, newClientOrderId, cell_array_of_params)
            warning('binance_api::place_new_limit_sell_order(): not implemented yet');
        end
        
        %% panic sell all assets. quote asset is USDT
        % all base assets will be retrieved from current account. for all
        % assets a market order will be placed with timeInForce=GTC,
        % newOrderRespType=ACK
        % quote asset against which to sell is USDT. Can be configured in
        % code.
        % Use with caution!
        % no input params required...we are in panic!
        % This function will create ClientOderID with format
        % [STRATEGYID_SYMBOL] and will pass it to
        % new_order_function which will add a time stamp prior to placing
        % the oder to the exchange: [STRATEGYID_SYMBOL_timestamp]
        % output (same as for place_new_order())
        function [ret] = panic_sell_all_assets(self)
            
            % stable coin that you want to get in exchange for your other
            % crypto assets
            stable_coin = 'USDT';
            coins_to_exclude_from_sell = string({'BUSD', 'TRX', stable_coin});
            [~, balances] = get_account_info(self);
            if size(balances ,1) < 1
                warning('binance_api::panic_sell_all_assets(): no assets in your portfolio -> exit');
                ret = [];
                return
            end        
            
            % *****create crypto pairs while quote asset for all will be USDT
            % to array of strings for better filtering
            array_of_symbols = string({balances{:,1}});
            array_of_balances = string({balances{:,2}});

            % remove stable/non sellable coins from the list
            for i = 1:size(coins_to_exclude_from_sell, 2)
                array_of_balances = array_of_balances(array_of_symbols(:)~=coins_to_exclude_from_sell(i));
                array_of_symbols = array_of_symbols(array_of_symbols(:)~=coins_to_exclude_from_sell(i));
            end
            % check if USDT was the only asset in our portfolio
            % we dont check if other assets are above min threshold to
            % trade
            if size(array_of_symbols, 2) < 1
                warning('binance_api::panic_sell_all_assets(): no assets in your portfolio -> exit');
                ret = [];
                return
            end            
            
            % place market sell order for each asset
            for i=1:size(array_of_symbols, 2)
                selling_pair = sprintf('%s%s',array_of_symbols(i), stable_coin);
                order_unique_ID = sprintf('PANICSELL_%s', selling_pair);
                ret{i} = place_new_market_sell_order(self, selling_pair, order_unique_ID, array_of_balances(i));
            end
            
        end
    end
end

