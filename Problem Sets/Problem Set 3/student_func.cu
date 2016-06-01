/* Udacity Homework 3
   HDR Tone-mapping

  Background HDR
  ==============

  A High Dynamic Range (HDR) image contains a wider variation of intensity
  and color than is allowed by the RGB format with 1 byte per channel that we
  have used in the previous assignment.  

  To store this extra information we use single precision floating point for
  each channel.  This allows for an extremely wide range of intensity values.

  In the image for this assignment, the inside of church with light coming in
  through stained glass windows, the raw input floating point values for the
  channels range from 0 to 275.  But the mean is .41 and 98% of the values are
  less than 3!  This means that certain areas (the windows) are extremely bright
  compared to everywhere else.  If we linearly map this [0-275] range into the
  [0-255] range that we have been using then most values will be mapped to zero!
  The only thing we will be able to see are the very brightest areas - the
  windows - everything else will appear pitch black.

  The problem is that although we have cameras capable of recording the wide
  range of intensity that exists in the real world our monitors are not capable
  of displaying them.  Our eyes are also quite capable of observing a much wider
  range of intensities than our image formats / monitors are capable of
  displaying.

  Tone-mapping is a process that transforms the intensities in the image so that
  the brightest values aren't nearly so far away from the mean.  That way when
  we transform the values into [0-255] we can actually see the entire image.
  There are many ways to perform this process and it is as much an art as a
  science - there is no single "right" answer.  In this homework we will
  implement one possible technique.

  Background Chrominance-Luminance
  ================================

  The RGB space that we have been using to represent images can be thought of as
  one possible set of axes spanning a three dimensional space of color.  We
  sometimes choose other axes to represent this space because they make certain
  operations more convenient.

  Another possible way of representing a color image is to separate the color
  information (chromaticity) from the brightness information.  There are
  multiple different methods for doing this - a common one during the analog
  television days was known as Chrominance-Luminance or YUV.

  We choose to represent the image in this way so that we can remap only the
  intensity channel and then recombine the new intensity values with the color
  information to form the final image.

  Old TV signals used to be transmitted in this way so that black & white
  televisions could display the luminance channel while color televisions would
  display all three of the channels.
  

  Tone-mapping
  ============

  In this assignment we are going to transform the luminance channel (actually
  the log of the luminance, but this is unimportant for the parts of the
  algorithm that you will be implementing) by compressing its range to [0, 1].
  To do this we need the cumulative distribution of the luminance values.

  Example
  -------

  input : [2 4 3 3 1 7 4 5 7 0 9 4 3 2]
  min / max / range: 0 / 9 / 9

  histo with 3 bins: [4 7 3]

  cdf : [4 11 14]


  Your task is to calculate this cumulative distribution by following these
  steps.

*/

#include "utils.h"

__global__ void reduce_max_min(const float* const d_in, float* d_out, bool is_max=true)
{
	extern __shared__ float partial[];

	int tid = threadIdx.x;
	int idx = blockIdx.x *  blockDim.x + tid;

	partial[tid] = d_in[idx];
	// make sure all data in this block has loaded into shared memory
	__syncthreads();
	
	for(unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1){
		if(tid < stride){
			if(is_max)
				partial[tid] = max(partial[tid], partial[tid+stride]);	
			else
				partial[tid] = min(partial[tid], partial[tid+stride]);	
		}
		// make sure all operations at one stage are done!
		__syncthreads();
	}
	

	if(tid == 0)
		d_out[blockIdx.x] = partial[tid];
}

void reduce(const float* const d_in,float &min_logLum,float &max_logLum,const size_t numRows,const size_t numCols)
{

	const int BLOCK_SIZE = numCols;
	const int GRID_SIZE  = numRows;
		// declare GPU memory pointers
	float * d_intermediate, *d_max, *d_min;
		
	// allocate GPU memory
	cudaMalloc((void **) &d_intermediate, GRID_SIZE*sizeof(float));
	cudaMalloc((void **) &d_max, sizeof(float));
	cudaMalloc((void **) &d_min, sizeof(float));

	// find maximum;
	// firstly, find the maximum in each block
	reduce_max_min<<<GRID_SIZE,BLOCK_SIZE, BLOCK_SIZE*sizeof(float)>>>(d_in, d_intermediate, true);
	// then, find the global maximum
	reduce_max_min<<<1, GRID_SIZE, GRID_SIZE*sizeof(float)>>>(d_intermediate, d_max, true);

	checkCudaErrors(cudaMemset(d_intermediate,0,GRID_SIZE*sizeof(float)));
	// find minimum;
	// firstly, find the minimum in each block
	reduce_max_min<<<GRID_SIZE,BLOCK_SIZE, BLOCK_SIZE*sizeof(float)>>>(d_in, d_intermediate,false);
	// then, find the global minimum
	reduce_max_min<<<1, GRID_SIZE, GRID_SIZE*sizeof(float)>>>(d_intermediate, d_min, false);
	

	// transfer the output to CPU
	checkCudaErrors(cudaMemcpy(&max_logLum, d_max, sizeof(float), cudaMemcpyDeviceToHost));
	checkCudaErrors(cudaMemcpy(&min_logLum, d_min, sizeof(float), cudaMemcpyDeviceToHost));

	// free GPU memory location
	checkCudaErrors(cudaFree(d_intermediate));
	checkCudaErrors(cudaFree(d_max));
	checkCudaErrors(cudaFree(d_min));

	return;	
}


__global__ void hist(const float* const d_in, unsigned int * const d_out, const float logLumRange, const int min_logLum, const int numBins)
{
	int idx = blockIdx.x * blockDim.x + threadIdx.x;
	float num = d_in[idx];
	int bin_idx = (num - min_logLum)/logLumRange*numBins;
	if(bin_idx >= numBins)
		bin_idx--;
	atomicAdd(&(d_out[bin_idx]),1);
	
}


// Hillis Steele Scan
__global__ void prefixSum_HS(const unsigned int * const d_in, unsigned int * const d_out)
{

	extern __shared__ float partial[];

	int tid = threadIdx.x;
	int idx = blockIdx.x * blockDim.x + tid;

	// make sure all data in this block are loaded into shared shared memory
	partial[tid] = d_in[idx];
	__syncthreads();
	
	for(unsigned int stride = 1; stride < blockDim.x; stride <<= 1){
		if(tid + stride < blockDim.x)
			partial[tid+stride] += partial[tid];
		// make sure all operations at one stage are done!
		__syncthreads();
	}

	// exclusive scan
	if(tid == 0)
		d_out[tid] = 0;
	else
		d_out[tid] = partial[tid-1];	
}


void your_histogram_and_prefixsum(const float* const d_logLuminance,
                                  unsigned int* const d_cdf,
                                  float &min_logLum,
                                  float &max_logLum,
                                  const size_t numRows,
                                  const size_t numCols,
                                  const size_t numBins)
{
  //TODO
  /*Here are the steps you need to implement
    1) find the minimum and maximum value in the input logLuminance channel
       store in min_logLum and max_logLum
    2) subtract them to find the range
    3) generate a histogram of all the values in the logLuminance channel using
       the formula: bin = (lum[i] - lumMin) / lumRange * numBins
    4) Perform an exclusive scan (prefix sum) on the histogram to get
       the cumulative distribution of luminance values (this should go in the
       incoming d_cdf pointer which already has been allocated for you)       */


	
	// Step 1 : find minimum and maximum value
	reduce(d_logLuminance, min_logLum, max_logLum, numRows, numCols);

	// Step 2: find the range 
	float logLumRange = max_logLum - min_logLum;

	// Step 3 : generate a histogram of all the values
	// declare GPU memory pointers
	unsigned int  *d_bins;
	// allocate GPU memory
	checkCudaErrors(cudaMalloc((void **) &d_bins, numBins*sizeof(unsigned int)));
	checkCudaErrors(cudaMemset(d_bins,0,numBins*sizeof(unsigned int)));
	
	hist<<<numRows, numCols>>>(d_logLuminance, d_bins, logLumRange, min_logLum, numBins);
	
	// Step 4 : prefix sum
	prefixSum_HS<<<1, numBins, numBins*sizeof(unsigned int)>>>(d_bins, d_cdf);

	// free GPU memory allocation
	checkCudaErrors(cudaFree(d_bins));
}
