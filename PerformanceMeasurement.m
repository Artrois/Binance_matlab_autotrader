classdef PerformanceMeasurement
    %Performance measurement module
    %   here goes major implementation of different performance
    %   measurements of our trading 
    
    properties
        % containers.Map
        exchange_api_instances; % map of exchange API instances. use keys(exchange_api_instances) to retrieve keys associated with exchange instances
    end
    
    methods
        %% constructor
        function self = PerformanceMeasurement()
                self.exchange_api_instances = containers.Map;
        end
        
        %% register exchange
        % inputs:
        %       exchangeName: STRING with capital letters, name of exchange to be registered
        %       exchangeInstance: instance of exchange API
        function self = setExchange(self, exchangeName, exchangeInstance)
            if ~isa(exchangeName,'char') || ~isempty(exchangeInstance)
                self.exchange_api_instances(exchangeName) = exchangeInstance;
            else
                error('PerformanceMeasurement::setExchange(): exchangeName or exchangeInstance parameter not set -> exit');
            end
        end
        
        %% Trigger update of performance indicators
        % inputs:
        %       exchangeName:(MANDATORY) STRING with the name of exchange in capital
        %         letters. e.g.: BINANCE
        %       symbol:(MANDATORY) STRING crypto traiding pair that will be used to
        %         get recent trades form the exchange, in capital letters.
        %         e.g. BTCUSDT. Last 3 digits will be taken for quote
        %         asset.
        % outputs:
        %       profit_loss_struct_array: array of structs nx1
        %                   {
        %                      strategyID (STRING)
        %                      symbol (STRING), e.g. BTCUSDT
        %                      quotesymbol STRING), STRING quote symbol from traiding pair that 
        %                               was passed as input parameter. For symbol
        %                               BTCUSDT, quotesymbol is USDT.
        %                      profit_loss: LONG profit_loss value over full period 
        %                   }
        %
        function [performance_kpi_struct_array] = updatePerformanceIndicators(self, exchangeName, symbol)
            if nargin < 3
                error('PerformanceMeasurement::profitLossOverFullPeriod(): not enough arguments -> exit');
            end
            
            if ~isa(exchangeName, "string") || ~isa(symbol, "string")
                error('PerformanceMeasurement::profitLossOverFullPeriod(): exchangeName or symbol param not a string ->exit');
            end
            
            % preallocate the struct
            performance_kpi_struct_array = struct('strategyID', {}, 'symbol', {}, 'quotesymbol', {}, 'profit_loss', {});
            
            switch exchangeName
                case 'BINANCE'
                    %binance_api_instance = self.exchange_api_instances(exchangeName);
                    %trade_list = binance_api_instance.get_my_account_trade_list(symbol);
                    binance_api_instance = self.exchange_api_instances(exchangeName);
                    order_list = binance_api_instance.get_all_my_orders(symbol);                    
                    if isempty(order_list) || size(order_list, 1) == 1
                        fprintf("PerformanceMeasurement::updatePerformanceIndicators(): not enough orders found for symbol %s\n", symbol);
                    else
                        % extract the quotesymbol from the symbol pair
                        % (last three characters).
                        quotesymbol = extractAfter(symbol, 3);
                        
                        % get map of strategies associated with according
                        % orders. keys are the strategy names/strings and
                        % array of structs inckude executed orders/structs for each
                        % strategy.
                        map_container = self.map_orders_to_strategies(order_list);
                        
                        
                        if ~isempty(map_container)
                            strategy_keys = string(keys(map_container));
                          
                            %build the return struct
                            for i=1:length(strategy_keys)
                                performance_kpi_struct_array(i, 1).strategyID = strategy_keys(i);
                                performance_kpi_struct_array(i, 1).symbol = symbol;
                                performance_kpi_struct_array(i, 1).quotesymbol = quotesymbol;
                                
                                % ----here after we place our KPI calc functions
                                % ----run profitLossOverFullPeriod STRATEGY
                                order_list_per_strategy = map_container(strategy_keys(i));
                                performance_kpi_struct_array(i, 1).profit_loss = self.profitLossOverFullPeriod_from_order_list(order_list_per_strategy, false);
                                % END OF profitLossOverFullPeriod STRATEGY
                                
                            end
                        else
                            warning('PerformanceMeasurement::updatePerformanceIndicators(): something went wrong with mapping orders to strategies, map is empty');
                        end
                        
                    end
                otherwise
                    error('PerformanceMeasurement::updatePerformanceIndicators(): not supported exchange ->exit');
            end
        end
        
        %% sort orders to different strategies
        % function takes order list and creates separate order list for
        % each strategy that is defined in order_list(i).clientOrderId
        % converts time stamps to datetime
        % inputs:
        %       order_list: (MANDATORY)
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
        % outputs:
        %       map_container: containers.Map, keys are strategyIDs, values are
        %                   struct arrays of orders as received via input
        %                   binance_api::get_all_my_orders().
        %                   Empty map is returned if order_list was empty.
        function [map_container] = map_orders_to_strategies(~, order_list)
            map_container = containers.Map;
            if nargin < 2              
                error('PerformanceMeasurement::sort_orders_to_strategies(): not enough arguments -> exit');
            end
            if isempty(order_list)
                error('PerformanceMeasurement::sort_orders_to_strategies(): empty order list passed -> exit');
            end

            for i=1:size(order_list, 1)
                clientOrderId_split = split(order_list(i, 1).clientOrderId, "_");
                strategy_key = string(clientOrderId_split(1));
                if isKey(map_container, strategy_key)
                    % if strategy already addded to map then modify the
                    % struct array that is in the map
                    order_struct = map_container(strategy_key);
                    % convert binance time to proper time
                    %%order_list(i, 1).time = datetime(datestr(order_list(i, 1).time/86400/1000 + datenum(1970,1,1)));
                    % append
                    order_struct(size(order_struct, 1) + 1, 1) = order_list(i, 1);
                    map_container(strategy_key) = order_struct;
                else
                    % otherwise add new struct array to the current strategy key
                    % convert binance time to proper time
                    %%order_list(i, 1).time = datetime(datestr(order_list(i, 1).time/86400/1000 + datenum(1970,1,1)));
                    map_container(strategy_key) = order_list(i, 1);
                end
                
            end
        end
        
        %% profit loss over full period from orders
        % calculates profit/loss over full period of orders.
        % inputs:
        %       trade_list:(MANDATORY) list of trades
        % array of structs [
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
        %       consider_open_positions: (MANDATORY) BOOL,  if TRUE all sell
        %                   and buy (last buy positions which are not sold=open) will
        %                   be considered for calculation. 
        %                   if FALSE last buy positions
        %                   (last buy position that are open and not sold)
        %                   will be excluded from calculation. Basically we
        %                   consider the profits/loss after we have
        %                   sold/closed our positions (HODLING).
        %
        % outputs:
        %       profit_loss: DOUBLE cumulative proft/loss from all trades
        %                   $profit_loss = \sum_{i=1}^{n} sellvalue_{i} - \sum_{i=1}^{m} buyvalue_{i} | n=num(sellings), m=num(buyings)$
        %       
        %       timetable_profit_loss: TIMETABLE a series will absolute + relative profts/losses per SELL position
        %                                       {
        %                                           datetime
        %                                           DOUBLE profit/loss per SELL position
        %                                           DOUBLE relative profit/loss per SELL position
        %       profit_loss_per_month: DOUBLE
        %       profit_loss_per_week: DOUBLE
        %       average_hold_duration: DOUBLE 
        %       profit_to_loss_ratio: DOUBLE $\frac{\sum profits}{\sum losses}$. 
        %                               This value shall be far above 1. 1
        %                               would mean you make 0 profit. <1
        %                               means you are making losses. 2
        %                               means your profits are double the
        %                               losses.
        %       order_hit_ratio: DOUBLE qty of wins divided by qty sell orders $\frac{num(wins)}{num(sell orders)}$
        
        function [profit_loss, timetable_profit_loss, average_hold_duration] = profitLossOverFullPeriod_from_order_list(~, order_list, consider_open_positions)
            profit_loss = 0;
            if nargin < 2
                error('PerformanceMeasurement::profitLossOverFullPeriod(): not enough arguments -> exit');
            end
            if isempty(order_list)
                disp('PerformanceMeasurement::profitLossOverFullPeriod(): empty order list passed -> exit');
                return
            end
            % date = datetime(datestr(tradelist(10).time/86400/1000 + datenum(1970,1,1)));                   
                       
            % we want to remove last buy positions. we start traversing
            % trade_list from end/last/recent_trade
            if ~consider_open_positions
                for i=size(order_list, 1):-1:1
                    if isequal(order_list(i).side, 'BUY')
                        order_list(i) = [];
                    else
                        % stop once reach first occurance of a sell
                        break;
                    end
                end
            end
           %----- from here comes the code to calc all trades
           % transform to cell array
           cell_list_of_orders = struct2cell(order_list);
           % 8th row gives quoteQty
           cummulativeQuoteQty = str2double(cell_list_of_orders(8, : ));
           % 12th pos gives isBuy/side
           isBuys = string(cell_list_of_orders(12, : )) == "BUY";
           % 1 will become -1 and all 0 will become 1
           isBuys = (isBuys * -2) + 1;
           profit_loss = sum(isBuys .* cummulativeQuoteQty);
        end        
        
        %% profit loss over full period from trades
        % calculates profit/loss over full period of trades.
        % $profit_loss = \sum_{i=1}^{n} sellvalue_{i} - \sum_{i=1}^{m} buyvalue_{i} | n=num(sellings), m=num(buyings)$
        % inputs:
        %       trade_list:(MANDATORY) list of trades
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
        %       consider_open_positions: (MANDATORY) BOOL,  if TRUE all sell
        %                   and buy (last buy positions which are not sold=open) will
        %                   be considered for calculation. 
        %                   if FALSE last buy positions
        %                   (last buy position that are open and not sold)
        %                   will be excluded from calculation. Basically we
        %                   consider the profits/loss after we have
        %                   sold/closed our positions (HODLING).
        %
        % outputs:
        %       profit_loss: LONG
        function [profit_loss] = profitLossOverFullPeriod_from_trade_list(self, trade_list, consider_open_positions)
            if nargin < 2
                error('PerformanceMeasurement::profitLossOverFullPeriod(): not enough arguments -> exit');
            end
            % date = datetime(datestr(tradelist(10).time/86400/1000 + datenum(1970,1,1)));                   
            profit_loss = 0;
            
            % we want to remove last buy positions. we start traversing
            % trade_list from end/last/recent_trade
            if ~consider_open_positions
                for i=size(trade_list, 1):-1:1
                    if boolean(trade_list(i).isBuyer)
                        trade_list(i) = [];
                    else
                        % stop once reach first occurance of a sell
                        break;
                    end
                end
            end
           %----- from here comes the code to calc all trades
           % transform to cell array
           cell_list_of_trades = struct2cell(trade_list);
           % 7th row gives quoteQty
           quoteQtys = str2double(cell_list_of_trades(7, : ));
           % 11th pos gives isBuy
           isBuys = cell2mat(cell_list_of_trades(11, : ));
           % 1 will become -1 and all 0 will become 1
           isBuys = (isBuys * -2) + 1;
           profit_loss = sum(isBuys .* quoteQtys);
        end
        
        %% cumulated estimated balance over all assets with USDT as quote asset
        % inputs:
        %       exchangeInstance:(MANDATORY) instance of crypto exchange
        %       exchangeName:(MANDATORY) STRING with the name of exchange in capital
        %       letters.
        %
        % outputs:
        %       balance: long value with cumulated USDT for all assets
        function balanceUSDT = estimatedBalance(self, exchangeName, exchangeInstance)
            if nargin < 3
                error('PerformanceMeasurement::estimatedBalance(): not enough arguments -> exit');
              
            end
            % stable coin that we use as quote asset in which the cumulated
            % balance will be calculated
            stable_coin = 'USDT';
            balanceUSDT = 0;
            
            switch exchangeName
                case 'BINANCE'
                    % get all balances
                    [~, balances] = exchangeInstance.get_account_info();
                    if size(balances ,1) < 1
                        warning('PerformanceMeasurement::estimatedBalance(): no assets in your portfolio -> exit');
                        ret = [];
                        return
                    end
                    % *****create crypto pairs while quote asset for all will be USDT
                    % to array of strings for better filtering
                    array_of_assets = string({balances{:,1}});
                    array_of_balances = string({balances{:,2}});
                    % store balance of quote asset (pure USDT balance)
                    quote_asset_balance = array_of_balances(array_of_assets(:)==stable_coin);
                    % remove USDT from the list
                    array_of_balances = array_of_balances(array_of_assets(:)~=stable_coin);
                    array_of_assets = array_of_assets(array_of_assets(:)~=stable_coin);

                    
                    % check if USDT was the only asset in our portfolio
                    % we dont check if other assets are above min threshold to
                    % trade
                    if size(array_of_assets, 2) < 1
                        warning('PerformanceMeasurement::estimatedBalance(): no assets in your portfolio -> exit');
                        ret = [];
                        return
                    end
                    
                    % assemble symbol by attaching quote asset to each
                    % asset
                    array_of_asset_symbols = strings([1,size(array_of_assets, 2)]);
                    for i=1:size(array_of_assets, 2)
                        array_of_asset_symbols(i) = sprintf('%s%s', array_of_assets(i), stable_coin);
                    end

                    % we get all prices which is of weighting 2 for a single query. Checking
                    % for specific assets individually will be with
                    % weighting 1 per placed query. which is in most cases
                    % more expensive. 
                    [struct_prices] = exchangeInstance.get_price_ticker();
                    cell_prices = struct2cell(struct_prices);
                    latest_prices = cell_prices(2, :);
                    latest_symbols = cell_prices(1, :);
                    % locs = ismember(latest_symbols, array_of_asset_symbols);
                    for i=1:size(latest_symbols, 2)
                        for ii=1:size(array_of_asset_symbols, 2)
                            if latest_symbols(i) == array_of_asset_symbols(ii)
                                balanceUSDT = balanceUSDT + str2double(latest_prices(i)) * str2double(array_of_balances(ii));
                            end
                        end
                    end
                    balanceUSDT = balanceUSDT + str2double(quote_asset_balance);
                    % latest_prices_filtered = latest_prices(locs);

                otherwise
                    error('PerformanceMeasurement::estimatedBalance(): not supported exchange ->exit');
            end
            
        end
        
    end
end

