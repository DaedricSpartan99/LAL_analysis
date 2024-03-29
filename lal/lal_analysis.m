function LALAnalysis = lal_analysis(Opts)

    %% Input Options

    % Opts.MaximumEvaluations:      int, > 0
    % Opts.ExpDesign.X:             array N x M
    % Opts.ExpDesign.LogLikelihood: array N x 1
    % Opts.ExpDesign.InitEval       int       
    % Opts.LogLikelihood:           UQModel
    % Opts.Prior:                   UQInput
    % Opts.Discrepancy              UQInput
    % Opts.Bus.logC:                double
    % Opts.Bus.p0:                  double, 0 < p0 < 0.5
    % Opts.Bus.BatchSize:           int, > 0
    % Opts.Bus.MaxSampleSize        int, > 0
    % Opts.PCE.MinDegree:           int, > 0
    % Opts.PCE.MaxDegree:           int, > 0
    % Opts.ExpDesign.FilterZeros    logical, filter experimental design

    %% Output fields

    % LALAnalysis.ExpDesign.X:              enriched design, array N_out x M
    % LALAnalysis.ExpDesign.LogLikelihood:  enriched design, array N_out x 1
    % LALAnalysis.BusAnalysis:              BusAnalysis struct
    % LALAnalysis.Opts:                     LALAnalysis options struct

    %% Execution

    % Handles
    log_prior = @(x) uq_evalLogPDF(x, Opts.Prior);

    % Initialize output following initial guesses
    if isfield(Opts.ExpDesign, 'InitEval')

        X = uq_getSample(Opts.Prior, Opts.ExpDesign.InitEval); % 'LHS'

        logL = Opts.LogLikelihood(X);
    else
        X = Opts.ExpDesign.X;
        logL = Opts.ExpDesign.LogLikelihood;
    end

    if ~isfield(Opts, 'PlotConvergence')
        Opts.PlotConvergence = true;
    end

    if ~isfield(Opts, 'PlotLogLikelihood')
        Opts.PlotLogLikelihood = false;
    end

    post = logL + log_prior(X);

    %Opts.Validation.PostLogLikelihood = max(Opts.Validation.PostLogLikelihood, -1200);
    %Opts.Validation.PriorLogLikelihood = max(Opts.Validation.PriorLogLikelihood, -1200);

    if Opts.PlotConvergence

        reliability_indexes = zeros(1, Opts.MaximumEvaluations);

        figure
        axr = semilogy([1],[1],'-o', 'MarkerSize', 12, 'MarkerEdgeColor', 'black', 'MarkerFaceColor', "#EDB120", 'LineWidth', 1.);
        grid on
        xlabel('Iteration');
        ylabel('Reliability index');
        title('Convergence monitoring');
    end

    % plot setup
    if Opts.PlotLogLikelihood
        figure
        tiledlayout(2,2)

        check_interval = [min(Opts.Validation.PostLogLikelihood), max(Opts.Validation.PostLogLikelihood)];

        ax1 = nexttile;
        hold on
        plot(ax1, check_interval, check_interval);
        post_valid_plot = scatter(ax1, Opts.Validation.PostLogLikelihood, Opts.Validation.PostLogLikelihood);
        hold off
        title(ax1, 'Posterior samples')
        ylabel(ax1, 'Surrogate Log-Likelihood')
        xlabel(ax1, 'Real Log-Likelihood')
        xlim(check_interval)
        ylim(check_interval)

        check_interval = [min(Opts.Validation.PriorLogLikelihood), max(Opts.Validation.PriorLogLikelihood)];

        ax2 = nexttile;
        hold on
        plot(ax2, check_interval , check_interval);
        prior_valid_plot = scatter(ax2, Opts.Validation.PriorLogLikelihood, Opts.Validation.PriorLogLikelihood);
        hold off
        title(ax2, 'Prior samples')
        ylabel(ax2, 'Surrogate Log-Likelihood')
        xlabel(ax2, 'Real Log-Likelihood')
        xlim(check_interval)
        ylim(check_interval)

        ax3 = nexttile;
        histogram(ax3, logL, 12);
        title(ax3, 'Experimental design emplacement')
        xlabel('Log-likelihood')

        ax4 = nexttile;
        W_pca = pca(X);
        T = X * W_pca(:,1:2);
        Tpost = Opts.Validation.PostSamples * W_pca(:,1:2);
        hold on
        pca_post_scatter = scatter(ax4, Tpost(:,1), Tpost(:,2), 5);
        pca_scatter = scatter(ax4, T(:,1), T(:,2), 20, logL, 'Filled');
        pca_colorbar = colorbar(ax4);
        hold off
        title(ax4, 'Experimental design PCA')
        xlabel(ax4, 'x1')
        ylabel(ax4, 'x2')

        % Histogram figure
        figure
        m_tile = factor(size(X,2));
        m_tile = m_tile(1);
        tiledlayout(size(X,2)/m_tile,m_tile)

        hist_plots = cell(size(X,2),1);

        for k = 1:size(X,2)
            hist_plots{k}.ax = nexttile;

            hold on
            hist_plots{k}.Prior = histogram(Opts.Validation.PriorSamples(:,k),50);
            hist_plots{k}.Post = histogram(Opts.Validation.PostSamples(:,k),50); 
            hist_plots{k}.SuS = histogram(Opts.Validation.PostSamples(:,k),50); 
            hist_plots{k}.Opt = xline(mean(Opts.Validation.PostSamples(:,k)), 'LineWidth', 5);
            %hist_plots{k}.SuSMedian = xline(mean(Opts.Validation.PostSamples(:,k)),  '--b', 'LineWidth', 5);
            hold off
            legend('Prior', 'Posterior', 'SuS-Samples', 'Min cost point')
            title(sprintf('Component %d',k))
        end
        
        drawnow
    end

    if isfield(Opts, 'StoreBusResults') && Opts.StoreBusResults
        LALAnalysis.lsfEvaluations = cell(Opts.MaximumEvaluations,1);
    end

    if ~isfield(Opts, 'ClusteredMetaModel')
        Opts.ClusteredMetaModel = false;
    end

    if ~isfield(Opts, 'ClusterRange')
        Opts.ClusterRange = 3;
    end

    if ~isfield(Opts, 'SelectMax')
        Opts.SelectMax = min(Opts.ClusterRange);
    end

    if ~isfield(Opts, 'ClusterMaxIter')
        Opts.ClusterMaxIter = 50;
    end

    if ~isfield(Opts, 'OptMode')
        Opts.OptMode = 'clustering';
    end

    if ~isfield(Opts, 'GradientCost')
        Opts.GradientCost = false;
    end

    if ~isfield(Opts, 'FilterOutliers')
        Opts.FilterOutliers = false;
    end

    %post_input = Opts.Prior;
    
    % Begin iterations
    for i = 1:Opts.MaximumEvaluations

        %% Construct a PC-Kriging surrogate of the log-likelihood

        % Create definitive PCK
        MetaOpts = Opts.MetaOpts;
        MetaOpts.Type = 'Metamodel';
        MetaOpts.Input = Opts.Prior; 
                
        if isfield(Opts, 'Validation')
            MetaOpts.ValidationSet.X = Opts.Validation.PostSamples;
            MetaOpts.ValidationSet.Y = Opts.Validation.PostLogLikelihood;
        end

        % Address instabilities in the experimental design (0.05 quantile)
        if isfield(Opts, 'cleanQuantile')   
            in_logL_mask = logL > quantile(logL,Opts.cleanQuantile);
            X_cleaned = X(in_logL_mask,:);
            logL_cleaned = logL(in_logL_mask); 
        else

            X_cleaned = X;
            logL_cleaned = logL;
        end

        % Create MetaModel
        if Opts.ClusteredMetaModel 

            ClustModelOpts.MetaOpts = MetaOpts;
            ClustModelOpts.ExpDesign.X = X_cleaned;
            ClustModelOpts.ExpDesign.Y = logL_cleaned;
            %ClustModelOpts.DBEpsilon = Opts.DBEpsilon;
            ClustModelOpts.DBMinPts = Opts.DBMinPts;

            clust_logL_PCK = clustered_PCK(ClustModelOpts);
            logL_PCK = clust_logL_PCK.MetaModel;
        else

            MetaOpts.ExpDesign.X = X_cleaned;
            MetaOpts.ExpDesign.Y = logL_cleaned;

            logL_PCK = uq_createModel(MetaOpts, '-private');

            fprintf("Iteration number: %d\n", i)
            fprintf("PCK LOO error: %g\n", logL_PCK.Error.LOO)

            if isfield(Opts, 'Validation')
                fprintf("PCK Validation error: %g\n", logL_PCK.Error.Val)
            end
        end   
        
        % TODO: Determine optimal c = 1 / max(L)

        % Execute Bayesian Analysis in Bus framework
        BayesOpts.Prior = Opts.Prior;

        if isfield(Opts, 'Bus')
            BayesOpts.Bus = Opts.Bus;
        else
            BayesOpts.Bus.CStrategy = 'max';
        end

        BayesOpts.LogLikelihood = logL_PCK; 

        % Adaptively determine constant Bus.logC
            % TODO: better algorithm
            if ~isfield(Opts.Bus, 'logC')
    
                % Default strategy
                if ~isfield(BayesOpts.Bus, 'CStrategy')
                    BayesOpts.Bus.CStrategy = 'max';
                end
               
                % Take specified strategy
                switch BayesOpts.Bus.CStrategy
                    case 'max'
                        BayesOpts.Bus.logC = -max(logL);
                    case 'latest'
                        BayesOpts.Bus.logC = -logL(end);
                    case 'maxpck' 
    
                        % get maximum of experimental design
                        [maxl_logL, maxl_index] = max(logL_cleaned);
                        maxl_x0 = X_cleaned(maxl_index, :);

                        % sample from prior distribution for other points
                        Opts.Maxpck.priorSamples = 5000;
                        x_prior = uq_getSample(Opts.Prior, Opts.Maxpck.priorSamples);

                        x0 = mean(x_prior);
                        lb = min(x_prior);
                        up = max(x_prior);

                        f = @(x) -uq_evalModel(logL_PCK, x);
                        gs = GlobalSearch;
                        problem = createOptimProblem('fmincon','x0',x0,'objective',f,'lb',lb,'ub',up);
                        xopt_pck = run(gs,problem)
                        logL_pck_opt = uq_evalModel(logL_PCK, xopt_pck);

%                         Opts.Maxpck.qbounds = [0.025, 0.975];
%                         qxb = min(quantile(x_prior, Opts.Maxpck.qbounds(1)), min(X_cleaned));
%                         qxu = max(quantile(x_prior, Opts.Maxpck.qbounds(2)), max(X_cleaned));
%                         x_prior = x_prior(all(x_prior > qxb & x_prior < qxu, 2), :);
% 
%                         % rescale data via normalization
%                         x_mean = mean(x_prior);
%                         x_std = std(x_prior);
% 
%                         % Optimize from each point
%                         Opts.Maxpck.startPoints = 5;
%                         z0 = ([maxl_x0; x_prior(1:Opts.Maxpck.startPoints,:)] - x_mean) ./ x_std;
%                         xmin = (min(x_prior) - x_mean) ./ x_std;
%                         xmax = (max(x_prior) - x_mean) ./ x_std;
%     
%                         % determine c from experimental design
%                         c_zero_variance = -maxl_logL;    
%     
%                         % define inverse log-likelihood to find the minimum of
%                         f = @(z) -uq_evalModel(logL_PCK, x_std .* z + x_mean);
% 
%                         opt_pck = zeros(size(z0,1),1);
% 
%                         for opt_ind = 1:size(z0,1)
% 
%                             % maximize surrogate log-likelihood
%                             options = optimoptions('fmincon', 'Display', 'off');
%                             [~, maxl_pck, found_flag] = fmincon(f, z0(opt_ind,:), [], [], [], [], xmin, xmax, [], options);
%         
%                             % Take negative log-likelihood (overestimation)
%                             if found_flag >= 0
%                                 opt_pck(opt_ind) = -maxl_pck;
%                             else
%                                 fprintf('Found patological value of log(c) estimation, correcting with experimental design maximum.\n')
%                                 opt_pck(opt_ind) = -c_zero_variance;
%                             end
%                             fprintf("Peak index %d, fmincon flag: %d, log-likelihood: %f \n", opt_ind, found_flag, -maxl_pck)
%                         end
    
%                        BayesOpts.Bus.logC = min(c_zero_variance, -max(opt_pck));
                        %BayesOpts.Bus.logC = -max(opt_pck);

                        BayesOpts.Bus.logC = min(-max(logL), -logL_pck_opt);
    
                    case 'delaunay'
    
                        if ~isfield(Opts.Bus, 'Delaunay') || ~isfield(Opts.Bus.Delaunay, 'maxk')
                            Opts.Bus.Delaunay.maxk = 10;
                        end
    
                        % Rescale experimental design
                        %stdX = (X - mean(X)) ./ std(X);
                        %stdX = X ./ max(X);
                        T = delaunayn(X_cleaned, {'QbB'});
        
                        % compute midpoints and maximize variances
                        W_del = reshape(X_cleaned(T,:), size(T,1), size(T,2), []);
                        Wm = mean(W_del, 2);
                        midpoints = permute(Wm, [1,3,2]);
                        [mmeans, mvars] = uq_evalModel(logL_PCK , midpoints);
                        
                        % get only a certain number of max variance
                        [~, varindex] = maxk(mvars, Opts.Bus.Delaunay.maxk);
                        midpoints = midpoints(varindex,:);
                        mmeans = mmeans(varindex);
    
                        % sort by greatest mean
                        [~, meanindex] = sort(mmeans, 'descend');
                        midpoints = midpoints(meanindex,:);
        
                        BayesOpts.Bus.logC = -uq_evalModel(logL_PCK , midpoints(1,:));
                end
            end

        %% Perform Bus Analysis

        fprintf("Taking constant logC: %g\n", BayesOpts.Bus.logC)
        BusAnalysis = bus_analysis(BayesOpts);

        % evaluate U-function on the limit state function
        % Idea: maximize misclassification probability
        px_samples = BusAnalysis.Results.Bus.PostSamples;

        % Normalize data before clustering
        x_mean = mean(px_samples(:,2:end));
        x_std = std(px_samples(:,2:end));
        x_norm = (px_samples(:,2:end) - x_mean) ./ x_std;

        if Opts.FilterOutliers
            minpts = 50;
            kD = pdist2(x_norm,x_norm,'euc','Smallest',minpts);
            kD = sort(kD(end,:));
            [~,eps_dbscan_ind] = knee_pt(kD, 1:length(kD));
            eps_dbscan = kD(eps_dbscan_ind);

            dbscan_labels = dbscan(x_norm, eps_dbscan,minpts);

            % Filter spacial outliers
            px_samples = px_samples(dbscan_labels ~= -1, :);
            x_norm = x_norm(dbscan_labels ~= -1, :);
        end

        % Filter out outliers
        %qXb = quantile(px_samples(:,2:end), 0.025);
        %qXt = quantile(px_samples(:,2:end), 0.975);
        %px_samples = px_samples(all(px_samples(:,2:end) > qXb & px_samples(:,2:end) < qXt,2), :);            
      
        % Take lsf evaluations
        [mean_post_LSF, var_post_LSF] = uq_evalModel(BusAnalysis.Results.Bus.LSF, px_samples);
    
        % Compute surrogate log-likelihood
        %logL_pck_samples = uq_evalModel(logL_PCK, px_samples(:,2:end));

        % Compute U-function and misclassification probability
        cost_LSF = abs(mean_post_LSF) ./ sqrt(var_post_LSF);

        % Compute total cost function
        W = normcdf(-cost_LSF);

        % Include gradient estimation
        if Opts.GradientCost

            rw_std = x_std / 1e4;
            grad = zeros(size(mean_post_LSF,1),10);
            grad_std = zeros(size(mean_post_LSF,1),10);

            for grad_j = 1:10
                rw = random('normal', 0, rw_std);
            
                [rw_mean_post_LSF, rw_var_post_LSF] = uq_evalModel(BusAnalysis.Results.Bus.LSF, px_samples + [0, rw]);

                grad(:,grad_j) = abs(rw_mean_post_LSF - mean_post_LSF) / norm(rw);
                grad_std(:,grad_j) = sqrt(rw_var_post_LSF + var_post_LSF) / norm(rw);
            end

            [grad, best_grad] = max(grad, [], 2);
            grad_std = sum(grad_std .* bsxfun(@eq, cumsum(ones(size(grad_std)), 2), best_grad),2);       

            cost_grad = grad ./ grad_std;
   
            W = W .* normcdf(cost_grad);
        end

        %% Determine optimal sample
        
        switch Opts.OptMode
            case 'clustering'
            
                if length(Opts.ClusterRange) == 1
                    [cost_labels, c_norm] = kw_means(x_norm, W, Opts.ClusterRange, Opts.ClusterMaxIter); 
                
                    % Check consistency
                    [c_uniques, ~] = count_unique(cost_labels);

                    c_norm = c_norm(c_uniques,:);

                    % clean up singularities
                    finite_mask = all(isfinite(c_norm),2);
                    c_norm = c_norm(finite_mask,:);
                    cost_labels = cost_labels(any(cost_labels == c_uniques(finite_mask)', 2));
                else
                    [cost_labels, c_norm] = w_means(x_norm, W, Opts.ClusterRange, Opts.ClusterMaxIter);
                end
        
                % Un-normalize xopt and sort by weights
                xopt = c_norm .* x_std + x_mean;

                c_labels = unique(cost_labels);
                c_weights = zeros(length(c_labels),1);
                for j = 1:length(c_labels)
                    lab = c_labels(j);
                    p_j = px_samples(cost_labels == lab,1);
                    w_j = W(cost_labels == lab);
        
                    %xopt(j,:) = colwise_weightedMedian(px_samples(cost_labels == j,2:end),w_j);
                    %xopt(j,:) = sum(px_samples(cost_labels == j,2:end) .* w_j) / sum(w_j);
        
                    % Take greatest likelihood points
                    c_weights(j) = sum(p_j .* w_j);
                    %c_weights(j) = weightedMedian(w_j, p_j);
                    %c_weights(j) = sum(w_j);
                end

                if size(xopt,1) ~= length(unique(cost_labels))
                    disp("Inconsistent size")
                end
        
                [~, opt_ind] = maxk(c_weights, min(Opts.SelectMax, length(c_weights)));
                xopt = xopt(opt_ind,:);

                
            case 'single'

                [~,opt_ind] = min(cost_LSF);
                xopt = px_samples(opt_ind,2:end);
        end
    
        fprintf("Optimal X chosen to: ")
        display(xopt)
        fprintf("\n")

        %fprintf("With cluster cost: ")
        %display(c_weights)
        %fprintf("\n")

        % Compute surrogate log-likelihood
        logL_pck_opt = uq_evalModel(logL_PCK, xopt);

        fprintf("Optimal points surrogate log-likelihood: ")
        display(logL_pck_opt)
        fprintf("\n")

        % Compute real log-likelihood
        logL_opt = Opts.LogLikelihood(xopt);
        
        fprintf("Optimal points real log-likelihood: ")
        display(logL_opt)
        fprintf("\n")
        
        % Add to experimental design
        X = [X; xopt];
        logL = [logL; logL_opt ];
        post = [post; logL_opt + log_prior(xopt)];

        % Store result as history
        LALAnalysis.OptPoints(i).X = xopt;
        LALAnalysis.OptPoints(i).logL = logL(end);
        %LALAnalysis.OptPoints(i).lsf = uq_evalModel(BusAnalysis.Results.Bus.LSF, centroids);
        LALAnalysis.PCK(i) = logL_PCK;

        if isfield(Opts, 'StoreBusResults') && Opts.StoreBusResults
            % Store in results
            LALAnalysis.BusAnalysis(i) = BusAnalysis;
            % Store evaluations
            LALAnalysis.lsfEvaluations{i} = cost_LSF;
            % Store target
            LALAnalysis.logC(i) = BayesOpts.Bus.logC;
        end

        % Update convegence monitor
        if Opts.PlotConvergence
            reliability_indexes(i) = BusAnalysis.Results.ReliabilityIndex;
            set(axr, 'XData', 1:i, 'YData',reliability_indexes(1:i));

            drawnow
        end

        % Update plot
        if Opts.PlotLogLikelihood

            set(post_valid_plot, 'XData', Opts.Validation.PostLogLikelihood, 'YData', uq_evalModel(logL_PCK, Opts.Validation.PostSamples));
            set(prior_valid_plot, 'XData', Opts.Validation.PriorLogLikelihood, 'YData', uq_evalModel(logL_PCK, Opts.Validation.PriorSamples));
            histogram(ax3, logL_cleaned, 12);
            %set(logLhist, 'Data', logL_cleaned, 'BinLimits', [min(logL_cleaned), max(logL_cleaned)]);

            W_pca = pca(X_cleaned);
            T = X_cleaned * W_pca(:,1:2);
            Tpost = Opts.Validation.PostSamples * W_pca(:,1:2);
            set(pca_scatter, 'XData',T(:,1), 'YData', T(:,2), "CData", logL_cleaned)
            set(pca_post_scatter, 'XData', Tpost(:,1), 'YData', Tpost(:,2))
            set(pca_colorbar, 'Limits', [min(logL_cleaned), max(logL_cleaned)])
            %pca_scatter = scatter(T(:,1), T(:,2), "ColorVariable", logL, 'Filled')

            % Histogram plots
            for k = 1:size(X,2)
                set(hist_plots{k}.SuS, 'Data', px_samples(:,k+1))
                set(hist_plots{k}.Opt, 'Value', xopt(1,k));
                %set(hist_plots{k}.SuSMedian, 'Value', x_medians(k));
            end

            drawnow
        end
    end

    %% Run a latest subset simulation starting from max of experimental design

    fprintf("Finalizing Bayesian analysis\n")

    Opts.Maxpck.priorSamples = 5000;
    x_prior = uq_getSample(Opts.Prior, Opts.Maxpck.priorSamples);

    x0 = mean(x_prior);
    lb = min(x_prior);
    up = max(x_prior);

    f = @(x) -uq_evalModel(logL_PCK, x);
    gs = GlobalSearch;
    problem = createOptimProblem('fmincon','x0',x0,'objective',f,'lb',lb,'ub',up);
    xopt_pck = run(gs,problem)
    logL_pck_opt = uq_evalModel(logL_PCK, xopt_pck);
    
    BayesOpts.Bus = Opts.Bus;
    BayesOpts.Bus.logC = min(-max(logL), -logL_pck_opt);
    BayesOpts.Prior = Opts.Prior;

    fprintf("Constant log(c) = %f\n", BayesOpts.Bus.logC)

    BayesOpts.Bus.BatchSize = 10000;
    BayesOpts.Bus.MaxSampleSize = 1000000;

    BusAnalysis = bus_analysis(BayesOpts);

    px_samples = BusAnalysis.Results.Bus.PostSamples;

    %% Store results

    % Experimental design
    LALAnalysis.ExpDesign.X = X;
    LALAnalysis.ExpDesign.LogLikelihood = logL;
    LALAnalysis.ExpDesign.UnNormPosterior = post;

    % Posterior samples
    LALAnalysis.PostSamples = px_samples(mean_post_LSF < 0, 2:end); 

    % Evidence estimation
    LALAnalysis.Evidence = BusAnalysis.Results.Evidence;

    % Options
    LALAnalysis.Opts = Opts;
end