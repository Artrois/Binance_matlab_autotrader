function README_BITFINEX()
    return
    %load testnet settings
    bitfinex_settings_instance = bitfinex_settings(true);
    bitfinex_settings_instance = bitfinex_settings(false, "ENTER_SECRET_HERE");

    %create API instance
    bitfinex_api_instance = bitfinex_api(bitfinex_settings_instance);

    time_frame = '1W';
    %one week time frame
    ende = bitfinex_api_instance.datetime_to_epoch(datetime('now'));
    start = ende - bitfinex_api_instance.limit_to_millisecs(time_frame);
    
    time_table_klines_bitfinex = bitfinex_api_instance.get_klines('BTCUSD', '1m', start, ende, 10000);
    
    % register bitfinex API with perf calculator
    perfInstance= PerformanceMeasurement();
    perfInstance.setExchange("BINANCE", bitfinex_api_instance);

    load bitfinex_test_orderlist_BTCUSDT.mat

    order_list = bitfinex_api_instance.get_all_my_orders("BTCUSDT");

     performance_kpi_struct_array = perfInstance.updatePerformanceIndicators("BINANCE","BTCUSDT");
    map_container=perfInstance.map_orders_to_strategies(bitfinex_test_orderlist_BTCUSDT);
    control_GUI = GUI();
    uiAxesObj = control_GUI.UIAxesCandles;
    candle(uiAxesObj, time_table_klines);
    
    [A,cURL_out] = system('curl https://api-pub.bitfinex.com/v2/candles/trade:1m:tBTCUSD/hist?start=1642206608069&end=1642811408069&limit=1000')
 
end

 
