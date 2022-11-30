#!/bin/bash

# Tell the model where your libraries are at runtime
# export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

# Execute the program
mpiexec -n 8 IMAU_ICE_program config-files/config_projection
# mpiexec -n 8 IMAU_ICE_program config-files/config_spinup
# mpiexec -n 16 IMAU_ICE_program config-files/config_3dgia
