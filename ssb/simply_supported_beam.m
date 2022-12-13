clearvars
rng(100,'twister')
uqlab

addpath('../lal')

%% visualize

uq_figure
[I,~] = imread('SimplySupportedBeam.png');
image(I)
axis equal
set(gca, 'visible', 'off')

%% forward model setup

ModelOpts.mFile = 'uq_SimplySupportedBeam';
ModelOpts.isVectorized = true;

myForwardModel = uq_createModel(ModelOpts);

%% prior setup

PriorOpts.Marginals(1).Name = 'b';               % beam width
PriorOpts.Marginals(1).Type = 'Constant';
PriorOpts.Marginals(1).Parameters = [0.15];      % (m)

PriorOpts.Marginals(2).Name = 'h';               % beam height
PriorOpts.Marginals(2).Type = 'Constant';
PriorOpts.Marginals(2).Parameters = [0.3];       % (m)

PriorOpts.Marginals(3).Name = 'L';               % beam length
PriorOpts.Marginals(3).Type = 'Constant';
PriorOpts.Marginals(3).Parameters = 5;           % (m)

PriorOpts.Marginals(4).Name = 'E';               % Young's modulus
PriorOpts.Marginals(4).Type = 'LogNormal';
PriorOpts.Marginals(4).Moments = [30 4.5]*1e9;   % (N/m^2)

PriorOpts.Marginals(5).Name = 'p';               % uniform load
PriorOpts.Marginals(5).Type = 'Gaussian';
PriorOpts.Marginals(5).Moments = [12000 600]; % (N/m)

myPriorDist = uq_createInput(PriorOpts);

%% Measurement setup

myData.y = [12.84; 13.12; 12.13; 12.19; 12.67]/1000; % (m)
myData.Name = 'Mid-span deflection';

%% Log-likelihood definition

LOpts.Name = 'log_likelihood_model';
LOpts.mFile = 'log_likelihood_model';
LOpts.Parameters.ForwardModel = myForwardModel;
LOpts.Parameters.y = myData.y;

LogLikelihoodModel = uq_createModel(LOpts);

%% Bayesian analysis

LALOpts.Bus.c = sqrt(2*pi*var(myData.y))^length(myData.y) * 1.25;    % best value: 1 / (max L + small_quantity) 
LALOpts.Bus.p0 = 0.1;                            % Quantile probability for Subset
LALOpts.Bus.BatchSize = 1e3;                             % Number of samples for Subset simulation
LALOpts.Bus.MaxSampleSize = 1e4;
LALOpts.MaximumEvaluations = 30;
init_expdesign = 20;

LALOpts.ExpDesign.X = uq_getSample(init_expdesign);
LALOpts.ExpDesign.LogLikelihood = uq_evalModel(LogLikelihoodModel, LALOpts.ExpDesign.X);

LALOpts.PCE.MinDegree = 2;
LALOpts.PCE.MaxDegree = 32;
%LALOpts.PCE.Method = 'OLS';

LALOpts.LogLikelihood = LogLikelihoodModel;
LALOpts.Prior = myPriorDist;

LALAnalysis = lal_analysis(LALOpts);

