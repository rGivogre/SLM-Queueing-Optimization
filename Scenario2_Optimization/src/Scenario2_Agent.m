%% Scenario 2: Agent - Batch Scheduling Optimization
% Minimize makespan for N prompts through CPU1 -> GPU1/GPU2 -> CPU2
% Compares random scheduling vs ILP optimization

clear; clc

%% Parameters
N_values = [5, 7, 9];           % Batch sizes to test
Seeds = [1, 2, 3, 4, 5];        % Random seeds
mu_C = 8;                       % CPU service rate (prompts/min)
mu_G = 5;                       % GPU service rate (prompts/min)
TimeLimit = 60;                 % Solver time limit (seconds)

Results = [];

%% Main Loop
for N = N_values
    for seed_val = Seeds
        rng(seed_val);
        
        % Generate processing times: P(machine, job)
        % Machines: 1=CPU1, 2=GPU1, 3=GPU2, 4=CPU2
        P = zeros(4, N);
        P(1,:) = exprnd(1/mu_C, 1, N);  % CPU1
        P(2,:) = exprnd(1/mu_G, 1, N);  % GPU1
        P(3,:) = exprnd(1/mu_G, 1, N);  % GPU2
        P(4,:) = exprnd(1/mu_C, 1, N);  % CPU2
        
        % Variant 1: Random scheduling (baseline)
        [makespan_rand, ~, ~] = random_simulation(P, N);
        
        % Variant 2: ILP optimization
        [makespan_opt, ~, ~] = optimization_model(P, N, TimeLimit);
        
        improvement = (makespan_rand - makespan_opt) / makespan_rand * 100;
        Results = [Results; N, seed_val, makespan_rand, makespan_opt, improvement];
        
        fprintf('N=%d, Seed=%d: Random=%.4f, Opt=%.4f, Improvement=%.1f%%\n', ...
                N, seed_val, makespan_rand, makespan_opt, improvement);
    end
end

%% Results Summary
fprintf('\n========== AVERAGE BY BATCH SIZE ==========\n');
for n_val = N_values
    rows = Results(:,1) == n_val;
    avg_rand = mean(Results(rows, 3));
    avg_opt = mean(Results(rows, 4));
    avg_imp = mean(Results(rows, 5));
    fprintf('N=%d: Random=%.4f, Optimized=%.4f, Improvement=%.2f%%\n', ...
            n_val, avg_rand, avg_opt, avg_imp);
end
fprintf('============================================\n');

% Save results
save('results_scenario2.mat', 'Results');

%% ==================== FUNCTIONS ====================

function [makespan, C, gpu_assign] = random_simulation(P, N)
% Simulate random GPU assignment and sequential processing
    gpu_assign = randi([0,1], 1, N);  % 1=GPU1, 0=GPU2
    t = [0 0 0 0];  % Machine availability times
    C = zeros(4, N);
    
    for j = 1:N
        % CPU1
        C(1,j) = t(1) + P(1,j);
        t(1) = C(1,j);
        
        % GPU stage
        if gpu_assign(j) == 1
            C(2,j) = max(C(1,j), t(2)) + P(2,j);
            t(2) = C(2,j);
            C(4,j) = max(C(2,j), t(4)) + P(4,j);
        else
            C(3,j) = max(C(1,j), t(3)) + P(3,j);
            t(3) = C(3,j);
            C(4,j) = max(C(3,j), t(4)) + P(4,j);
        end
        t(4) = C(4,j);
    end
    makespan = max(C(4,:));
end

function [makespan, C_out, x_out] = optimization_model(P, N, TimeLimit)
% ILP model to minimize makespan with optimal GPU assignment and sequencing
    BigM = 1000;
    
    % Decision variables
    C = optimvar('C', 4, N, 'LowerBound', 0);           % Completion times
    Cmax = optimvar('Cmax', 'LowerBound', 0);           % Makespan
    x = optimvar('x', N, 'Type', 'integer', 'LowerBound', 0, 'UpperBound', 1);  % GPU assignment
    y = optimvar('y', N, N, 'Type', 'integer', 'LowerBound', 0, 'UpperBound', 1); % Sequencing
    
    prob = optimproblem;
    prob.Objective = Cmax;
    
    % Makespan constraint
    for j = 1:N
        Makespan(j) = Cmax >= C(4,j);
    end
    
    % Release time (CPU1 starts at 0)
    for j = 1:N
        RelTime(j) = C(1,j) >= P(1,j);
    end
    
    % Flow constraints (precedence between stages)
    for j = 1:N
        Flow1(j) = C(2,j) >= C(1,j) + P(2,j) - BigM*(1-x(j));  % CPU1 -> GPU1
        Flow2(j) = C(3,j) >= C(1,j) + P(3,j) - BigM*x(j);      % CPU1 -> GPU2
        Flow3(j) = C(4,j) >= C(2,j) + P(4,j) - BigM*(1-x(j));  % GPU1 -> CPU2
        Flow4(j) = C(4,j) >= C(3,j) + P(4,j) - BigM*x(j);      % GPU2 -> CPU2
    end
    
    % Disjunctive constraints (no overlap on same machine)
    for i = 1:N
        for j = i+1:N
            % CPU1 (all jobs)
            D1_C1(i,j) = C(1,j)-P(1,j) >= C(1,i) - BigM*(1-y(i,j));
            D2_C1(i,j) = C(1,i)-P(1,i) >= C(1,j) - BigM*y(i,j);
            
            % GPU1 (only if both use GPU1)
            D1_G1(i,j) = C(2,j)-P(2,j) >= C(2,i) - BigM*(1-y(i,j)) - BigM*(1-x(i)) - BigM*(1-x(j));
            D2_G1(i,j) = C(2,i)-P(2,i) >= C(2,j) - BigM*y(i,j) - BigM*(1-x(i)) - BigM*(1-x(j));
            
            % GPU2 (only if both use GPU2)
            D1_G2(i,j) = C(3,j)-P(3,j) >= C(3,i) - BigM*(1-y(i,j)) - BigM*x(i) - BigM*x(j);
            D2_G2(i,j) = C(3,i)-P(3,i) >= C(3,j) - BigM*y(i,j) - BigM*x(i) - BigM*x(j);
            
            % CPU2 (all jobs)
            D1_C2(i,j) = C(4,j)-P(4,j) >= C(4,i) - BigM*(1-y(i,j));
            D2_C2(i,j) = C(4,i)-P(4,i) >= C(4,j) - BigM*y(i,j);
        end
    end
    
    % Add constraints to problem
    prob.Constraints.Makespan = Makespan;
    prob.Constraints.RelTime = RelTime;
    prob.Constraints.Flow1 = Flow1;
    prob.Constraints.Flow2 = Flow2;
    prob.Constraints.Flow3 = Flow3;
    prob.Constraints.Flow4 = Flow4;
    prob.Constraints.D1_C1 = D1_C1;
    prob.Constraints.D2_C1 = D2_C1;
    prob.Constraints.D1_G1 = D1_G1;
    prob.Constraints.D2_G1 = D2_G1;
    prob.Constraints.D1_G2 = D1_G2;
    prob.Constraints.D2_G2 = D2_G2;
    prob.Constraints.D1_C2 = D1_C2;
    prob.Constraints.D2_C2 = D2_C2;
    
    % Solve
    opts = optimoptions('intlinprog', 'MaxTime', TimeLimit, 'Display', 'off');
    [Sol, fval] = solve(prob, 'solver', 'intlinprog', 'Options', opts);
    
    makespan = fval;
    C_out = Sol.C;
    x_out = round(Sol.x);
end
