#include <cutil_inline.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include "cuda.h"
#include "curand.h"
#include <curand_kernel.h>

//cube libraries

//rubik's cube libs
#include "../CPU/cube/parse.c"
#include "../CPU/cube/move.c"

/*ACO parameters*/
  //Number of nodes in the graph
  #define GRAPH_SIZE 1024
  //Number of iteration in ACO algorithm
  #define ACO_ITER_MAX 2
  //evaporation rate
  #define EVAP_RATE 0.3
  //influence rate of the pheroneme
  #define ALPHA 0.2
  //influence rate of the heuristic (distance)
  #define BETA 0.8
  //Initial level of pheroneme
  #define INIT_PHERONEME 5
  //Update pheroneme constant
  #define UPDT_PHERONEME_CONST 2
  //Number of moves allowed through the graph
  #define NSTEPS 2
  //Number of ants
  #define NB_ANT 1024
/*End ACO parameters*/

/*GPU parameters*/
  #define GRID_SIZE 1
  #define ITER_BENCHMARK 100
/*End GPU parameters*/

//random numbers macros
#define CUDA_CALL(x) do { if((x)!=cudaSuccess) { \
    printf("Error at %s:%d\n",__FILE__,__LINE__);\
    return EXIT_FAILURE;}} while(0)
#define CURAND_CALL(x) do { if((x)!=CURAND_STATUS_SUCCESS) { \
    printf("Error at %s:%d\n",__FILE__,__LINE__);\
    return EXIT_FAILURE;}} while(0)




//function prototypes
void h_datainit_graph(int*, int);
void h_datainit_pheroneme(float*, int);
void h_update_pheroneme(float* h_pheroneme, int size);
float* h_sum_probability(int* h_graph, float* h_pheroneme, int size);
void h_update_probability(int* h_graph,float* h_pheroneme,float* h_probability, int size, float* h_sum);
int* h_find_best_solution(int* h_solutions, int* h_length, int size);
;
//a macro function that takes as parameters the indexes
//of a 2d matrix and it's row size, and returns the 
//serialized index
#define SERIALIZE(i,j,row_size) i * row_size + j;


__global__ void ACO_kernel(int* d_graph, float* d_pheroneme, float* d_probability, float* d_random_numbers, int* d_solutions,int* d_length)
{
  int tid = threadIdx.x;

  int index,j;
  //initialize the array that contain the solution
  //each thread initialise one row
  for(j=0; j<GRAPH_SIZE ; j++)
  {
    index = SERIALIZE(tid,j,GRAPH_SIZE);
    d_solutions[index]=0;
  }


  __syncthreads();


  //Generate the solution
  float rdm;
  index=SERIALIZE(tid,1,GRAPH_SIZE);
  //For the cube it is going to be loop until NB_STEP is reached or solution found 
  while(d_solutions[index-1] != GRAPH_SIZE-1)
  {
      //select the next node based on the probability
      //take a random number between 0 and 1 with 0 excluded
      rdm=d_random_numbers[index];

      //Probability to select the next node
      float Pnext = 0;

      int j,ip;
      for(j=0; j<GRAPH_SIZE; j++)
      {
          ip = SERIALIZE(d_solutions[index-1], j, GRAPH_SIZE);
          Pnext += d_probability[ip];

          //if the random number is less or equal to
          //the probability to select the next node we select it
          if( rdm <= Pnext )
          {
              d_solutions[index]=j;
              break;
          }
       }

      index++;
  }

  __syncthreads();

  //Calculate the length of the path for each ant
  d_length[tid]=0;
  j=0;
  index=SERIALIZE(tid,j,GRAPH_SIZE)
  while(d_solutions[index] != GRAPH_SIZE-1)
  {
      d_length[tid] += d_graph[d_solutions[index]*GRAPH_SIZE + d_solutions[index+1]];
      j++;
      index=SERIALIZE(tid,j,GRAPH_SIZE);
  }

  //Update the pheroneme based on constructed solution
  //Each ant update its own path in the pheroneme matrix
  index=SERIALIZE(tid,0,GRAPH_SIZE);
  while(d_solutions[index] != GRAPH_SIZE-1)
    {
        j=SERIALIZE(d_solutions[index],d_solutions[index+1],GRAPH_SIZE);
        d_pheroneme[j] += UPDT_PHERONEME_CONST/d_length[tid];
        index++;
    }

}
  

/*
 * Main program and benchmarking 
 */
int main(int argc, char** argv)
{


  // allocate host memory 
  unsigned int nb_node              = GRAPH_SIZE; 
  unsigned int size_graph           = GRAPH_SIZE*GRAPH_SIZE;
  unsigned int mem_size_graph_int   = sizeof(int) * size_graph;
  unsigned int mem_size_graph_float = sizeof(float) * size_graph;
  unsigned int mem_size_ant         = sizeof(int) * NB_ANT;
  unsigned int mem_size_solution    = sizeof(int)*NB_ANT*GRAPH_SIZE;    
  int*   h_graph                    = (int*)malloc(mem_size_graph_int); 
  float* h_pheroneme                = (float*)malloc(mem_size_graph_float);
  float* h_probability              = (float*)malloc(mem_size_graph_float);
  int*   h_solutions                = (int*)malloc(mem_size_solution);
  int*   h_length                   = (int*)malloc(mem_size_ant);

  //Initialise random numbers
  float *d_random_numbers;
  //create curand generator object
  curandGenerator_t gen;
  /* Allocate n floats on device */
  CUDA_CALL(cudaMalloc((void **)&d_random_numbers, NB_ANT * nb_node *sizeof(float)));

  /* Create pseudo-random number generator */
  CURAND_CALL(curandCreateGenerator(&gen, 
              CURAND_RNG_PSEUDO_DEFAULT));
  /* Set seed */
  CURAND_CALL(curandSetPseudoRandomGeneratorSeed(gen, 
              time(NULL)));
  /* Generate n floats on device */
  CURAND_CALL(curandGenerateUniform(gen, d_random_numbers, NB_ANT * nb_node ));

  printf("Input size : %d\n", GRAPH_SIZE);

  //Initialise the graph, the pheroneme and the probabilities
  h_datainit_graph(h_graph, nb_node);
  h_datainit_pheroneme(h_pheroneme, nb_node);
  float* h_sum = h_sum_probability(h_graph, h_pheroneme, nb_node);
  h_update_probability(h_graph, h_pheroneme, h_probability, nb_node, h_sum);



  // allocate device memory
  int* d_graph;
  cutilSafeCall(cudaMalloc((void**) &d_graph, mem_size_graph_int));
  float* d_pheroneme;
  cutilSafeCall(cudaMalloc((void**) &d_pheroneme, mem_size_graph_float));
  float* d_probability;
  cutilSafeCall(cudaMalloc((void**) &d_probability, mem_size_graph_float));
  int* d_solutions;
  cutilSafeCall(cudaMalloc((void**) &d_solutions, mem_size_solution));

  //Array that contain the length of the path generated by each ant
  int* d_length;
  cutilSafeCall(cudaMalloc((void**) &d_length, mem_size_ant));  
  

  // copy host memory to device

  //The graph needs to be copied in the constant memory!!!!!!!!!!!!!!!
  cutilSafeCall(cudaMemcpy(d_graph, h_graph, 
              mem_size_graph_int, cudaMemcpyHostToDevice));

  cutilSafeCall(cudaMemcpy(d_pheroneme, h_pheroneme, 
              mem_size_graph_float, cudaMemcpyHostToDevice));

  cutilSafeCall(cudaMemcpy(d_probability, h_probability, 
              mem_size_graph_float, cudaMemcpyHostToDevice));             

  // set up kernel for execution
  printf("Run %d Kernels.\n\n", ITER_BENCHMARK);
  unsigned int timer = 0;
  cutilCheckError(cutCreateTimer(&timer));
  cutilCheckError(cutStartTimer(timer));  

int* h_best_solution;
// execute kernel
  for (int j = 0; j < ITER_BENCHMARK; j++) 
      for(int i = 0; i < ACO_ITER_MAX; i++){

          ACO_kernel<<<1, NB_ANT >>>(d_graph, d_pheroneme, d_probability, d_random_numbers, d_solutions, d_length);
          // copy result from device to host
          cutilSafeCall(cudaMemcpy(h_solutions, d_solutions, 
               mem_size_solution, cudaMemcpyDeviceToHost));
          cutilSafeCall(cudaMemcpy(h_length, d_length, 
               mem_size_ant, cudaMemcpyDeviceToHost));
          cutilSafeCall(cudaMemcpy(h_pheroneme, d_pheroneme, 
               mem_size_graph_float, cudaMemcpyDeviceToHost));
          //find the best solution and its length
          h_best_solution = h_find_best_solution(h_solutions,h_length,NB_ANT);
          //update the pheroneme (evaporation)
          h_update_pheroneme(h_pheroneme,nb_node);
          //update the probability
          h_sum = h_sum_probability(h_graph, h_pheroneme, nb_node);
          h_update_probability(h_graph, h_pheroneme, h_probability, nb_node, h_sum);
          //copy back the update pheroneme and probability to the GPU
          cutilSafeCall(cudaMemcpy(d_pheroneme, h_pheroneme, 
              mem_size_graph_float, cudaMemcpyHostToDevice));

          cutilSafeCall(cudaMemcpy(d_probability, h_probability, 
              mem_size_graph_float, cudaMemcpyHostToDevice));

                  //regenerate random numbers
        /* Set seed */
        CURAND_CALL(curandSetPseudoRandomGeneratorSeed(gen, 
                    time(NULL)));
        /* Generate n floats on device */
        CURAND_CALL(curandGenerateUniform(gen, d_random_numbers, NB_ANT * nb_node ));
      }

  printf("the best path is: \n");
  int i = 1;
  printf("%d ",h_best_solution[0]);
  while(h_best_solution[i-1] != GRAPH_SIZE-1)
  {
    printf("%d ",h_best_solution[i]);
    i++;
  }
  printf("\n");
  // printf("last set of solutions \n");
  // int index;
  // for(int i=0; i<NB_ANT; i++)
  // {
  //   for(int j=0; j<nb_node; j++)
  //   {
  //       index = SERIALIZE(i,j,nb_node);
  //       printf("%d ",h_solutions[index]);
  //   }
  //    printf("\n");
  // }

  // printf("last set of length solution \n");
  // for(int i=0; i<NB_ANT; i++)
  // {
  //   printf("%d ",h_length[i]);
  // }
  // printf("\n");

  // check if kernel execution generated and error
  cutilCheckMsg("Kernel execution failed");

  // wait for device to finish
  cudaThreadSynchronize();

  // stop and destroy timer
  cutilCheckError(cutStopTimer(timer));
  double dSeconds = cutGetTimerValue(timer)/(1000.0);
  double dNumOps = ITER_BENCHMARK * (size_graph * 3 + NB_ANT * GRAPH_SIZE + NB_ANT);
  double gflops = dNumOps/dSeconds/1.0e9;

  //Log througput
  printf("Throughput = %.4f GFlop/s\n", gflops);
  cutilCheckError(cutDeleteTimer(timer));

  // clean up memory
  free(h_graph);
  free(h_pheroneme);
  free(h_probability);
  free(h_solutions);
  free(h_length);
  free(h_sum);
  free(h_best_solution);
  cutilSafeCall(cudaFree(d_graph));
  cutilSafeCall(cudaFree(d_pheroneme));
  cutilSafeCall(cudaFree(d_probability));
  cutilSafeCall(cudaFree(d_solutions));
  cutilSafeCall(cudaFree(d_length));

  CURAND_CALL(curandDestroyGenerator(gen));
  CUDA_CALL(cudaFree(d_random_numbers)); 

  // exit and clean up device status
  cudaThreadExit();
}

// 
void h_datainit_graph(int* h_graph, int size)
{    
    //same method as the CPU version
    int i,j,index;
    for(i=0 ; i<size ; i++)
    {
        for(j=0 ; j<size ; j++)
        {
            index = SERIALIZE(i,j,size);

            if(i < j) {

                h_graph[index] = 1;
            }
            else {
            h_graph[index] = 0;
          }
        }
    }
 
}

void h_datainit_pheroneme(float* h_pheroneme, int size)
{
  //same method as the CPU version
    int i,j,index;
    for(i=0 ; i<size ; i++)
    {
        for(j=0 ; j<size ; j++)
        {
            index = SERIALIZE(i,j,size);
            if(i < j)
                h_pheroneme[index] = INIT_PHERONEME;
            else{
            h_pheroneme[index] = 0;}
        }
    }

}


void h_datainit_graph_cube(int * h_graph,int max_depth) {
    
    int i, j;

    //calculate the number of nodes available
    long num_nodes = max_cube_moves(max_depth);

    //calculate the number of nodes that are at depth max_depth -1
    long num_nodes_at_depth_minus_one = max_cube_moves(max_depth - 1);


    //let's initialize the first row separately because it doesn't follow the trend
    for (j=1 ; j < num_nodes; j++) {
    
        int index = SERIALIZE(0,j,num_nodes);
        if (j < 19 ) {
          h_graph[index] = 1;
        }
        else {
          h_graph[index] = 0;
        }
      }
    
    // we do the rest of the rows that contain "1's"
    // Since it's a tree, we shift to the right in each row
    //because the nodes are only connected to only 15 other nodes, 
      //we skip three nodes in each row because after doing a move,
      //we don't want to do a same-face rotation again
      // 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 
      // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0
      // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0
      // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0
      // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0
      //....
    for (i=1 ; i < num_nodes_at_depth_minus_one; i++) {
      for (j=0 ; j < num_nodes; j++) {

        int index = SERIALIZE(i,j,num_nodes);

        if (  ( j >= 18 + (i-1) * 15 + 1) &&   j < (18 + (i-1) * 15 + 15 + 1     ) )  {

          h_graph[index] = 1;
        
        }
        else {
          h_graph[index] = 0;
         }
      }

    }

    //put zeros in the last level of nodes
    for (i=num_nodes_at_depth_minus_one ; i < num_nodes; i++) {
      for (j=0 ; j < num_nodes; j++) {
          h_graph[i * num_nodes + j] = 0;
      }
    }
}

/*
void datainit_graph_cube(int *graph,int max_depth) {
    
    //calculate the number of nodes available
    long num_nodes = max_cube_moves(max_depth);

    //calculate the number of nodes that are at depth max_depth -1
    long num_nodes_at_depth_minus_one = max_cube_moves(max_depth - 1);
    int i;

    for (i=0 ; i < num_nodes_at_depth_minus_one; i++) {
      if ( i >= i * 18 + 1 && i < (i * 18 + 18) ) {
        graph[i] = 1;
      }
      else {
        graph[i] = 0;
       }
    }

    //put zeros in the last level of nodes
    for (i=num_nodes_at_depth_minus_one ; i < num_nodes; i++) {
      graph[i] = 0;
    }
    int i,j;
    //start from node 2, and keep track of the next node number
    int current_node = 2;


    //initialize the first row
    for (i =0; i < num_nodes; i++) {

          int index = SERIALIZE(i,j,18);
            graph[index] = 0;
            current_node++:      
    }


    for (i =0; i < num_nodes; i++) {

        for (j=0; j<18; j++) {

          int index = SERIALIZE(i,j,18);

          if () { 
            graph[index] = current_node;
            current_node++:
          }
          else {
            graph[index] = 0;
          }

        }
    }   
}
*/



void h_update_pheroneme(float* h_pheroneme, int size)
{
    int i,j,index;
    //evaporation
    for(i=0 ; i<size ; i++)
    {
        for(j=0 ; j<size ; j++)
        {
          index = SERIALIZE(i,j,size);
            if(h_pheroneme !=0)
            {
              h_pheroneme[index] = (1-EVAP_RATE) * h_pheroneme[index];
            }
        }
    }
}


float* h_sum_probability(int* h_graph, float* h_pheroneme, int size)

{
    int i,j,index;
    float* sum = (float*)malloc(sizeof(float)*size);
    for(i=0 ; i<size ; i++)
    {
        sum[i]=0;
        for(j=0 ; j<size ; j++)
        {
            index = SERIALIZE(i,j,size);
            if(h_graph[index] != 0){
                sum[i] += pow(h_pheroneme[index],ALPHA) * pow(1/h_graph[index],BETA);
            }
        }
    }
    return sum;
}


void h_update_probability(int* h_graph,float* h_pheroneme,float* h_probability, int size, float* h_sum)
{
    //same methode as the CPU version
    int i,j,index;
    for(i=0 ; i<size ; i++)
    {
        for(j=0 ; j<size ; j++)
        {
            index = SERIALIZE(i,j,size);
            if(h_graph[index] != 0)
            {
                h_probability[index] = pow(h_pheroneme[index],ALPHA) * pow(1/h_graph[index],BETA)/h_sum[i];
            }
            else{
                h_probability[index] = 0;
            }
        }
    }

}
//
int* h_find_best_solution(int* h_solutions, int* h_length, int size)
{
  //find the shortest length and path
  int* h_best_solution = (int*)malloc(sizeof(int) * GRAPH_SIZE);
  int Lmin=h_length[0];
  int index;
  for(int i=1; i<size; i++)
  {
      if(h_length[i]<=Lmin)
      {
        Lmin = h_length[i];
        index = SERIALIZE(i,0,GRAPH_SIZE);
        memcpy(h_best_solution, &(h_solutions[index]), sizeof(int)*GRAPH_SIZE);
      }   
  }
  return h_best_solution;
}
