classdef DLS < dynamicprops & Graphics & Utils
%============================================================================
%
% DLS class for plotting, fitting, showing dynamic light scattering data
% taken from an array of type Data
%
% Author:	Fabio Zanini
% Companies:	Institut Laue Langevin, Universität Tübingen
% Date:		15 May 2010
% Version:	1.3
%
% Syntax: dlsclass = DLS( input_data_classes )
%
% A list of things you can do:
% - show data parameters (angles, q vectors, concentrations, etc.);
% - plot data;
% - fit the data according to usual DLS models (single or double exponential,
%   cumulant of second order, streched exponential);
% - find the H function using both DLS and SLS.
%
%============================================================================

 %============================================================================
 % PUBLIC PROPERTIES
 %============================================================================
 properties (Access=public)
 % N.B.: some dynamic properties could be called later on, like Gamma, D, etc.

  Sample
  Unit_C
  Unit_Q
  Unit_Q2
  % both Angles and Q are the unique reduction (union) of all their partners
  % in the input Data classes
  Unit_Tau
  T

 end	% public properties
 
 %============================================================================
 % OBSERVED PUBLIC PROPERTIES
 %============================================================================
 properties ( Access = public, SetObservable, AbortSet )
 % These are useful for triggering events after change in a property value
 % In this class, the Data struct is changed according to changes in Q and C

  C
  Phi
  Angles
  Q
  Q2
  Data			= struct(	'C',		[],	...
					'Phi',		[],	...
					'Angles',	[],	...
					'Q',		[],	...
					'Q2',		[],	...
					'Tau',		[],	...
					'G',		[],	...
					'dG',		[]	);
  % Data is a struct with all the data stored as fields (vectors or cell arrays)
  % For instance, all correlations are stored in dls.Data.G
  % Therefore one is allowed to use such syntaxes like the following:
  %
  % dls.Data.G ( dls.Data.Angles == 30 )
  %
  % meaning that we look for all correlogramms for data at 30°. This is *very*
  % flexible and the best way to store things (remember dynamic field get-set
  % methods, etc.)
  %
 end	% observed public properties

 %============================================================================
 % HIDDEN PUBLIC PROPERTIES
 %============================================================================
 properties ( Access = public, Hidden)

  MinimalLagtime	= 1e-6		% ms
  MaximalLagtime	= 1e4		% ms
  MinimalG		= -0.05
  MaximalG		= 1.2

 end	% properties

 %============================================================================
 % PUBLIC METHODS
 %============================================================================
 methods ( Access = public )

  %============================================================================
  % CONSTRUCTOR
  %============================================================================
  function dls = DLS ( dataclasses )
  % this class takes an array of Data classes as input

   % eat the strings
   dls.Sample	= dataclasses(1).Sample;
   dls.Unit_Q	= dataclasses(1).Unit_Q;
   dls.Unit_Q2	= regexprep(dls.Unit_Q,'\^\{*-1\}*','\^\{-2\}');
   dls.Unit_C	= dataclasses(1).Unit_C;
   dls.Unit_Tau	= dataclasses(1).Unit_Tau;
   dls.T	= dataclasses(1).T;

   % write the data as a structure (easier to manage)
   conc = [];
   for i = 1 : length(dataclasses)
    for j = 1 : length(dataclasses(i).Angles_dyn)
     conc	= [ conc dataclasses(i).C ];
    end
   end
   dls.Data.C		= conc;
   dls.Data.Angles	= horzcat(dataclasses.Angles_dyn);
   dls.Data.Q		= horzcat(dataclasses.Q_dyn);
   dls.Data.Q2		= horzcat(dataclasses.Q_dyn).^2;
   dls.Data.Tau		= horzcat(dataclasses.Tau);
   dls.Data.G		= horzcat(dataclasses.G);
   dls.Data.dG		= horzcat(dataclasses.dG);

   dls.Data.Phi		= dls.Data.C * LIT.(dls.Sample).v0;

   % create unique properties with the update_uniques function in the Utils class
   dls.update_uniques('C','Phi','Q','Q2','Angles');

   % monitor properties with listeners in the Utils class
   dls.monitorprop('C','Phi','Q','Q2','Angles');

  end % constructor

  %============================================================================
  % PLOT CORRELATIONS
  %============================================================================
  function plot_correlations ( self, varargin )
  % plot the autocorrelation data or its laplace transform
  %
  % varargin allows the user to choose some details of the plot. The syntax is
  % e.g. the following:
  %
  % plot_correlations('figure',gcf,'C',[ 2 3 ],'Angles',[30 50 100])
  %
  % The optional parameters are the following (default values in brackets):
  % - figure (new figures)
  % - Angles (all angles)
  % - C (all concentrations)
  % - Type ('real'):		this can be 'real' or 'Laplace'

   options = struct(varargin{:});						% eat the optional arguments as a struct

   try	C = options.C;			catch	C = self.C;		end	% concentrations
   try	angles = options.Angles;	catch	angles = self.Angles;	end	% angles

   try	color = options.Color;		catch   color	= 'Green';	end	% color
   nuances	= self.get_color(color,length(C));				% nuances for plot colors

   try	type = options.Type;		catch	type	= 'real';	end	% type ('real' or 'laplace' )
   
   [ c_long angles_long x y ] = self.prepare_data_correlations ( type );	% prepare data

   % create the figures and plot the data
   for j = 1 : length(angles)							% for every angle...

    ax(j)		= self.prepare_plot_correlations ( angles(j), type );	% ...prepare plots...
    legend_names{j}	= {};	legend_group{j}	= [];				% ...prepare legends...

    for l = 1 : length(c_long)						% look for data to be plotted...

     if ( angles_long(l) == angles(j) && ismember(c_long(l),C) )	% ...look the right indices
 
      nuance	= nuances( c_long(l) == C, :);				% select the nuance for the plot
      plo	= plot(ax(j), x{l}, y{l},'-o',				...
					'Color',	nuance,		...
					'LineWidth', 0.1*self.LineWidth,...
					'MarkerSize',0.3*self.MarkerSize );	% plot

      legen	=['Protein conc = ',num2str(c_long(l),1),' ',self.Unit_C];	% legend

      % create legend arrays
      if ~ismember({legen},legend_names{j})
       legend_names{j}	= [ legend_names{j}; {legen}	];
       legend_group{j}	= [ legend_group{j}; plo	];
      end

     end
    end

    legend(ax(j),legend_group{j},legend_names{j},'FontSize',14);	% show the legend for every figure

   end

  end	% end of plot function

  %============================================================================
  % PREPARE PLOT FOR CORRELOGRAMMS (IN REAL OR LAPLACE SPACE)
  %============================================================================
  function ax = prepare_plot_correlations ( self, angle, type )

   % create the figure
   fig		= self.create_figure;						% ...create the figure...
   ax		= get(fig,'CurrentAxes');					% ...get the axis...

   set(gca, 'xscale','log');							% ...set the log scale...

   switch type
    case 'real'
     axis([ 	self.MinimalLagtime	self.MaximalLagtime	...
		self.MinimalG		self.MaximalG 		]);		% ...set the limits for the plot...

     xlabel(['\tau [ ',self.Unit_Tau,' ]']);					% ...set the x label...
     ylabel('g_1^2 [ normalised ]');						% ...set the y label...
     title(['Correlogramms at ',num2str(angle),'°']);				% ...set a title

    case 'Laplace'
     xlabel(['D [ ',self.Unit_D,' ]']);						% ...set the x label...
     ylabel('distr [ normalised ]');						% ...set the y label...
     title(['Laplace Inverted correlogramms at ',num2str(angle),'°']);		% ...set a title
   end

  end	% prepare_plot_correlations

  %============================================================================
  % PREPARE DATA FOR CORRELOGRAMMS (IN REAL OR LAPLACE SPACE)
  %============================================================================
  function [ c_long angles_long x y ] = prepare_data_correlations ( self, type )
  % this function prepares the data for the plots

   switch type
    case 'real'
     c_long		= self.Data.C;
     angles_long	= self.Data.Angles;

     for l = 1 : length(c_long)
      x{l} = self.Data.Tau{l};
      y{l} = self.Data.G{l};
     end

    case 'Laplace'
     c_long		= self.LP_C;
     angles_long	= self.LP_Angles;

     for l = 1 : length(c_long)
      x{l} = self.LP_D{l};
      y{l} = self.LP_G{l};
     end
   end
  end	% prepare_data_correlations

  %============================================================================
  % PLOT CORRELOGRAMMS IN 3D
  %============================================================================
  function plot3D ( self, type, plottype );
  % TODO: you cannot average over for the real correlations!

   if nargin == 1	type		= 'Laplace';	end			% default: plot real correlogramms
   if nargin < 3	plottype	= 'contour';	end			% default: plot real correlogramms

   switch type

    case 'real'								% if the correlogramms are real

     t	= self.Data.Tau;
     g	= self.Data.G;
     c	= self.Data.C;
     q	= self.Data.Q;
     angles	= self.Data.Angles;
     
     [ t g c q angles ] = self.filter_repetitions ( t, g, c, q,angles);	% filter out repetitions

     % transpose the cell contents... !
     for i = 1 : length(t)
      tt{i}	= t{i}' * ( q(i)^2 );
      gt{i}	= g{i}';
     end
     t		= tt;
     g		= gt;

     yname	= 'Tau';

    case 'Laplace'

     t	= self.LP_D;
     g	= self.LP_G;
     c	= self.LP_C;

     yname	= 'D';

   end

   assignin('base','t',t)

   x		= unique(c);
   y		= unique(horzcat(t{:}));

   for i = 1 : length(t)

    zz{i}	= interp1( t{i}, g{i}, y );

   end

   zzM	= cell2mat(zz');

   for i = 1 : length(x)
    index	= ( c == x(i) );
    z(:,i)	= mean(zzM(index,:))';
   end

   switch plottype
    case 'contour'
     contour(x,y,z,30);
    case 'mesh'
     mesh(x,y,z);
    case 'surf'
     surf(x,y,z);
   end

   set(gca,'Yscale','log');
   xlabel(['C [ ',self.Unit_C, ' ]']);
   ylabel([yname ' [ ', self.(['Unit_' yname]), ' ]']);
   zlabel('Dist [a.u.]');
   rotate3d;

  end	% plot3D

  %============================================================================
  % FIT CORRELATIONS
  %============================================================================
  function fit_correlations ( self , method, varargin )
  % This functions fits all the correlogramms of the class. Method is one of the following:
  % - 'Single': single exponential;
  % - 'Double'(default): double exponential;
  % - 'Single+Streched': single fast exponential and slow streched exponential (0<beta<1);
  % Not in use but easy to implement:
  % - 'Cumulant2', cumulant second order (see Koppel et al.);
  % - 'Cumulant3', cumulant third order.

   if nargin == 1	method = 'Double';   end		% default method: double exponential
 
   options = struct(varargin{:});				% interpret the optional arguments

   try system = options.system;	catch try system = self.system; catch system = 'BSA'; end; end;		% try to read the system from opt args

   % select which range of data to use for the fit. The problem is mainly
   % that for long lag times I'm fitting background, whereas for very short
   % lag times it is afterpulse noise of the APDs
   for l = 1 : length(self.Data.Tau)
    inde	= self.Data.Tau{l} > 1e-6 & self.Data.Tau{l} < 1e2;
    t{l}	= self.Data.Tau{l}(inde);
    g{l}	= self.Data.G{l}(inde);
    dg{l}	= self.Data.dG{l}(inde);
    c(l)	= self.Data.C(l);
    q(l)	= self.Data.Q(l);
    angles(l)	= self.Data.Angles(l);
   end

   % act differently depending on method chosen
   switch method

    case {'Single', 'Streched', 'Double', 'Single+Streched'}					% DISCRETE DECAYS

     for l = 1 : length(t)
      [ coeffnames coeffval dcoeffval ] = self.fit_discrete (	t{l}, g{l}, dg{l},	...
								method, q(l), system	);	% perform the fit

      % group the output coefficients from every correlogramm
      for i = 1 : length(coeffnames)
       fitoutput.(coeffnames{i})(l)	= coeffval(i);
       dfitoutput.(coeffnames{i})(l)	= dcoeffval(i);
      end
     end

    case 'Laplace'										% LAPLACE INVERSION

     try alpha	= options.Alpha;	catch alpha	= 1e-3;		end			% default alpha: 1e-3
     try cycles= options.Cycles;	catch cycles	= 1;		end			% default cycles: 1

     [ tf gf cf qf anglesf ] = self.filter_repetitions ( t, g, c, q, angles );			% filter out repetitions (the fit is faster)

     for l = 1 : length(tf)
      disp(['Fit n. ' num2str(l) ]);								% Show the fit number
      [ LP_Gamma LP_D LP_G ] = self.invert_laplace ( tf{l}, gf{l}, qf(l), alpha, cycles );	% invert Laplace!

     % group the output coefficients
      fitoutput.LP_Gamma{l}	= LP_Gamma;
      fitoutput.LP_D{l}		= LP_D;
      fitoutput.LP_G{l}	= LP_G;
     end

     close;											% close fit figure

     coeffnames		= {'LP_Gamma' 'LP_D' 'LP_G' 'LP_C' 'LP_Q' 'LP_Angles'};
     fitoutput.LP_C		= cf;
     fitoutput.LP_Q		= qf;
     fitoutput.LP_Angles	= anglesf;
     
    otherwise											% if the method is not recognized...
     error('Fit method not recognized!');							% ...print an error
   end

   % if the fields are cell arrays, add an abstract layer (STUPID MATLAB!)
   for i = 1 : length(coeffnames)
    if iscell(fitoutput.(coeffnames{i}))
     fitoutput.(coeffnames{i}) = {fitoutput.(coeffnames{i})};
    end
   end

   % add the coefficients as class properties
   for i = 1 : length(coeffnames)
    self.check_add_prop(	coeffnames{i},		fitoutput.(coeffnames{i})	);
    try self.check_add_prop(	['d',coeffnames{i}],	dfitoutput.(coeffnames{i})	); end	% CONTIN does not give any errors!
   end

   self.check_add_prop('Unit_Gamma',	[ self.Unit_Tau,'^{-1}']);	% add Unit_Gamma to the class
   self.check_add_prop('Unit_D',	'A^2/ns');			% add Unit_D to the class

  end	% fit_correlations

  %============================================================================
  % FIT CUMULANT (DEAD)
  %============================================================================
  % function varargout = fit_cumulant ( obj, order )
  % fit autocorrelation data according to Koppel JCP 57,11, 4814 (1972)
  %
  % the fit tries to fit with a cumulant expansion, plus amplitude
  % normalization, plus background, i.e. the assumed decay has the form:
  %
  %	g2-1 = b + | A * exp ( - K1 * t + K2 / 2 * t*t - K3 / 6 * t*t*t ) |^2
  %
  % NB: here it is |g1|^2 the fitted function
  %
  % The input syntax is simple: just write which order you prefer to use.

  %============================================================================
  % FIT GAMMA vs Q^2
  %============================================================================
  function fit_gamma_q2 ( obj, gammaname, varargin )
  % fit Gamma against Q^2 with a linear (*not* affine) dependence
  % moreover, average A for all angles
  % accepted optional arguments: plot ('yes' or 'no')

   try
    gammaname;
   catch
    error('please select a Gamma you want to fit against q^2 (e.g. Gamma, Gamma1, Gamma2)');
   end

   % find the kind of gamma and label the diffusion constant accordingly
   switch gammaname

    case 'Gamma'
     prop_suff = '';
    case {'Gamma1','Gamma2','Gammae','Gammas'}
     prop_suff = gammaname(6);
    case {'K1','k1'}
     prop_suff = '_K1';
    otherwise
     error('Gamma not recognized!');

   end

   % give some names to the output parameters
   Dname	= ['D',prop_suff];
   dDname	= ['dD',prop_suff];
   Unit_Dname	= ['Unit_D',prop_suff];
   Aname	= ['A',prop_suff];
   A_avname	= ['A',prop_suff,'m'];
   dA_avname	= ['dA',prop_suff,'m'];

   % interpret optional arguments
   options = struct(varargin{:});

   % plot fit results if not forbidden by the user
   try
    options.Plot;
   catch
    options = setfield(options,'Plot','no');
   end

   % initialize some fit options
   fit_function	= '1e6 .* D .* q2';	% unit conversion from ns^-1 to ms^-1
   lowerbond		= 1e-6;
   upperbond		= 1e3;
   startpoint		= 7;

   % fit every concentration
   for i = 1 : length(obj.C)
 
    % this is subtle: I'm using elementwise logical operators and dynamic structure fields
    % In the end we get an array of 1 or 0 indicating us which elements of, say, Gamma1
    % are to be fitted now. I exclude NaN values (bad fits of the correlogramms).
    inde = ~( obj.Data.C - obj.C(i) ) & ~isnan(obj.(gammaname)) & ~isnan(obj.(['d',gammaname]));

    % prepare the vectors for the fit
    q = obj.Data.Q(inde);
    gamma = obj.(gammaname)(inde);
    dgamma = obj.(['d',gammaname])(inde);

    % take also the amplitudes in case of double fit, since they say something
    a = obj.(Aname)(inde);
    da = obj.(['d',Aname])(inde);
 
    % set fit options
    weights =  1 ./ ( dgamma .^ 2 );
    fit_options = fitoptions('Method','NonLinearLeastSquares',	...
       		'Weights', weights, 'MaxFunEvals',100000,	...
           		'Lower',lowerbond,			...
       		'Upper',upperbond,				...
       		'Startpoint',startpoint					);
    fit_type = fittype(fit_function,				...
       		'independent','q2', 				...
       		'coefficients',{'D'},				...
       		'options',fit_options					);

    % perform the numerical
    [ cf gof ] = fit( q' .^2, gamma', fit_type );
     
    % get fit result
    par = coeffvalues (cf); 
    confidence = confint(cf,0.95);
    dpar =  0.5*(confidence(2,:)-confidence(1,:));  

    % output coefficients
    D(i)		= par(1);
    dD(i)		= dpar(1);

    % average amplitudes
    A(i)		= mean(a);
    dA(i)		= sqrt(mean(da .^2));		% assume they have the same mean etc.

   end
 
   % add the D, dD and Unit_D prop to the class
   obj.check_add_prop(Dname,D,dDname,dD,Unit_Dname,'A^2/ns',A_avname,A,dA_avname,dA);

   % print the diffusion constants
   fprintf(['The diffusion constants are: ', Dname, ' ', mat2str(obj.(Dname),2),' ',obj.(Unit_Dname),'\n']);

   % plot fit results if the option is positive
   if strcmp(options.Plot,'yes')
    obj.plot_gamma_q2(gammaname);
   end

  end	% fit_gamma_q2

  %============================================================================
  % CORRELATE GAMMA
  %============================================================================
  function correlate_gamma ( self, gamma1, gamma2, varargin )
  % this function plots gamma1 vs gamma2, to look for correlations
  % moreover, it calculates the cross-correlation and shows it
  % Accepted optional arguments:
  % - Color:	Base color for nuances, such as Green, Red, etc.
  % - Figure:	Use existing figure or create new one
  % - Type:	type of plot, such as Fill, Points, Lines

   if nargin == 1							% fallback gammas: Gamma1 and Gamma2
    gamma1 = 'Gamma1';	gamma2 = 'Gamma2';
   end

   try		self.(gamma1);	self.(gamma2);				% check for existence of the gammas
   catch	error('Something is wrong with your gammas.');
   end

   options	= struct(varargin{:});					% get optional parameters

   try color = options.Color;	catch	color = 'Green'; end		% color...
   try type = options.Type;	catch	type = 'Fill'; end		% ...type of plot...

   try parameter = options.Parameter; catch parameter = 'C'; end	% ...get the parameter for color nuances...
   nuances = self.get_color(color,length(self.(parameter)));		% ...nuances for plot

   D1_a		= 1e-6 * self.(gamma1) ./ ( self.Data.Q.^2 );		% get the data from the class
   D2_a		= 1e-6 * self.(gamma2) ./ ( self.Data.Q.^2 );
   dD1_a	= 1e-6 * self.(['d',gamma1]) ./ ( self.Data.Q.^2 );
   dD2_a	= 1e-6 * self.(['d',gamma2]) ./ ( self.Data.Q.^2 );

   try fig = options.Figure;
   catch
    fig = self.create_figure;						% create the figure
    xlabel('Faster diffusion [ A^2 / ns ]');				% x label
    ylabel('Slower diffusion [ A^2 / ns ]');				% y label
   
   end
   ax = get(fig,'CurrentAxes');

   for i = 1 : length(self.(parameter))					% group the points for colors, convhull etc.
    D1{i}	= D1_a( self.Data.(parameter)	== self.(parameter)(i) );
    D2{i}	= D2_a(	self.Data.(parameter)	== self.(parameter)(i) );
    dD1{i}	= dD1_a(self.Data.(parameter)	== self.(parameter)(i) );
    dD2{i}	= dD2_a(self.Data.(parameter)	== self.(parameter)(i) );

    switch type								% plot differently according to type
     case 'Points'							% only the fit points
      plot(ax, D1{i}, D2{i},	'*',				...
			'Color',	nuances(i,:),		...
			'MarkerSize',	0.6*self.MarkerSize	);

     case 'Lines'							% only the convex hull
      K	= convhull(D1{i},D2{i});					% calculate the convex hull
      plot(ax, D1{i}(K), D2{i}(K),	'-',			...
			'Color',	nuances(i,:),		...
			'LineWidth',	self.LineWidth		);

     case 'Fill'							% only the area inside the convex hull
      K	= convhull(D1{i},D2{i});					% calculate the convex hull
      p = patch( D1{i}(K), D2{i}(K), nuances(i,:) );			% plot filled area of convex hull	
      set(p,'FaceAlpha',.7,'EdgeAlpha',.5);				% set transparency

     otherwise
      error('Plot type not understood!');
    end

   end

   CC	= ( mean(D1_a .* D2_a) / ( mean(D1_a) * mean(D2_a) )  ) - 1;

   text('Units','normalized','Position',[0.67 0.05],		...
	'FontSize',	self.FontSize,				... 
	'FontName',	self.FontName,				...
	'FontWeight',	self.FontWeight,				...
	'String',['g_1(\',gamma1,',\',gamma2,')',	...
		'=',num2str(CC,3)]);					% show cross-correlation

  end	% correlate gamma

  %============================================================================
  % LOG LIN TOGGLE
  %============================================================================
  function loglin_toggle ( obj, axes)
  % convert a lin_log plot into a log_lin plot, with reasonable limits for axes

   try ax	= axes;		catch ax = gca;		end		% try to select the axes

   old_scale	= [ get(ax,'yscale') get(ax,'xscale') ];		% the old scale of both axes

   % behaviour depends on the actual situation
   switch old_scale
    case 'linearlog'
     set(ax,'yscale','log','xscale','lin');				
     axis(ax,[ 0 1 1e-2 1 ]);						% the zoom goes up to 1 ms
     
    case 'loglinear'
     set(ax,'yscale','lin','xscale','log');
     axis(ax,'auto' );							% here the autozoom works

    otherwise
     error('This function only converts loglin into linlog and vice versa!');
   end

  end	% end of function

  %==========================================================================
  % PLOT (OVERLOADED METHOD)
  %==========================================================================
  function plot ( self, name, varargin )
  % function for plotting every kind of property quickly
  % first we look in the Data struct. Otherwise, the property is searched for directly
  % Accepted optional arguments:
  % - Independent:	name of the independent
  % - Average:		averaging over some kind of parameter?
  % - Parameter:	what is the parameter ( in case of parametric plots)
  % - Color:		what color nuances to use
  %
  % N.B.: this function can be overloaded by subclass methods, and should be considered
  % a fallback method

   optargs	= varargin;								% get the optional arguments

   switch name										% act differently according to the property

    case 'G'										% correlogramms
     self.plot_correlations ( optargs{:} );

    case {'LD_D' 'LD_Gamma' 'Laplace'}							% laplace correlogramms
     self.plot_correlations ( 'Type', 'Laplace', optargs{:} );

    case {'Fit_D1' 'Fit_De' 'Fit_Ds'}

     name	= regexprep(name,'Fit_','');						% cut the part 'Fit_' from the name
     [ ax, x, y, color ] = self.prepare_plot( name, optargs{:} );			% prepare the plot TODO: allow x-axis choice
     self.make_plot ( ax, x, y, color, optargs{:} );					% plot the data

     options	= struct(optargs{:});
     try independent = options.Independent;	catch independent = 'C'; end
     q	= self.D0;									% select the right intercept
     m	= q * self.(['k' independent]);							% select the right slope

     self.plot_affine_fit ( x, q, m );							% plot the fit

    otherwise										% use fallback methods for other props
     [ ax, x, y, color ] = self.prepare_plot ( name, optargs{:} );			% prepare the plot ( get_units is overloaded!)
     self.make_plot ( ax, x, y, color, optargs{:} );					% make the plot

   end

  end % plot

  %==========================================================================
  % GET AXES UNITS
  %==========================================================================
  function [ xunit yunit ] = get_units( self, independent, dependent )
  % this function eats the axes names and outputs the units for labels
  % NB: this method can be overloaded by subclasses

   switch independent
    case 'Phi'
     xunit	= '';									% volume fraction has no units
    otherwise
     xunit	= self.(['Unit_',independent]);						% try to get the units of x axis...
   end

   try		yunit	= self.(['Unit_',dependent]);					% try to set the units for y axis...
   catch
    if strncmpi(dependent,'Gamma',5)	yunit = self.Unit_Gamma;			% ...otherwise, look whether it is a gamma...
    elseif strncmpi(dependent,'D',1)	yunit = self.Unit_D;				% ...or a diffusion constant
    end
   end

  end	% get_units

  %==========================================================================
  % FIT DIFFUSION LINEARLY
  %==========================================================================
  function fit_D_linear( self, Dname, varargin )
  % this function takes a diffusion constant and fits it linearly as a function
  % of concentration or volume fraction

   options	= struct(varargin{:});							% get optional arguments

   independent	= 'C';									% C is the indepenent: Phi values are calculated later

   try n = options.N;	catch n = min(4,length(self.(independent))); 		end	% default number of points: 4 OR total number of points

   x		= self.Data.(independent)';						% x values
   y		= self.(Dname)';							% y values
   dy		= self.(['d' Dname])';							% y errors

   % filter the data to include only the low-C datapoints
   index	= ( x <= self.(independent)(n) );
   x		= x(index);
   y		= y(index);
   dy		= dy(index);

   weights	= 1 ./ ( dy .^2 );							% weights for the fit

%   fit_function	= 'D0 + D0k * x';								% fit function
   coefficients	= {'D0'	'D0k'		};						% coefficients
   fit_expr	= {'1'	independent	};						% one MUST use this syntax with linear models

   fit_options	= fitoptions(	'Method',	'LinearLeastSquares',	...
				'Weights',	weights			);		% fit options

   fit_type	= fittype(fit_expr,	'independent',	independent,	...
 				      	'coefficients',	coefficients,	...
					'options',	fit_options	);		% fit type
 
   [ cf gof ] = fit( x, y, fit_type );							% perform numerical fit
   confidence = confint(cf,0.95);
 
   % get fit result
   cout		= coeffvalues (cf); 
   dcout	=  0.5*(confidence(2,:)-confidence(1,:));

   D0	= cout(1);
   dD0	= dcout(1);
   D0k	= cout(2);
   dD0k	= dcout(2);
   kC	= D0k / D0;
   dkC	= kC * sqrt( ( dD0/D0 ) ^2 + ( dD0k /D0k ) ^2 );
   kPhi	= kC / LIT.(self.Sample).v0;
   dkPhi= dkC / LIT.(self.Sample).v0;

   self.check_add_prop(	'D0',			D0,	...
			'dD0',			dD0,	...
			'kC',			kC,	...
			'dkC',			dkC,	...
			'kPhi',			kPhi,	...
			'dkPhi',		dkPhi,	...
			'Unit_kC',		'l/g'	);	% add props to the class

  end	% fit_D_linear

 end	% end of public methods
 
 %============================================================================
 % STATIC METHODS
 %============================================================================
 methods ( Static )

  %============================================================================
  % FIT DISCRETE DECAYS
  %============================================================================
  [ coeffnames coeffval dcoeffval ] = fit_discrete ( t, g, dg, method, q, varargin)

  %============================================================================
  % INVERSE LAPLACE TRANSFORM (CONTIN)
  %============================================================================
  [ LP_Gamma LP_D LP_Dist ] = invert_laplace ( t, g, q, alpha, cycles )

  %============================================================================
  % FILTER REPETITIONS
  %============================================================================
  function [ tf gf cf qf anglesf ] = filter_repetitions ( t, g, c, q, angles )

   % filter the data to avoid fitting repetitions (too long)
   tf		= {};
   gf		= {};
   cf		= [];
   qf		= [];
   anglesf	= [];

   for l = 1 : length(t)
    isc	= ismember(cf,c(l));								% elements with the same C
    isq	= ismember(qf,q(l));								% elements with the same Q
    if isempty(cf) | ~( sum(isc & isq) )						% if no sample with the same C and Q exists...
     tf	= { tf{:}	t{l}	};							% ... add props to the filtered data
     gf	= { gf{:}	g{l}	};
     cf	= [ cf		c(l)	];
     qf	= [ qf		q(l)	];
     anglesf	= [ anglesf	angles(l)	];
    end
   end

  end	% filter_repetitions

 end	% end of static methods
end	% end of class
