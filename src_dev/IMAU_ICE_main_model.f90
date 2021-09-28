MODULE IMAU_ICE_main_model

  ! Contains all the routines for initialising and running the IMAU-ICE regional ice-sheet model.

  USE mpi
  USE configuration_module,            ONLY: dp, C           
  USE parallel_module,                 ONLY: par, sync, cerr, ierr, &
                                             allocate_shared_int_0D, allocate_shared_dp_0D, &
                                             allocate_shared_int_1D, allocate_shared_dp_1D, &
                                             allocate_shared_int_2D, allocate_shared_dp_2D, &
                                             allocate_shared_int_3D, allocate_shared_dp_3D, &
                                             allocate_shared_bool_0D, &
                                             deallocate_shared, partition_list
  USE data_types_module,               ONLY: type_model_region, type_ice_model, type_PD_data_fields, type_init_data_fields, &
                                             type_climate_model, type_climate_matrix, type_SMB_model, type_BMB_model, type_forcing_data, type_grid
  USE utilities_module,                ONLY: check_for_NaN_dp_1D,  check_for_NaN_dp_2D,  check_for_NaN_dp_3D, &
                                             check_for_NaN_int_1D, check_for_NaN_int_2D, check_for_NaN_int_3D, &
                                             inverse_oblique_sg_projection, surface_elevation
  USE parameters_module,               ONLY: seawater_density, ice_density, T0
  USE reference_fields_module,         ONLY: initialise_PD_data_fields, initialise_init_data_fields, map_PD_data_to_model_grid, map_init_data_to_model_grid, &
                                             initialise_topo_data_fields, map_topo_data_to_model_grid
  USE netcdf_module,                   ONLY: debug, write_to_debug_file, initialise_debug_fields, create_debug_file, associate_debug_fields, &
                                             create_restart_file, create_help_fields_file, write_to_restart_file, write_to_help_fields_file, &
                                             create_regional_scalar_output_file
  USE forcing_module,                  ONLY: forcing
  USE general_ice_model_data_module,   ONLY: update_general_ice_model_data
  USE ice_velocity_module,             ONLY: solve_DIVA
  USE ice_dynamics_module,             ONLY: initialise_ice_model,       run_ice_model
  USE calving_module,                  ONLY: apply_calving_law
  USE thermodynamics_module,           ONLY: initialise_ice_temperature, run_thermo_model
  USE climate_module,                  ONLY: initialise_climate_model,   run_climate_model
  USE SMB_module,                      ONLY: initialise_SMB_model,       run_SMB_model
  USE BMB_module,                      ONLY: initialise_BMB_model,       run_BMB_model
  USE isotopes_module,                 ONLY: initialise_isotopes_model,  run_isotopes_model
  USE bedrock_ELRA_module,             ONLY: initialise_ELRA_model,      run_ELRA_model
  USE SELEN_main_module,               ONLY: apply_SELEN_bed_geoid_deformation_rates
  USE scalar_data_output_module,       ONLY: write_regional_scalar_data

  IMPLICIT NONE

CONTAINS

  SUBROUTINE run_model( region, t_end)
    ! Run the model until t_end (usually a 100 years further)
  
    IMPLICIT NONE  
    
    ! In/output variables:
    TYPE(type_model_region),    INTENT(INOUT)     :: region
    REAL(dp),                   INTENT(IN)        :: t_end
    
    ! Local variables:
    REAL(dp)                                      :: tstart, tstop, t1, t2
    INTEGER                                       :: it
    
    IF (par%master) WRITE(0,*) ''
    IF (par%master) WRITE(0,'(A,A3,A,A13,A,F9.3,A,F9.3,A)') '  Running model region ', region%name, ' (', TRIM(region%long_name), & 
                                                            ') from t = ', region%time/1000._dp, ' to t = ', t_end/1000._dp, ' kyr'
    
    ! Set the intermediary pointers in "debug" to this region's debug data fields
    CALL associate_debug_fields(  region)
               
    ! Computation time tracking
    region%tcomp_total          = 0._dp
    region%tcomp_ice            = 0._dp
    region%tcomp_thermo         = 0._dp
    region%tcomp_climate        = 0._dp
    region%tcomp_GIA            = 0._dp
    
    tstart = MPI_WTIME()
                            
  ! ====================================
  ! ===== The main model time loop =====
  ! ====================================
    
    it = 0
    DO WHILE (region%time < t_end)
      it = it + 1
      
    ! GIA
    ! ===
    
      t1 = MPI_WTIME()
      IF     (C%choice_GIA_model == 'none') THEN
        ! Nothing to be done
      ELSEIF (C%choice_GIA_model == 'ELRA') THEN
        CALL run_ELRA_model( region)
      ELSEIF (C%choice_GIA_model == 'SELEN') THEN
        CALL apply_SELEN_bed_geoid_deformation_rates( region)
      ELSE
        IF (par%master) WRITE(0,*) '  ERROR - choice_GIA_model "', C%choice_GIA_model, '" not implemented in run_model!'
        CALL MPI_ABORT( MPI_COMM_WORLD, cerr, ierr)
      END IF
      t2 = MPI_WTIME()
      region%tcomp_GIA = region%tcomp_GIA + t2 - t1
      
    ! Ice dynamics
    ! ============
    
      ! Calculate ice velocities and the resulting change in ice geometry
      ! NOTE: geometry is not updated yet; this happens at the end of the time loop
      t1 = MPI_WTIME()
      CALL run_ice_model( region, t_end)
      t2 = MPI_WTIME()
      region%tcomp_ice = region%tcomp_ice + t2 - t1
      
    ! Climate , SMB and BMB
    ! =====================
    
      t1 = MPI_WTIME()
            
      ! Run the climate model
      IF (region%do_climate) THEN
        CALL run_climate_model( region%grid, region%ice, region%SMB, region%climate, region%name, region%time)
      END IF
    
      ! Run the SMB model
      IF (region%do_SMB) THEN
        CALL run_SMB_model( region%grid, region%ice, region%climate%applied, region%time, region%SMB, region%mask_noice)
      END IF
    
      ! Run the BMB model
      IF (region%do_BMB) THEN
        CALL run_BMB_model( region%grid, region%ice, region%climate%applied, region%BMB, region%name)
      END IF
      
      t2 = MPI_WTIME()
      region%tcomp_climate = region%tcomp_climate + t2 - t1
      
    ! Thermodynamics
    ! ==============
    
      t1 = MPI_WTIME()
      CALL run_thermo_model( region%grid, region%ice, region%climate%applied, region%SMB, do_solve_heat_equation = region%do_thermo)
      t2 = MPI_WTIME()
      region%tcomp_thermo = region%tcomp_thermo + t2 - t1
      
    ! Isotopes
    ! ========
    
      CALL run_isotopes_model( region)
      
    ! Time step and output
    ! ====================
                            
      ! Write output
      IF (region%do_output) THEN
        IF (par%master) CALL write_to_restart_file(     region, forcing)
        IF (par%master) CALL write_to_help_fields_file( region)
        CALL sync
      END IF
      
      ! Update ice geometry and advance region time
      region%ice%Hi_a( :,region%grid%i1:region%grid%i2) = region%ice%Hi_tplusdt_a( :,region%grid%i1:region%grid%i2)
      CALL update_general_ice_model_data( region%grid, region%ice, region%time)
      CALL apply_calving_law( region%grid, region%ice, region%PD)
      CALL update_general_ice_model_data( region%grid, region%ice, region%time)
      IF (par%master) region%time = region%time + region%dt
      CALL sync
      
      ! DENK DROM
      !region%time = t_end
    
    END DO ! DO WHILE (region%time < t_end)
                            
  ! ===========================================
  ! ===== End of the main model time loop =====
  ! ===========================================
    
    ! Write to NetCDF output one last time at the end of the simulation
    IF (region%time == C%end_time_of_run) THEN
      IF (par%master) CALL write_to_restart_file(     region, forcing)
      IF (par%master) CALL write_to_help_fields_file( region)
    END IF 
    
    ! Determine total ice sheet area, volume, volume-above-flotation and GMSL contribution,
    ! used for writing to text output and in the inverse routine
    CALL calculate_icesheet_volume_and_area(region)
    
    tstop = MPI_WTIME()
    region%tcomp_total = tstop - tstart
    
    ! Write to text output
    CALL write_regional_scalar_data( region, region%time)
    
  END SUBROUTINE run_model
  
  ! Initialise the entire model region - read initial and PD data, initialise the ice dynamics, climate and SMB sub models
  SUBROUTINE initialise_model( region, name, matrix)
  
    USE climate_module, ONLY: map_glob_to_grid_2D
  
    IMPLICIT NONE  
    
    ! In/output variables:
    TYPE(type_model_region),         INTENT(INOUT)     :: region
    CHARACTER(LEN=3),                INTENT(IN)        :: name
    TYPE(type_climate_matrix),       INTENT(IN)        :: matrix
    
    ! Local variables:
    CHARACTER(LEN=20)                                  :: short_filename
    INTEGER                                            :: n
              
    ! Basic initialisation
    ! ====================
    
    ! Region name
    region%name      = name    
    IF     (region%name == 'NAM') THEN
      region%long_name = 'North America'
    ELSEIF (region%name == 'EAS') THEN
      region%long_name = 'Eurasia'
    ELSEIF (region%name == 'GRL') THEN
      region%long_name = 'Greenland'
    ELSEIF (region%name == 'ANT') THEN
      region%long_name = 'Antarctica'
    END IF
    
    IF (par%master) WRITE(0,*) ''
    IF (par%master) WRITE(0,*) ' Initialising model region ', region%name, ' (', TRIM(region%long_name), ')...'
    
    ! Timers and time steps
    ! =====================
    
    CALL allocate_shared_dp_0D(   region%time,             region%wtime            )
    CALL allocate_shared_dp_0D(   region%dt,               region%wdt              )
    CALL allocate_shared_dp_0D(   region%dt_prev,          region%wdt_prev         )
    CALL allocate_shared_dp_0D(   region%dt_crit_SIA,      region%wdt_crit_SIA     )
    CALL allocate_shared_dp_0D(   region%dt_crit_SSA,      region%wdt_crit_SSA     )
    CALL allocate_shared_dp_0D(   region%dt_crit_ice,      region%wdt_crit_ice     )
    CALL allocate_shared_dp_0D(   region%dt_crit_ice_prev, region%wdt_crit_ice_prev)
    
    CALL allocate_shared_dp_0D(   region%t_last_SIA,       region%wt_last_SIA      )
    CALL allocate_shared_dp_0D(   region%t_next_SIA,       region%wt_next_SIA      )
    CALL allocate_shared_bool_0D( region%do_SIA,           region%wdo_SIA          )
    
    CALL allocate_shared_dp_0D(   region%t_last_SSA,       region%wt_last_SSA      )
    CALL allocate_shared_dp_0D(   region%t_next_SSA,       region%wt_next_SSA      )
    CALL allocate_shared_bool_0D( region%do_SSA,           region%wdo_SSA          )
    
    CALL allocate_shared_dp_0D(   region%t_last_DIVA,      region%wt_last_DIVA     )
    CALL allocate_shared_dp_0D(   region%t_next_DIVA,      region%wt_next_DIVA     )
    CALL allocate_shared_bool_0D( region%do_DIVA,          region%wdo_DIVA         )
    
    CALL allocate_shared_dp_0D(   region%t_last_thermo,    region%wt_last_thermo   )
    CALL allocate_shared_dp_0D(   region%t_next_thermo,    region%wt_next_thermo   )
    CALL allocate_shared_bool_0D( region%do_thermo,        region%wdo_thermo       )
    
    CALL allocate_shared_dp_0D(   region%t_last_output,    region%wt_last_output   )
    CALL allocate_shared_dp_0D(   region%t_next_output,    region%wt_next_output   )
    CALL allocate_shared_bool_0D( region%do_output,        region%wdo_output       )
    
    CALL allocate_shared_dp_0D(   region%t_last_climate,   region%wt_last_climate  )
    CALL allocate_shared_dp_0D(   region%t_next_climate,   region%wt_next_climate  )
    CALL allocate_shared_bool_0D( region%do_climate,       region%wdo_climate      )
    
    CALL allocate_shared_dp_0D(   region%t_last_SMB,       region%wt_last_SMB      )
    CALL allocate_shared_dp_0D(   region%t_next_SMB,       region%wt_next_SMB      )
    CALL allocate_shared_bool_0D( region%do_SMB,           region%wdo_SMB          )
    
    CALL allocate_shared_dp_0D(   region%t_last_BMB,       region%wt_last_BMB      )
    CALL allocate_shared_dp_0D(   region%t_next_BMB,       region%wt_next_BMB      )
    CALL allocate_shared_bool_0D( region%do_BMB,           region%wdo_BMB          )
    
    CALL allocate_shared_dp_0D(   region%t_last_ELRA,      region%wt_last_ELRA     )
    CALL allocate_shared_dp_0D(   region%t_next_ELRA,      region%wt_next_ELRA     )
    CALL allocate_shared_bool_0D( region%do_ELRA,          region%wdo_ELRA         ) 
    
    IF (par%master) THEN
      region%time           = C%start_time_of_run
      region%dt             = C%dt_min
      region%dt_prev        = C%dt_min
      
      region%t_last_SIA     = C%start_time_of_run
      region%t_next_SIA     = C%start_time_of_run
      region%do_SIA         = .TRUE.
      
      region%t_last_SSA     = C%start_time_of_run
      region%t_next_SSA     = C%start_time_of_run
      region%do_SSA         = .TRUE.
      
      region%t_last_DIVA    = C%start_time_of_run
      region%t_next_DIVA    = C%start_time_of_run
      region%do_DIVA        = .TRUE.
      
      region%t_last_thermo  = C%start_time_of_run
      region%t_next_thermo  = C%start_time_of_run + C%dt_thermo
      region%do_thermo      = .FALSE.
      
      region%t_last_climate = C%start_time_of_run
      region%t_next_climate = C%start_time_of_run
      region%do_climate     = .TRUE.
      
      region%t_last_SMB     = C%start_time_of_run
      region%t_next_SMB     = C%start_time_of_run
      region%do_SMB         = .TRUE.
      
      region%t_last_BMB     = C%start_time_of_run
      region%t_next_BMB     = C%start_time_of_run
      region%do_BMB         = .TRUE.
      
      region%t_last_ELRA    = C%start_time_of_run
      region%t_next_ELRA    = C%start_time_of_run
      region%do_ELRA        = .TRUE.
      
      region%t_last_output  = C%start_time_of_run
      region%t_next_output  = C%start_time_of_run
      region%do_output      = .TRUE.
    END IF
    
    ! ===== Ice-sheet volume and area =====
    ! =====================================
    
    CALL allocate_shared_dp_0D( region%ice_area                     , region%wice_area                     )
    CALL allocate_shared_dp_0D( region%ice_volume                   , region%wice_volume                   )
    CALL allocate_shared_dp_0D( region%ice_volume_PD                , region%wice_volume_PD                )
    CALL allocate_shared_dp_0D( region%ice_volume_above_flotation   , region%wice_volume_above_flotation   )
    CALL allocate_shared_dp_0D( region%ice_volume_above_flotation_PD, region%wice_volume_above_flotation_PD)
    
    ! ===== Regionally integrated SMB components =====
    ! ================================================
    
    CALL allocate_shared_dp_0D( region%int_T2m                      , region%wint_T2m                      )
    CALL allocate_shared_dp_0D( region%int_snowfall                 , region%wint_snowfall                 )
    CALL allocate_shared_dp_0D( region%int_rainfall                 , region%wint_rainfall                 )
    CALL allocate_shared_dp_0D( region%int_melt                     , region%wint_melt                     )
    CALL allocate_shared_dp_0D( region%int_refreezing               , region%wint_refreezing               )
    CALL allocate_shared_dp_0D( region%int_runoff                   , region%wint_runoff                   )
    CALL allocate_shared_dp_0D( region%int_SMB                      , region%wint_SMB                      )
    CALL allocate_shared_dp_0D( region%int_BMB                      , region%wint_BMB                      )
    CALL allocate_shared_dp_0D( region%int_MB                       , region%wint_MB                       )
    
    ! ===== Englacial isotope content =====
    ! =====================================
    
    CALL allocate_shared_dp_0D( region%GMSL_contribution            , region%wGMSL_contribution            )
    CALL allocate_shared_dp_0D( region%mean_isotope_content         , region%wmean_isotope_content         )
    CALL allocate_shared_dp_0D( region%mean_isotope_content_PD      , region%wmean_isotope_content_PD      )
    CALL allocate_shared_dp_0D( region%d18O_contribution            , region%wd18O_contribution            )
    CALL allocate_shared_dp_0D( region%d18O_contribution_PD         , region%wd18O_contribution_PD         )
    
    ! ===== PD, topo, and init reference data fields =====
    ! ====================================================
    
    CALL initialise_PD_data_fields(   region%PD,   region%name)
    CALL initialise_topo_data_fields( region%topo, region%PD, region%name)
    CALL initialise_init_data_fields( region%init, region%name)
    
    ! ===== Initialise this region's grid =====
    ! =========================================
    
    CALL initialise_model_grid( region)
    IF (par%master) WRITE (0,'(A,F5.2,A,I4,A,I4,A)') '   Initialised model grid at ', region%grid%dx/1000._dp, ' km resolution: [', region%grid%nx, ' x ', region%grid%ny, '] pixels'
    
    ! ===== Initialise dummy fields for debugging
    ! ===========================================
    
    CALL initialise_debug_fields( region)

    ! ===== Map PD, topo, and init data to the model grid =====
    ! =========================================================
    
    CALL map_PD_data_to_model_grid(   region%grid, region%PD  )
    CALL map_topo_data_to_model_grid( region%grid, region%topo)
    CALL map_init_data_to_model_grid( region%grid, region%init)
    
    ! Smooth input geometry (bed and ice)
    IF (C%do_smooth_geometry) THEN
      CALL smooth_model_geometry( region%grid, region%PD%Hi,   region%PD%Hb  )
      CALL smooth_model_geometry( region%grid, region%init%Hi, region%init%Hb)
    END IF
    
    CALL calculate_PD_sealevel_contribution( region)
    
    ! ===== Define mask where no ice is allowed to form (i.e. Greenland in NAM and EAS, Ellesmere Island in GRL)
    ! ==========================================================================================================
    
    CALL initialise_mask_noice( region)
       
    ! ===== Output files =====
    ! ========================

    ! Set output filenames for this region
    short_filename = 'restart_NAM.nc'
    short_filename(9:11) = region%name
    DO n = 1, 256
      region%restart%filename(n:n) = ' '
    END DO
    region%restart%filename = TRIM(C%output_dir)//TRIM(short_filename)

    short_filename = 'help_fields_NAM.nc'
    short_filename(13:15) = region%name
    DO n = 1, 256
      region%help_fields%filename(n:n) = ' '
    END DO
    region%help_fields%filename = TRIM(C%output_dir)//TRIM(short_filename)

    ! Let the Master create the (empty) NetCDF files
    IF (par%master)                             CALL create_restart_file(     region, forcing)
    IF (par%master)                             CALL create_help_fields_file( region)
    IF (par%master .AND. C%do_write_debug_data) CALL create_debug_file(       region)
    CALL associate_debug_fields(  region)
        
    ! ===== The climate model =====
    ! =============================
    
    CALL initialise_climate_model( region%grid, region%climate, matrix, region%PD, region%name, region%mask_noice)    
    
    ! ===== The SMB model =====
    ! =========================    
    
    CALL initialise_SMB_model( region%grid, region%init, region%SMB, region%name)     
    
    ! ===== The BMB model =====
    ! =========================    
    
    CALL initialise_BMB_model( region%grid, region%BMB, region%name)       
  
    ! ===== The ice dynamics model
    ! ============================
    
    CALL initialise_ice_model( region%grid, region%ice, region%PD, region%init)
    
    ! Geothermal heat flux
    IF     (C%choice_geothermal_heat_flux == 'constant') THEN
      region%ice%GHF_a( :,region%grid%i1:region%grid%i2) = C%constant_geothermal_heat_flux
    ELSEIF (C%choice_geothermal_heat_flux == 'spatial') THEN
      CALL map_glob_to_grid_2D( forcing%ghf_nlat, forcing%ghf_nlon, forcing%ghf_lat, forcing%ghf_lon, region%grid, forcing%ghf_ghf, region%ice%GHF_a)
    ELSE
      IF (par%master) WRITE(0,*) '  ERROR: choice_geothermal_heat_flux "', TRIM(C%choice_geothermal_heat_flux), '" not implemented in initialise_model!'
      CALL MPI_ABORT( MPI_COMM_WORLD, cerr, ierr)
    END IF
    
    ! Run the climate, BMB and SMB models once, to get the correct surface temperature field for the ice temperature initialisation,
    ! and so that all the relevant fields already have sensible values in the first time frame of the output file.
    CALL update_general_ice_model_data( region%grid, region%ice, region%time)
    CALL run_climate_model(             region%grid, region%ice, region%SMB, region%climate, region%name, C%start_time_of_run)
    CALL run_SMB_model(                 region%grid, region%ice, region%climate%applied, C%start_time_of_run, region%SMB, region%mask_noice)
    CALL run_BMB_model(                 region%grid, region%ice, region%climate%applied, region%BMB, region%name)
    
    ! Initialise the ice temperature profile
    CALL initialise_ice_temperature( region%grid, region%ice, region%climate%applied, region%init, region%SMB)
    
    ! Calculate physical properties again, now with the initialised temperature profile, determine the masks and slopes
    CALL update_general_ice_model_data( region%grid, region%ice, C%start_time_of_run)
    
    ! Calculate ice sheet metadata (volume, area, GMSL contribution) for writing to the first line of the output file
    CALL calculate_icesheet_volume_and_area(region)
    
    ! If we're running with choice_ice_dynamics == "none", calculate a velocity field
    ! once during initialisation (so that the thermodynamics are solved correctly)
    IF (C%choice_ice_dynamics == 'none') THEN
      C%choice_ice_dynamics = 'DIVA'
      CALL solve_DIVA( region%grid, region%ice)
      C%choice_ice_dynamics = 'none'
    END IF
    
    ! ===== The isotopes model =====
    ! ==============================
   
    CALL initialise_isotopes_model( region)
    
    ! ===== The GIA model =====
    ! =========================
    
    IF     (C%choice_GIA_model == 'none') THEN
      ! Nothing to be done
    ELSEIF (C%choice_GIA_model == 'ELRA') THEN
      CALL initialise_GIA_model_grid( region)
      CALL initialise_ELRA_model( region%grid, region%grid_GIA, region%ice, region%topo)
    ELSEIF (C%choice_GIA_model == 'SELEN') THEN
      CALL initialise_GIA_model_grid( region)
    ELSE
      WRITE(0,*) '  ERROR - choice_GIA_model "', C%choice_GIA_model, '" not implemented in initialise_model!'
      CALL MPI_ABORT( MPI_COMM_WORLD, cerr, ierr)
    END IF
    
    ! ===== Computation times =====
    ! =============================
    
    CALL allocate_shared_dp_0D( region%tcomp_total   , region%wtcomp_total   )
    CALL allocate_shared_dp_0D( region%tcomp_ice     , region%wtcomp_ice     )
    CALL allocate_shared_dp_0D( region%tcomp_thermo  , region%wtcomp_thermo  )
    CALL allocate_shared_dp_0D( region%tcomp_climate , region%wtcomp_climate )
    CALL allocate_shared_dp_0D( region%tcomp_GIA     , region%wtcomp_GIA     )
    
    ! ===== Scalar output (regionally integrated ice volume, SMB components, etc.)
    ! ============================================================================
    
    CALL create_regional_scalar_output_file( region)
    CALL write_regional_scalar_data(         region, C%start_time_of_run)
    CALL sync
    
    IF (par%master) WRITE (0,*) ' Finished initialising model region ', region%name, '.'
    
  END SUBROUTINE initialise_model
  SUBROUTINE initialise_model_grid( region)
  
    IMPLICIT NONE  
    
    ! In/output variables:
    TYPE(type_model_region),         INTENT(INOUT)     :: region
    
    ! Local variables:
    INTEGER                                            :: nsx, nsy, i, j
    
    nsx = 0
    nsy = 0
    
    ! Allocate shared memory
    CALL allocate_shared_int_0D( region%grid%nx,           region%grid%wnx          )
    CALL allocate_shared_int_0D( region%grid%ny,           region%grid%wny          )
    CALL allocate_shared_dp_0D(  region%grid%dx,           region%grid%wdx          )
    CALL allocate_shared_dp_0D(  region%grid%xmin,         region%grid%wxmin        )
    CALL allocate_shared_dp_0D(  region%grid%xmax,         region%grid%wxmax        )
    CALL allocate_shared_dp_0D(  region%grid%ymin,         region%grid%wymin        )
    CALL allocate_shared_dp_0D(  region%grid%ymax,         region%grid%wymax        )
    CALL allocate_shared_dp_0D(  region%grid%lambda_M,     region%grid%wlambda_M    )
    CALL allocate_shared_dp_0D(  region%grid%phi_M,        region%grid%wphi_M       )
    CALL allocate_shared_dp_0D(  region%grid%alpha_stereo, region%grid%walpha_stereo)
    
    ! Let the Master do the work
    IF (par%master) THEN
  
      ! Resolution and projection parameters for this region are determined from the config
      IF     (region%name == 'NAM') THEN
        region%grid%dx           = C%dx_NAM
        region%grid%lambda_M     = C%lambda_M_NAM
        region%grid%phi_M        = C%phi_M_NAM
        region%grid%alpha_stereo = C%alpha_stereo_NAM
      ELSEIF (region%name == 'EAS') THEN
        region%grid%dx           = C%dx_EAS
        region%grid%lambda_M     = C%lambda_M_EAS
        region%grid%phi_M        = C%phi_M_EAS
        region%grid%alpha_stereo = C%alpha_stereo_EAS
      ELSEIF (region%name == 'GRL') THEN
        region%grid%dx           = C%dx_GRL
        region%grid%lambda_M     = C%lambda_M_GRL
        region%grid%phi_M        = C%phi_M_GRL
        region%grid%alpha_stereo = C%alpha_stereo_GRL
      ELSEIF (region%name == 'ANT') THEN
        region%grid%dx           = C%dx_ANT
        region%grid%lambda_M     = C%lambda_M_ANT
        region%grid%phi_M        = C%phi_M_ANT
        region%grid%alpha_stereo = C%alpha_stereo_ANT
      END IF
      
      ! Determine the number of grid cells we can fit in this domain (based on specified resolution, and the domain covered by the initial file)
      nsx = FLOOR( (1 / region%grid%dx) * (MAXVAL(region%init%x) + (region%init%x(2)-region%init%x(1))/2) - 1)
      nsy = FLOOR( (1 / region%grid%dx) * (MAXVAL(region%init%y) + (region%init%y(2)-region%init%y(1))/2) - 1)
      
      IF (C%do_benchmark_experiment .AND. C%choice_benchmark_experiment == 'SSA_icestream') nsx = 3
      
      region%grid%nx = 1 + 2*nsx
      region%grid%ny = 1 + 2*nsy
    
      ! If doing a restart from a previous run with the same resolution, just take that grid
      ! (due to rounding, off-by-one errors are nasty here)
      IF (C%is_restart) THEN
        IF (ABS( 1._dp - region%grid%dx / ABS(region%init%x(2) - region%init%x(1))) < 1E-4_dp) THEN
          region%grid%nx = region%init%nx
          region%grid%ny = region%init%ny
          nsx = INT((REAL(region%grid%nx,dp) - 1._dp) / 2._dp)
          nsy = INT((REAL(region%grid%ny,dp) - 1._dp) / 2._dp)
        END IF
      END IF
      
      ! If prescribed model resolution is the same as the initial file resolution, just use the initial file frid
      IF (ABS(1._dp - (region%grid%dx / (region%init%x(2) - region%init%x(1)))) < 1E-4_dp) THEN
        region%grid%nx = region%init%nx
        region%grid%ny = region%init%ny
      END IF
    
    END IF ! IF (par%master) THEN
    CALL sync
    
    ! Assign range to each processor
    CALL partition_list( region%grid%nx, par%i, par%n, region%grid%i1, region%grid%i2)
    CALL partition_list( region%grid%ny, par%i, par%n, region%grid%j1, region%grid%j2)
    
    ! Allocate shared memory for x and y
    CALL allocate_shared_dp_1D( region%grid%nx, region%grid%x, region%grid%wx)
    CALL allocate_shared_dp_1D( region%grid%ny, region%grid%y, region%grid%wy)
    
    ! Fill in x and y
    IF (par%master) THEN
      DO i = 1, region%grid%nx
        region%grid%x( i) = -nsx*region%grid%dx + (i-1)*region%grid%dx
      END DO
      DO j = 1, region%grid%ny
        region%grid%y( j) = -nsy*region%grid%dx + (j-1)*region%grid%dx
      END DO
      
      region%grid%xmin = MINVAL(region%grid%x)
      region%grid%xmax = MAXVAL(region%grid%x)
      region%grid%ymin = MINVAL(region%grid%y)
      region%grid%ymax = MAXVAL(region%grid%y)
    END IF ! IF (par%master) THEN
    CALL sync
    
    ! Lat,lon coordinates
    CALL allocate_shared_dp_2D( region%grid%ny, region%grid%nx, region%grid%lat, region%grid%wlat)
    CALL allocate_shared_dp_2D( region%grid%ny, region%grid%nx, region%grid%lon, region%grid%wlon)
    
    DO i = region%grid%i1, region%grid%i2
    DO j = 1, region%grid%ny
      CALL inverse_oblique_sg_projection( region%grid%x( i), region%grid%y( j), region%grid%lambda_M, region%grid%phi_M, region%grid%alpha_stereo, region%grid%lon( j,i), region%grid%lat( j,i))
    END DO
    END DO
    CALL sync
    
  END SUBROUTINE initialise_model_grid
  SUBROUTINE initialise_GIA_model_grid( region)
  
    IMPLICIT NONE  
    
    ! In/output variables:
    TYPE(type_model_region),         INTENT(INOUT)     :: region
    
    ! Local variables:
    INTEGER                                            :: nsx, nsy, i, j
    
    nsx = 0
    nsy = 0
    
    ! Allocate shared memory
    CALL allocate_shared_int_0D( region%grid_GIA%nx,           region%grid_GIA%wnx          )
    CALL allocate_shared_int_0D( region%grid_GIA%ny,           region%grid_GIA%wny          )
    CALL allocate_shared_dp_0D(  region%grid_GIA%dx,           region%grid_GIA%wdx          )
    CALL allocate_shared_dp_0D(  region%grid_GIA%xmin,         region%grid_GIA%wxmin        )
    CALL allocate_shared_dp_0D(  region%grid_GIA%xmax,         region%grid_GIA%wxmax        )
    CALL allocate_shared_dp_0D(  region%grid_GIA%ymin,         region%grid_GIA%wymin        )
    CALL allocate_shared_dp_0D(  region%grid_GIA%ymax,         region%grid_GIA%wymax        )
    CALL allocate_shared_dp_0D(  region%grid_GIA%lambda_M,     region%grid_GIA%wlambda_M    )
    CALL allocate_shared_dp_0D(  region%grid_GIA%phi_M,        region%grid_GIA%wphi_M       )
    CALL allocate_shared_dp_0D(  region%grid_GIA%alpha_stereo, region%grid_GIA%walpha_stereo)
    
    ! Let the Master do the work
    IF (par%master) THEN
  
      ! Resolution and projection parameters for this region are determined from the config
      region%grid_GIA%dx           = C%dx_GIA
      IF     (region%name == 'NAM') THEN
        region%grid_GIA%lambda_M     = C%lambda_M_NAM
        region%grid_GIA%phi_M        = C%phi_M_NAM
        region%grid_GIA%alpha_stereo = C%alpha_stereo_NAM
      ELSEIF (region%name == 'EAS') THEN
        region%grid_GIA%lambda_M     = C%lambda_M_EAS
        region%grid_GIA%phi_M        = C%phi_M_EAS
        region%grid_GIA%alpha_stereo = C%alpha_stereo_EAS
      ELSEIF (region%name == 'GRL') THEN
        region%grid_GIA%lambda_M     = C%lambda_M_GRL
        region%grid_GIA%phi_M        = C%phi_M_GRL
        region%grid_GIA%alpha_stereo = C%alpha_stereo_GRL
      ELSEIF (region%name == 'ANT') THEN
        region%grid_GIA%lambda_M     = C%lambda_M_ANT
        region%grid_GIA%phi_M        = C%phi_M_ANT
        region%grid_GIA%alpha_stereo = C%alpha_stereo_ANT
      END IF
      
      ! Determine the number of grid cells we can fit in this domain (based on specified resolution, and the domain covered by the initial file)
      nsx = FLOOR( (1 / region%grid_GIA%dx) * (MAXVAL(region%init%x) + (region%init%x(2)-region%init%x(1))/2) + 1)
      nsy = FLOOR( (1 / region%grid_GIA%dx) * (MAXVAL(region%init%y) + (region%init%y(2)-region%init%y(1))/2) + 1)
      
      region%grid_GIA%nx = 1 + 2*nsx
      region%grid_GIA%ny = 1 + 2*nsy
      
      ! If prescribed model resolution is the same as the initial file resolution, just use the initial file frid
      IF (ABS(1._dp - (region%grid_GIA%dx / (region%init%x(2) - region%init%x(1)))) < 1E-4_dp) THEN
        region%grid_GIA%nx = region%init%nx
        region%grid_GIA%ny = region%init%ny
      END IF
    
    END IF ! IF (par%master) THEN
    CALL sync
     
    ! Assign range to each processor
    CALL partition_list( region%grid_GIA%nx, par%i, par%n, region%grid_GIA%i1, region%grid_GIA%i2)
    CALL partition_list( region%grid_GIA%ny, par%i, par%n, region%grid_GIA%j1, region%grid_GIA%j2)
    
    ! Allocate shared memory for x and y
    CALL allocate_shared_dp_1D( region%grid_GIA%nx, region%grid_GIA%x, region%grid_GIA%wx)
    CALL allocate_shared_dp_1D( region%grid_GIA%ny, region%grid_GIA%y, region%grid_GIA%wy)
    
    ! Fill in x and y
    IF (par%master) THEN
      DO i = 1, region%grid_GIA%nx
        region%grid_GIA%x( i) = -nsx*region%grid_GIA%dx + (i-1)*region%grid_GIA%dx
      END DO
      DO j = 1, region%grid_GIA%ny
        region%grid_GIA%y( j) = -nsy*region%grid_GIA%dx + (j-1)*region%grid_GIA%dx
      END DO
      
      region%grid_GIA%xmin = MINVAL(region%grid_GIA%x)
      region%grid_GIA%xmax = MAXVAL(region%grid_GIA%x)
      region%grid_GIA%ymin = MINVAL(region%grid_GIA%y)
      region%grid_GIA%ymax = MAXVAL(region%grid_GIA%y)
    END IF ! IF (par%master) THEN
    CALL sync
    
    ! Lat,lon coordinates
    CALL allocate_shared_dp_2D( region%grid_GIA%ny, region%grid_GIA%nx, region%grid_GIA%lat, region%grid_GIA%wlat)
    CALL allocate_shared_dp_2D( region%grid_GIA%ny, region%grid_GIA%nx, region%grid_GIA%lon, region%grid_GIA%wlon)
    
    DO i = region%grid_GIA%i1, region%grid_GIA%i2
    DO j = 1, region%grid_GIA%ny
      CALL inverse_oblique_sg_projection( region%grid_GIA%x( i), region%grid_GIA%y( j), region%grid_GIA%lambda_M, region%grid_GIA%phi_M, region%grid_GIA%alpha_stereo, region%grid_GIA%lon( j,i), region%grid_GIA%lat( j,i))
    END DO
    END DO
    CALL sync
    
  END SUBROUTINE initialise_GIA_model_grid
  SUBROUTINE initialise_mask_noice( region)
    ! Mask a certain area where no ice is allowed to grow. This is used to "remove"
    ! Greenland from NAM and EAS, and Ellesmere Island from GRL.
  
    IMPLICIT NONE  
    
    ! In/output variables:
    TYPE(type_model_region),         INTENT(INOUT)     :: region
    
    ! Local variables:
    INTEGER                                            :: i,j
    REAL(dp), DIMENSION(2)                             :: pa, pb, pc, pd
    REAL(dp)                                           :: yl_ab, yl_bc, yl_cd
    
    ! Allocate shared memory
    CALL allocate_shared_int_2D( region%grid%ny, region%grid%nx, region%mask_noice, region%wmask_noice)
    
    region%mask_noice(    :,region%grid%i1:region%grid%i2) = 0
    
    ! Exceptions for benchmark experiments
    IF (C%do_benchmark_experiment) THEN
      IF (C%choice_benchmark_experiment == 'Halfar' .OR. &
          C%choice_benchmark_experiment == 'Bueler' .OR. &
          C%choice_benchmark_experiment == 'EISMINT_1' .OR. &
          C%choice_benchmark_experiment == 'EISMINT_2' .OR. &
          C%choice_benchmark_experiment == 'EISMINT_3' .OR. &
          C%choice_benchmark_experiment == 'EISMINT_4' .OR. &
          C%choice_benchmark_experiment == 'EISMINT_5' .OR. &
          C%choice_benchmark_experiment == 'EISMINT_6' .OR. &
          C%choice_benchmark_experiment == 'SSA_icestream' .OR. &
          C%choice_benchmark_experiment == 'MISMIP_mod' .OR. &
          C%choice_benchmark_experiment == 'ISMIP_HOM_A' .OR. &
          C%choice_benchmark_experiment == 'ISMIP_HOM_B' .OR. &
          C%choice_benchmark_experiment == 'ISMIP_HOM_C' .OR. &
          C%choice_benchmark_experiment == 'ISMIP_HOM_D' .OR. &
          C%choice_benchmark_experiment == 'ISMIP_HOM_E' .OR. &
          C%choice_benchmark_experiment == 'ISMIP_HOM_F') THEN
        RETURN
      ELSE
        IF (par%master) WRITE(0,*) '  ERROR: benchmark experiment "', TRIM(C%choice_benchmark_experiment), '" not implemented in initialise_mask_noice!'
        CALL MPI_ABORT( MPI_COMM_WORLD, cerr, ierr)
      END IF
    END IF ! IF (C%do_benchmark_experiment) THEN
    
    IF (region%name == 'NAM') THEN
      ! North America: remove Greenland
      
      pa = [ 490000._dp, 1530000._dp]
      pb = [2030000._dp,  570000._dp]
      
      DO i = region%grid%i1, region%grid%i2
        yl_ab = pa(2) + (region%grid%x(i) - pa(1))*(pb(2)-pa(2))/(pb(1)-pa(1))
        DO j = 1, region%grid%ny
          IF (region%grid%y(j) > yl_ab .AND. region%grid%x(i) > pa(1) .AND. region%grid%y(j) > pb(2)) THEN
            region%mask_noice( j,i) = 1
          END IF
        END DO
      END DO
      CALL sync
    
    ELSEIF (region%name == 'EAS') THEN
      ! Eurasia: remove Greenland
    
      pa = [-2900000._dp, 1300000._dp]
      pb = [-1895000._dp,  900000._dp]
      pc = [ -835000._dp, 1135000._dp]
      pd = [ -400000._dp, 1855000._dp]
      
      DO i = region%grid%i1, region%grid%i2
        yl_ab = pa(2) + (region%grid%x(i) - pa(1))*(pb(2)-pa(2))/(pb(1)-pa(1))
        yl_bc = pb(2) + (region%grid%x(i) - pb(1))*(pc(2)-pb(2))/(pc(1)-pb(1))
        yl_cd = pc(2) + (region%grid%x(i) - pc(1))*(pd(2)-pc(2))/(pd(1)-pc(1))
        DO j = 1, region%grid%ny
          IF ((region%grid%x(i) <  pa(1) .AND. region%grid%y(j) > pa(2)) .OR. &
              (region%grid%x(i) >= pa(1) .AND. region%grid%x(i) < pb(1) .AND. region%grid%y(j) > yl_ab) .OR. &
              (region%grid%x(i) >= pb(1) .AND. region%grid%x(i) < pc(1) .AND. region%grid%y(j) > yl_bc) .OR. &
              (region%grid%x(i) >= pc(1) .AND. region%grid%x(i) < pd(1) .AND. region%grid%y(j) > yl_cd)) THEN
            region%mask_noice( j,i) = 1
          END IF
        END DO
      END DO
      CALL sync
      
    ELSEIF (region%name == 'GRL') THEN
      ! Greenland: remove Ellesmere island
      
      pa = [-750000._dp,  900000._dp]
      pb = [-250000._dp, 1250000._dp]
      
      DO i = region%grid%i1, region%grid%i2
        yl_ab = pa(2) + (region%grid%x(i) - pa(1))*(pb(2)-pa(2))/(pb(1)-pa(1))
        DO j = 1, region%grid%ny
          IF (region%grid%y(j) > pa(2) .AND. region%grid%y(j) > yl_ab .AND. region%grid%x(i) < pb(1)) THEN
            region%mask_noice( j,i) = 1
          END IF
        END DO
      END DO
      CALL sync
      
    ELSEIF (region%name == 'ANT') THEN
      ! Antarctica: no changes needed
      
    END IF ! IF (region%name == 'NAM') THEN
    
  END SUBROUTINE initialise_mask_noice
  SUBROUTINE smooth_model_geometry( grid, Hi, Hb)
    ! Apply some light smoothing to the initial geometry to improve numerical stability
    
    USE utilities_module, ONLY: smooth_Gaussian_2D, is_floating

    IMPLICIT NONE

    ! Input variables:
    TYPE(type_grid),                     INTENT(IN)    :: grid
    REAL(dp), DIMENSION(:,:  ),          INTENT(INOUT) :: Hi, Hb
    
    ! Local variables:
    INTEGER                                            :: i,j
    REAL(dp), DIMENSION(:,:  ), POINTER                ::  Hs,  Hb_old,  dHb
    INTEGER                                            :: wHs, wHb_old, wdHb
    REAL(dp)                                           :: r_smooth
    
    ! Smooth with a 2-D Gaussian filter with a standard deviation of 1/2 grid cell
    r_smooth = grid%dx * C%r_smooth_geometry
    
    ! Allocate shared memory
    CALL allocate_shared_dp_2D( grid%ny, grid%nx, Hs,     wHs    )
    CALL allocate_shared_dp_2D( grid%ny, grid%nx, Hb_old, wHb_old)
    CALL allocate_shared_dp_2D( grid%ny, grid%nx, dHb,    wdHb   )
    
    ! Calculate original surface elevation
    DO i = grid%i1, grid%i2
    DO j = 1, grid%ny
      Hs( j,i) = surface_elevation( Hi( j,i), Hb( j,i), 0._dp)
    END DO
    END DO
    CALL sync
    
    ! Store the unsmoothed bed topography so we can determine the smoothing anomaly later
    Hb_old( :,grid%i1:grid%i2) = Hb( :,grid%i1:grid%i2)
    CALL sync
    
    ! Apply smoothing to the bed topography
    CALL smooth_Gaussian_2D( grid, Hb, r_smooth)
    
    DO i = grid%i1, grid%i2
    DO j = 1, grid%ny
      
      ! Calculate the smoothing anomaly
      dHb( j,i) = Hb( j,i) - Hb_old( j,i)
      
      IF (.NOT. is_floating( Hi( j,i), Hb( j,i), 0._dp) .AND. Hi( j,i) > 0._dp) THEN
      
        ! Correct the ice thickness so the ice surface remains unchanged (only relevant for floating ice)
        Hi( j,i) = Hi( j,i) - dHb( j,i)
      
        ! Don't allow negative ice thickness
        Hi( j,i) = MAX(0._dp, Hi( j,i))
      
        ! Correct the surface elevation for this if necessary
        Hs( j,i) = Hi( j,i) + MAX( 0._dp - ice_density / seawater_density * Hi( j,i), Hb( j,i))
        
      END IF
      
    END DO
    END DO
    CALL sync
    
    ! Clean up after yourself
    CALL deallocate_shared( wHb_old)
    CALL deallocate_shared( wdHb   )
    
  END SUBROUTINE smooth_model_geometry
  
  ! Calculate this region's ice sheet's volume and area
  SUBROUTINE calculate_icesheet_volume_and_area( region)
    
    USE parameters_module,           ONLY: ocean_area, seawater_density, ice_density
  
    IMPLICIT NONE  
    
    TYPE(type_model_region),    INTENT(INOUT)     :: region
    
    INTEGER                                       :: i,j
    REAL(dp)                                      :: ice_area, ice_volume, thickness_above_flotation, ice_volume_above_flotation
    
    ice_area                   = 0._dp
    ice_volume                 = 0._dp
    ice_volume_above_flotation = 0._dp
    
    ! Calculate ice area and volume for processor domain
    DO i = region%grid%i1, region%grid%i2
    DO j = 1, region%grid%ny
    
      IF (region%ice%mask_ice_a( j,i) == 1) THEN
        ice_volume = ice_volume + (region%ice%Hi_a(j,i) * region%grid%dx * region%grid%dx * ice_density / (seawater_density * ocean_area))
        ice_area   = ice_area   + region%grid%dx * region%grid%dx * 1.0E-06_dp ! [km^3]
    
        ! Thickness above flotation
        thickness_above_flotation = MAX(0._dp, region%ice%Hi_a( j,i) - MAX(0._dp, (region%ice%SL_a( j,i) - region%ice%Hb_a( j,i) * (seawater_density / ice_density))))
        
        ice_volume_above_flotation = ice_volume_above_flotation + thickness_above_flotation * region%grid%dx * region%grid%dx * ice_density / (seawater_density * ocean_area)
      END IF     
      
    END DO
    END DO
    CALL sync
    
    CALL MPI_REDUCE( ice_area,                   region%ice_area,                   1, MPI_DOUBLE_PRECISION, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
    CALL MPI_REDUCE( ice_volume,                 region%ice_volume,                 1, MPI_DOUBLE_PRECISION, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
    CALL MPI_REDUCE( ice_volume_above_flotation, region%ice_volume_above_flotation, 1, MPI_DOUBLE_PRECISION, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
    
    ! Calculate GMSL contribution
    IF (par%master) region%GMSL_contribution = -1._dp * (region%ice_volume_above_flotation - region%ice_volume_above_flotation_PD)
    CALL sync
    
  END SUBROUTINE calculate_icesheet_volume_and_area
  SUBROUTINE calculate_PD_sealevel_contribution( region)
    
    USE parameters_module,           ONLY: ocean_area, seawater_density, ice_density
  
    IMPLICIT NONE  
    
    TYPE(type_model_region),    INTENT(INOUT)     :: region
    
    INTEGER                                       :: i, j
    REAL(dp)                                      :: ice_volume, thickness_above_flotation, ice_volume_above_flotation
    
    ice_volume                 = 0._dp
    ice_volume_above_flotation = 0._dp
    
    DO i = region%grid%i1, region%grid%i2
    DO j = 1, region%grid%ny
    
      ! Thickness above flotation
      IF (region%PD%Hi( j,i) > 0._dp) THEN
        thickness_above_flotation = MAX(0._dp, region%PD%Hi( j,i) - MAX(0._dp, (0._dp - region%PD%Hb( j,i)) * (seawater_density / ice_density)))
      ELSE
        thickness_above_flotation = 0._dp
      END IF
      
      ! Ice volume (above flotation) in m.s.l.e
      ice_volume                 = ice_volume                 + region%PD%Hi( j,i)        * region%grid%dx * region%grid%dx * ice_density / (seawater_density * ocean_area)
      ice_volume_above_flotation = ice_volume_above_flotation + thickness_above_flotation * region%grid%dx * region%grid%dx * ice_density / (seawater_density * ocean_area)
      
    END DO
    END DO
    
    CALL MPI_REDUCE( ice_volume                , region%ice_volume_PD,                 1, MPI_DOUBLE_PRECISION, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
    CALL MPI_REDUCE( ice_volume_above_flotation, region%ice_volume_above_flotation_PD, 1, MPI_DOUBLE_PRECISION, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
    
  END SUBROUTINE calculate_PD_sealevel_contribution

END MODULE IMAU_ICE_main_model
