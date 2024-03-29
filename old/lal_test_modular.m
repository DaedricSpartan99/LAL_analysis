% LAL = likelihood active learning

clearvars
rng(100,'twister')
uqlab

%% Bayesian inversion definition (single measurement)

% Measurement (single)
measurements = [3,]                % measurement value
measurement_error = 0.2   % measurement confindence interval = 2 * std 

% Prior definition
PriorOpts.Name = 'Prior'
PriorOpts.Marginals(1).Type = 'Gaussian'    % prior form
PriorOpts.Marginals(1).Moments = [0., 1.]   % prior mean and variance
PriorInput = uq_createInput(PriorOpts);

% Model definition
a = 2
ModelOpts.Name = 'myModel';
ModelOpts.mFile = 'myModel'           % model selection
ModelOpts.Parameters.a = a;
myModel = uq_createModel(ModelOpts);  

% Initial experimental design
init_expdesign = 5;


%% Likelihood definition for inversion
LOpts.Name = 'log_likelihood_model';
LOpts.mFile = 'log_likelihood_model';
LOpts.Parameters.ForwardModel = myModel;
LOpts.Parameters.y = measurements;
LOpts.Parameters.Discrepancy = (measurement_error / 2)^2;     % discrepancy model

LogLikelihoodModel = uq_createModel(LOpts);

%% LAL setup and hyperparameters tuning

LALOpts.Bus.logC = log(sqrt(2*pi*LOpts.Parameters.Discrepancy))    % best value: 1 / (max L + small_quantity) 
LALOpts.Bus.p0 = 0.1                            % Quantile probability for Subset
LALOpts.Bus.BatchSize = 1e4                             % Number of samples for Subset simulation
LALOpts.Bus.MaxSampleSize = 1e5;
LALOpts.MaximumEvaluations = 20

LALOpts.ExpDesign.X = uq_getSample(init_expdesign);
LALOpts.ExpDesign.LogLikelihood = uq_evalModel(LogLikelihoodModel, LALOpts.ExpDesign.X);

LALOpts.PCE.MinDegree = 2;
LALOpts.PCE.MaxDegree = 12;

LALOpts.LogLikelihood = LogLikelihoodModel;
LALOpts.Prior = PriorInput;

LALAnalysis = lal_analysis(LALOpts);

%% Graphics setup


set(groot,'defaulttextinterpreter','latex'); 
set(groot, 'defaultAxesTickLabelInterpreter','latex'); 
set(groot, 'defaultLegendInterpreter','latex');


%% Likelihood visualization

% Get analytical curve
x_ana = linspace(-4.5, 4.5, 1000).';
L_ana = exp(uq_evalModel(LogLikelihoodModel, x_ana));
prior_ana = exp(- (x_ana -  PriorOpts.Marginals(1).Moments(1)).^2 / (2. * PriorOpts.Marginals(1).Moments(2))) / sqrt(2*pi*PriorOpts.Marginals(1).Moments(2));

% Plot Likelihood experimental design
figure
hold on
plot(x_ana, L_ana)
plot(x_ana, prior_ana)
scatter(LALAnalysis.ExpDesign.X(1:init_expdesign), exp(LALAnalysis.ExpDesign.LogLikelihood(1:init_expdesign)), 'filled')
scatter(LALAnalysis.ExpDesign.X(init_expdesign+1:end), exp(LALAnalysis.ExpDesign.LogLikelihood(init_expdesign+1:end)), 'filled')
hold off
xlab = xlabel('Input parameter $x$');
set(xlab, 'Interpreter','latex');
set(xlab,'FontSize',17);
ylab = ylabel('Likelihood or Prior PDF');
%set(ylab, 'Interpreter','latex');
%set(ylab,'FontSize',17);
title('LAL experimental design');
lgd = legend('Analytical likelihood $\mathcal{L}(x; \mathcal{M}(x) = 2x; \mathcal{Y} = \{3\})$', 'Analytical prior $\pi(x) \sim \mathcal{N}(0,1)$', 'Initial exp. design of $\mathcal{L}(x)$', 'LAL exp. design of $\mathcal{L}(x)$');
set(lgd, 'Interpreter','latex');
set(lgd,'FontSize',16);
lgd.Location = 'northwest';

%% PCK of likelihood

% Construct a PC-Kriging surrogate of the log-likelihood
PCKOpts.Type = 'Metamodel';
PCKOpts.MetaType = 'PCK';
PCKOpts.Mode = 'sequential';
PCKOpts.FullModel = LogLikelihoodModel;
PCKOpts.PCE.Degree = LALOpts.PCE.MinDegree:2:LALOpts.PCE.MaxDegree;
PCKOpts.PCE.Method = 'LARS';
PCKOpts.ExpDesign.X = LALAnalysis.ExpDesign.X;
PCKOpts.ExpDesign.Y = LALAnalysis.ExpDesign.LogLikelihood;
PCKOpts.Kriging.Corr.Family = 'Gaussian';

logL_PCK = uq_createModel(PCKOpts);

logL_PCK.Error

%% Get samples and draw an histogram

N_samples = 4e3;

BayesOpts.Prior = PriorInput;
BayesOpts.LogLikelihood = logL_PCK;
BayesOpts.Bus = LALOpts.Bus;
BayesOpts.Bus.BatchSize = N_samples;
BayesOpts.Bus.MaxSampleSize = 1e5;

BayesAnalysis = bus_analysis(BayesOpts);

% Get evidence
Z = BayesAnalysis.Results.Evidence

% Use MCMC to sample with reconstructed likelihood
BayesOpts.Type = 'Inversion';
BayesOpts.Name = 'Final invertion';
BayesOpts.Prior = PriorInput;
myData.y = measurements;
BayesOpts.Data = myData;
BayesOpts.LogLikelihood = @(params,y) uq_evalModel(logL_PCK, params);

myBayesianAnalysis = uq_createAnalysis(BayesOpts);
uq_postProcessInversion(myBayesianAnalysis, 'burnIn', 0.7)
post_samples = myBayesianAnalysis.Results.PostProc.PostSample;
post_samples = reshape(post_samples, size(post_samples,1) * size(post_samples,3), 1); 

%% Plots

% Get some prior samples
uq_selectInput('Prior');
prior_samples_X = uq_getSample(N_samples);

figure
hold on
histogram(prior_samples_X)
histogram(post_samples)
hold off
xlab = xlabel('Input random variable $X$');
set(xlab, 'Interpreter','latex');
set(xlab,'FontSize',17);
ylabel('Occurrences');
title('Prior vs Posterior sample comparison');
lgd = legend('Prior $\pi$', 'Posterior $\frac{\pi \mathcal{L}}{Z}$');
lgd.Location = 'northwest';
set(lgd,'FontSize',16);
set(lgd,'Interpreter','latex');

%% Plot marginal P

P_bus_samples = BayesAnalysis.Results.Bus.PostSamples(:,1);

figure
histogram(P_bus_samples)
xlab = xlabel('Input random variable $P$');
set(xlab, 'Interpreter','latex');
set(xlab,'FontSize',17);
ylabel('Occurrences');
title('Bus-Posterior samples of P');
lgd = legend('Bus-Posterior of $P$');
lgd.Location = 'northwest';
set(lgd,'FontSize',16);
set(lgd,'Interpreter','latex');

