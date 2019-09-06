classdef parwaitbar < handle
%PARWAITBAR Waitbar class compatible with parfor.
%     PARWAITBAR prints a progress bar to the command window/terminal that can
%     be used with for and parfor loops.
%
%     If 'parallel.pool.DataQueue' is available, PARWAITBAR uses the queue to
%     update the waitbar asynchronously.
%     If 'parallel.pool.DataQueue' is unavailable, PARWAITBAR creates a
%     temporary text file, saved in the current folder, to communicate
%     information between workers. The file is deleted when the last task is completed.
%
%     Constructor
%
%     PARWAITBAR(N), initiate waitbar for N number of tasks.
%     PARWAITBAR(...,'WaitMessage',msg), set msg as the default wait message.
%     PARWAITBAR(...,'FinalMessage',msg), display msg in bar after completion.
%     PARWAITBAR(...,'Marker',m), use m to fill the progress bar.
%     PARWAITBAR(...,'BarLength',x), set the length of the progress bar to x.
%     PARWAITBAR(...,'RemainingTime',true/false), display/hide the remaining time.
%     PARWAITBAR(...,'Date',true/false), display/hide current date.
%     PARWAITBAR(...,'Overwrite',true/false), overwrite/stack progress bar output.
%
%     Methods
%     h = parwaitbar(N)
%
%     h.progress(), update bar with default wait message.
%     h.progress(message), update bar and display message (char) in the bar.
%     h.progress(x), update bar and display x (double) in the bar.
%
%     h.delete(), delete bar along with associated objects/file.
%
%     Examples
%     %% 1)
%     N = 100;
%     wb = parwaitbar(N);
%     parfor i=1:N
%         pause(rand);
%         wb.progress();
%     end
%
%     %% 2)
%     N = 100;
%     wb = parwaitbar(N,'BarLength',10);
%     for i=1:N
%         pause(rand);
%         wb.progress();
%     end
%
%     %% 3)
%     N = 100;
%     wb = parwaitbar(N,'WaitMessage','Hang on...','FinalMessage','Done!');
%     parfor i=1:N
%         pause(rand);
%         wb.progress();
%     end
%
%     %% 4)
%     N = 100;
%     wb = parwaitbar(N,'Marker','=','BarLength',10,'WaitMessage','Hang on...','FinalMessage','Done!','Date',false,'Overwrite',false);
%     parfor i=1:N
%         pause(rand);
%         wb.progress(sprintf('Here is a random number:%d',randi(1000)));
%     end
%
%     Copyright (C) 2019 Olivier Trottier
    
    properties (SetAccess = immutable, GetAccess = public)
        NTasks % (double) Total number of tasks
        StartTime % (double) Time in seconds when class is instantiated
        WaitMessage % (char) Message displayed while waiting for progress
        FinalMessage % (char) Message displayed when all tasks are completed
        NoDesktop % (logical) When matlab is started with -nodesktop, print bar to terminal
        Marker % (char) Marker used to fill the progress bar
        BarLength % (double) Length of the progress bar in number of characters
        DisplayRemainingTime % (logical) Display the remaining time
        DisplayDate % (logical) Display current date
        Overwrite % (logical) Overwrite existing bar when updating progress
        UseQueue % (logical) Use DataQueue as the update method, if available
        Queue % (parallel.pool.DataQueue) Queue used to update the progress bar asynchronously
        UpdateFilename % (char) Filename used to update progress if UseQueue=false
    end
    
    properties (SetAccess = private, GetAccess = public)
        NCompletedTasks = 0 % (double) Number of completed tasks
        ProgressPercent = 0 % (double) Current progress percentage
        FullbarLength = 0 % (double) Full length of progress bar, including date, message, time and bar
        MessageMaxLength = 0 % (double) Maximum length of messages previously displayed
        FullbarString = '' % (char) Array representing the full progress bar
    end
    
    properties (SetAccess = immutable, GetAccess = private, Transient)
        Listener = [] % (event.listener) Listener for DataQueue updates.
    end
    
    methods (Access = public)
        %% Constructor
        function obj = parwaitbar(NTasks, varargin)
            % h = parwaitbar(N), h = parwaitbar(N,Name,Value) where Name,Value are keyworded arguments
            % Check inputs
            assert(isnumeric(NTasks), 'The number of tasks must be numeric.');
            assert(round(NTasks) == NTasks, 'The number of tasks must be an integer.');
            obj.NTasks = NTasks;
            
            % Optional Parameters.
            p = inputParser;
            addParameter(p, 'WaitMessage', '', @ischar); % Display message while waiting.
            addParameter(p, 'FinalMessage', '', @ischar); % Display message after completion.
            addParameter(p, 'Marker', '*', @(x) ischar(x) & numel(x) == 1); % Marker use to fill progress bar.
            addParameter(p, 'BarLength', 20, @(x) isnumeric(x) & x == round(x)); % Length of progress bar (number of characters).
            addParameter(p, 'RemainingTime', true); % Display estimated remaining time.
            addParameter(p, 'Date', true); % Display the current time and date.
            addParameter(p, 'Overwrite', true); % Overwrite progress bar when update.
            parse(p, varargin{:});
            options = p.Results;
            
            % Initialize properties.
            obj.NoDesktop = ~usejava('desktop'); % Print to terminal if Matlab was started with -nodesktop.
            obj.StartTime = tic;
            
            % Initialize properties depending on the update technique.
            % Use Data queue if available. Otherwise, write to a temporary
            % file.
            obj.UseQueue = ~isempty(which('parallel.pool.DataQueue'));
            if obj.UseQueue
                % Initialize queue with listener.
                obj.Queue = parallel.pool.DataQueue;
                obj.Listener = obj.Queue.afterEach(@(x) obj.advance(x));
            else
                % Create temporary file that stores the number of completed tasks.
                [~, Filename] = fileparts(tempname);
                obj.UpdateFilename = [class(obj), '_', Filename, '.txt'];
                FileID = fopen(obj.UpdateFilename, 'wt+');
                fprintf(FileID, '%d', 0);
                fclose(FileID);
            end
            
            % Pass optional parameters
            obj.WaitMessage = options.WaitMessage;
            obj.FinalMessage = options.FinalMessage;
            obj.Marker = options.Marker;
            obj.BarLength = options.BarLength;
            obj.DisplayRemainingTime = logical(options.RemainingTime);
            obj.DisplayDate = logical(options.Date);
            obj.Overwrite = logical(options.Overwrite);
            
            % Initialize waitbar.
            obj.format();
            obj.print();
        end
        %% Update waitbar progress
        function progress(obj, CustomMessage)
            % Increment bar progress by 1 task.
            if nargin == 1
                CustomMessage = '';
            end
            if isnumeric(CustomMessage)
                CustomMessage = num2str(CustomMessage);
            end
            
            if obj.UseQueue
                obj.Queue.send(CustomMessage);
            else
                obj.advance(CustomMessage);
            end
        end
        %% Destructor
        function delete(obj)
            % If UseQueue=true, delete queue and listener. If UseQueue=false, delete temporary update file.
            if obj.UseQueue
                delete(obj.Listener);
                delete(obj.Queue);
            else
                % Delete the update file.
                if exist(obj.UpdateFilename, 'file')
                    % Open the file to check the number of completed tasks.
                    FileID = fopen(obj.UpdateFilename, 'r+');
                    NCompletedTasks_temp = fscanf(FileID, '%d');
                    
                    % Delete file if all tasks have been completed.
                    if NCompletedTasks_temp == obj.NTasks
                        delete(obj.UpdateFilename);
                    end
                end
            end
        end
    end
    
    methods (Access = protected)
        %% Advance progress and print waitbar.
        function advance(obj, CustomWaitMessage)
            % Advance progress of the waitbar and print.
            
            % Increment the number of completed tasks.
            if ~obj.UseQueue
                % Open the update file and increment the number of
                % completed tasks.
                FileID = fopen(obj.UpdateFilename, 'r+');
                obj.NCompletedTasks = fscanf(FileID, '%d');
                frewind(FileID);
                fprintf(FileID, '%d', obj.NCompletedTasks+1);
                fclose(FileID);
            end
            obj.NCompletedTasks = obj.NCompletedTasks+1;
            obj.ProgressPercent = obj.NCompletedTasks/obj.NTasks;
            
            % Format and print bar.
            if nargin == 1
                CustomWaitMessage = '';
            end
            obj.format(CustomWaitMessage);
            obj.print();
            
            % Delete object when all tasks are completed.
            if obj.NCompletedTasks == obj.NTasks
                delete(obj);
            end
        end
        %% Format waitbar
        function format(obj, CustomWaitMessage)
            % Format the full bar including date, message, completion percentage, remaining time and progress.
            % The progress bar format is: [Current Date] - [Wait Message] - [Remaining Time] [Percentage] [Bar]
            % The final bar format is: [End Date] - [Final Message] - [Total Time] [Percentage] [Bar]
            
            % Format date.
            if obj.DisplayDate
                Date_string = [datestr(now), ' - '];
            else
                Date_string = '';
            end
            
            % Format message to display.
            if obj.ProgressPercent < 1
                % Display custom/default wait message.
                if nargin > 1 && ~isempty(CustomWaitMessage)
                    Message = CustomWaitMessage;
                else
                    Message = obj.WaitMessage;
                end
            else
                % Display final message.
                Message = obj.FinalMessage;
            end
            
            % Fix length and add separator if message is non-empty.
            CurentMessageLength = numel(Message);
            if CurentMessageLength > 0
                obj.MessageMaxLength = max(CurentMessageLength, obj.MessageMaxLength);
                Message = [Message, repmat(' ', 1, obj.MessageMaxLength-CurentMessageLength)];
                Message = [Message, ' - '];
            end
            
            % Format time string.
            [RemainingTime, ElapsedTime] = obj.calculate_remaining_time();
            if obj.DisplayRemainingTime && obj.ProgressPercent < 1
                Time_string = ['Remaining:', char(duration(0, 0, RemainingTime, 'Format', 'hh:mm:ss')), ' '];
            elseif obj.ProgressPercent == 1
                Time_string = ['Total:', char(duration(0, 0, ElapsedTime, 'Format', 'hh:mm:ss')), ' '];
            else
                Time_string = '';
            end
            
            % Format progress percentage string.
            Percentage_string = sprintf('%3.0f%% ', obj.ProgressPercent*100);
            
            % Format bar string.
            N_markers = floor(obj.ProgressPercent*obj.BarLength);
            Bar_string = ['[', repmat(obj.Marker, 1, N_markers), repmat(' ', 1, obj.BarLength-N_markers), ']'];
            
            % Format full bar string.
            obj.FullbarString = [Date_string, Message, Time_string, Percentage_string, Bar_string];
        end
        %% Print string to command window/terminal.
        function print(obj)
            % Print to command window/terminal
            % Move cursor to the previous line if a bar has been printed
            % previously.
            if obj.Overwrite && obj.FullbarLength > 0
                % Rewind and print.
                if obj.NoDesktop
                    % If terminal is used, use ANSI codes to move cursor.
                    %system('tput cuu1;tput el');
                    system('printf "\033[1A"'); % Move cursor up.
                    system('printf "\033[K"'); % Erase line.
                else
                    % If desktop is used, print backspaces to rewind the cursor.
                    disp(repmat(char(8), 1, obj.FullbarLength+2));
                end
            end
            
            % Print string.
            disp(obj.FullbarString);
            
            % Update the full bar length for rewinding on the next print.
            obj.FullbarLength = numel(obj.FullbarString);
        end
        %% Calculate remaining time (in seconds).
        function [RemainingTime, ElapsedTime] = calculate_remaining_time(obj)
            % Calculate remaining time using the StartTime property.
            ElapsedTime = toc(obj.StartTime);
            RemainingTime = ElapsedTime*(1/obj.ProgressPercent-1);
        end
    end
end