clear;
close all;

load('traces.mat');

% Rmat = cell2mat(non_reals(1)); 
Rmat = ABC_real; 
Raw = Rmat(:,2);
RawT = Rmat(:,1); 

[R, RT] = resample(Raw, RawT, 400);


v{1} = ABC_replay(:,2);
v{2} = AB_replay(:,2);
v{3} = AC_replay(:,2);
v{4} = BC_replay(:,2);
v{5} = A_replay(:,2);
v{6} = B_replay(:,2);
v{7} = C_replay(:,2);
v{8} = None_replay(:,2);

t{1} = ABC_replay(:,1);
t{2} = AB_replay(:,1);
t{3} = AC_replay(:,1);
t{4} = BC_replay(:,1);
t{5} = A_replay(:,1);
t{6} = B_replay(:,1);
t{7} = C_replay(:,1);
t{8} = None_replay(:,1);


title_name = ["ABC", "AB", "AC", "BC", "A", "B", "C", "None"];
%distance measure
for i=1:8
    subplot(4, 2, i);
%     [x{i}, r] = alignsignals(v{i},R);
    plot(v{i}(1:21000));
    hold on;
    plot(R(1:21000)); %plot(r);
    diff2 = abs(v{i}(1:21000) - R(1:21000));
%     yyaxis right; area(diff);ylim([0,3000]);
    yyaxis right; area(diff2);
    title(strcat(title_name(i), ": ", num2str(mean(diff)), ", ", num2str(mean(diff2))));
end

