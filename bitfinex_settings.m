classdef bitfinex_settings
    %BITFINEX_SETTINGS Summary of this class goes here
    %   Detailed explanation goes here(NE8QzWo9B9xbOZw)
    
    properties (Access = public)
        test_net_enabled = false;  
    end
    properties (Access = private)
        aes % instance of encryption class
        BITFINEX_KEY = '6z7PFtcTEz9LC5hqNXs7f6ATyLSRWQ4S20w3M8jr6zmvxcjwGQ8vqeLaVsf6LeozKYEbE0t4ND2H3DBhH+ZzMAbPCwgb1lABniDlezj2d0w=';
        BITFINEX_SECRET = 'WRlkZuSUgJjD1DlyZExDLZQ2TY5Xnf5H3YrUOXkco6BgjLOMhrtJKPatUBxDEyt3Ote7jE8wgINkbPGCnyyPmgbPCwgb1lABniDlezj2d0w=';
        BITFINEX_USERNAME=''; %this is empty no need for username
        BITFINEX_TESTNET_KEY = 'b7zP0kA5ZBDW4twdlTUh5b1rwbG6yHRtbhBixjIBnvDy4Dg3ADmLiUcs8ZHPUraF';
        BITFINEX_TESTNET_SECRET = 'FsDPwj4KKJZmNE8QzWo9B9xbOZwE0zJ3c41sjMmO4rCg9sNUNreQTAJdbgusBOXi';
        
        spotAPI_URL = 'https://api.bitfinex.com/v2/auth';
        spotAPI1_URL = 'https://api.bitfinex.com/v2/auth';
        spotAPI_TestNet_URL = ''; %'https://testnet.binance.vision';
        publicAPI_URL = 'https://api-pub.bitfinex.com/v2';
        websocket_URL = 'wss://api-pub.bitfinex.com/ws/2';
        websocket_TestNet_URL = ''; %'wss://testnet.binance.vision/ws';

    end
    methods
        %% constructor
        % input:
        %       test_net_setting: (MANDATORY) BOOL 
        %                           true = bitfinex test net settings will be used
        %                           false = real bitfinex server will be
        %                           used. You will have to set
        %                           auto_trader_secret to decrypt bitfinex
        %                           secret
        %       auto_trader_secret: (OPTIONAL) STRING with secret to decrypt BITFINEX
        %       API keys
        function self = bitfinex_settings(test_net_setting, auto_trader_secret)
            %BITFINEX_SETTINGS Construct an instance of this class  
            switch nargin
                case 0
                    error("bitfinex_settings::no parameter set->exit");
                case 1
                    if islogical(test_net_setting)
                        if test_net_setting
                            self.test_net_enabled = true;
                            disp('bitfinex_settings::constructor():user selected test net settings');
                        end
                    else
                        self.test_net_enabled = false;
                        error("bitfinex_settings::constructor(): auto trader secret key not set->exit");
                        
                    end
                case 2
                    if (test_net_setting || isempty(auto_trader_secret))
                        error('bitfinex_settings::constructor(): auto_trader_secret not set->exit');
                    end
                        self.test_net_enabled = false;
                        self.aes = CipherClass(auto_trader_secret);

                otherwise
                    error("bitfinex_settings::constructor(): too many parameters set->exit");
            end
        end

        %% get_key function
        % returns HMAC_SHA256 key
        function key = get_key(self)
            if self.test_net_enabled
                key = self.BITFINEX_TESTNET_KEY;
            else
                key = self.aes.decrypt(self.BITFINEX_KEY);
            end
        end
        
        %% get_secret function
        % returns HMAC_SHA256 secret
        function secret = get_secret(self)
            if self.test_net_enabled
                secret = self.BITFINEX_TESTNET_SECRET;
            else
                secret = self.aes.decrypt(self.BITFINEX_SECRET);
            end
        end
        
        %% get_exchange_API URL function
        % returns authaticated URL to exchange as string. If testnet is
        % selected then testnet URL will be returned
        function url = get_API_URL(self)
            if self.test_net_enabled
                url = self.spotAPI_TestNet_URL;
            else
                url = self.spotAPI_URL;
            end
        end

        %% get_exchange_API URL function
        % returns authaticated URL to exchange as string
        function url = get_public_API_URL(self)
                url = self.publicAPI_URL;
        end
        
        %% get_exchange websocket URL function
        % returns URL to websocket as string
        function url = get_websocket_URL(self)
            if self.test_net_enabled
                url = self.websocket_TestNet_URL;
            else
                url = self.websocket_URL;
            end
        end   
    end
end

