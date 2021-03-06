/*
------------------------------------------------------------------------------

 Marcus Hennig
 hennig@ill.fr
 
 Start:		11/20/2008
 Update:	11/24/2008

 Description: Contin is an algorithm that performs an inversion of the integral 
 kernel operation on a function. The problem is to determine the spectral funtion 
 s(tau) for a given function y for a specific kernel K
 
 y(t) = integral(K(t,tau)s(tau), {tau,-inf, inf})
 
 The algorithm based on the following idea: quadrature of the integral 
 leads to 
 
 y(k) = sum(c(j) * K(k, j) * s(j), {j})
 
 where c(j) are the weights due to the quadrature of the integral
 
 Minimizing 
 
 sum(w(k) * |y(k) - sum(c(j)*K(k, j)*s(j), {j})|^2, {k}) + alpha^2 * sum(|s"(j)|^2, {j})
 
 in respect to s gives us the spectral function s.
 The last term of the above expression is the so-called regularizer 
 and includes the second derivative of the s. By choosing the appropriate alpha the 
 smoothness of s can be fine-tuned. Small alpha causes a spiky s whereas a large alpha 
 causes a quite smooth s.  

 	
------------------------------------------------------------------------------
*/

#ifdef MATLAB_MEX_FILE
	#include "math.h"
	#include "mex.h" 
#endif

#include <stdio.h>
#include <math.h>
#include <ool/ool_conmin.h>
#include <gsl/gsl_matrix.h>
        
/*
------------------------------------------------------------------------------

 square function 

------------------------------------------------------------------------------
*/

inline 
double sqr(double x)
{
	return x * x;
}

/*
------------------------------------------------------------------------------

 generates a multi-exponential (t, y) with
 
 y(t) = sum(I(n)*exp(-t/tau(n)), {n,0, N})

------------------------------------------------------------------------------
*/

void example(gsl_vector* intensity, 
			 gsl_vector* tau,
			 gsl_vector* t,
			 gsl_vector* y,
			 gsl_vector* var,
			 int n, 
			 double t0,
			 double tend)
{
	double dt = (tend - t0) / (n - 1);
	int i, k;
	double yi, ti;
	for (i = 0;  i < n; i++)
	{
		ti = t0 + dt * i;
		
		yi = 0;
		for (k = 0; k < tau->size; k++)
			yi += gsl_vector_get(intensity, k) * exp(- ti / gsl_vector_get(tau, k));
			
		gsl_vector_set(t, i, ti);
		gsl_vector_set(y, i, yi);
		gsl_vector_set(var, i, 1);
	}
}

/*
------------------------------------------------------------------------------

 parameter struct for optimazation routine 

------------------------------------------------------------------------------
*/

typedef struct 
{
	gsl_matrix* K;		/* matrix for integration kernel */
	gsl_vector* y;		/* y-axis of observed data */
	gsl_vector* t;		/* t-axis of observed data */
	gsl_vector* tau;	/* tau-axis for time constants */
	gsl_vector* w;		/* weights for euclidian norm */
	gsl_vector* c;		/* weights due to numerical intergration */
	double alpha;		/* strenght of regularizer */
	
} parameter;

/*
------------------------------------------------------------------------------

 allocate memory for parameter-struct entries and intialize 
 kernel K, tau, ... etc

------------------------------------------------------------------------------
*/

parameter* parameter_alloc(gsl_vector* t, 
						    gsl_vector* y,
						    gsl_vector* var,
						    double alpha,
						    double tau0,
						    double tau1,
						    int m,
							int kernelType)
{
	parameter* p = malloc(sizeof(parameter));
	int n = t->size;
	
	p -> K   = gsl_matrix_alloc( n, m );
	p -> w   = gsl_vector_alloc( n );
	p -> c   = gsl_vector_alloc( m );
	p -> y   = gsl_vector_alloc( n );
	p -> tau = gsl_vector_alloc( m );
	p -> t = gsl_vector_alloc( n );
	
	p -> alpha = alpha;
	
	double dtau = (tau1 - tau0) / (m - 1);
	int i, j;
	
	gsl_vector_memcpy(p->y, y);
	gsl_vector_memcpy(p->t, t);
	
	for (j = 0; j < m; j++)
		gsl_vector_set(p->tau, j, tau0 + j * dtau);
	
	for (i = 0; i < n; i++)
	{
		for (j = 0; j < m; j++)
		{
			if (kernelType == 0)
			{
				// multi-exponential
				gsl_matrix_set(p->K, i, j, exp(-gsl_vector_get(p->t,i) / gsl_vector_get(p->tau, j)));
			}
			else if (kernelType == 1)
			{
				// multi-lorentzian
				gsl_matrix_set(p->K, i, j, M_1_PI *  gsl_vector_get(p->tau, j) / (sqr(gsl_vector_get(p->t, i)) + sqr(gsl_vector_get(p->tau, j))));
				
			}
		}
		gsl_vector_set(p->w, i, 1.0 / gsl_vector_get(var, i));
	}		
	
	/* 
	 weights for quadrature of integral, trapezoidal rule 
	*/
	for (j = 0; j < m; j++)
	{
		if(j == 0 || j == m - 1)
			gsl_vector_set(p->c, j, 0.5 * dtau);
		else
			gsl_vector_set(p->c, j, dtau);
	}
	return p;
}

/*
------------------------------------------------------------------------------

 release allocated memory for parameter struct

------------------------------------------------------------------------------
*/

void parameter_free(parameter* p)
{
	if ( p->K ) gsl_matrix_free( p->K );
	if ( p->w ) gsl_vector_free( p->w );
	if ( p->c ) gsl_vector_free( p->c );
	if ( p->y ) gsl_vector_free( p->y );
	if ( p->t ) gsl_vector_free( p->t );
	if ( p->tau ) gsl_vector_free( p->tau );
	free(p);
}

/*
------------------------------------------------------------------------------

 discrete 2nd derivative of g

------------------------------------------------------------------------------
*/
 
void diff2(const gsl_vector *x, gsl_vector * ddg)
{
	int i;
	for (i = 1; i < ddg->size - 1; i++)
		gsl_vector_set(ddg, i, gsl_vector_get(x, i - 1) - 2 * gsl_vector_get(x, i) + gsl_vector_get(x, i + 1));
		
	gsl_vector_set(ddg, 0, - 2 * gsl_vector_get(x, 0) + gsl_vector_get(x, 1));
	gsl_vector_set(ddg,  ddg->size - 1, gsl_vector_get(x, ddg->size - 2) - 2 * gsl_vector_get(x, ddg->size - 1));
}

/*
------------------------------------------------------------------------------
 z = A*g + b 
 f(g, b) = |y - z|^2 + a^2*|D2g|^2
 x = (g, b)
------------------------------------------------------------------------------
*/

double fun(const gsl_vector* x, void* params)
{
	parameter* p = (parameter*) params;
	
	int n = p->y->size;
	int m = x->size - 1;
		
	gsl_vector* d2g = gsl_vector_alloc(m);
	
	/* x= (g,b), diff2 acts only on the g-part of x*/
	diff2(x, d2g);
	
	/*
	 integral operation, A is the kernel discretization
	 and c are the weights of the quadrature formula
	*/
	
	int i, j;
	double var = 0;
	double reg = 0;
	double z;
	double b = gsl_vector_get(x, m);
	
	for (i = 0; i < n; i++)
	{
		z = b;
		for (j = 0; j < m ; j++)
			z += gsl_vector_get(p->c, j) * gsl_matrix_get(p->K, i, j) * gsl_vector_get(x, j);
		var += gsl_vector_get(p->w, i) * sqr(gsl_vector_get(p->y, i) - z );
	}
	
	/* regularizer, second derivative of g*/
	for (i = 0; i < m; i++)
		reg += sqr(gsl_vector_get(d2g, i));
	
	/* 
	 free memory
	*/
	gsl_vector_free( d2g  );
	
	return var + p->alpha * p->alpha * reg;
}

/*
------------------------------------------------------------------------------

 gradient of f(g, b) = |y - A*g+b|^2 + a^2*|Pg|^2
 x = (g, b)

------------------------------------------------------------------------------
*/

void fun_df(const gsl_vector *x, void* params, gsl_vector *grad)
{
	parameter* p = (parameter*) params;
	
	int n = p->y->size;
	int m = x->size - 1;
		
	gsl_vector* z   = gsl_vector_alloc( n );
	gsl_vector* d2g = gsl_vector_alloc( m );
	gsl_vector* d4g = gsl_vector_alloc( m );
	
	diff2(x,   d2g);
	diff2(d2g, d4g);
	
	int i, j;
	double zi;
	double b = gsl_vector_get(x, m);
	
	for (i = 0; i < n; i++)
	{
		zi = b;
		for (j = 0; j < m; j++)
			zi += gsl_vector_get(p->c, j) * gsl_matrix_get(p->K, i, j) * gsl_vector_get(x, j);
		gsl_vector_set(z, i, zi);
	}
	
	double gradi;
	for (i = 0; i < m; i++)
	{
		gradi = 0;
		for (j = 0; j < n; j++)
			gradi += 2 * gsl_vector_get(p->w, j) * (gsl_vector_get(z, j) - gsl_vector_get(p->y, j)) * gsl_vector_get(p->c, i) * gsl_matrix_get(p->K, j, i);	
			
		gsl_vector_set(grad, i, gradi + 2 * p->alpha * p->alpha * gsl_vector_get(d4g, i));
	}
	
	double gradm = 0;
	for (j = 0; j < n; j++)
		gradm += 2 * gsl_vector_get(p->w, j) * (gsl_vector_get(z, j) - gsl_vector_get(p->y, j));
	gsl_vector_set(grad, m, gradm);

	gsl_vector_free( z   );
	gsl_vector_free( d2g );
	gsl_vector_free( d4g );
}

/*
------------------------------------------------------------------------------

 gradient and function value together 

------------------------------------------------------------------------------
*/

void fun_fdf(	const gsl_vector *x, void* params,
				double *f, gsl_vector *grad )
{
	parameter* p = (parameter*) params;
	
	int n = p->y->size;
	int m = x->size - 1;
		
	gsl_vector* z   = gsl_vector_alloc( n );
	gsl_vector* d2g = gsl_vector_alloc( m );
	gsl_vector* d4g = gsl_vector_alloc( m );

	diff2(x,   d2g);
	diff2(d2g, d4g);
		
	/*
	 integral operation, A is the kernel discretization
	 and c are the weights of the quadrature formula
	*/
	
	int i, j;
	double zi;
	double b = gsl_vector_get(x, m);
	
	for (i = 0; i < n; i++)
	{
		zi = b;
		for (j = 0; j < m; j++)
			zi += gsl_vector_get(p->c, j) * gsl_matrix_get(p->K, i, j) * gsl_vector_get(x, j);
		gsl_vector_set(z, i, zi);
	}
	
	double var = 0;
	for (i = 0; i < n; i++)
		var += gsl_vector_get(p->w, i) * sqr(gsl_vector_get(p->y, i) - gsl_vector_get(z, i));
	
	/* determine the second derivative of g */
	
	
	double reg = 0;
	for (i = 0; i < m; i++)
		reg += sqr(gsl_vector_get(d2g, i));
	
	*f = var + p->alpha * p->alpha * reg;
	
	double gradi;
	for (i = 0; i < m; i++)
	{
		gradi = 0;
		for (j = 0; j < n; j++)
			gradi += 2 * gsl_vector_get(p->w, j) * (gsl_vector_get(z, j) - gsl_vector_get(p->y, j)) * gsl_vector_get(p->c, i) * gsl_matrix_get(p->K, j, i);	
			
		gsl_vector_set(grad, i, gradi + 2 * p->alpha * p->alpha * gsl_vector_get(d4g, i));
	}
	
	double gradm = 0;
	for (j = 0; j < n; j++)
		gradm += 2 * gsl_vector_get(p->w, j) * (gsl_vector_get(z, j) - gsl_vector_get(p->y, j));
	gsl_vector_set(grad, m, gradm);

	/* 
	 free memory
	*/
	
	gsl_vector_free( z );  
	gsl_vector_free( d2g  );
	gsl_vector_free( d4g  );
}

/*
------------------------------------------------------------------------------

 product of hessian matrix with arbitrary vector v

------------------------------------------------------------------------------
*/

void fun_Hv( const gsl_vector *x, void *params,
			 const gsl_vector *v, gsl_vector *hv )
{
	parameter* p = (parameter*) params;
	
	int n = p->y->size;
	int m = x->size - 1;
	
	gsl_vector* d2v = gsl_vector_alloc(m);
	gsl_vector* d4v = gsl_vector_alloc(m);
	
	diff2(v,   d2v);
	diff2(d2v, d4v);
	
	double H1ij;
	double H2i;
	double H3 = 0;
	int i, j, k;
	for (k = 0; k < n; k++)
		H3 += 2 * gsl_vector_get(p->w, k);
	
	double hvi;
	double hvm = H3 * gsl_vector_get(v, m);
	for (i = 0; i < m; i++)
	{
		H2i = 0;
		for (k = 0; k < n; k++)
			H2i += 2 * gsl_vector_get(p->w, k) * gsl_vector_get(p->c, i) * gsl_matrix_get(p->K, k, i);
		
		hvm += H2i * gsl_vector_get(v, i);
		
		hvi = H2i * gsl_vector_get(v, m);
		for (j = 0; j < m; j++)
		{
			H1ij = 0;
			for (k = 0; k < n; k++)
				H1ij += 2*gsl_vector_get(p->w, k) * gsl_vector_get(p->c, i) * gsl_matrix_get(p->K, k, i) * gsl_vector_get(p->c, j) * gsl_matrix_get(p->K, k, j);
			
			hvi += H1ij * gsl_vector_get(v, j);
		}
		gsl_vector_set(hv, i, hvi + gsl_vector_get(d4v, i));
	}
	gsl_vector_set(hv, m, hvm);
	
	gsl_vector_free( d2v );
	gsl_vector_free( d4v );
}

/*
------------------------------------------------------------------------------

 displays first two arguements during optimization

------------------------------------------------------------------------------
*/

void iteration_echo( ool_conmin_minimizer *M )
{
	double f = M->f;	size_t ii, nn;

	nn = 2;

	printf( "f( " );
	for( ii = 0; ii < 3; ii++ )
		printf( "%+6.3e, ", gsl_vector_get( M->x, ii ) );
	printf( "... ) = %+6.3e\n", f );

}

/*
------------------------------------------------------------------------------

 save function to text file

------------------------------------------------------------------------------
*/

void saveData(gsl_vector* x, gsl_vector* y, char* fileName)
{
	FILE* fileID = fopen(fileName, "w");
	
	int i;
	for (i = 0; i < x->size; i++)
		fprintf(fileID, "%lf\t%lf\n", gsl_vector_get(x, i), 
									  gsl_vector_get(y, i));
									  
	fclose(fileID);
}

/*
------------------------------------------------------------------------------

 Contin Algorithm 
 For given data (t,y) the spectral function (tau, s) is determined such that 
 y(t) = integral(K(t,s)*g(s) + b, {s, s0, s1})
 

------------------------------------------------------------------------------
*/

int contin( parameter*  p, 
			gsl_vector* s,
			gsl_vector* g,
			double*     b)
{

	/*
	 start minimization to find spectral function 
	*/
	int m = g->size;
	size_t nn   =  m + 1;
	size_t nmax = 100000;
	size_t ii;
	int status;
	
	/*
	 select which optimization algorithm will be used, the SPG algorithm, 
	 in this example
	*/
	
	const ool_conmin_minimizer_type *T = ool_conmin_minimizer_spg;
	ool_conmin_spg_parameters P;

	/*
	 declare variables to hold the objective function, the constraints, 
	 the minimizer method, and the initial iterate, respectively
	*/
	
	ool_conmin_function   F;
	ool_conmin_constraint C;
	ool_conmin_minimizer *M;
	gsl_vector *X;
	
	/*
	 the function structure is filled in with the number of variables, 
	 pointers to routines to evaluate the objective function and its 
	 derivatives, and a pointer to the function parameters */
	 
	F.n   = nn;
	F.f   = &fun;
	F.df  = &fun_df;
	F.fdf = &fun_fdf;
	F.Hv  = &fun_Hv;
	F.params = (void *) p;
	
	/*
	 the lower and upper bounds are set to -3 and 3, respectively, 
	 to all variables.
	*/
	
	C.n = nn;
	C.L = gsl_vector_alloc( C.n );
	C.U = gsl_vector_alloc( C.n );

	gsl_vector_set_all( C.L,    0.0 );
	gsl_vector_set_all( C.U,  100.0 );
	
	/* 
	 these two lines allocate and set the initial iterate 
	*/
	
	X = gsl_vector_alloc( nn );
	gsl_vector_set_all( X, 1.0 );
	/* we better set the background parameter to 0 */
	gsl_vector_set(X, X->size - 1, 0);
	
	
	/*
	 allocate the necessary memory for an instance of the
	 optimization algorithm of type T. Initializes its parameters 
	 to default values. If the you want to tune the method by 
	 changing the default values to some parameter this should 
	 be done 
	*/
	
	M = ool_conmin_minimizer_alloc( T, nn );
	ool_conmin_parameters_default( T, (void*)(&P) );
	
	/*
	 everything is put together. It states that this instance of 
	 the method M is responsible for minimizing function F, subject 
	 to constraints C, starting from point X, with parameters P. 
	*/
	
	ool_conmin_minimizer_set( M, &F, &C, X, (void*)(&P) );
	
	/*
	 The iteration counter is initialized and some information
	 concerning the initial point is displayed. The iteration 
	 loop is repeated while the maximum number of iterations was not reached
	 and the status is OOL_CONTINUE. Further conditions could also be 
	 considered (maximum number of function/gradient evaluation for example).
	 The iteration counter is incremented and one single iteration of the 
	 method is performed. Current iterate is checked for optimality. 
	 Finally some information concerning this iteration is displayed. 
	*/
	
	ii = 0;
	status = OOL_CONTINUE;
	
	/*printf( "%4i : ", ii );
		iteration_echo ( M );
	printf( "\n" );			*/

	while( ii < nmax && status == OOL_CONTINUE )
	{
		ii++;
		ool_conmin_minimizer_iterate( M );
		status = ool_conmin_is_optimal( M );

	/*	if( ii % 100 == 0 )
		{
			printf( "%4i ", ii );
			iteration_echo( M );
		}					*/
	}
	
	if(status == OOL_SUCCESS)
		printf("Convergence in %i iterations", ii);
	else
		printf("Stopped with %i iterations", ii);

/*	printf( "\nvariables................: %6i"
			"\nfunction evaluations.....: %6i"
			"\ngradient evaluations.....: %6i"
			"\nfunction value...........: % .6e"
			"\nprojected gradient norm..: % .6e\n",
			nn,
			ool_conmin_minimizer_fcount( M ),
			ool_conmin_minimizer_gcount( M ),
			ool_conmin_minimizer_minimum( M ),
			ool_conmin_minimizer_size( M ));	*/

	gsl_vector_memcpy(s, p->tau);
	int i;
	for (i = 0; i < g->size; i++)
		gsl_vector_set(g, i, gsl_vector_get(M->x, i));
	*b =  gsl_vector_get(M->x, m);
	
	gsl_vector_free( C.L );
	gsl_vector_free( C.U );
	gsl_vector_free( X );

	ool_conmin_minimizer_free( M );
	
	return OOL_SUCCESS;
	
}

/*
------------------------------------------------------------------------------

 Matlab wrapper
 
 to produce a matlab executable we have to compile this file
 with: mex -lool -lgsl -lgslcblas -lm contin.c
 
 Within in the matlab shell we can then invoke the algorithm by 
 [tau, s] = contin(t, y, dy, tau0, tau1, m, alpha)
 
 (t, y, dy) observed data (should be a multi-exponential)
 (tau, s) is the spectral function unveiling the relaxation times
 of the observed data. 
 
 y(t) = integral(exp(-t/tau)*s(tau),{tau, tau0, tau1})
 
 alpha is the magnitude of the regularizer
 m is the number of equidistant intervals for the quadratization
 of the integral.
 

------------------------------------------------------------------------------
*/

#ifdef MATLAB_MEX_FILE

void mexFunction(int nlhs, 
				 mxArray *plhs[], 
				 int nrhs, 
				 const mxArray *prhs[])
{
	if(nrhs =! 8 || nlhs!= 3)
	{
		 mexErrMsgTxt("Not enough input arguments\n\n"
				"[s, g, b] = contin(t, y, var, s0, s1, m, alpha, kernel)\n"
				"\ncontin minimizes ||y(t) - (∫K(t,s)g(s)ds + b)||\n"
				"t\ttime-axis of data\n"
				"y\ty-axis of data\n"
				"var\tvariance of y\n"
				"s0\tsmallest possible time constant\n"
				"s1\tlargest possible time constant\n"
				"m\tnumber of equidistant intervals for quadratization\n"
				"alpha\tstrength of regularizer\n"
				"kernel\t0: Multi-exponential, 1: Multi-lorentzian\n");
		return;
	}
	
	/* wrapper for matlab */
	int n = mxGetN(prhs[0]) * mxGetM(prhs[0]);

	gsl_vector* t     = gsl_vector_alloc(n);	
	gsl_vector* y     = gsl_vector_alloc(n);
	gsl_vector* var   = gsl_vector_alloc(n);
	
	double* ptr_t     = mxGetPr(prhs[0]);
	double* ptr_y     = mxGetPr(prhs[1]);
	double* ptr_var = mxGetPr(prhs[2]);
	
	int i;
	for (i = 0; i < n; i++)
	{
		gsl_vector_set(t,    i, ptr_t[i]);
		gsl_vector_set(y,    i, ptr_y[i]);
		gsl_vector_set(var , i, ptr_var[i]);
	}	
	
	double s0      = mxGetScalar(prhs[3]);
	double s1      = mxGetScalar(prhs[4]);
	int m          = (int) mxGetScalar(prhs[5]);
	double alpha   = mxGetScalar(prhs[6]);
	int kernelType = (int) mxGetScalar(prhs[7]);
	
	parameter* p = parameter_alloc(t, y, var, alpha, s0, s1, m, kernelType);
	
	gsl_vector* s = gsl_vector_alloc(m);
	gsl_vector* g = gsl_vector_alloc(m);
	
	double b;	// background
	contin(p, s, g, &b);
	
	parameter_free(p);
	
	//Allocate memory and assign output pointer
	plhs[0] = mxCreateDoubleMatrix(m, 1, mxREAL); //mxReal is our data-type
	plhs[1] = mxCreateDoubleMatrix(m, 1, mxREAL); //mxReal is our data-type
	plhs[2] = mxCreateDoubleScalar(b);
	
	//Get a pointer to the data space in our newly allocated memory

	double* ptr_s = mxGetPr(plhs[0]);
	double* ptr_g = mxGetPr(plhs[1]);

	//Copy matrix while multiplying each point by 2
	
	for(i = 0; i < m; i++)
	{
		ptr_s[i] = gsl_vector_get(s, i);
		ptr_g[i]   = gsl_vector_get(g, i);
	}
	
	gsl_vector_free(t);
	gsl_vector_free(y);
	gsl_vector_free(var);
	gsl_vector_free(g);
	gsl_vector_free(s);
}
#endif

#ifndef MATLAB_MEX_FILE
int main( void )
{
	/*
	 generate a multi-exponential time-signal
	*/
	
	int n = 1000; /* number of sample points */
	int m = 10; /* number of time constants */
		
	gsl_vector* t     = gsl_vector_alloc(n);
	gsl_vector* y     = gsl_vector_alloc(n);
	gsl_vector* sigma = gsl_vector_alloc(n);
	
	gsl_vector* intensity = gsl_vector_alloc(2);
	gsl_vector* r       = gsl_vector_alloc(2);

	gsl_vector_set(r, 0, 0.4); 
	gsl_vector_set(r, 1, 1.6); 
	gsl_vector_set(intensity, 0, 1.0);	
	gsl_vector_set(intensity, 1, 2.0);
	
	example(intensity, r, t, y, sigma, n, 0.0, 4.0);
	/*
	 compute parameters for the inversion problem	
	*/
	
	parameter* p = parameter_alloc(t, y, sigma, 0.01, 0.1, 4.0, m , 0);
	
	/*
	release used memory
	*/
	
	gsl_vector_free( t ); 	
	gsl_vector_free( y ); 
	gsl_vector_free( sigma );
	gsl_vector_free( intensity );
	gsl_vector_free( r );
	
	/* 
	 start contin minimization 
	*/
	gsl_vector* g = gsl_vector_alloc(m);
	gsl_vector* s = gsl_vector_alloc(m);
	double b;
	
	gsl_vector* X  = gsl_vector_alloc(m + 1);
	gsl_vector* G  = gsl_vector_alloc(m + 1);
	
	gsl_vector_set_all(X, 1.0);
	
	double fh, f = fun(X, p);
	fun_df(X, p, G);
	
	int i;
	double h = 1e-5;
	for (i=0; i < m + 1; i++)
	{
		gsl_vector_set(X, i, gsl_vector_get(X, i) + h);
		fh = fun(X, p);
		printf("G[%d] = (%lf, %lf)\n", i, gsl_vector_get(G, i), (fh - f) / h);
		gsl_vector_set(X, i, gsl_vector_get(X, i) - h);
	}
	
	gsl_vector_free(X);
	gsl_vector_free(G);
	contin(p, s, g, &b);
	
	saveData(p->t, p->y, "in.txt");
	saveData(s,    g, "out.txt");
	
	gsl_vector_free(g);
	gsl_vector_free(s);
	parameter_free(p);
	
	return 0;
}
#endif

