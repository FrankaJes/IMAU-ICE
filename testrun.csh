#! /bin/csh -f

./compile_all.csh

#rm -rf Berends2022_basal_inversion/exp_I_target_40km
#rm -rf Berends2022_basal_inversion/exp_I_target_20km
#rm -rf Berends2022_basal_inversion/exp_I_target_10km

#mpiexec -n 2 IMAU_ICE_program Berends2022_basal_inversion/config-files/config_exp_I_target_40km
#mpiexec -n 2 IMAU_ICE_program Berends2022_basal_inversion/config-files/config_exp_I_target_20km
#mpiexec -n 2 IMAU_ICE_program Berends2022_basal_inversion/config-files/config_exp_I_target_10km

#rm -rf Berends2022_basal_inversion/exp_I_inv_40km_unperturbed
#rm -rf Berends2022_basal_inversion/exp_I_inv_20km_unperturbed
rm -rf Berends2022_basal_inversion/exp_I_inv_20km_unperturbed_CISMplus
#rm -rf Berends2022_basal_inversion/exp_I_inv_20km_unperturbed_noflowline

#mpiexec -n 2 IMAU_ICE_program Berends2022_basal_inversion/config-files/config_exp_I_inv_40km_unperturbed
#mpiexec -n 2 IMAU_ICE_program Berends2022_basal_inversion/config-files/config_exp_I_inv_20km_unperturbed
mpiexec -n 2 IMAU_ICE_program Berends2022_basal_inversion/config-files/config_exp_I_inv_20km_unperturbed_CISMplus
#mpiexec -n 2 IMAU_ICE_program Berends2022_basal_inversion/config-files/config_exp_I_inv_20km_unperturbed_noflowline

#rm -rf Berends2022_basal_inversion/exp_II_target_5km

#mpiexec -n 2 IMAU_ICE_program Berends2022_basal_inversion/config-files/config_exp_II_target_5km

#rm -rf Berends2022_basal_inversion/exp_II_inv_5km_unperturbed
#rm -rf Berends2022_basal_inversion/exp_II_inv_5km_unperturbed_noflowline

#mpiexec -n 2 IMAU_ICE_program Berends2022_basal_inversion/config-files/config_exp_II_inv_5km_unperturbed
#mpiexec -n 2 IMAU_ICE_program Berends2022_basal_inversion/config-files/config_exp_II_inv_5km_unperturbed_noflowline