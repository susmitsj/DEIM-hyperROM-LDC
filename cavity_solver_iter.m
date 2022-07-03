function [sol_p, sol_u, sol_v, rhs_p, rhs_u, rhs_v, conv] =...
    cavity_solver_iter(uinf, rho, imax, jmax, imms, isgs, u,...
    loc_p, loc_u, loc_v)

% tic   %begin timer function
%--- Variables for file handling ---
%--- All files are globally accessible ---

global neq nmax m
global zero tenth sixth fifth fourth third half one two three four six
global iterout irstr ipgorder lim cfl Cx Cy toler rkappa Re pinf xmin xmax ymin ymax Cx2 Cy2 fsmall
global rmu phi0 phix phiy phixy apx apy apxy fsinx fsiny fsinxy
%--------------------------------------------------------------------------------------------------------------------------%
global rhs
% global u;         % Solution vector [p, u, v]^T at each node
%--------------------------------------------------------------------------------------------------------------------------%

%**Use these variables cautiously as these are globally accessible from all functions.**


global uold;      % Previous (old) solution vector
global s;         % Source term
global dt;        % Local time step at each node
global artviscx;  % Artificial viscosity in x-direction
global artviscy;  % Artificial viscosity in y-direction
global ummsArray; % Array of umms values (funtion umms evaluated at all nodes)

%************ Following are fixed parameters for array sizes *************
%--------------------------------------------------------------------------------------------------------------------------%
% imax = 65;   % Number of points in the x-direction (use odd numbers only)
% jmax = 65;   % Number of points in the y-direction (use odd numbers only)
%--------------------------------------------------------------------------------------------------------------------------%
neq = 3;     % Number of equation to be solved ( = 3: mass, x-mtm, y-mtm)
%********************************************
%***** All  variables declared here. **
%**** These variables SHOULD not be changed *
%********* by the program once set. *********
%********************************************
%**** The variables declared "" CAN ****
%** not be changed by the program once set **
%********************************************

%--------- Numerical constants --------
zero   = 0.0;
tenth  = 0.1;
sixth  = 1.0/6.0;
fifth  = 0.2;
fourth = 0.25;
third  = 1.0/3.0;
half   = 0.5;
one    = 1.0;
two    = 2.0;
three  = 3.0;
four   = 4.0;
six    = 6.0;

%--------- User sets inputs here  --------

%--------------------------------------------------------------------------------------------------------------------------%
nmax = 2;        % Maximum number of iterations
iterout = 2;       % Number of time steps between solution output
% imms = 1;             % Manufactured solution flag: = 1 for manuf. sol., = 0 otherwise
% isgs = 1;             % Symmetric Gauss-Seidel  flag: = 1 for SGS, = 0 for point Jacobi
irstr = 1;            % Restart flag: = 1 for restart (file 'restart.in', = 0 for initial run
m = length(loc_p);   % Reduced RHS dimension
%--------------------------------------------------------------------------------------------------------------------------%
ipgorder = 0;         % Order of pressure gradient: 0 = 2nd, 1 = 3rd (not needed)
lim = 1;              % variable to be used as the limiter sensor (= 1 for pressure)

cfl  = 0.5;      % CFL number used to determine time step
Cx = 0.01;     	% Parameter for 4th order artificial viscosity in x
Cy = 0.01;      	% Parameter for 4th order artificial viscosity in y
toler = 1.e-4; 	% Tolerance for iterative residual convergence
rkappa = 0.1;   	% Time derivative preconditioning constant
pinf = 0.801333844662; % Initial pressure (N/m^2) -> from MMS value at cavity center
%--------------------------------------------------------------------------------------------------------------------------%
% uinf = 1.0;               % Lid velocity (m/s)
% rho = 1.0;                % Density (kg/m^3)
rmu = 5e-4;              % Constant viscosity (N*s/m^2)
L = 0.05;                   % Maximum length (m)
Re = rho*uinf*L/rmu;        % Reynolds number = rho*Uinf*L/rmu
ymax = L;                   % Maximum y location (m)
xmax = L;                   % Maximum x location (m)
%--------------------------------------------------------------------------------------------------------------------------%
xmin = 0.0;      % Cavity dimensions...: minimum x location (m)
ymin = 0.0;      %                       maximum y location (m)
Cx2 = 0.0;       % Coefficient for 2nd order damping (not required)
Cy2 = 0.0;     	 % Coefficient for 2nd order damping (not required)
fsmall = 1.e-20; % small parameter

%-- Derived input quantities (set by function 'set_derived_inputs' called from main)----

% rhoinv =  -99.9; 	% Inverse density, 1/rho (m^3/kg)
% rlength = -99.9;  	% Characteristic length (m) [cavity width]
% vel2ref = -99.9;  	% Reference velocity squared (m^2/s^2)
% dx = -99.9; 		% Delta x (m)
% dy = -99.9;  		% Delta y (m)
% rpi = -99.9; 		% Pi = 3.14159... (defined below)

%-- constants for manufactured solutions ----
phi0 = [0.25, 0.3, 0.2];          % MMS constant
phix = [0.5, 0.15, 1.0/6.0];      % MMS amplitude constant
phiy = [0.4, 0.2, 0.25];          % MMS amplitude constant
phixy = [1.0/3.0, 0.25, 0.1];     % MMS amplitude constant
apx = [0.5, 1.0/3.0, 7.0/17.0]; 	% MMS frequency constant
apy = [0.2, 0.25, 1.0/6.0];         % MMS frequency constant
apxy = [2.0/7.0, 0.4, 1.0/3.0];     % MMS frequency constant
fsinx = [0.0, 1.0, 0.0];            % MMS constant to determine sine vs. cosine
fsiny = [1.0, 0.0, 0.0];            % MMS constant to determine sine vs. cosine
fsinxy = [1.0, 1.0, 0.0];           % MMS constant to determine sine vs. cosine
% Note: fsin = 1 means the sine function
% Note: fsin = 0 means the cosine function
% Note: arrays here refer to the 3 variables

%************************************************************************
%      						Main Function
%************************************************************************
%----- Looping indices --------

conv = -99.9 ; % Minimum of iterative residual norms from three equations


%--------- Solution variables declaration --------

dtmin = 1.0e99;        % Minimum time step for a given iteration (initialized large)

% x = -99.9;       % Temporary variable for x location
% y = -99.9;       % Temporary variable for y location

dt = zeros(imax,jmax);
artviscx = zeros(imax,jmax);
artviscy = zeros(imax,jmax);
%--------------------------------------------------------------------------------------------------------------------------%
rhs = zeros(imax,jmax,neq);
% u = zeros(imax,jmax,neq);
%--------------------------------------------------------------------------------------------------------------------------%

ummsArray = zeros(imax,jmax,neq);
s = zeros(imax,jmax,neq);

dt(:,:) = -99.9;

% Set derived input quantities
set_derived_inputs(uinf, rho, imax, jmax);

% Set Initial Profile for u vector
[~, ~] = initial(imax, jmax);

% Set Boundary Conditions for u
u = set_boundary_conditions(imms, imax, jmax, uinf, u);

% Initialize Artificial Viscosity arrays to zero (note: artviscx(i,j) and artviscy(i,j)
artviscx(:,:) = zero;
artviscy(:,:) = zero;

% Evaluate Source Terms Once at Beginning
%(only interior points; will be zero for standard cavity)
compute_source_terms(imax, jmax, imms, rho, loc_p, loc_u, loc_v);

%========== Main Loop ==========

% for n = ninit:nmax
    % Calculate time step
    [~] = compute_time_step(dtmin, rho, u, loc_p, loc_u, loc_v);
    
    % Save u values at time level n (u and uold are 2D arrays)
    uold = u;
    
    if isgs==1 % ==Symmetric Gauss Seidel==
        
        % Artificial Viscosity
        Compute_Artificial_Viscosity(imax, jmax, rho, u, loc_p);
        
        % Symmetric Gauss-Siedel: Forward Sweep
        u = SGS_forward_sweep(rho, u, loc_p, loc_u, loc_v);
        
        % Set Boundary Conditions for u
        u = set_boundary_conditions(imms, imax, jmax, uinf, u);
        
        % Artificial Viscosity
        Compute_Artificial_Viscosity(imax, jmax, rho, u, loc_p);
        
        % Symmetric Gauss-Siedel: Backward Sweep
        u = SGS_backward_sweep(rho, u, loc_p, loc_u, loc_v);
        
        % Set Boundary Conditions for u
        u = set_boundary_conditions(imms, imax, jmax, uinf, u);

    else
        if isgs==0 % ==Point Jacobi==
            
            % Artificial Viscosity
            Compute_Artificial_Viscosity(imax, jmax, rho, u, loc_p);
            
            % Point Jacobi: Forward Sweep
            u = point_Jacobi(rho, u, loc_p, loc_u, loc_v);
            
            % Set Boundary Conditions for u
            u = set_boundary_conditions(imms, imax, jmax, uinf, u);
        else
            fprintf('ERROR: isgs must equal 0 or 1!\n');
            return;
        end
    end
    
    % Pressure Rescaling (based on center point)
    u = pressure_rescaling(imax, jmax, imms, u, loc_p);
    
% end  % ========== End Main Loop ==========

%---------------------------------------------------------------------------------------------------------------------------%
% Output vectors
sol_p = zeros(imax*jmax,1);
sol_u = zeros(imax*jmax,1);
sol_v = zeros(imax*jmax,1);

rhs_p = zeros(m,1);
rhs_u = zeros(m,1);
rhs_v = zeros(m,1);

for j = 1 : jmax
    sol_p((j-1)*imax + 1 : j*imax) = u(:,j,1);
    sol_u((j-1)*imax + 1 : j*imax) = u(:,j,2);
    sol_v((j-1)*imax + 1 : j*imax) = u(:,j,3);
%     rhs_p((j-1)*imax + 1 : j*imax) = rhs(:,j,1);
%     rhs_u((j-1)*imax + 1 : j*imax) = rhs(:,j,2);
%     rhs_v((j-1)*imax + 1 : j*imax) = rhs(:,j,3);
end

for k = 1 : m
    rhs_p(k) = rhs(loc_p(k,1),loc_p(k,2),1);
    rhs_u(k) = rhs(loc_u(k,1),loc_u(k,2),2);
    rhs_v(k) = rhs(loc_v(k,1),loc_v(k,2),3);
end
            

%--------------------------------------------------------------------------------------------------------------------------%

% PrsMatrix = u(:,:,1);    %output arrays
% uvelMatrix = u(:,:,2);
% vvelMatrix = u(:,:,3);

% toc  %end timer function
end

%**************************************************************************/
%*      					All Other	Functions					      */
%**************************************************************************/

%**************************************************************************
%**************************************************************************
function set_derived_inputs(uinf, rho, imax, jmax)
global one
global rhoinv xmin xmax ymin ymax
global rlength rmu vel2ref dx dy rpi

rhoinv = 1/rho;                            % Inverse density, 1/rho (m^3/kg) */
rlength = xmax - xmin;                       % Characteristic length (m) [cavity width] */
%--------------------------------------------------------------------------------------------------------------------------%
rmu = 5e-4;                               % Constant viscosity (N*s/m^2) 
% rmu = rho*uinf*rlength/Re;                   % Viscosity (N*s/m^2) */
%--------------------------------------------------------------------------------------------------------------------------%
vel2ref = uinf*uinf;                         % Reference velocity squared (m^2/s^2) */
dx = (xmax - xmin)/(imax - 1);          % Delta x (m) */
dy = (ymax - ymin)/(jmax - 1);          % Delta y (m) */
rpi = acos(-one);                            % Pi = 3.14159... */
% fprintf('rho,V,L,mu,Re: %f %f %f %f %f\n',rho,uinf,rlength,rmu,Re);
end

%************************************************************************
function u = set_boundary_conditions(imms, imax, jmax, uinf, u)
%
%Uses global variable(s): imms
%To modify: u (via other functions: bndry() and bndrymms())

% This subroutine determines the appropriate BC routines to call
if (imms==0)
    u = bndry(imax, jmax, uinf, u);
else
    if (imms==1)
        u = bndrymms(imax, jmax, u);
    else
        printf('ERROR: imms must equal 0 or 1!\n');
        return;
    end
end
end
%************************************************************************
function u = bndry(imax, jmax, uinf, u)
%
%Uses global variable(s): zero, one, two, half, imax, jmax, uinf
%To modify: u

% i                        % i index (x direction)
% j                        % j index (y direction)

global zero two half

% This applies the cavity boundary conditions
% Side Walls
for j = 2:jmax-1
    %    u(1,j,1) = ( 18*u(2,j,1) - 9*u(3,j,1) + two*u(4,j,1) ) / 11;   % 3rd Order BC
    u(1,j,1) = two*u(2,j,1) - u(3,j,1);   % 2nd Order BC
    %    u(1,j,1) = u(2,j,1);      % 1st Order BC
    u(1,j,2) = zero;
    u(1,j,3) = zero;
    %   u(imax,j,1) = ( 18*u(imax-1,j,1) - 9*u(imax-2,j,1) \
    %                   + two*u(imax-3,j,1) ) / 11;  % 3rd Order BC
    u(imax,j,1) = two*u(imax-1,j,1) - u(imax-2,j,1);   % 2nd Order BC
    %  u(imax,j,1) = u(imax-1,j,1);    % 1st Order BC
    u(imax,j,2) = zero;
    u(imax,j,3) = zero;
    
end

% Top/Bottom Walls
for i = 2:imax-1
    %   u(i,1,1) = ( 18*u(i,2,1) - 9*u(i,3,1) + two*u(i,4,1) ) / 11;   % 3rd Order BC
    u(i,1,1) = two*u(i,2,1) - u(i,3,1);   % 2nd Order BC
    %    u(i,1,1) = u(i,2,1);       % 1st Order BC
    u(i,1,2) = zero;
    u(i,1,3) = zero;
    %    u(i,jmax,1) = ( 18*u(i,jmax-1,1) - 9*u(i,jmax-2,1) \
    %                   + two*u(i,jmax-3,1) ) / 11;  % 3rd Order BC
    u(i,jmax,1) = two*u(i,jmax-1,1) - u(i,jmax-2,1);  % 2nd Order BC
    %    u(i,jmax,1) = u(i,jmax-1,1);     % 1st Order BC
    u(i,jmax,2) = uinf;
    u(i,jmax,3) = zero;
    
end

% Corners
u(1,jmax,1) = half*( u(2,jmax,1) + u(1,jmax-1,1) );
u(imax,jmax,1) = half*( u(imax-1,jmax,1) + u(imax,jmax-1,1) );
u(1,jmax,2) = zero;      % uinf   /two     uinf
u(imax,jmax,2) = zero;   % uinf   /two     uinf
u(1,jmax,3) = zero;
u(imax,jmax,3) = zero;

u(1,1,1) = half*( u(2,1,1) + u(1,2,1) );
u(imax,1,1) = half*( u(imax-1,1,1) + u(imax,2,1) );
u(1,1,2) = zero;
u(imax,1,2) = zero;
u(1,1,3) = zero;
u(imax,1,3) = zero;
end
%************************************************************************
function u = bndrymms(imax, jmax, u)
%
%Uses global variable(s): two, imax, jmax, neq, xmax, xmin, ymax, ymin, rlength
%To modify: u
% i                        % i index (x direction)
% j                        % j index (y direction)
% k                        % k index (# of equations)
% x        % Temporary variable for x location
% y        % Temporary variable for y location
% This applies the cavity boundary conditions for the manufactured solution

global two neq
global ummsArray

% Side Walls
for j = 2:jmax-1
    i = 1;
    for k = 1:neq
        u(i,j,k) = ummsArray(i,j,k);
    end
    u(1,j,1) = two*u(2,j,1) - u(3,j,1);    % 2nd Order BC
    %    u(1,j,1) = u(2,j,1);                  % 1st Order BC
    
    i=imax;
    for k = 1:neq
        u(i,j,k) = ummsArray(i,j,k);
    end
    u(imax,j,1) = two*u(imax-1,j,1) - u(imax-2,j,1);   % 2nd Order BC
    %	u(imax,j,1) = u(imax-1,j,1);                       % 1st Order BC
end

% Top/Bottom Walls
for i=1:imax
    j = 1;
    for k = 1:neq
        u(i,j,k) = ummsArray(i,j,k);
    end
    u(i,1,1) = two*u(i,2,1) - u(i,3,1);   % 2nd Order BC
    
    j = jmax;
    for k = 1:neq
        u(i,j,k) = ummsArray(i,j,k);
    end
    u(i,jmax,1) = two*u(i,jmax-1,1) - u(i,jmax-2,1);   % 2nd Order BC
end
end

%************************************************************************
function [ninit, rtime] = initial(imax, jmax)
%
%Uses global variable(s): zero, one, irstr, imax, jmax, neq, uinf, pinf
%To modify: ninit, rtime, resinit, u, s

% i                        % i index (x direction)
% j                        % j index (y direction)
% k                        % k index (# of equations)
% x        % Temporary variable for x location
% y        % Temporary variable for y location

% This subroutine sets inital conditions in the cavity
% Note: The vector of primitive variables is:
%              u = (p, u, v)^T

global neq xmax xmin ymax ymin
global ummsArray

% Initialize the ummsArray with values computed with umms function
for j=1:jmax
    for i=1:imax
        for k=1:neq
            x = (xmax - xmin)*(i-1)/(imax - 1);
            y = (ymax - ymin)*(j-1)/(jmax - 1);
            ummsArray(i,j,k) = umms(x,y,k);
        end
    end
end

ninit = 1;
rtime = 0;


end

%************************************************************************
function [ummstmp] = umms(x, y, k)
%
%Uses global variable(s): one, rpi, rlength
%Inputs: x, y, k
%To modify: <none>
%Returns: umms

% ummstmp; % Define return value for umms as % precision

% termx       % Temp variable
% termy       % Temp variable
% termxy      % Temp variable
% argx        % Temp variable
% argy        % Temp variable
% argxy       % Temp variable

% This function returns the MMS exact solution

global one rpi rlength
global phi0 phix phiy phixy apx apy apxy fsinx fsiny fsinxy

argx = apx(k)*rpi*x/rlength;
argy = apy(k)*rpi*y/rlength;
argxy = apxy(k)*rpi*x*y/rlength/rlength;
termx = phix(k)*(fsinx(k)*sin(argx)+(one-fsinx(k))*cos(argx));
termy = phiy(k)*(fsiny(k)*sin(argy)+(one-fsiny(k))*cos(argy));
termxy = phixy(k)*(fsinxy(k)*sin(argxy)+(one-fsinxy(k))*cos(argxy));

ummstmp = phi0(k) + termx + termy + termxy;
end

%************************************************************************
function compute_source_terms(imax, jmax, imms, rho, loc_p, loc_u, loc_v)
%
%Uses global variable(s): imax, jmax, imms, rlength, xmax, xmin, ymax, ymin
%To modify: s (source terms)

% i                        % i index (x direction)
% j                        % j index (y direction)

% x        % Temporary variable for x location
% y        % Temporary variable for y location

% Evaluate Source Terms Once at Beginning (only %erior po%s; will be zero for standard cavity)

global xmax xmin ymax ymin
global s m

for k = 1:m
    s(loc_p(k,1),loc_p(k,2),1) = (imms)*...
        srcmms_mass((xmax - xmin)*(loc_p(k,1)-1)/(imax - 1),...
        (ymax - ymin)*(loc_p(k,2)-1)/(jmax - 1), rho);
    
    s(loc_u(k,1),loc_u(k,2),2) = (imms)*...
        srcmms_xmtm((xmax - xmin)*(loc_u(k,1)-1)/(imax - 1),...
        (ymax - ymin)*(loc_u(k,2)-1)/(jmax - 1), rho);
    
    s(loc_v(k,1),loc_v(k,2),3) = (imms)*...
        srcmms_ymtm((xmax - xmin)*(loc_v(k,1)-1)/(imax - 1),...
        (ymax - ymin)*(loc_v(k,2)-1)/(jmax - 1), rho);
end

end
%************************************************************************
function [srcmasstmp] = srcmms_mass(x, y, rho)
%
%Uses global variable(s): rho, rpi, rlength
%Inputs: x, y
%To modify: <none>
%Returns: srcmms_mass
% srcmasstmp; % Define return value for srcmms_mass as % precision

% dudx; 	% Temp variable: u velocity gradient in x direction
% dvdy;  % Temp variable: v velocity gradient in y direction

% This function returns the MMS mass source term

global rpi rlength
global phix phiy phixy apx apy apxy

dudx = phix(2)*apx(2)*rpi/rlength*cos(apx(2)*rpi*x/rlength)  ...
    + phixy(2)*apxy(2)*rpi*y/rlength/rlength  ...
    * cos(apxy(2)*rpi*x*y/rlength/rlength);

dvdy = -phiy(3)*apy(3)*rpi/rlength*sin(apy(3)*rpi*y/rlength)  ...
    - phixy(3)*apxy(3)*rpi*x/rlength/rlength  ...
    * sin(apxy(3)*rpi*x*y/rlength/rlength);

srcmasstmp = rho*dudx + rho*dvdy;
end
%************************************************************************
function [srcxmtmtmp] = srcmms_xmtm(x, y, rho)
%
%Uses global variable(s): rho, rpi, rmu, rlength
%Inputs: x, y
%To modify: <none>
%Returns: srcmms_xmtm

% srcxmtmtmp; % Define return value for srcmms_xmtm as % precision

% dudx; 	% Temp variable: u velocity gradient in x direction
% dudy;  % Temp variable: u velocity gradient in y direction
% termx;        % Temp variable
% termy;        % Temp variable
% termxy;       % Temp variable
% uvel;         % Temp variable: u velocity
% vvel;         % Temp variable: v velocity
% dpdx;         % Temp variable: pressure gradient in x direction
% d2udx2;       % Temp variable: 2nd derivative of u velocity in x direction
% d2udy2;       % Temp variable: 2nd derivative of u velocity in y direction

%This function returns the MMS x-momentum source term

global rpi rmu rlength
global phi0 phix phiy phixy apx apy apxy

termx = phix(2)*sin(apx(2)*rpi*x/rlength);
termy = phiy(2)*cos(apy(2)*rpi*y/rlength);
termxy = phixy(2)*sin(apxy(2)*rpi*x*y/rlength/rlength);
uvel = phi0(2) + termx + termy + termxy;

termx = phix(3)*cos(apx(3)*rpi*x/rlength);
termy = phiy(3)*cos(apy(3)*rpi*y/rlength);
termxy = phixy(3)*cos(apxy(3)*rpi*x*y/rlength/rlength);
vvel = phi0(3) + termx + termy + termxy;

dudx = phix(2)*apx(2)*rpi/rlength*cos(apx(2)*rpi*x/rlength) ...
    + phixy(2)*apxy(2)*rpi*y/rlength/rlength  ...
    * cos(apxy(2)*rpi*x*y/rlength/rlength);

dudy = -phiy(2)*apy(2)*rpi/rlength*sin(apy(2)*rpi*y/rlength)  ...
    + phixy(2)*apxy(2)*rpi*x/rlength/rlength  ...
    * cos(apxy(2)*rpi*x*y/rlength/rlength);

dpdx = -phix(1)*apx(1)*rpi/rlength*sin(apx(1)*rpi*x/rlength) ...
    + phixy(1)*apxy(1)*rpi*y/rlength/rlength  ...
    * cos(apxy(1)*rpi*x*y/rlength/rlength);

d2udx2 = -phix(2)*((apx(2)*rpi/rlength).^2)  ...
    * sin(apx(2)*rpi*x/rlength)  ...
    - phixy(2)*((apxy(2)*rpi*y/rlength/rlength).^2)  ...
    * sin(apxy(2)*rpi*x*y/rlength/rlength);

d2udy2 = -phiy(2)*((apy(2)*rpi/rlength).^2)  ...
    * cos(apy(2)*rpi*y/rlength)  ...
    - phixy(2)*((apxy(2)*rpi*x/rlength/rlength).^2)  ...
    * sin(apxy(2)*rpi*x*y/rlength/rlength);

srcxmtmtmp = rho*uvel*dudx + rho*vvel*dudy + dpdx  ...
    - rmu*( d2udx2 + d2udy2 );

end
%************************************************************************
function [srcymtmtmp] = srcmms_ymtm(x, y, rho)
%
%Uses global variable(s): rho, rpi, rmu, rlength
%Inputs: x, y
%To modify: <none>
%Returns: srcmms_ymtm

% srcymtmtmp; % Define return value for srcmms_ymtm as % precision

% dvdx;         % Temp variable: v velocity gradient in x direction
% dvdy;         % Temp variable: v velocity gradient in y direction
% termx;        % Temp variable
% termy;        % Temp variable
% termxy;       % Temp variable
% uvel;         % Temp variable: u velocity
% vvel;         % Temp variable: v velocity
% dpdy;         % Temp variable: pressure gradient in y direction
% d2vdx2;       % Temp variable: 2nd derivative of v velocity in x direction
% d2vdy2;       % Temp variable: 2nd derivative of v velocity in y direction

% This function returns the MMS y-momentum source term

global rpi rmu rlength
global phi0 phix phiy phixy apx apy apxy

termx = phix(2)*sin(apx(2)*rpi*x/rlength);
termy = phiy(2)*cos(apy(2)*rpi*y/rlength);
termxy = phixy(2)*sin(apxy(2)*rpi*x*y/rlength/rlength);
uvel = phi0(2) + termx + termy + termxy;

termx = phix(3)*cos(apx(3)*rpi*x/rlength);
termy = phiy(3)*cos(apy(3)*rpi*y/rlength);
termxy = phixy(3)*cos(apxy(3)*rpi*x*y/rlength/rlength);
vvel = phi0(3) + termx + termy + termxy;

dvdx = -phix(3)*apx(3)*rpi/rlength*sin(apx(3)*rpi*x/rlength)  ...
    - phixy(3)*apxy(3)*rpi*y/rlength/rlength  ...
    * sin(apxy(3)*rpi*x*y/rlength/rlength);

dvdy = -phiy(3)*apy(3)*rpi/rlength*sin(apy(3)*rpi*y/rlength)  ...
    - phixy(3)*apxy(3)*rpi*x/rlength/rlength  ...
    * sin(apxy(3)*rpi*x*y/rlength/rlength);

dpdy = phiy(1)*apy(1)*rpi/rlength*cos(apy(1)*rpi*y/rlength)  ...
    + phixy(1)*apxy(1)*rpi*x/rlength/rlength  ...
    * cos(apxy(1)*rpi*x*y/rlength/rlength);

d2vdx2 = -phix(3)*((apx(3)*rpi/rlength).^2)  ...
    * cos(apx(3)*rpi*x/rlength)  ...
    - phixy(3)*((apxy(3)*rpi*y/rlength/rlength).^2)  ...
    * cos(apxy(3)*rpi*x*y/rlength/rlength);

d2vdy2 = -phiy(3)*((apy(3)*rpi/rlength).^2)  ...
    * cos(apy(3)*rpi*y/rlength)  ...
    - phixy(3)*((apxy(3)*rpi*x/rlength/rlength).^2)  ...
    * cos(apxy(3)*rpi*x*y/rlength/rlength);

srcymtmtmp = rho*uvel*dvdx + rho*vvel*dvdy + dpdy  ...
    - rmu*( d2vdx2 + d2vdy2 );

end
%************************************************************************
function dtmin = compute_time_step(dtmin, rho, u, loc_p, loc_u, loc_v)

%Uses global variable(s): one, two, four, half, fourth
%Uses global variable(s): vel2ref, rmu, rho, dx, dy, cfl, rkappa, imax, jmax
%Uses: u
%To Modify: dt, dtmin

% i                        % i index (x direction)
% j                        % j index (y direction)

% dtvisc       % Viscous time step stability criteria (constant over domain)
% uvel2        % Local velocity squared
% beta2        % Beta squared paramete for time derivative preconditioning
% lambda_x     % Max absolute value eigenvalue in (x,t)
% lambda_y     % Max absolute value eigenvalue in (y,t)
% lambda_max   % Max absolute value eigenvalue (used in convective time step computation)
% dtconv       % Local convective time step restriction

global four half fourth
global vel2ref rmu dx dy cfl rkappa
global dt m

% dtmin = +1.0e99;
dtvisc = fourth*dx*dy*rho/rmu;

for k = 1:m
    i = loc_p(k,1);
    j = loc_p(k,2);
   
    uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
    beta2 = max( uvel2, rkappa.*vel2ref );
    lambda_x = half*( abs(u(i,j,2)) + sqrt((u(i,j,2).^2)+four.*beta2) );
    lambda_y = half*( abs(u(i,j,3)) + sqrt((u(i,j,3).^2)+four.*beta2) );
    lambda_max = max(lambda_x,lambda_y);
    dtconv = min(dx,dy) ./ ( lambda_max );
    dt(i,j) = cfl*min(dtconv,dtvisc);

    dtmin = min(dt(i,j),dtmin);
    
    i = loc_u(k,1);
    j = loc_u(k,2);
    
    uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
    beta2 = max( uvel2, rkappa.*vel2ref );
    lambda_x = half*( abs(u(i,j,2)) + sqrt((u(i,j,2).^2)+four.*beta2) );
    lambda_y = half*( abs(u(i,j,3)) + sqrt((u(i,j,3).^2)+four.*beta2) );
    lambda_max = max(lambda_x,lambda_y);
    dtconv = min(dx,dy) ./ ( lambda_max );
    dt(i,j) = cfl*min(dtconv,dtvisc);

    dtmin = min(dt(i,j),dtmin);
    
    i = loc_v(k,1);
    j = loc_v(k,2);
    
    uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
    beta2 = max( uvel2, rkappa.*vel2ref );
    lambda_x = half*( abs(u(i,j,2)) + sqrt((u(i,j,2).^2)+four.*beta2) );
    lambda_y = half*( abs(u(i,j,3)) + sqrt((u(i,j,3).^2)+four.*beta2) );
    lambda_max = max(lambda_x,lambda_y);
    dtconv = min(dx,dy) ./ ( lambda_max );
    dt(i,j) = cfl*min(dtconv,dtvisc);

    dtmin = min(dt(i,j),dtmin);
end

end
%************************************************************************
function Compute_Artificial_Viscosity(imax, jmax, rho, u, loc_p)
%
%Uses global variable(s): zero, one, two, four, six, half, fourth
%Uses global variable(s): imax, jmax, lim, rho, dx, dy, Cx, Cy, Cx2, Cy2, fsmall, vel2ref, rkappa
%Uses: u
%To Modify: artviscx, artviscy

% i                        % i index (x direction)
% j                        % j index (y direction)

% uvel2        % Local velocity squared
% beta2        % Beta squared paramete for time derivative preconditioning
% lambda_x     % Max absolute value e-value in (x,t)
% lambda_y     % Max absolute value e-value in (y,t)
% d4pdx4       % 4th derivative of pressure w.r.t. x
% d4pdy4       % 4th derivative of pressure w.r.t. y
% d2pdx2       % 2nd derivative of pressure w.r.t. x
% d2pdy2       % 2nd derivative of pressure w.r.t. y
% pfunct1      % Temporary variable for 2nd derivative damping
% pfunct2      % Temporary variable for 2nd derivative damping

global two four six half
global lim dx dy Cx Cy Cx2 Cy2 fsmall vel2ref rkappa
global artviscx artviscy m

for k = 1:m
    i = loc_p(k,1);
    j = loc_p(k,2);
    
    %Interior points
    if i ~= 2 && i ~= imax-1 && j ~=2 && j ~= jmax-1
    
        d4pdx4 = ( u(i+2,j,1) - four*u(i+1,j,1) + six*u(i,j,1) ...
            - four*u(i-1,j,1) + u(i-2,j,1) )./((dx.^4));
        d4pdy4 = ( u(i,j+2,1) - four*u(i,j+1,1) + six*u(i,j,1) ...
            - four*u(i,j-1,1) + u(i,j-2,1) )./((dy.^4));
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_x = half*( abs(u(i,j,2)) + sqrt((u(i,j,2).^2)+four*beta2) );
        lambda_y = half*( abs(u(i,j,3)) + sqrt((u(i,j,3).^2)+four*beta2) );
        
        artviscx(i,j) = -lambda_x.*Cx.*(dx.^3)./beta2.*d4pdx4;
        artviscy(i,j) = -lambda_y.*Cy.*(dy.^3)./beta2.*d4pdy4;
    
    % Side Walls
    % Left side
    elseif i==2 && j ~= 2 && j ~= jmax-1
        % For artviscy(i,j)
        d4pdy4 = ( u(i,j+2,1) - four*u(i,j+1,1) + six*u(i,j,1) ...
            - four*u(i,j-1,1) + u(i,j-2,1) )./((dy.^4));
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_y = half*( abs(u(i,j,3)) + sqrt((u(i,j,3).^2)+four*beta2) );
        
        artviscy(i,j) = -lambda_y*Cy*(dy.^3)./beta2.*d4pdy4;
        
        % For artviscx(i,j) = artviscx(i+1,j)
        i = i+1;
        d4pdx4 = ( u(i+2,j,1) - four*u(i+1,j,1) + six*u(i,j,1) ...
                - four*u(i-1,j,1) + u(i-2,j,1) )./((dx.^4));
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_x = half*( abs(u(i,j,2)) + sqrt((u(i,j,2).^2)+four*beta2) );
        
        artviscx(i,j) = -lambda_x.*Cx.*(dx.^3)./beta2.*d4pdx4;
    %Right Side
    elseif i==imax-1 && j ~= 2 && j ~= jmax-1
        % For artviscy(i,j)
        d4pdy4 = ( u(i,j+2,1) - four*u(i,j+1,1) + six*u(i,j,1) ...
            - four*u(i,j-1,1) + u(i,j-2,1) )./((dy.^4));

        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_y = half*( abs(u(i,j,3)) + sqrt((u(i,j,3).^2)+four*beta2) );

        artviscy(i,j) = -lambda_y*Cy*(dy.^3)./beta2.*d4pdy4;
        
        % For artviscx(i,j) = artviscx(i-1,j)
        i = i-1;
        d4pdx4 = ( u(i+2,j,1) - four*u(i+1,j,1) + six*u(i,j,1) ...
                - four*u(i-1,j,1) + u(i-2,j,1) )./((dx.^4));
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_x = half*( abs(u(i,j,2)) + sqrt((u(i,j,2).^2)+four*beta2) );
        
        artviscx(i,j) = -lambda_x.*Cx.*(dx.^3)./beta2.*d4pdx4;
        
    % Bottom wall
    elseif j==2 && i ~= 2 && i ~= imax-1
        % For artviscx(i,j)
        d4pdx4 = ( u(i+2,j,1) - four*u(i+1,j,1) + six*u(i,j,1) ...
            - four*u(i-1,j,1) + u(i-2,j,1) )./((dx.^4));

        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_x = half*( abs(u(i,j,2)) + sqrt((u(i,j,2).^2)+four*beta2) );

        artviscx(i,j) = -lambda_x*Cx*(dx.^3)./beta2.*d4pdx4; 
        
        % For artviscy(i,j) = artiviscy(i,j+1)
        j = j+1;
        d4pdy4 = ( u(i,j+2,1) - four*u(i,j+1,1) + six*u(i,j,1) ...
             - four*u(i,j-1,1) + u(i,j-2,1) )./((dy.^4));

        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_y = half*( abs(u(i,j,3)) + sqrt((u(i,j,3).^2)+four*beta2) );

        artviscy(i,j) = -lambda_y*Cy*(dy.^3)./beta2.*d4pdy4;
        
    % Top Wall
    elseif j==jmax-1 && i ~= 2 && i ~= imax-1
        % For artviscx(i,j)
        d4pdx4 = ( u(i+2,j,1) - four*u(i+1,j,1) + six*u(i,j,1) ...
            - four*u(i-1,j,1) + u(i-2,j,1) )./((dx.^4));

        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_x = half*( abs(u(i,j,2)) + sqrt((u(i,j,2).^2)+four*beta2) );

        artviscx(i,j) = -lambda_x*Cx*(dx.^3)./beta2.*d4pdx4; 
        
        % For artviscy(i,j) = artiviscy(i,j-1)
        j = j-1;
        d4pdy4 = ( u(i,j+2,1) - four*u(i,j+1,1) + six*u(i,j,1) ...
             - four*u(i,j-1,1) + u(i,j-2,1) )./((dy.^4));

        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_y = half*( abs(u(i,j,3)) + sqrt((u(i,j,3).^2)+four*beta2) );

        artviscy(i,j) = -lambda_y*Cy*(dy.^3)./beta2.*d4pdy4;
        
    % Corners
    elseif i == 2 && j == 2
        % For artviscx(i,j) = half*(artviscx(i+1,j)+artviscx(i,j+1));
        % For artviscy(i,j) = half*(artviscy(i+1,j)+artviscy(i,j+1));
        i = 2+1;
%         j = 2;
        d4pdx4 = ( u(i+2,j,1) - four*u(i+1,j,1) + six*u(i,j,1) ...
            - four*u(i-1,j,1) + u(i-2,j,1) )./((dx.^4));
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_x = half*( abs(u(i,j,2)) + sqrt((u(i,j,2).^2)+four*beta2) );
        artviscxip1 = -lambda_x.*Cx.*(dx.^3)./beta2.*d4pdx4;
%         i = 2+1;
        j = 2+1;
        d4pdy4 = ( u(i,j+2,1) - four*u(i,j+1,1) + six*u(i,j,1) ...
            - four*u(i,j-1,1) + u(i,j-2,1) )./((dy.^4));
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_y = half*( abs(u(i,j,3)) + sqrt((u(i,j,3).^2)+four*beta2) );     
        artviscyip1 = -lambda_y.*Cy.*(dy.^3)./beta2.*d4pdy4;
    
        i = 2;
        j = 2+1;
        d4pdy4 = ( u(i,j+2,1) - four*u(i,j+1,1) + six*u(i,j,1) ...
            - four*u(i,j-1,1) + u(i,j-2,1) )./((dy.^4));
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_y = half*( abs(u(i,j,3)) + sqrt((u(i,j,3).^2)+four*beta2) );
        artviscyjp1 = -lambda_y.*Cy.*(dy.^3)./beta2.*d4pdy4;
        i = 2+1;
%         j = 2+1;
        d4pdx4 = ( u(i+2,j,1) - four*u(i+1,j,1) + six*u(i,j,1) ...
            - four*u(i-1,j,1) + u(i-2,j,1) )./((dx.^4));
        lambda_x = half*( abs(u(i,j,2)) + sqrt((u(i,j,2).^2)+four*beta2) );
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        artviscxjp1 = -lambda_x.*Cx.*(dx.^3)./beta2.*d4pdx4;
            
        i = 2;
        j = 2;
    
        artviscx(i,j) = half*(artviscxip1+artviscxjp1);
        artviscy(i,j) = half*(artviscyip1+artviscyjp1);
        
    elseif i == imax-1 && j == 2
        % For artviscx(i,j) = half*(artviscx(i-1,j)+artviscx(i,j+1));
        % For artviscy(i,j) = half*(artviscy(i-1,j)+artviscy(i,j+1));
        i = imax-1-1;
%         j = 2;
        d4pdx4 = ( u(i+2,j,1) - four*u(i+1,j,1) + six*u(i,j,1) ...
            - four*u(i-1,j,1) + u(i-2,j,1) )./((dx.^4));
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_x = half*( abs(u(i,j,2)) + sqrt((u(i,j,2).^2)+four*beta2) );
        artviscxim1 = -lambda_x.*Cx.*(dx.^3)./beta2.*d4pdx4;
%         i = imax-1-1;
        j = 2+1;
        d4pdy4 = ( u(i,j+2,1) - four*u(i,j+1,1) + six*u(i,j,1) ...
            - four*u(i,j-1,1) + u(i,j-2,1) )./((dy.^4));
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_y = half*( abs(u(i,j,3)) + sqrt((u(i,j,3).^2)+four*beta2) );   
        artviscyim1 = -lambda_y.*Cy.*(dy.^3)./beta2.*d4pdy4;
    
        i = imax-1;
        j = 2+1;
        d4pdy4 = ( u(i,j+2,1) - four*u(i,j+1,1) + six*u(i,j,1) ...
            - four*u(i,j-1,1) + u(i,j-2,1) )./((dy.^4));
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_y = half*( abs(u(i,j,3)) + sqrt((u(i,j,3).^2)+four*beta2) );
        artviscyjp1 = -lambda_y.*Cy.*(dy.^3)./beta2.*d4pdy4;
        i = imax-1-1;
%         j = 2+1;
        d4pdx4 = ( u(i+2,j,1) - four*u(i+1,j,1) + six*u(i,j,1) ...
            - four*u(i-1,j,1) + u(i-2,j,1) )./((dx.^4));
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_x = half*( abs(u(i,j,2)) + sqrt((u(i,j,2).^2)+four*beta2) );
        artviscxjp1 = -lambda_x.*Cx.*(dx.^3)./beta2.*d4pdx4;
            
        i = imax-1;
        j = 2;
    
        artviscx(i,j) = half*(artviscxim1+artviscxjp1);
        artviscy(i,j) = half*(artviscyim1+artviscyjp1);
        
    elseif i == 2 && j == jmax-1
        % For artviscx(i,j) = half*(artviscx(i+1,j)+artviscx(i,j-1));
        % For artviscy(i,j) = half*(artviscy(i+1,j)+artviscy(i,j-1));
        i = 2+1;
%         j = jmax-1;
        d4pdx4 = ( u(i+2,j,1) - four*u(i+1,j,1) + six*u(i,j,1) ...
            - four*u(i-1,j,1) + u(i-2,j,1) )./((dx.^4));
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_x = half*( abs(u(i,j,2)) + sqrt((u(i,j,2).^2)+four*beta2) );
        artviscxip1 = -lambda_x.*Cx.*(dx.^3)./beta2.*d4pdx4;
%         i = 2+1;
        j = jmax-1-1;
        d4pdy4 = ( u(i,j+2,1) - four*u(i,j+1,1) + six*u(i,j,1) ...
            - four*u(i,j-1,1) + u(i,j-2,1) )./((dy.^4));
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_y = half*( abs(u(i,j,3)) + sqrt((u(i,j,3).^2)+four*beta2) );        
        artviscyip1 = -lambda_y.*Cy.*(dy.^3)./beta2.*d4pdy4;
    
        i = 2;
        j = jmax-1-1;
        d4pdy4 = ( u(i,j+2,1) - four*u(i,j+1,1) + six*u(i,j,1) ...
            - four*u(i,j-1,1) + u(i,j-2,1) )./((dy.^4));
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_y = half*( abs(u(i,j,3)) + sqrt((u(i,j,3).^2)+four*beta2) );
        artviscyjm1 = -lambda_y.*Cy.*(dy.^3)./beta2.*d4pdy4;
        i = 2+1;
%         j = jmax-1-1;
        d4pdx4 = ( u(i+2,j,1) - four*u(i+1,j,1) + six*u(i,j,1) ...
            - four*u(i-1,j,1) + u(i-2,j,1) )./((dx.^4));
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_x = half*( abs(u(i,j,2)) + sqrt((u(i,j,2).^2)+four*beta2) );       
        artviscxjm1 = -lambda_x.*Cx.*(dx.^3)./beta2.*d4pdx4;
            
        i = 2;
        j = jmax-1;
    
        artviscx(i,j) = half*(artviscxip1+artviscxjm1);
        artviscy(i,j) = half*(artviscyip1+artviscyjm1);
        
    elseif i == imax-1 && j == jmax-1
        % For artviscx(i,j) = half*(artviscx(i-1,j)+artviscx(i,j-1));
        % For artviscy(i,j) = half*(artviscy(i-1,j)+artviscy(i,j-1));
        i = imax-1-1;
%         j = jmax-1;
        d4pdx4 = ( u(i+2,j,1) - four*u(i+1,j,1) + six*u(i,j,1) ...
            - four*u(i-1,j,1) + u(i-2,j,1) )./((dx.^4));
        
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_x = half*( abs(u(i,j,2)) + sqrt((u(i,j,2).^2)+four*beta2) );
        artviscxim1 = -lambda_x.*Cx.*(dx.^3)./beta2.*d4pdx4;
%         i = i-1;
        j = jmax-1-1;
        d4pdy4 = ( u(i,j+2,1) - four*u(i,j+1,1) + six*u(i,j,1) ...
            - four*u(i,j-1,1) + u(i,j-2,1) )./((dy.^4));
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_y = half*( abs(u(i,j,3)) + sqrt((u(i,j,3).^2)+four*beta2) );      
        artviscyim1 = -lambda_y.*Cy.*(dy.^3)./beta2.*d4pdy4;
    
        i = imax-1;
        j = jmax-1-1;
        d4pdy4 = ( u(i,j+2,1) - four*u(i,j+1,1) + six*u(i,j,1) ...
            - four*u(i,j-1,1) + u(i,j-2,1) )./((dy.^4));
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_y = half*( abs(u(i,j,3)) + sqrt((u(i,j,3).^2)+four*beta2) );
        artviscyjm1 = -lambda_y.*Cy.*(dy.^3)./beta2.*d4pdy4;
        i = imax-1-1;
%         j = jmax-1-1;
        d4pdx4 = ( u(i+2,j,1) - four*u(i+1,j,1) + six*u(i,j,1) ...
            - four*u(i-1,j,1) + u(i-2,j,1) )./((dx.^4));
        uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
        beta2 = max( uvel2,rkappa*vel2ref );
        lambda_x = half*( abs(u(i,j,2)) + sqrt((u(i,j,2).^2)+four*beta2) );       
        artviscxjm1 = -lambda_x.*Cx.*(dx.^3)./beta2.*d4pdx4;
            
        i = imax-1;
        j = 2;
    
        artviscx(i,j) = half*(artviscxim1+artviscxjm1);
        artviscy(i,j) = half*(artviscyim1+artviscyjm1);
        
    end
        
        
    
end


% Second Derivative Damping
if ((Cy2~=0.0)&&(Cx2~=0.0))
    for k = 1:m
        i = loc_p(k,1);
        j = loc_p(k,2);
        if ismember(2:imax-1,i) && ismember(2:jmax-1,j)
            pfunct1 = abs( u(i+1,j,lim) - two*u(i,j,lim) + u(i-1,j,lim) );
            pfunct2 = abs( u(i+1,j,lim) + two*u(i,j,lim) + u(i-1,j,lim) );
            
            d2pdx2 = ( u(i+1,j,lim) - two*u(i,j,lim) + u(i-1,j,lim) )/(dx*dx);
            artviscx(i,j) = artviscx(i,j) ...
                + rho*Cx2*dx*d2pdx2*pfunct1/(pfunct2+fsmall);  %2nd form
            
            pfunct1 = abs( u(i,j+1,lim) - two*u(i,j,lim) + u(i,j-1,lim) );
            pfunct2 = abs( u(i,j+1,lim) + two*u(i,j,lim) + u(i,j-1,lim) );
            
            d2pdy2 = (u(i,j+1,lim) - two*u(i,j,lim) + u(i,j-1,lim) )/(dy*dy);
            artviscy(i,j) = artviscy(i,j)  ...
                + rho*Cy2*dy*d2pdy2*pfunct1/(pfunct2+fsmall);   %2nd form
        end
    end
    
end

end
%************************************************************************
function u = SGS_forward_sweep(rho, u, loc_p, loc_u, loc_v)
%
%Uses global variable(s): two, three, six, half
%Uses global variable(s): imax, imax, jmax, ipgorder, rho, rhoinv, dx, dy, rkappa, ...
%                      xmax, xmin, ymax, ymin, rmu, vel2ref
%Uses: artviscx, artviscy, dt, s
%To Modify: u

% i                        % i index (x direction)
% j                        % j index (y direction)

% dpdx         % First derivative of pressure w.r.t. x
% dudx         % First derivative of x velocity w.r.t. x
% dvdx         % First derivative of y velocity w.r.t. x
% dpdy         % First derivative of pressure w.r.t. y
% dudy         % First derivative of x velocity w.r.t. y
% dvdy         % First derivative of y velocity w.r.t. y
% d2udx2       % Second derivative of x velocity w.r.t. x
% d2vdx2       % Second derivative of y velocity w.r.t. x
% d2udy2       % Second derivative of x velocity w.r.t. y
% d2vdy2       % Second derivative of y velocity w.r.t. y
% beta2        % Beta squared parameter for time derivative preconditioning
% uvel2        % Velocity squared

global two half
global rhoinv dx dy rkappa rmu vel2ref
global artviscx artviscy dt s
%-------------------------------------------------------------------------%
global rhs m
%-------------------------------------------------------------------------%

% Symmetric Gauss-Siedel: Forward Sweep

for k = 1:m
    % p equation
    i = loc_p(k,1);
    j = loc_p(k,2);
    
    dudx = half.*(u(i+1,j,2) - u(i-1,j,2))./dx;
    dvdy = half*(u(i,j+1,3) - u(i,j-1,3))./dy;
    
    uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
    beta2 = max( uvel2,rkappa.*vel2ref );
            
    rhs(i,j,1) = beta2.*( rho.*dudx + rho.*dvdy  ...
        - artviscx(i,j) - artviscy(i,j)  ...
        - s(i,j,1) );
        
    u(i,j,1) = u(i,j,1)  ...
        - dt(i,j).*rhs(i,j,1);
    
    % u equation
    i = loc_u(k,1);
    j = loc_u(k,2);
    
    dpdx = half.*(u(i+1,j,1) - u(i-1,j,1))./dx;
    dudx = half.*(u(i+1,j,2) - u(i-1,j,2))./dx;
    dudy = half*(u(i,j+1,2) - u(i,j-1,2))./dy;
    
    d2udx2 = (u(i+1,j,2) - two*u(i,j,2) + u(i-1,j,2))./(dx.*dx);
    d2udy2 = (u(i,j+1,2) - two*u(i,j,2) + u(i,j-1,2))./(dy.*dy);
            
    rhs(i,j,2) = ( u(i,j,2).*dudx + u(i,j,3).*dudy ...
        + rhoinv.*dpdx  ...
        - rhoinv.*rmu.*d2udx2 - rhoinv.*rmu.*d2udy2  ...
        - rhoinv.*s(i,j,2) );
                    
    u(i,j,2) = u(i,j,2)  ...
        - dt(i,j).*rhs(i,j,2);
    
    % v equation
    i = loc_v(k,1);
    j = loc_v(k,2);
    
    dpdy = half.*(u(i,j+1,1) - u(i,j-1,1))./dy;
    dvdx = half.*(u(i+1,j,3) - u(i-1,j,3))./dx;
    dvdy = half*(u(i,j+1,3) - u(i,j-1,3))./dy;
    
    d2vdx2 = (u(i+1,j,3) - two*u(i,j,3) + u(i-1,j,3))./(dx.*dx);
    d2vdy2 = (u(i,j+1,3) - two*u(i,j,3) + u(i,j-1,3))./(dy.*dy);
            
    rhs(i,j,3) = ( u(i,j,2).*dvdx + u(i,j,3).*dvdy ...
        + rhoinv.*dpdy  ...
        - rhoinv.*rmu.*d2vdx2 - rhoinv.*rmu.*d2vdy2  ...
        - rhoinv.*s(i,j,3) );
                    
    u(i,j,3) = u(i,j,3)  ...
        - dt(i,j).*rhs(i,j,3);
    
end



end
%************************************************************************
function u = SGS_backward_sweep(rho, u, loc_p, loc_u, loc_v)
%
%Uses global variable(s): two, three, six, half
%Uses global variable(s): imax, imax, jmax, ipgorder, rho, rhoinv, dx, dy, rkappa, ...
%                      xmax, xmin, ymax, ymin, rmu, vel2ref
%Uses: artviscx, artviscy, dt, s
%To Modify: u

% i                        % i index (x direction)
% j                        % j index (y direction)

% dpdx         % First derivative of pressure w.r.t. x
% dudx         % First derivative of x velocity w.r.t. x
% dvdx         % First derivative of y velocity w.r.t. x
% dpdy         % First derivative of pressure w.r.t. y
% dudy         % First derivative of x velocity w.r.t. y
% dvdy         % First derivative of y velocity w.r.t. y
% d2udx2       % Second derivative of x velocity w.r.t. x
% d2vdx2       % Second derivative of y velocity w.r.t. x
% d2udy2       % Second derivative of x velocity w.r.t. y
% d2vdy2       % Second derivative of y velocity w.r.t. y
% beta2        % Beta squared parameter for time derivative preconditioning
% uvel2        % Velocity squared

global two half
global rhoinv dx dy rkappa rmu vel2ref
global artviscx artviscy dt s
%------------------------------------------------------------------------------------------------------------------%
global rhs m
%------------------------------------------------------------------------------------------------------------------%

% Symmetric Gauss-Siedel: Backward Sweep
for k = m:-1:1
    % p equation
    i = loc_p(k,1);
    j = loc_p(k,2);
    
    dudx = half.*(u(i+1,j,2) - u(i-1,j,2))./dx;
    dvdy = half*(u(i,j+1,3) - u(i,j-1,3))./dy;
    
    uvel2 = (u(i,j,2).^2) + (u(i,j,3).^2);
    beta2 = max( uvel2,rkappa.*vel2ref );
            
    rhs(i,j,1) = beta2.*( rho.*dudx + rho.*dvdy  ...
        - artviscx(i,j) - artviscy(i,j)  ...
        - s(i,j,1) );
        
    u(i,j,1) = u(i,j,1)  ...
        - dt(i,j).*rhs(i,j,1);
    
    % u equation
    i = loc_u(k,1);
    j = loc_u(k,2);
    
    dpdx = half.*(u(i+1,j,1) - u(i-1,j,1))./dx;
    dudx = half.*(u(i+1,j,2) - u(i-1,j,2))./dx;
    dudy = half*(u(i,j+1,2) - u(i,j-1,2))./dy;
    
    d2udx2 = (u(i+1,j,2) - two*u(i,j,2) + u(i-1,j,2))./(dx.*dx);
    d2udy2 = (u(i,j+1,2) - two*u(i,j,2) + u(i,j-1,2))./(dy.*dy);
            
    rhs(i,j,2) = ( u(i,j,2).*dudx + u(i,j,3).*dudy ...
        + rhoinv.*dpdx  ...
        - rhoinv.*rmu.*d2udx2 - rhoinv.*rmu.*d2udy2  ...
        - rhoinv.*s(i,j,2) );
                    
    u(i,j,2) = u(i,j,2)  ...
        - dt(i,j).*rhs(i,j,2);
    
    % v equation
    i = loc_v(k,1);
    j = loc_v(k,2);
    
    dpdy = half.*(u(i,j+1,1) - u(i,j-1,1))./dy;
    dvdx = half.*(u(i+1,j,3) - u(i-1,j,3))./dx;
    dvdy = half*(u(i,j+1,3) - u(i,j-1,3))./dy;
    
    d2vdx2 = (u(i+1,j,3) - two*u(i,j,3) + u(i-1,j,3))./(dx.*dx);
    d2vdy2 = (u(i,j+1,3) - two*u(i,j,3) + u(i,j-1,3))./(dy.*dy);
            
    rhs(i,j,3) = ( u(i,j,2).*dvdx + u(i,j,3).*dvdy ...
        + rhoinv.*dpdy  ...
        - rhoinv.*rmu.*d2vdx2 - rhoinv.*rmu.*d2vdy2  ...
        - rhoinv.*s(i,j,3) );
                    
    u(i,j,3) = u(i,j,3)  ...
        - dt(i,j).*rhs(i,j,3);
    
end

end
%************************************************************************
function u = point_Jacobi(rho, u, loc_p, loc_u, loc_v)
%
%Uses global variable(s): two, three, six, half
%Uses global variable(s): imax, imax, jmax, ipgorder, rho, rhoinv, dx, dy, rkappa, ...
%                      xmax, xmin, ymax, ymin, rmu, vel2ref
%Uses: uold, artviscx, artviscy, dt, s
%To Modify: u


% i                        % i index (x direction)
% j                        % j index (y direction)

% dpdx         % First derivative of pressure w.r.t. x
% dudx         % First derivative of x velocity w.r.t. x
% dvdx         % First derivative of y velocity w.r.t. x
% dpdy         % First derivative of pressure w.r.t. y
% dudy         % First derivative of x velocity w.r.t. y
% dvdy         % First derivative of y velocity w.r.t. y
% d2udx2       % Second derivative of x velocity w.r.t. x
% d2vdx2       % Second derivative of y velocity w.r.t. x
% d2udy2       % Second derivative of x velocity w.r.t. y
% d2vdy2       % Second derivative of y velocity w.r.t. y
% beta2        % Beta squared parameter for time derivative preconditioning
% uvel2        % Velocity squared
global two half
global rhoinv dx dy rkappa rmu vel2ref
global uold artviscx artviscy dt s
%-------------------------------------------------------------------------%
global rhs m
%-------------------------------------------------------------------------%

% Point Jacobi method
for k = 1:m
    % p equation
    i = loc_p(k,1);
    j = loc_p(k,2);
    
    dudx = half.*(uold(i+1,j,2) - uold(i-1,j,2))./dx;
    dvdy = half*(uold(i,j+1,3) - uold(i,j-1,3))./dy;
    
    uvel2 = (uold(i,j,2).^2) + (uold(i,j,3).^2);
    beta2 = max( uvel2,rkappa.*vel2ref );
            
    rhs(i,j,1) = beta2.*( rho.*dudx + rho.*dvdy  ...
        - artviscx(i,j) - artviscy(i,j)  ...
        - s(i,j,1) );
        
    u(i,j,1) = uold(i,j,1)  ...
        - dt(i,j).*rhs(i,j,1);
    
    % u equation
    i = loc_u(k,1);
    j = loc_u(k,2);
    
    dpdx = half.*(uold(i+1,j,1) - uold(i-1,j,1))./dx;
    dudx = half.*(uold(i+1,j,2) - uold(i-1,j,2))./dx;
    dudy = half*(uold(i,j+1,2) - uold(i,j-1,2))./dy;
    
    d2udx2 = (uold(i+1,j,2) - two*uold(i,j,2) + uold(i-1,j,2))./(dx.*dx);
    d2udy2 = (uold(i,j+1,2) - two*uold(i,j,2) + uold(i,j-1,2))./(dy.*dy);
            
    rhs(i,j,2) = ( uold(i,j,2).*dudx + uold(i,j,3).*dudy ...
        + rhoinv.*dpdx  ...
        - rhoinv.*rmu.*d2udx2 - rhoinv.*rmu.*d2udy2  ...
        - rhoinv.*s(i,j,2) );
                    
    u(i,j,2) = uold(i,j,2)  ...
        - dt(i,j).*rhs(i,j,2);
    
    % u equation
    i = loc_v(k,1);
    j = loc_v(k,2);
    
    dpdy = half.*(uold(i,j+1,1) - uold(i,j-1,1))./dy;
    dvdx = half.*(uold(i+1,j,3) - uold(i-1,j,3))./dx;
    dvdy = half*(uold(i,j+1,3) - uold(i,j-1,3))./dy;
    
    d2vdx2 = (uold(i+1,j,3) - two*uold(i,j,3) + uold(i-1,j,3))./(dx.*dx);
    d2vdy2 = (uold(i,j+1,3) - two*uold(i,j,3) + uold(i,j-1,3))./(dy.*dy);
            
    rhs(i,j,3) = ( uold(i,j,2).*dvdx + uold(i,j,3).*dvdy ...
        + rhoinv.*dpdy  ...
        - rhoinv.*rmu.*d2vdx2 - rhoinv.*rmu.*d2vdy2  ...
        - rhoinv.*s(i,j,3) );
                    
    u(i,j,3) = uold(i,j,3)  ...
        - dt(i,j).*rhs(i,j,3);
    
end

end
%************************************************************************
function u = pressure_rescaling(imax, jmax, imms, u, loc_p)
%
%Uses global variable(s): imax, jmax, imms, xmax, xmin, ymax, ymin, rlength, pinf
%To Modify: u

% i                        % i index (x direction)
% j                        % j index (y direction)

% iref                      % i index location of pressure rescaling point
% jref                      % j index location of pressure rescaling point

% x        % Temporary variable for x location
% y        % Temporary variable for y location
% deltap   % delta_pressure for rescaling all values

global xmax xmin ymax ymin pinf m

iref = (imax-1)/2+1;     % Set reference pressure to center of cavity
jref = (jmax-1)/2+1;
if (imms==1)
    x = (xmax - xmin)*(iref-1)/(imax - 1);
    y = (ymax - ymin)*(jref-1)/(jmax - 1);
    deltap = u(iref,jref,1) - umms(x,y,1); % Constant in MMS
else
    deltap = u(iref,jref,1) - pinf; % Reference pressure
end

for k = 1:m
    u(loc_p(k,1),loc_p(k,2),1) = u(loc_p(k,1),loc_p(k,2),1) - deltap;
end


end
%************************************************************************


