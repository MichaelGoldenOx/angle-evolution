/* 
 * File:   maintpd.cpp
 * Author: Eduardo
 *
 * Created on November 20, 2015, 11:38 PM
 */

#include <stdio.h>
#include <cstdlib>
#include <armadillo>
#include <iostream>

using namespace std;

// Declaration
arma::vec DensStatMWNOU(arma::mat x, arma::vec mu, arma::vec alpha, arma::vec sigma, int maxK, double etrunc);

// Main
int main(int argc, char** argv) {
  
  /*
   *  Argument codification in argv: 
   *  mu1 mu2 alpha1 alpha2 alpha3 sigma1 sigma2 maxK etrunc x
   *  (where x is the N x 2 matrix of evaluation points stored by rows as a vector)
   */
  
  // Set parameters
  arma::vec mu(2); 
  mu(0) = atof(argv[1]); mu(1) = atof(argv[2]);
  arma::vec alpha(3); 
  alpha(0) = atof(argv[3]); alpha(1) = atof(argv[4]); alpha(2) = atof(argv[5]);
  arma::vec sigma(2); 
  sigma(0) = atof(argv[6]); sigma(1) = atof(argv[7]);
  int maxK = atoi(argv[8]);
  double etrunc = atof(argv[9]);
  
  // Read matrix
  int count = 10;
  int n_rows = (argc - count)/2;
  arma::mat x(n_rows, 2);
  for (int i = 0; i < n_rows; i++){
    for (int j = 0; j < 2; j++){
      x(i, j) = atof(argv[count]);
      count++;
    }
  }

  // Call function
  arma::vec result = DensStatMWNOU(x, mu, alpha, sigma, maxK, etrunc);

  // Print result
  result.t().print();

  return 0;
    
}

// Subroutine
arma::vec DensStatMWNOU(arma::mat x, arma::vec mu, arma::vec alpha, arma::vec sigma, int maxK = 2, double etrunc = 50) {
  
  /*
  * Description: Density of the stationary distribution of a MWN-OU diffusion (with diagonal diffusion matrix)
  * 
  * Arguments:
  *
  * - x: matrix of size N x 2 containing the evaluation points. They must be in [-PI, PI) so that the truncated wrapping by 
  *      maxK windings is able to capture periodicity.
  * - mu: a vector of length 2 with the mean parameter of the MWN-OU process. The mean of the MWN stationary distribution. 
  *       It must be in [PI, PI) x [PI, PI).
  * - alpha: vector of length 3 containing the A matrix of the drift of the MWN-OU process in the following codification: 
  *        A = [alpha[0], alpha[2] * sqrt(sigma[0] / sigma[1]); alpha[2] * sqrt(sigma[1] / sigma[0]), alpha[1]]. 
  *        This enforces that A^(-1) * Sigma is symmetric. Positive definiteness is guaranteed if
  *        alpha[0] * alpha[1] > alpha[2] * alpha[2]. The function checks for it and, if violated, returns the 
  *        density from a close A^(-1) * Sigma that is positive definite.
  * - sigma: vector of length 2 containing the diagonal of Sigma, the diffusion matrix. Note that these are the *squares*
  *          (i.e. variances) of the diffusion coefficients that multiply the Wiener process.
  * - maxK: maximum number of winding number considered in the computation of the approximated transition probability density.
  * - etrunc: truncation for exponential. exp(x) with x <= -etrunc is set to zero.
  * 
  * Warning: 
  * 
  *  - A combination of small etrunc (< 30) and low maxK (<= 1) can lead to NaNs produced by 0 / 0 in the weight computation. 
  *    This is specially dangerous if sigma is large and there are values in x or x0 outside [-PI, PI).
  *    
  * Value: 
  * 
  * - dens: vector of size N containing the density evaluated at the grid x.
  * 
  * Author: Eduardo García-Portugués (egarcia@math.ku.dk) 
  * 
  */
  
  /*
  * Create basic objects
  */
  
  // Number of pairs
  int N = x.n_rows;
  
  // Create and initialize A
  double quo = sqrt(sigma(0) / sigma(1));
  arma::mat A(2, 2); 
  A(0, 0) = alpha(0); 
  A(1, 1) = alpha(1); 
  A(0, 1) = alpha(2) * quo;
  A(1, 0) = alpha(2) / quo;
  
  // Create and initialize Sigma
  arma::mat Sigma = diagmat(sigma);
  
  // Sequence of winding numbers
  const int lk = 2 * maxK + 1;
  arma::vec twokpi = arma::linspace<arma::vec>(-maxK * 2 * M_PI, maxK * 2 * M_PI, lk);
  
  // Bivariate vector (2 * K1 * PI, 2 * K2 * PI) for weighting
  arma::vec twokepivec(2);
  
  /*
  * Check for symmetry and positive definiteness of A^(-1) * Sigma
  */
  
  // Only positive definiteness can be violated with the parametrization of A
  double testalpha = alpha(0) * alpha(1) - alpha(2) * alpha(2);
  
  // Check positive definiteness 
  if(testalpha <= 0) {
    
    // Update alpha(2) such that testalpha > 0
    alpha(2) = std::signbit(alpha(2)) * sqrt(alpha(0) * alpha(1)) * 0.9999;
    
    // Reset A to a matrix with positive determinant
    A(0, 1) = alpha(2) * quo;
    A(1, 0) = alpha(2) / quo;
    
  }
  
  // Inverse of 1/2 * A^(-1) * Sigma: 2 * Sigma^(-1) * A
  arma::mat invSigmaA = 2 * diagmat(1 / diagvec(Sigma)) * A;
  
  // Log-normalizing constant for the Gaussian with covariance SigmaA
  double lognormconstSigmaA = -log(2 * M_PI) + log(det(invSigmaA)) / 2;
  
  /* 
  * Evaluation of the density reusing the code from the weights of the winding numbers
  * in logLikWnOuPairs for each data point. Here we sum all the unstandarized weights 
  * for each data point.
  */
  
  // We store the weights in a matrix to skip the null later in the computation of the tpd
  arma::mat weightswindsinitial(N, lk * lk);
  
  // Loop in the data
  for(int i = 0; i < N; i++){
    
    // Compute the factors in the exponent that do not depend on the windings
    arma::vec xmu = x.row(i).t() - mu;
    arma::vec xmuinvSigmaA = invSigmaA * xmu;
    double xmuinvSigmaAxmudivtwo = dot(xmuinvSigmaA, xmu) / 2;
    
    // Loop in the winding weight K1
    for(int wek1 = 0; wek1 < lk; wek1++){
      
      // 2 * K1 * PI
      twokepivec(0) = twokpi(wek1); 
      
      // Compute once the index
      int wekl1 = wek1 * lk;
      
      // Loop in the winding weight K2  
      for(int wek2 = 0; wek2 < lk; wek2++){
        
        // 2 * K2 * PI
        twokepivec(1) = twokpi(wek2);
        
        // Decomposition of the exponent
        double exponent = xmuinvSigmaAxmudivtwo + dot(xmuinvSigmaA, twokepivec) + dot(invSigmaA * twokepivec, twokepivec) / 2 - lognormconstSigmaA;
        
        // Truncate the negative exponential
        if(exponent > etrunc){
          
          weightswindsinitial(i, wek1 * lk + wek2) = 0;
          
        }else{
          
          weightswindsinitial(i, wekl1 + wek2) = exp(-exponent);
          
        }
        
      }
      
    }
    
  }
  
  // The density is the sum of the weights
  arma::vec dens = sum(weightswindsinitial, 1);
  
  return dens;
  
}

