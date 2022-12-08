#!/bin/bash

# Tell the model where your libraries are at runtime
# export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

# Execute the program
# mpiexec -n 16 IMAU_ICE_program config-files/config_projection_test
# mpiexec -n 16 IMAU_ICE_program config-files/config_spinup
# mpiexec -n 16 IMAU_ICE_program config-files/config_3dgia
# mpiexec -n 16 IMAU_ICE_program config-files/config_projection


# mpiexec -n 24 IMAU_ICE_program config-files/config_baseline
# mpiexec -n 24 IMAU_ICE_program config-files/config_CESMssp585_ELRA
mpiexec -n 16 /home/caroline/HetGroteKoppelScript_IMAUICE/IMAU-ICE/IMAU_ICE_program /home/caroline/HetGroteKoppelScript_IMAUICE/IMAU-ICE/config-files/config_CESMssp585_1D20



