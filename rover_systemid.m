clear;
close all;
filename = 'Test6/00000028.csv';
train_data = csvread(filename, 2, 0);  
% states(x) [x y yaw vx vy r] 
% vx: longitudinal velocity (body frame), vy: lateral velocity (body frame)

% output(y) = [x y yaw vx vy r]  (ground truth is the same as output)
% vx: North velocity (world frame) vy: East velocity (world frame)

% input [steering, wheel_rotation]

% compared with drone code, rover's code is in NED frame and the yaw value
% range is [-pi, pi]
NX = 6;    
NY = 6;
NU = 2;

%reset start time
train_data(:,1) = train_data(:,1) - train_data(1,1);

% %trim data (remove unnecessary parts with starting point (s) and end point (s)
%     sp = 10; % starting skip (s)
%     ep = 20; % end skip (s)
%     isp = find(train_data(:,1) * 1e-6 > sp, 1);
%     iep = find(train_data(:,1) > train_data(end,1) - ep * 1e6, 1);
%     train_data = train_data(isp:iep, :);
    
raw_timestamps = train_data(:,1) * 1e-6;    %(s)    time vector
raw_states = train_data(:,2:13);            % array of state vector: 12 states

% converting: motor_input = (pwm - 1100)/900 
% motor signal [0..1] --> motor speed (PWM servo) [0...2000]
% raw_motors = (((train_data(:,14:17)*1000)+1000)-1100)/900;   %(((0.5595*1000)+1000)-1100)/900=0.51
raw_motors = train_data(:,14:17);

raw_N = size(train_data,1);                 % size of samples

%%%Preprocessing ================================


% extract 6 states  [x y yaw vx vy r]
raw_states(:,1) = raw_states(:,1);
raw_states(:,2) = raw_states(:,2);
raw_states(:,3) = raw_states(:,6);
raw_states(:,4) = raw_states(:,7);
raw_states(:,5) = raw_states(:,8);
raw_states(:,6) = raw_states(:,12);
raw_states(:,7:12) = [];
% raw_states(:,1) = raw_states(:,7);
% raw_states(:,2) = raw_states(:,8);
% raw_states(:,3) = raw_states(:,12);
% raw_states(:,4:12) = []

% convert input signals
% steering (motor1) : 0-0.5 is left turn, 0.5-1 is right turn. => pi
% [-0.5...0.5] *
% throttle (motor3):  
raw_motors(:,1) = (raw_motors(:,1)-0.5)*pi;   
raw_motors(:,2) = raw_motors(:,3)-0.5;
raw_motors(:,3:4) = [];


%%resample (for uniform sampling time)
desiredFs = 400; %(default 50Hz)
Ts = 1/desiredFs;
[res_states, res_timestamps] = resample(raw_states,raw_timestamps,desiredFs);
[res_motors, res_timestamps] = resample(raw_motors,raw_timestamps,desiredFs);
N = size(res_timestamps,1);

%%states start from zero
% res_states = res_states - res_states(1,:);
res_states(1,4) = 0.1;
res_states(:, 3) = wrapToPi(res_states(:, 3));

%plot (original and sampeled)
% title_name = ["x(North)", "y(West)", "z(up)", "roll", "pitch", "yaw", "vx", "vy", "vz", "p", "q", "r"]; 
title_name = ["x(longitudinal-north)", "y(lateral-east)", "yaw", "vx", "vy", "r"]; 
% title_name = ["vx(longitudinal-north)", "vy(lateral-east)", "r"]; 

figure;
for n=1:NY
    subplot(NY/3, 3, n);
    plot(raw_timestamps,raw_states(:,n),'b.-');
    hold on;
    plot(res_timestamps, res_states(:,n),'r-');
    legend('Original','Resampled');
    title(title_name(n));
end
% figure;
%     plot(raw_timestamps,raw_states(:,1),'b.-');
%     hold on;
%     plot(res_timestamps, res_states(:,1),'r-');
%     legend('Original','Resampled');


%%convert to column vectors
timestamps = res_timestamps';
states = res_states';   
motors = res_motors';
%%%============================================

%% ==============================================================
%% parameters (default)
% m = 1700
% a = 1.5
% b = 1.5
% Cx = 8500
% Cy = 405.1
% CA = 170.6
% m = 1700
% a = 0.5
% b = 0.5
% Cx = 17000
% Cy = 2500
% CA = 170.6
m = 1.7
a = 0.5
b = 0.7
Cx = 17
Cy = 17
CA = 0.1706

p = [m; a; b; Cx; Cy; CA];

%====================================
% test the model implementation
t = timestamps;
x = zeros(NX,N);   % x(1:NX,1) = states(:,1);

%set initial value
x([1:3, 6], 1) = states([1:3, 6], 1);
ef2bf_m = [cos(x(3, 1)), sin(x(3, 1));
        -sin(x(3, 1)), cos(x(3, 1))];
x(4:5, 1) = ef2bf_m * states(4:5, 1);
          

dx = zeros(NX,N);
y = zeros(NY,N);
u = motors;
err = zeros(NX, N);

for n=1:N-1
    dt = t(n+1) - t(n);
    [dx(:,n),y(:,n)] = rover_m(t(n), x(:,n), u(:,n), m,a,b,Cx,Cy,CA);
    x(:,n+1) = x(:,n) + dx(:,n) * dt; 
    x(3,n+1) = wrapToPi(x(3,n+1)); % to [-pi, pi]
    
    if abs(x(4,n+1)) > 30
        x(4,n+1) = sign(x(4,n+1)) * 30;
    end
    
    if abs(x(5,n+1)) > 30
        x(5,n+1) = sign(x(5,n+1)) * 30;
    end
    
    if abs(x(6,n+1)) > 5
        x(6,n+1) = sign(x(6,n+1)) * 5;
    end


    
%     k-step ahead estiamtion (sync at every-k loop)
%     k = desiredFs;
%     if mod(n, k) == 0
%           x([1:3, 6], n+1) = states([1:3, 6], n+1);
%           ef2bf_m = [cos(x(3, n+1)), sin(x(3, n+1));
%                     -sin(x(3, n+1)), cos(x(3, n+1))];
%           x(4:5, n+1) = ef2bf_m * states(4:5, n+1);
%     end
%     
    err(:, n) = abs(y(:, n) - states(:, n));
end

% err_mean = mean(err, 2);
% err_max = max(err, [], 2);
% err_quants = quantile(err', [0.25, 0.75])';
% err_thresh = err_quants(:, 2) + 1.5 * (err_quants(:, 2)-err_quants(:, 1));

figure;
for n=1:NY
    if NY > 1
        subplot(NY/3, 3, n);
    end
    yyaxis left
    plot(timestamps, states(n,:),'r.-');
    hold on;
    plot(t, y(n,:), 'b-');  
%     yyaxis right
%     area(t, err(n, :), 'FaceAlpha', 0.8, 'EdgeColor', 'none');
%     plot(t, err_mean(n, 1)*ones(1, length(t)), 'g');
%     plot(t, err_max(n, 1)*ones(1, length(t)), 'r');
%     plot(t, err_thresh(n, 1)*ones(1, length(t)), 'b');
    legend('State', 'Model', 'Error', 'Mean\_err', 'Max\_err', 'Thresh\_err');
    title(title_name(n));
end
% figure;
%     plot(timestamps, states(1,:),'r.-');
%     hold on;
%     plot(t, y(1,:), 'b-');  
%     legend('State', 'Model');


return

%====================================
%% Nonlinear grey-box model - idnlgrey
%
% data = iddata(states, motors, 'SamplingInstants', timestamps); %non-uniform sampling
data = iddata(states', motors', Ts);    % uniform sampling (Ts)
Filename       = 'rover_m';                % File describing the model structure.
Order          = [NY NU NX];               % Model orders [ny nu nx].
Parameters    = p   % Initial parameter vector.
InitialStates = x(:,1);
nlgr_m    = idnlgrey(Filename, Order, Parameters, InitialStates);   %Nonlinear grey-box model

%% Parameter setting
% 
nlgr_m.Parameters(1).Fixed = true;      
% nlgr_m.Parameters(2).Fixed = true;      
% nlgr_m.Parameters(3).Fixed = true;
% nlgr_m.Parameters(4).Fixed = true;
% nlgr_m.Parameters(5).Fixed = true;      
% nlgr_m.Parameters(6).Fixed = true;      
% %-----------------------------------------------------------
nlgr_m.Parameters(1).Minimum = 0.5;
% nlgr_m.Parameters(2).Minimum = 0.10;      
% nlgr_m.Parameters(3).Minimum = 0.10;      
nlgr_m.Parameters(4).Minimum = 0;
nlgr_m.Parameters(5).Minimum = 0;
nlgr_m.Parameters(6).Minimum = 0;

nlgr_m.Parameters(1).Maximum = 2;
% nlgr_m.Parameters(2).Maximum = 0.30; %0.16;
% nlgr_m.Parameters(3).Maximum = 0.30; %0.16;
% nlgr_m.Parameters(4).Maximum = 0.30; %0.20;
% nlgr_m.Parameters(5).Maximum = 1.6;%1.4;         %weight     
% nlgr_m.Parameters(6).Maximum = 0.1;        %I_x

% nlgr_m = setpar(nlgr_m, 'Name', {'m' 'a' 'b' 'Cx' 'Cy' 'CA'});
% nlgr_m = setpar(nlgr_m, 'Unit', {'m' 'm' 'm' 'm' 'kg' 'kg*m^2'});
% nlgr_m.SimulationOptions.AbsTol = 1e-10;
% nlgr_m.SimulationOptions.RelTol = 1e-10;

% System Identification
%%SI options ===================================================
%
opt = nlgreyestOptions;
opt.Display = 'on';
%opt.GradientOptions.DiffMaxChange              % default: Inf
% opt.GradientOptions.DiffMinChange = 1e-3;    % defailt: 0.01*sqrt(eps) = 1.4901e-10
%opt.GradientOptions.DiffScheme = 'auto';       % default: auto, 'Central approximation', 'Forward approximation', 'Backward approximation'
% opt.GradientOptions.GradientType = 'auto';      % default: auto, 'Basic', 'Refined'
% opt.SearchMethod = 'gn';                        % default: auto(lsqnonlin), gn, gna, lm, grad, fmincon
% opt.SearchOption.Tolerance = 1e-10;     %FunctionTolerance (1e-5) - gn
% opt.SearchOption.Algorithm = 'interior-point';     % interior-point, sqp, active-set, trust-region-reflective, 
% opt.SearchOption.TolFun = 1e-10;      %FunctionTolerance (1e-5)
% opt.SearchOption.TolX = 1e-10;        %StepTolerance (1e-6)
opt.SearchOption.MaxIter = 100;
% opt.SearchOption.Advanced.GnPinvConst = 10000000;
%opt.Regularization.Nominal = 'model';          %default: 'zero'

%--------------------------------------------
% outputweight = eye(NX);
% outputweight(1,1) = 1;
% outputweight(2,2) = 1;
% outputweight(3,3) = 1;
% outputweight(4,4) = 1000;
% outputweight(5,5) = 1;
% outputweight(6,6) = 1;
% opt.OutputWeight = outputweight;

model = nlgreyest(data, nlgr_m, opt);    %Estimate nonlinear grey-box model parameters
present(model);
figure; compare(model, data);

% return
%%===================================================
%% plot results
%%

% sim vs prediction
input_data = iddata([], motors', Ts);
ys = sim(model,input_data);
K = 10; % K-step-ahead prediction
yp = predict(nlgr_m, data, K);

figure;
for n=1:NY
    if NY > 1
        subplot(NY/3, 3, n);
    end
    plot(timestamps, data.y(:,n), 'k-');
    hold on; 
    plot(timestamps, ys.y(:,n),'r.-');
    hold on;
    plot(timestamps, yp.y(:,n), 'b.');  
    legend('truth', 'simulated', 'predicted');
    title(title_name(n));
end

