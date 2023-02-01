clearvars
rng(100,'twister')
uqlab

addpath('../lal')

%% Data set
load('uq_Example_BayesianPreyPred.mat')

%% Model definition

normYear = Data.year-Data.year(1);

ModelOpts.mHandle = @(x) uq_predatorPreyModel(x,normYear);
ModelOpts.isVectorized = true;

myForwardModel = uq_createModel(ModelOpts);

%% Prior setup

PriorOpts.Marginals(1).Name = ('alpha');
PriorOpts.Marginals(1).Type = 'LogNormal';
PriorOpts.Marginals(1).Moments = [1 0.1];
%PriorOpts.Marginals(1).Type = 'Constant';
%PriorOpts.Marginals(1).Parameters = 0.6035;

PriorOpts.Marginals(2).Name = ('beta');
PriorOpts.Marginals(2).Type = 'LogNormal';
PriorOpts.Marginals(2).Moments = [0.05 0.005];
%PriorOpts.Marginals(2).Type = 'Constant';
%PriorOpts.Marginals(2).Parameters = 0.0360;

PriorOpts.Marginals(3).Name = ('gamma');
PriorOpts.Marginals(3).Type = 'LogNormal';
PriorOpts.Marginals(3).Moments = [1 0.1];
%PriorOpts.Marginals(3).Type = 'Constant';
%PriorOpts.Marginals(3).Parameters = 0.9072;

PriorOpts.Marginals(4).Name = ('delta');
PriorOpts.Marginals(4).Type = 'LogNormal';
PriorOpts.Marginals(4).Moments = [0.05 0.005];
%PriorOpts.Marginals(4).Type = 'Constant';
%PriorOpts.Marginals(4).Parameters = 0.0296;

PriorOpts.Marginals(5).Name = ('initH');
PriorOpts.Marginals(5).Type = 'LogNormal';
PriorOpts.Marginals(5).Parameters = [log(10) 1];

PriorOpts.Marginals(6).Name = ('initL');
PriorOpts.Marginals(6).Type = 'LogNormal';
PriorOpts.Marginals(6).Parameters = [log(10) 1];
%PriorOpts.Marginals(6).Type = 'Constant';
%PriorOpts.Marginals(6).Parameters = 5.1753;

myPriorDist = uq_createInput(PriorOpts);

%% Measurements

myData(1).y = Data.hare.'/1000; %in 1000
myData(1).Name = 'Hare data';
myData(1).MOMap = 1:21; % Output ID

myData(2).y = Data.lynx.'/1000; %in 1000
myData(2).Name = 'Lynx data';
myData(2).MOMap = 22:42; % Output ID

%% Discrepancy model

SigmaOpts.Marginals(1).Name = 'Sigma2L';
SigmaOpts.Marginals(1).Type = 'Lognormal';
SigmaOpts.Marginals(1).Parameters = [-1 1];

SigmaDist1 = uq_createInput(SigmaOpts);

SigmaOpts.Marginals(1).Name = 'Sigma2H';
SigmaOpts.Marginals(1).Type = 'Lognormal';
SigmaOpts.Marginals(1).Parameters = [-1 1];

SigmaDist2 = uq_createInput(SigmaOpts);

% Choose otion
DiscrepancyOpts(1).Type = 'Gaussian';
%DiscrepancyOpts(1).Prior = SigmaDist1;
DiscrepancyOpts(1).Parameters = 21.9068;
DiscrepancyOpts(2).Type = 'Gaussian';
%DiscrepancyOpts(2).Prior = SigmaDist2;
DiscrepancyOpts(2).Parameters = 12.9847;


%% Reference model definition

Solver.Type = 'MCMC';
Solver.MCMC.Sampler = 'AIES';
Solver.MCMC.Steps = 400;
Solver.MCMC.NChains = 100;

%Solver.MCMC.Visualize.Parameters = [5 6];
%Solver.MCMC.Visualize.Interval = 40;

BayesOpts.Type = 'Inversion';
BayesOpts.Name = 'Bayesian model';
BayesOpts.Prior = myPriorDist;
BayesOpts.Data = myData;
BayesOpts.Discrepancy = DiscrepancyOpts;
BayesOpts.Solver = Solver;

refBayesAnalysis = uq_createAnalysis(BayesOpts);

uq_postProcessInversionMCMC(refBayesAnalysis);

%% post sample exctraction and clean up

M = size(refBayesAnalysis.Results.PostProc.PostSample,2);

post_samples = reshape(refBayesAnalysis.Results.PostProc.PostSample(end,:,:), M, Solver.MCMC.NChains)';
post_logL_samples = refBayesAnalysis.Results.PostProc.PostLogLikeliEval(end,:)';

post_samples = post_samples(post_logL_samples > quantile(post_logL_samples, 0.1), :);
post_logL_samples = post_logL_samples(post_logL_samples > quantile(post_logL_samples, 0.1));
post_samples_size = size(post_samples, 1); 

%% Bayesian analysis

LALOpts.Bus.logC = -max(post_logL_samples); % best value: -max log(L) 
LALOpts.Bus.p0 = 0.1;                            % Quantile probability for Subset
LALOpts.Bus.BatchSize = 1e3;                             % Number of samples for Subset simulation
%LALOpts.Bus.MaxSampleSize = 1e4;
LALOpts.MaximumEvaluations = 70;
LALOpts.ExpDesign.InitEval = 21;
LALOpts.PlotLogLikelihood = true;
%LALOpts.dbscanQuantile = 0.1;
LALOpts.dbscanMinpts = 5;
LALOpts.lsfEvaluations = 1;
%LALOpts.CStrategy = 'max';

%LALOpts.PCK.PCE.Degree = 0:2:4;
%LALOpts.PCK.PCE.Method = 'LARS';
%LALOpts.PCK.Optim.Method = 'CMAES';
LALOpts.PCK.Kriging.Corr.Type = 'Separable';
%LALOpts.PCK.Kriging.Optim.MaxIter = 1000;
%LALOpts.PCK.Kriging.Corr.Family = 'Gaussian';
%LALOpts.PCK.Display = 'verbose';

LALOpts.LogLikelihood = refBayesAnalysis.LogLikelihood;
LALOpts.Prior = refBayesAnalysis.Internal.FullPrior;

LALOpts.Validation.PostSamples = post_samples;
LALOpts.Validation.PostLogLikelihood = post_logL_samples;
LALOpts.Validation.PriorSamples = uq_getSample(LALOpts.Prior, post_samples_size);
LALOpts.Validation.PriorLogLikelihood = refBayesAnalysis.LogLikelihood(LALOpts.Validation.PriorSamples);

LALAnalysis = lal_analysis(LALOpts);

%% Analysis: plot of experimental design and real log-likelihood on marginal 5 and 6



%figure
%xlabel('X_5')
%ylabel('X_6')
%zlabel('logL')
%hold on
%scatter3(LALAnalysis.ExpDesign.X(:,5), LALAnalysis.ExpDesign.X(:,6), LALAnalysis.ExpDesign.LogLikelihood ./ LOpts.Parameters.Amplification , "filled")
%surfplot = surf(X5_samples, X6_samples, reshape(logL_real, n_samples, n_samples));
%surfplot.EdgeColor = 'none';
%hold off
%legend('Experimental design', 'Real Log-Likelihood')

