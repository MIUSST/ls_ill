classdef ALV
% This class describes the features of the ALV light scattering instrument at ILL

 properties ( Constant )

  Goniometer	= 'ALV-CGS3';
  Correlator	= 'ALV-7004/FAST';
  Lambda	= 6328;
  Unit_Lambda	= 'A';
  Angles	= struct(	'Min',	12,	...
				'Max',	150	);
  T		= struct(	'Min',	-Constants.T0,	...	% Minimal T = 0°C
				'Max',	-Constants.T0+45	);	% Maximal T = 45°C

 end

 methods ( Static )

  Point	= read_static_file 	( path )
  Point	= read_dynamic_file	( path )
  Point	= invoke_read_dynamic_file_fast( path )
  Point = read_static(path_standard, path_solvent, path_file, protein_conc, dn_over_dc, start_index, end_index)
  [t gt dgt Angle temperature] = read_dynamic_file_fast( path );
  s = read_tol_file(path_of_tol_file)
  [angle count_rate1 count_rate2 I_mon temperature] = read_static_from_autosave(path_of_autosave_file)
  
 end

end
