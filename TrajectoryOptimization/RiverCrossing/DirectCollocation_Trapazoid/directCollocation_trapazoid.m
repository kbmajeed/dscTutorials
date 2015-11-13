function [time, state, control, exitFlag, output] = directCollocation_trapazoid(bound, guess, param)
% [time, state, control, exitFlag, output] = directCollocation_trapazoid(bound, guess, param)
%
% This function solves the river crossing trajectory optimization problem
% by direct collocation with the trapazoid rule.
%

nGrid = param.nGrid;

%%% Bounds on decision variables:
%
T_low = bound.timeLow;
X_low = bound.stateLow*ones(1,nGrid);
U_low = bound.controlLow*ones(1,nGrid);
T_upp = bound.timeUpp;
X_upp = bound.stateUpp*ones(1,nGrid);
U_upp = bound.controlUpp*ones(1,nGrid);
%
%%%

%%% Enforce boundary conditions:
%
z0 = [0;0];
zF = [0;param.riverWidth];

X_low(:,1) = z0;
X_upp(:,1) = z0;

X_low(:,end) = zF;
X_upp(:,end) = zF;

%
%%%
zLow = packDecVar(T_low, X_low, U_low);
zUpp = packDecVar(T_upp, X_upp, U_upp);

%%% Guess at the decision variables (initialization for FMINCON)
%
T_guess = guess.time(end);

tGuess = linspace(0,T_guess,nGrid); % Time at the boundaries of each segment
X_guess = interp1(guess.time', guess.state',tGuess')';  %Interpolate guess at intermediate grid points
U_guess = interp1(guess.time', guess.control',tGuess')';  %Interpolate guess at intermediate grid points

zGuess = packDecVar(T_guess, X_guess, U_guess);
%
%%%



%%% Create problem struct for fmincon
%
problem.options = optimset(...
    'Display','iter',... % {'final','iter'}
    'MaxFunEvals',1e5);

problem.x0 = zGuess;
problem.lb = zLow;
problem.ub = zUpp;
problem.Aineq = [];
problem.Aeq = [];
problem.bineq = [];
problem.beq = [];
problem.objective = @(z)( z(1) );  %Minimize trajectory duration
problem.nonlcon = @(z)( constraintFun(z,param) );
problem.solver = 'fmincon';
%
%%%

%%% Solve the non-linear program (NLP)
%
[zSoln, ~, exitFlag, output] = fmincon(problem);
%
%%%

[T, X, U] = unpackDecVar(zSoln, nGrid);

time = linspace(0,T,nGrid);
state = X;
control = U;

end



function z = packDecVar(T,X,U)
%
% This function takes the three types of decision variables and collapses
% them into a single column vector for FMINCON
%

z = [...
    T;
    reshape(X,numel(X),1);
    reshape(U,numel(U),1)];

end



function [T, X, U] = unpackDecVar(z, nGrid)
%
% This function takes the column vector of decision variables and unpacks
% it into the duration, state, and control matricies that are used to
% enforce the dynamics along the trajectory.
%

nx = 2*nGrid;   %2 = dimension of the state space
nu = 1*nGrid;

T = z(1);  %Duration

xIdx = 1 + (1:nx);
uIdx = 1 + nx + (1:nu);

X = reshape(z(xIdx),2,nGrid);
U = reshape(z(uIdx),1,nGrid);

end


function [c, ceq] = constraintFun(z,param)
%
% This function is called by FMINCON on each iteration as it solves the
% non-linear program (NLP). It enforces all non-linear constraints on the
% problem. In other words, it ensures that the dynamics are satisfied along
% the trajectory.
%
% The dynamics are enforced by a defect constraint. This constraint ensures
% that the end of each segment of the trajectory matches the beginning of
% the next. In the case of the last segment, it ensures that the boundary
% conditions are satisfied.
%

% Unpack the decision variables
nGrid = param.nGrid;
[T, X, U] = unpackDecVar(z, nGrid);

h = T/(nGrid-1);  %integration time step
dX = riverBoatDynamics(X,U,param);   %Dynamics

%%% Trapazoid Integration:
%

idxLow = 1:(nGrid-1);
idxUpp = 2:nGrid;

% xUpp = xLow + (h/2)*(dxLow + dxUpp)
defect = (X(:,idxUpp) - X(:,idxLow)) - (h/2)*(dX(:,idxUpp) + dX(:,idxLow));

%
%%%

%%% Pack up for fmincon:
c = [];
ceq = reshape(defect,numel(defect),1);

end


