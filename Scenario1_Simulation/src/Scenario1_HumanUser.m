%% Scenario 1: Human User - Queueing System Analysis
% Find minimum buffer capacities (Kc, Kg) for system ergodicity
% Tests 3 routing policies: Uniform Probability, Lower Load Queue, Unified GPUs

clear; close all; clc

%% System Parameters
Tsim = 7000;            % Simulation time
gamma_p = 5;            % Arrival rate (prompts/min)
mu_c = 8;               % CPU service rate (prompts/min)
mu_g = 5;               % GPU service rate (prompts/min)
p_a = 0.7;              % Acceptance probability

%% Test Configuration
Kc_values = [5 7 8 10 15];      % CPU2 buffer capacities to test
Kg_values = [5 7 8 10 15];      % GPU buffer capacities to test
seed_values = [1 2 3 4 5];      % Random seeds for statistical confidence

% Simulink models for each routing policy
modelNames = ["same_probability_model", "lower_load_model", "unified_gpus_model"];
configNames = ["Uniform Probability (50/50)", "Lower Load Queue", "Unified GPUs (M/M/2/K)"];

% Store results
all_min_kc = zeros(1, 3);
all_min_kg = zeros(1, 3);

%% Main Simulation Loop
for config = 1:3
    modelName = modelNames(config);
    fprintf('\n=== Configuration %d: %s ===\n', config, configNames(config));
    
    results = [];
    
    for seed_idx = 1:length(seed_values)
        seed = seed_values(seed_idx);
        rng(seed);
        
        for Kc = Kc_values
            for Kg = Kg_values
                fprintf("Kc=%d, Kg=%d, Seed=%d... ", Kc, Kg, seed);
                
                try
                    sim(modelName + ".slx");
                catch ME
                    fprintf("ERROR: %s\n", ME.message);
                    continue;
                end
                
                % Extract queue lengths (remove warm-up period)
                vals_cpu1 = n_cpu1.Data;
                vals_cpu2 = n_cpu2.Data;
                
                if config == 3  % Unified GPUs model
                    vals_gpu = n_unified_gpus.Data;
                    L = min([length(vals_cpu1), length(vals_gpu), length(vals_cpu2)]);
                    idx = floor(L/2):L;
                    Xgpu1 = mean(vals_gpu(idx));
                    Xgpu2 = NaN;
                    % Ergodicity criterion (unified queue has capacity 2*Kg)
                    stable = (mean(vals_cpu1(idx)) < 50) && ...
                             (Xgpu1 < 0.8*2*Kg) && ...
                             (mean(vals_cpu2(idx)) < 0.8*Kc);
                else
                    vals_gpu1 = n_gpu1.Data;
                    vals_gpu2 = n_gpu2.Data;
                    L = min([length(vals_cpu1), length(vals_gpu1), length(vals_gpu2), length(vals_cpu2)]);
                    idx = floor(L/2):L;
                    Xgpu1 = mean(vals_gpu1(idx));
                    Xgpu2 = mean(vals_gpu2(idx));
                    % Ergodicity criterion
                    stable = (mean(vals_cpu1(idx)) < 50) && ...
                             (Xgpu1 < 0.8*Kg) && (Xgpu2 < 0.8*Kg) && ...
                             (mean(vals_cpu2(idx)) < 0.8*Kc);
                end
                
                Xcpu1 = mean(vals_cpu1(idx));
                Xcpu2 = mean(vals_cpu2(idx));
                
                results = [results; seed Kc Kg Xcpu1 Xgpu1 Xgpu2 Xcpu2 stable];
                fprintf("Ergodic=%d\n", stable);
            end
        end
    end
    
    % Convert to table
    results_table = array2table(results, ...
        'VariableNames', {'Seed','Kc','Kg','X_CPU1','X_GPU1','X_GPU2','X_CPU2','Ergodic'});
    
    %% Find Minimum Ergodic Capacities
    % Require 80% of seeds to be ergodic for a configuration
    unique_kc = unique(results_table.Kc);
    unique_kg = unique(results_table.Kg);
    
    min_kc = inf; min_kg = inf;
    for i = 1:length(unique_kc)
        for j = 1:length(unique_kg)
            kc_val = unique_kc(i);
            kg_val = unique_kg(j);
            rows = (results_table.Kc == kc_val) & (results_table.Kg == kg_val);
            ergodic_ratio = sum(results_table.Ergodic(rows)) / sum(rows);
            
            if ergodic_ratio >= 0.8 && (kc_val + kg_val) < (min_kc + min_kg)
                min_kc = kc_val;
                min_kg = kg_val;
            end
        end
    end
    
    fprintf('Minimum Ergodic: Kc = %d, Kg = %d\n', min_kc, min_kg);
    all_min_kc(config) = min_kc;
    all_min_kg(config) = min_kg;
    
    % Save results
    save(sprintf('results_config%d.mat', config), 'results_table', 'min_kc', 'min_kg');
end

%% Final Summary
fprintf('\n========== RESULTS SUMMARY ==========\n');
fprintf('Config 1 (Uniform 50/50):  Kc = %d, Kg = %d, Total = %d\n', all_min_kc(1), all_min_kg(1), all_min_kc(1)+all_min_kg(1));
fprintf('Config 2 (Lower Load):     Kc = %d, Kg = %d, Total = %d\n', all_min_kc(2), all_min_kg(2), all_min_kc(2)+all_min_kg(2));
fprintf('Config 3 (Unified GPUs):   Kc = %d, Kg = %d, Total = %d\n', all_min_kc(3), all_min_kg(3), all_min_kc(3)+all_min_kg(3));
fprintf('=====================================\n');
