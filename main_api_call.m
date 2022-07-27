function [response, response2]=main_api_call(server,method,params)
    server_names={'btce','cexio','bitstamp','bitfinex','huobi','gdax','bittrex', 'binance'};
    function_list={@main_api_call_btce,@main_api_call_cexio,@main_api_call_bitstamp,@main_api_call_bitfinex,@main_api_call_huobi,@main_api_call_gdax,@main_api_call_bittrex, @main_api_call_binance};
    server_select=find(strcmp(server,server_names),1);
    [response, response2] = function_list{server_select}(method,params);
end