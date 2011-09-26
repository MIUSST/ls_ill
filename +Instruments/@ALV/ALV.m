classdef ALV
% This class describes the features of the ALV light scattering instrument at ILL

 properties ( Constant )

  Goniometer	= 'ALV-CGS3';
  Correlator	= 'ALV-7004/FAST';
  Lambda	= 6328;
  Unit_Lambda	= 'A';
  Angles	= struct(	'Min',	12,	...
				'Max',	150	);
  T		= struct(	'Min',	LIT.Constants.T0,	...	% Minimal T = 0°C
				'Max',	LIT.Constants.T0+45	);	% Maximal T = 45°C

 end

 methods ( Static )

  Point	= read_static_file 	( path )
  Point	= read_dynamic_file	( path )

 end

end
