%% 1)
N = 100;
wb = parwaitbar(N);
parfor i=1:N
    pause(rand);
    wb.progress();
end

%% 2)
N = 100;
wb = parwaitbar(N,'BarLength',10);
for i=1:N
    pause(rand);
    wb.progress();
end

%% 3)
N = 100;
wb = parwaitbar(N,'WaitMessage','Hang on...','FinalMessage','Done!');
parfor i=1:N
    pause(rand);
    wb.progress();
end

%% 4)
N = 100;
wb = parwaitbar(N,'Marker','=','BarLength',10,'WaitMessage','Hang on...','FinalMessage','Done!','Date',false,'Overwrite',false);
parfor i=1:N
    pause(rand);
    wb.progress(sprintf('Here is a random number:%d',randi(1000)));
end