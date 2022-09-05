clc
clear all
close all

filename_template = 'config_template';

% choice_system = 'local';
choice_system = 'Snellius';

% The eight model versions
model_versions = list_model_versions;

% All the different FCM forcings
RCM_forcings   = list_RCM_forcings;

% The three retreat mask R factors
Rfactors = {'Rmed','Rlow','Rhigh'};

% Create all the config files
for mi = 1: length( model_versions)
  for rfi = 1: length( RCM_forcings)
    for ri = 1: length( Rfactors)

      %% List all config variables that need to be changed

      % Config variables pertaining to the spin-up version and the RCM% forcing
      vars = [model_versions( mi).vars, RCM_forcings( rfi).vars];

      % Variables that contain info from both
      vi = length( vars);
      
      % Output folder
      vi = vi+1;
      vars( vi).name  = 'fixed_output_dir_config';
      vars( vi).value = ['PROTECT_projections/' model_versions( mi).name '_' RCM_forcings( rfi).name '_' Rfactors{ ri}];

      % ISMIP output experiment code
      vi = vi+1;
      vars( vi).name  = 'ISMIP_output_experiment_code_config';
      vars( vi).value = [RCM_forcings( rfi).name '_' Rfactors{ ri}];
      
      % Retreat mask filename
      vi = vi+1;
      vars( vi).name  = 'prescribed_retreat_mask_filename_config';
      if strcmpi( choice_system,'local')
        vars( vi).value = ['/Users/berends/Documents/PROTECT/Greenland/data/retreat_masks/' ...
          model_versions( mi).name '/retreatmasks_hist_med_v1_' RCM_forcings( rfi).retreatmaskname '-' ...
          Rfactors{ ri} '_PRO_' model_versions( mi).name '.nc'];
      elseif strcmpi( choice_system,'Snellius')
        vars( vi).value = ['/home/berends/PROTECT/Greenland/data/retreat_masks/' ...
          model_versions( mi).name '/retreatmasks_hist_med_v1_' RCM_forcings( rfi).retreatmaskname '-' ...
          Rfactors{ ri} '_PRO_' model_versions( mi).name '.nc'];
      else
        error('unknown system choice')
      end
      
      % Exception for the MARv3.12 MPI-ESM masks, which for reasons
      % unknown have deviated file names...
      if     strcmpi( RCM_forcings( rfi).name,'MPI-ESM1-2-HR-ssp126_MARv3.12')
        vars( vi).value = ['/home/berends/PROTECT/Greenland/data/retreat_masks/' ...
          model_versions( mi).name '/retreatmasks_hist_med_v1_MARv3.12_MPIESM12HR-ssp126-' ...
          Rfactors{ ri} '_PRO_' model_versions( mi).name '.nc'];
      elseif strcmpi( RCM_forcings( rfi).name,'MPI-ESM1-2-HR-ssp245_MARv3.12')
        vars( vi).value = ['/home/berends/PROTECT/Greenland/data/retreat_masks/' ...
          model_versions( mi).name '/retreatmasks_hist_med_v1_MARv3.12_MPIESM12HR-ssp245-' ...
          Rfactors{ ri} '_PRO_' model_versions( mi).name '.nc'];
      elseif strcmpi( RCM_forcings( rfi).name,'MPI-ESM1-2-HR-ssp585_MARv3.12')
        vars( vi).value = ['/home/berends/PROTECT/Greenland/data/retreat_masks/' ...
          model_versions( mi).name '/retreatmasks_hist_med_v1_MARv3.12_MPIESM12HR-ssp585-' ...
          Rfactors{ ri} '_PRO_' model_versions( mi).name '.nc'];
      end
      
      % Another exception for the MARv3.12 UKESM masks, where probably
      % Heiko forgot the change the name of the GCM
      if strcmpi( RCM_forcings( rfi).name,'UKESM1-0-LL-ssp585_MARv3.12')
        vars( vi).value = ['/home/berends/PROTECT/Greenland/data/retreat_masks/' ...
          model_versions( mi).name '/retreatmasks_hist_med_v1_MARv3.12_UKESM1-CM6-ssp585-' ...
          Rfactors{ ri} '_PRO_' model_versions( mi).name '.nc'];
      end
      
      %% Read, change, and write config file
      
      % New config filename
      config_filename = ['config_' model_versions( mi).name '_' RCM_forcings( rfi).name '_' Rfactors{ ri}];

      % Read the template config file
      fid = fopen( filename_template,'r');
      C = textscan( fid,'%s','delimiter','\n'); C = C{1};
      fclose( fid);

      % Replace all the config variables with the newly specified values
      for vi = 1: length( vars)
        varname  = vars( vi).name;
        varvalue = vars( vi).value;
        foundvar = false;
        for li = 1: length( C)
          if length( C{li}) < length( varname); continue; end
          if strcmpi( C{ li}(1:length( varname)), varname)
            % Found the specified config variable in the template
            foundvar = true;
            % Replace its value
            if     strcmpi( class( varvalue),'double')
              C{ li} = [varname ' = ' num2str( varvalue)];
            elseif strcmpi( class( varvalue),'char')
              C{ li} = [varname ' = ''' varvalue ''''];
            else
              error(['Cannot handle variable type "' class( varvalue) '"!'])
            end
          end
        end
        if ~foundvar
          error(['Couldnt find config variable "' varname '" in the template!'])
        end
      end
      
      % Create and write to the new config file
      if exist( config_filename, 'file')
        delete( config_filename)
      end
      
      fid = fopen( config_filename,'w');
      for li = 1: length( C)
        if strcmpi( choice_system,'local')
          C{li} = strrep( C{li},'/home/berends','/Users/berends/Documents');
        elseif strcmpi( choice_system,'Snellius')
          C{li} = strrep( C{li},'/Users/berends/Documents','/home/berends');
        else
          error('unknown system choice')
        end
        fprintf( fid,'%s\n',C{li});
      end
      fclose( fid);

    end % for ri = 1: length( Rfactors)
  end % for rfi = 1: length( RCM_forcings)
end % for mi = 1: length( model_versions)

function model_versions = list_model_versions

  mi = 0;
  
  %% IMAUICE1: default + 40 km
  
  mi = mi+1;
  model_versions( mi).name = 'IMAUICE1';
  vi = 0;

  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'ISMIP_output_model_code_config';
  model_versions( mi).vars( vi).value = model_versions( mi).name;
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'dx_GRL_config';
  model_versions( mi).vars( vi).value = 40000.0;
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'filename_refgeo_init_GRL_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_PMIP3ens_40km/restart_GRL.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'basal_roughness_filename_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase4_holocene/hybrid_ZoetIverson_PMIP3ens_40km/bed_roughness_inv.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'choice_sliding_law_config';
  model_versions( mi).vars( vi).value = 'Zoet-Iverson';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'ISMIP_forcing_filename_baseline_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_PMIP3ens_40km/baseline_climate_1960_1989.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'prescribed_retreat_mask_refice_filename_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase4_holocene/hybrid_ZoetIverson_PMIP3ens_40km/retreat_mask_refice.nc';
  
  %% IMAUICE2: default + 30 km

  mi = mi+1;
  model_versions( mi).name = 'IMAUICE2';
  vi = 0;

  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'ISMIP_output_model_code_config';
  model_versions( mi).vars( vi).value = model_versions( mi).name;
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'dx_GRL_config';
  model_versions( mi).vars( vi).value = 30000.0;
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'filename_refgeo_init_GRL_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_PMIP3ens_30km/restart_GRL.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'basal_roughness_filename_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase4_holocene/hybrid_ZoetIverson_PMIP3ens_30km/bed_roughness_inv.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'choice_sliding_law_config';
  model_versions( mi).vars( vi).value = 'Zoet-Iverson';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'ISMIP_forcing_filename_baseline_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_PMIP3ens_30km/baseline_climate_1960_1989.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'prescribed_retreat_mask_refice_filename_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase4_holocene/hybrid_ZoetIverson_PMIP3ens_30km/retreat_mask_refice.nc';
  
  %% IMAUICE3: default

  mi = mi+1;
  model_versions( mi).name = 'IMAUICE3';
  vi = 0;

  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'ISMIP_output_model_code_config';
  model_versions( mi).vars( vi).value = model_versions( mi).name;
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'dx_GRL_config';
  model_versions( mi).vars( vi).value = 20000.0;
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'filename_refgeo_init_GRL_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_PMIP3ens_20km/restart_GRL.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'basal_roughness_filename_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase4_holocene/hybrid_ZoetIverson_PMIP3ens_20km/bed_roughness_inv.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'choice_sliding_law_config';
  model_versions( mi).vars( vi).value = 'Zoet-Iverson';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'ISMIP_forcing_filename_baseline_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_PMIP3ens_20km/baseline_climate_1960_1989.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'prescribed_retreat_mask_refice_filename_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase4_holocene/hybrid_ZoetIverson_PMIP3ens_20km/retreat_mask_refice.nc';
  
  %% IMAUICE4: default + 16 km

  mi = mi+1;
  model_versions( mi).name = 'IMAUICE4';
  vi = 0;

  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'ISMIP_output_model_code_config';
  model_versions( mi).vars( vi).value = model_versions( mi).name;
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'dx_GRL_config';
  model_versions( mi).vars( vi).value = 16000.0;
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'filename_refgeo_init_GRL_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_PMIP3ens_16km/restart_GRL.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'basal_roughness_filename_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase4_holocene/hybrid_ZoetIverson_PMIP3ens_16km/bed_roughness_inv.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'choice_sliding_law_config';
  model_versions( mi).vars( vi).value = 'Zoet-Iverson';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'ISMIP_forcing_filename_baseline_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_PMIP3ens_16km/baseline_climate_1960_1989.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'prescribed_retreat_mask_refice_filename_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase4_holocene/hybrid_ZoetIverson_PMIP3ens_16km/retreat_mask_refice.nc';
  
  %% IMAUICE5: default + 10 km

  mi = mi+1;
  model_versions( mi).name = 'IMAUICE5';
  vi = 0;

  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'ISMIP_output_model_code_config';
  model_versions( mi).vars( vi).value = model_versions( mi).name;
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'dx_GRL_config';
  model_versions( mi).vars( vi).value = 10000.0;
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'filename_refgeo_init_GRL_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_PMIP3ens_10km/restart_GRL.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'basal_roughness_filename_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase4_holocene/hybrid_ZoetIverson_PMIP3ens_10km/bed_roughness_inv.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'choice_sliding_law_config';
  model_versions( mi).vars( vi).value = 'Zoet-Iverson';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'ISMIP_forcing_filename_baseline_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_PMIP3ens_10km/baseline_climate_1960_1989.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'prescribed_retreat_mask_refice_filename_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase4_holocene/hybrid_ZoetIverson_PMIP3ens_10km/retreat_mask_refice.nc';
  
  %% IMAUICE6: default + HadCM3

  mi = mi+1;
  model_versions( mi).name = 'IMAUICE6';
  vi = 0;

  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'ISMIP_output_model_code_config';
  model_versions( mi).vars( vi).value = model_versions( mi).name;
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'dx_GRL_config';
  model_versions( mi).vars( vi).value = 20000.0;
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'filename_refgeo_init_GRL_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_HadCM3_20km/restart_GRL.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'basal_roughness_filename_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase4_holocene/hybrid_ZoetIverson_HadCM3_20km/bed_roughness_inv.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'choice_sliding_law_config';
  model_versions( mi).vars( vi).value = 'Zoet-Iverson';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'ISMIP_forcing_filename_baseline_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_HadCM3_20km/baseline_climate_1960_1989.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'prescribed_retreat_mask_refice_filename_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase4_holocene/hybrid_ZoetIverson_HadCM3_20km/retreat_mask_refice.nc';
  
  %% IMAUICE7: default + CCSM

  mi = mi+1;
  model_versions( mi).name = 'IMAUICE7';
  vi = 0;

  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'ISMIP_output_model_code_config';
  model_versions( mi).vars( vi).value = model_versions( mi).name;
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'dx_GRL_config';
  model_versions( mi).vars( vi).value = 20000.0;
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'filename_refgeo_init_GRL_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_CCSM_20km/restart_GRL.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'basal_roughness_filename_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase4_holocene/hybrid_ZoetIverson_CCSM_20km/bed_roughness_inv.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'choice_sliding_law_config';
  model_versions( mi).vars( vi).value = 'Zoet-Iverson';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'ISMIP_forcing_filename_baseline_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_CCSM_20km/baseline_climate_1960_1989.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'prescribed_retreat_mask_refice_filename_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase4_holocene/hybrid_ZoetIverson_CCSM_20km/retreat_mask_refice.nc';
  
  %% IMAUICE8: default + Coulomb_regularised

  mi = mi+1;
  model_versions( mi).name = 'IMAUICE8';
  vi = 0;

  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'ISMIP_output_model_code_config';
  model_versions( mi).vars( vi).value = model_versions( mi).name;
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'dx_GRL_config';
  model_versions( mi).vars( vi).value = 20000.0;
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'filename_refgeo_init_GRL_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase5_historicalperiod/hybrid_Coulombreg_PMIP3ens_20km/restart_GRL.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'basal_roughness_filename_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase4_holocene/hybrid_Coulombreg_PMIP3ens_20km/bed_roughness_inv.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'choice_sliding_law_config';
  model_versions( mi).vars( vi).value = 'Coulomb_regularised';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'ISMIP_forcing_filename_baseline_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase5_historicalperiod/hybrid_Coulombreg_PMIP3ens_20km/baseline_climate_1960_1989.nc';
  vi = vi+1;
  model_versions( mi).vars( vi).name  = 'prescribed_retreat_mask_refice_filename_config';
  model_versions( mi).vars( vi).value = 'spinup_GRL/phase4_holocene/hybrid_Coulombreg_PMIP3ens_20km/retreat_mask_refice.nc';
  
end
function RCM_forcings   = list_RCM_forcings

  rfi = 0;
  
  % CMIP6 simulations downscaled with MARv3.9
  CMIP6_MARv3p9 = {...
    'ACCESS1.3-rcp85',...
    'CESM2-ssp585',...
    'CNRM-CM6-ssp126',...
    'CNRM-CM6-ssp585',...
    'CNRM-ESM2-ssp585',...
    'CSIRO-Mk3.6-rcp85',...
    'HadGEM2-ES-rcp85',...
    'IPSL-CM5-MR-rcp85',...
    'MIROC5-rcp26',...
    'MIROC5-rcp85',...
    'NorESM1-rcp85',...
    'UKESM1-CM6-ssp585'};
  
  % CMIP6 simulations downscaled with MARv3.12
  CMIP6_MARv3p12 = {...
    'ACCESS1.3-rcp85',...
    'CESM2-ssp585',...
    'CNRM-CM6-ssp585',...
    'CNRM-ESM2-ssp585',...
    'MPI-ESM1-2-HR-ssp126',...
    'MPI-ESM1-2-HR-ssp245',...
    'MPI-ESM1-2-HR-ssp585',...
    'UKESM1-0-LL-ssp585'};
  
  % CMIP6 simulations downscaled with RACMO2.3p2
  CMIP6_RACMO2p3p2 = {...
    };
  
  % Merge
  RCMs(1).name = 'MARv3.9';
  RCMs(1).simulations = CMIP6_MARv3p9;
  RCMs(2).name = 'MARv3.12';
  RCMs(2).simulations = CMIP6_MARv3p12;
  RCMs(3).name = 'RACMO2.3p2';
  RCMs(3).simulations = CMIP6_RACMO2p3p2;
  
  for rcmi = 1: length( RCMs)
    
    RCM_name = RCMs( rcmi).name;
    CMIP6_sims = RCMs( rcmi).simulations;
  
    for cmip6i = 1: length( CMIP6_sims)

      rfi = rfi+1;
      RCM_forcings( rfi).name            = [CMIP6_sims{ cmip6i} '_' RCM_name]; % 'CSIRO-Mk3.6-rcp85_MARv3.9';
      RCM_forcings( rfi).retreatmaskname = [RCM_name '_' CMIP6_sims{ cmip6i}]; % 'MARv3.9_CSIRO-Mk3.6-rcp85';

      vi = 0;

      vi = vi+1;
      RCM_forcings( rfi).vars( vi).name  = 'ISMIP_forcing_foldername_aSMB_config';
      RCM_forcings( rfi).vars( vi).value = ['/home/berends/PROTECT/Greenland/data/RCM_forcing/' RCM_name '/aSMB_'   RCM_forcings( rfi).name];
      vi = vi+1;
      RCM_forcings( rfi).vars( vi).name  = 'ISMIP_forcing_foldername_dSMBdz_config';
      RCM_forcings( rfi).vars( vi).value = ['/home/berends/PROTECT/Greenland/data/RCM_forcing/' RCM_name '/dSMBdz_' RCM_forcings( rfi).name];
      vi = vi+1;
      RCM_forcings( rfi).vars( vi).name  = 'ISMIP_forcing_foldername_aST_config';
      RCM_forcings( rfi).vars( vi).value = ['/home/berends/PROTECT/Greenland/data/RCM_forcing/' RCM_name '/aST_'    RCM_forcings( rfi).name];
      vi = vi+1;
      RCM_forcings( rfi).vars( vi).name  = 'ISMIP_forcing_foldername_dSTdz_config';
      RCM_forcings( rfi).vars( vi).value = ['/home/berends/PROTECT/Greenland/data/RCM_forcing/' RCM_name '/dSTdz_'  RCM_forcings( rfi).name];
      vi = vi+1;
      RCM_forcings( rfi).vars( vi).name  = 'ISMIP_forcing_basefilename_aSMB_config';
      RCM_forcings( rfi).vars( vi).value = ['aSMB_' RCM_name '-yearly-' CMIP6_sims{ cmip6i} '-'];
      vi = vi+1;
      RCM_forcings( rfi).vars( vi).name  = 'ISMIP_forcing_basefilename_dSMBdz_config';
      RCM_forcings( rfi).vars( vi).value = strrep( RCM_forcings( rfi).vars( vi-1).value,'aSMB','dSMBdz');
      vi = vi+1;
      RCM_forcings( rfi).vars( vi).name  = 'ISMIP_forcing_basefilename_aST_config';
      RCM_forcings( rfi).vars( vi).value = strrep( RCM_forcings( rfi).vars( vi-1).value,'dSMBdz','aST');
      vi = vi+1;
      RCM_forcings( rfi).vars( vi).name  = 'ISMIP_forcing_basefilename_dSTdz_config';
      RCM_forcings( rfi).vars( vi).value = strrep( RCM_forcings( rfi).vars( vi-1).value,'aST','dSTdz');

    end
  end

end