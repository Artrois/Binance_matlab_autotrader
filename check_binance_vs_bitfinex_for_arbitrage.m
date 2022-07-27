%% this script is to get historical klines from binance and from bitfinex to
% analyse for cointegration
% used symbol/traiding pair is BTCUSD
% timeframe one week
% resolution for kline ticks 1m

clear

traiding_pair_binance = 'ETHUSDT';
traiding_pair_bitfinex = 'ETHUST';

answer = questdlg('You want to load stored klines?','Deafult data','Yes','No','Cancel', 'Cancel');
if strcmp(answer, 'Yes') && ~isfile('time_table_klines_binance_and_bitfinex.mat')
    disp('User selected to load from time_table_klines_binance_and_bitfinex.mat but it does not exist -> treat this as No')
    answer = 'No';
end

switch answer
    case 'Cancel'
        disp('User decided to cancel the process ->exit');
        return
    case 'No'
         %get binance klines first
        binance_settings_instance = binance_settings(true);
        %create API instance
        binance_api_instance = binance_api(binance_settings_instance);
        %time_frame = '1D';
        kline_resolution = '1m';
        limit = 1000;%limit to the number of klines 

        %time frame of 1000 ticks
        ende = binance_api_instance.datetime_to_epoch(datetime('now'));
        %binance starts the klines by 59secs later and not as bitfinex at the even minute
        start_binance = ende - binance_api_instance.limit_to_millisecs(kline_resolution) * limit;


        time_table_klines_binance = binance_api_instance.get_klines(traiding_pair_binance, kline_resolution, start_binance, ende, limit);
        %binance closes a candle at 59sec of a minute and tags the close tick with 59sec. 
        %Bitfinex closes a candle with 59sec but tags the close candle with the
        %next minute after 59th sec. => we need to delay binance Time stamp by 1sec
        %to match with the timestamp from bitfinex
        time_table_klines_binance.Time = time_table_klines_binance.Time - seconds(59);


        start_bitfinex = start_binance; %ende - binance_api_instance.limit_to_millisecs(kline_resolution) * limit;
        %get bitfinex settings instance
        bitfinex_settings_instance = bitfinex_settings(true);
        %create bitfinanex API instance
        bitfinex_api_instance = bitfinex_api(bitfinex_settings_instance);

        %use same time frame as for binance to get bitfinex klines
        time_table_klines_bitfinex = bitfinex_api_instance.get_klines(traiding_pair_bitfinex, kline_resolution, start_bitfinex, ende, limit);       
    case 'Yes'
        load time_table_klines_binance_and_bitfinex.mat
end

%sometimes bitfinex omits some ticks which makes the dimensions of
%timetables not equal. we need to match the number of klines by removing
%access klines for the timetable that has more klines
if height(time_table_klines_bitfinex) < height(time_table_klines_binance)
    disp('#bitfinex klines < #binance klines => remove access klines from binance');
    time_table_klines_binance = time_table_klines_binance(time_table_klines_bitfinex.Time, : );
elseif height(time_table_klines_bitfinex) > height(time_table_klines_binance)
    disp('#bitfinex klines > #binance klines => remove access klines from bitfinex');
    time_table_klines_bitfinex = time_table_klines_bitfinex(time_table_klines_binance.Time, : );
end


tiledlayout(2, 1) % we use three subplots
% Top plot
nexttile

plot(time_table_klines_bitfinex.Time, time_table_klines_bitfinex.Close, 'r:x');

hold on
f=plot(time_table_klines_binance.Time, time_table_klines_binance.Close, 'k:x');

try
    diffs = timetable(time_table_klines_binance.Time, time_table_klines_bitfinex.Close - time_table_klines_binance.Close);
    %rename the second column to Diffs
    diffs.Properties.DimensionNames{2} = 'Diffs';


    %plot when bitfinex overlaps or drops below binance
    diffs_zero_crossings = diffs.Diffs <=0;
    plot(time_table_klines_bitfinex.Time(diffs_zero_crossings), time_table_klines_bitfinex.Close(diffs_zero_crossings),'ro');

    %calculate ticks that are bitfinex - binance > 70
    diff_more_than_70 = diffs.Diffs > 70;


    hold off

    title(traiding_pair_binance);
    legend('Bitfinex', 'Binance');

    grid on
    dcm = datacursormode;
    dcm.Enable = 'on';

    nexttile
    diffs_relative_to_binance = (diffs.Diffs / time_table_klines_binance.Close) * 100;
    plot(diffs.Time, diffs_relative_to_binance);
    legend('(Bitfinex.Close - Binance.Close)%');

    grid on
    dcm = datacursormode;
    dcm.Enable = 'on';


    %some analysis
    %position, x,y, X , Y
    uitable('Data', [mean(diffs.Diffs) max(diffs.Diffs) min(diffs.Diffs)], 'ColumnName', {'Mean', 'Max', 'Min'}, 'Position',[0.2,0.05,300,50]);
catch err
    fprintf(2, '%s\n', getReport(err, 'extended'));
end

