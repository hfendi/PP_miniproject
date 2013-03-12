#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>
#include <string.h>



// //libs
#include "constant.h"
#include "util.c"
#include "fileio.c"
#include "pheroneme.c"
#include "probability.c"
#include "graph.c"



int main(int argc, char **argv)
{
    //Let's denote n the number of nodes
    int n;

    //We define the graph using a matrix of size n*n
    //We load it from the file graph.txt
    int * G = load_int("data/graph.txt",&n);

    //We define the level of pheroneme for each edge in a matrix
    //We load it from the file pheroneme.txt
    float * T = load_float("data/pheroneme.txt",&n);

    //We define the matrice of the probabilities
    float * P = malloc(sizeof(float)*n*n);

    //Initialize the probabilities
    float * sum = sum_prob(G,T,n);
    update_prob(G,T,P,n,sum);

    printf("graph: \n");
    print_int(G,n);
    printf("pheroneme: \n");
    print_float(T,n);
    printf("probabilities: \n");
    print_float(P,n);

    //Array that contain the length of the path generated by each ant
    int * L = malloc(sizeof(int)*NB_ANT);

    //number of iteration
    int iter = 0;

    //Minimum length
    int Lmin;

    //Shortest path
    int * best_path = malloc(sizeof(int)*n);

    //Initialize srand to get different random number
    srand(time(NULL));

    while(iter<ITER_MAX)
    {
        //for each ant construct a path from the starting point to the final point
        int k;
        for(k=0 ; k<NB_ANT; k++)
        {

	    printf("\nThe %dth ant : \n",k+1);
            int i;
            //initialize the array that contain the solution
            int * kth_solution = malloc(sizeof(int)*n);
            for(i=0; i<n ; i++)
            {
                kth_solution[i]=0;

            }

            //Generate the solution
            i=1;
            float rdm;
            int j;
            while(kth_solution[i-1] != n-1)
            {
                printf("kth_sol[i-1]: %d \n",kth_solution[i-1]);
                //select the next node based on the probability
                //generate a random number between 0 and 1 with 0 excluded
                rdm = (rand()/(float)RAND_MAX);
                printf("random number : %f \n",rdm);

                //Probability to select the next node
                float Pnext = 0;

                for(j=kth_solution[i]; j<n; j++)
                {
                    Pnext += P[n*kth_solution[i-1] + j];

                    //if the random number is less or equal to
                    //the probability to select the next node we select it
                    printf("probability to move from %d to %d: %f \n",kth_solution[i-1],j,Pnext);
                    if( rdm <= Pnext )
                    {
                        kth_solution[i]=j;
                        break;
                    }
                }
                printf("kth_sol[i]: %d \n",kth_solution[i]);
                i++;

            }

            //printf("test \n");

            //Calculate the length of the path
            L[k]=0;
            i=0;
            while(kth_solution[i] != n-1)
            {
                L[k] += G[kth_solution[i]*n + kth_solution[i+1]];
                i++;
            }

            //find the shortest length and path
            Lmin=L[0];
            if(L[k]<=Lmin)
            {
                Lmin = L[k];
                memcpy(best_path, kth_solution, sizeof(int)*n );
            }

            //update pheroneme values based on the solution
            update_pheroneme1(T,n,kth_solution,L[k]);

            free(kth_solution);

        }

        //evaporation of the pheroneme
        update_pheroneme2(T,n);

        //update probabilities
        sum = sum_prob(G,T,n);
        update_prob(G,T,P,n,sum);

        //increment iter
        iter++;

        printf("pheroneme: \n");
        print_float(T,n);
        printf("probabilities: \n");
        print_float(P,n);

    }

    //Best path
    printf("the best path: \n");
    int i=1;
    printf("%d ",best_path[0]);
    while(best_path[i-1] !=  n-1)
    {
        printf("%d ",best_path[i]);
        i++;
    }
    printf("\n");
    printf("length of the best path: %d \n",Lmin);


    //Free the memory
    free(G);
    free(T);
    free(P);
    free(L);
    free(best_path);

    return 0;
}
