function README_BINANCE()
    return
    %load testnet settings
    binance_settings_instance = binance_settings(true);
    binance_settings_instance = binance_settings(false, "ENTER_SECRET_HERE");

    %create API instance
    binance_api_instance = binance_api(binance_settings_instance);
    time_frame = '1D';
    %one week time frame
    ende = bitfinex_api_instance.datetime_to_epoch(datetime('now'));
    start = ende - bitfinex_api_instance.limit_to_millisecs(time_frame) * 7;
    
    time_table_klines_binance = binance_api_instance.get_klines('BTCUSDT', '1m', start, ende, 1000);
    
    % register binance API with perf calculator
    perfInstance= PerformanceMeasurement();
    perfInstance.setExchange("BINANCE", binance_api_instance);

    load binance_test_orderlist_BTCUSDT.mat

    order_list = binance_api_instance.get_all_my_orders("BTCUSDT");

     performance_kpi_struct_array = perfInstance.updatePerformanceIndicators("BINANCE","BTCUSDT");
    map_container=perfInstance.map_orders_to_strategies(binance_test_orderlist_BTCUSDT);
    control_GUI = GUI();
    uiAxesObj = control_GUI.UIAxesCandles;
    candle(uiAxesObj, time_table_klines);
    
     [A,cURL_out] = system('curl https://api.binance.com/api/v3/klines?symbol=BTCUSDT&interval=1m&startTime=1642202512259&endTime=1642807312259&limit=1000');
end

%https://api.binance.com/api/v3/klines?symbol=BTCUSDT&interval=1m&startTime=1642202512259&endTime=1642807312259&limit=1000