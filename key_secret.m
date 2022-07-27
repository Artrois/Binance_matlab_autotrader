function [key,secret,username]=key_secret(server)
% please type your key and secrets for each server or server you will use.
% % % % % % % % % % % % BTC-E
BTCE_KEY = '';
BTCE_SECRET = '';
BTCE_USERNAME=''; %this is empty no need for username

% % % % % % % % % % % % CEX.IO
CEXIO_KEY = '';
CEXIO_SECRET = '';
CEXIO_USERNAME=''; %this is needed in header

% % % % % % % % % % % % BITSTAMP no need atm. will be updated
BITSTAMP_KEY = '';
BITSTAMP_SECRET = '';
BITSTAMP_USERNAME=''; %this is empty no need for username

% % % % % % % % % % % % BITFINEX
BITFINEX_KEY = '';
BITFINEX_SECRET = '';
BITFINEX_USERNAME=''; %this is empty no need for username

% % % % % % % % % % % % HUOBI no need atm. will be updated
HUOBI_KEY = '';
HUOBI_SECRET = '';
HUOBI_USERNAME=''; %this is empty no need for username

% % % % % % % % % % % % GDAX no need atm. will be updated
GDAX_KEY = '';
GDAX_SECRET = '';
GDAX_USERNAME=''; %this is passphrase
% % % % % % % % % % % % BITTREX 
BITTREX_KEY = '';
BITTREX_SECRET = '';
BITTREX_USERNAME=''; 

% % % % % % % % % % % % BINANCE
BINANCE_KEY = '';
BINANCE_SECRET = '';
BINANCE_USERNAME=''; %this is empty no need for username
BINANCE_TESTNET_KEY = 'b7zP0kA5ZBDW4twdlTUh5b1rwbG6yHRtbhBixjIBnvDy4Dg3ADmLiUcs8ZHPUraF';
BINANCE_TESTNET_SECRET = 'FsDPwj4KKJZmNE8QzWo9B9xbOZwE0zJ3c41sjMmO4rCg9sNUNreQTAJdbgusBOXi';

keys={BITFINEX_KEY,BINANCE_TESTNET_KEY};
secrets={BITFINEX_SECRET, BINANCE_TESTNET_SECRET};
usernames={BITFINEX_USERNAME, BINANCE_USERNAME};
server_names={'bitfinex', 'binance'};
server_loc=find(strcmp(server,server_names),1);
if isempty(server_loc)
    key = 0;
    secret = 0;
    fprintf('key_secret::No key for exchange %s found\n', server);
else
    key=keys{server_loc};
    secret=secrets{server_loc};
    username=usernames{server_loc};
end
end