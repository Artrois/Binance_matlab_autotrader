classdef SimpleClient < WebSocketClient
    %CLIENT Summary of this class goes here
    %   Detailed explanation goes here
    
    properties (Access = private)
           callBackFunc;
           parentObj;
    end
    
    methods
        function obj = SimpleClient(varargin)
            %Constructor
            obj@WebSocketClient(varargin{:});
        end
        
        %% Register a call back function
        % Call back function will be executed onMessage receive()
        % inputs:
        %       clbFunc: will be invoked as clbFunc(parent, kline_cell_array)
        %       parent: parent object that will be passed to the clbFunc
        %       along with the received message
        %
        function setCallBack(self, clbFunc, parent)
            if nargin < 3
                return 
            end
            self.callBackFunc = clbFunc;
            self.parentObj = parent;
        end
        
    end
    
    methods (Access = protected)
        function onOpen(obj,message)
            % This function simply displays the message received
            fprintf('%s %s\n', datetime('now'), message);
            if ~isa(obj.callBackFunc, 'function_handle')
                disp('warning SimpleClient::onOpen():callBackFunction not defined');
            end
        end
        
        function onTextMessage(obj,message)
       

            if isa(obj.callBackFunc, 'function_handle') && ~isempty(obj.parentObj)
                obj.callBackFunc(obj.parentObj, message);
            else
                % This function simply displays the message received
                fprintf('%s SimpleClient::onTextMessage(): Message received:\n%s\n',datetime('now'), message);
            end
        end
        
        function onBinaryMessage(obj,bytearray)
            % This function simply displays the message received
            fprintf('Binary message received:\n');
            fprintf('Array length: %d\n',length(bytearray));
        end
        
        function onError(obj,message)
            % This function simply displays the message received
            fprintf('%s Error: %s\n',datetime('now'), message);
        end
        
        function onClose(obj,message)
            % This function simply displays the message received
            fprintf('%s %s\n',datetime('now'), message);
        end
    end
end

