MODULE SMB_module

  ! Contains all the routines for calculating the surface mass balance for the current climate.

  USE mpi
  USE configuration_module,            ONLY: dp, C, routine_path, init_routine, finalise_routine, crash, warning
  USE parallel_module,                 ONLY: par, sync, cerr, ierr, &
                                             allocate_shared_int_0D, allocate_shared_dp_0D, &
                                             allocate_shared_int_1D, allocate_shared_dp_1D, &
                                             allocate_shared_int_2D, allocate_shared_dp_2D, &
                                             allocate_shared_int_3D, allocate_shared_dp_3D, &
                                             deallocate_shared
  USE data_types_module,               ONLY: type_grid, type_ice_model, type_SMB_model, type_climate_model, &
                                             type_restart_data, type_SMB_model_IMAU_ITM
  USE data_types_netcdf_module,        ONLY: type_netcdf_SMB_snapshot
  USE netcdf_module,                   ONLY: debug, write_to_debug_file, inquire_restart_file_SMB, read_restart_file_SMB, &
                                             read_SMB_snapshot_file
  USE utilities_module,                ONLY: check_for_NaN_dp_1D,  check_for_NaN_dp_2D,  check_for_NaN_dp_3D, &
                                             check_for_NaN_int_1D, check_for_NaN_int_2D, check_for_NaN_int_3D, &
                                             map_square_to_square_cons_2nd_order_2D, map_square_to_square_cons_2nd_order_3D, &
                                             transpose_dp_2D, transpose_dp_3D
  USE forcing_module,                  ONLY: forcing
  USE parameters_module,               ONLY: T0, L_fusion, sec_per_year, pi, ice_density

  IMPLICIT NONE

  REAL(dp), PARAMETER :: albedo_water        = 0.1_dp
  REAL(dp), PARAMETER :: albedo_soil         = 0.2_dp
  REAL(dp), PARAMETER :: albedo_ice          = 0.5_dp
  REAL(dp), PARAMETER :: albedo_snow         = 0.85_dp

CONTAINS

! == The main routines that should be called from the main ice model/program
! ==========================================================================

  SUBROUTINE run_SMB_model( grid, ice, climate, time, SMB, mask_noice, region_name)
    ! Run the selected SMB model.

    IMPLICIT NONE

    ! In/output variables
    TYPE(type_grid),                      INTENT(IN)    :: grid
    TYPE(type_ice_model),                 INTENT(IN)    :: ice
    TYPE(type_climate_model),             INTENT(IN)    :: climate
    REAL(dp),                             INTENT(IN)    :: time
    TYPE(type_SMB_model),                 INTENT(INOUT) :: SMB
    INTEGER,  DIMENSION(:,:  ),           INTENT(IN)    :: mask_noice
    CHARACTER(LEN=3),                     INTENT(IN)    :: region_name

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                       :: routine_name = 'run_SMB_model'
    INTEGER                                             :: i,j

    ! Add routine to path
    CALL init_routine( routine_name)

    IF     (C%choice_SMB_model == 'uniform') THEN
      ! Apply a simple uniform SMB

      DO i = grid%i1, grid%i2
      DO j = 1, grid%ny
        IF (mask_noice( j,i) == 0) THEN
          SMB%SMB( j,i) = C%SMB_uniform
        ELSE
          SMB%SMB( j,i) = 0._dp
        END IF
      END DO
      END DO
      CALL sync

    ELSEIF (C%choice_SMB_model == 'idealised') THEN
      ! Apply an idealised SMB parameterisation

      CALL run_SMB_model_idealised( grid, SMB, time, mask_noice)

    ELSEIF (C%choice_SMB_model == 'direct') THEN
      ! Use a directly prescribed SMB

      CALL run_SMB_model_direct( grid, SMB, time, mask_noice, region_name)

    ELSEIF (C%choice_SMB_model == 'ISMIP-style') THEN
      ! Use the ISMIP-style (SMB + aSMB + dSMBdz + ST + aST + dSTdz) forcing

      CALL run_SMB_model_ISMIP_style( grid, ice, climate, SMB, time)

    ELSEIF (C%choice_SMB_model == 'IMAU-ITM') THEN
      ! Run the IMAU-ITM SMB model

      CALL run_SMB_model_IMAUITM( grid, ice, climate, SMB%IMAU_ITM, mask_noice)

      ! Copy final SMB
      DO i = grid%i1, grid%i2
      DO j = 1, grid%ny
        IF (mask_noice( j,i) == 0) THEN
          SMB%SMB( j,i) = SMB%IMAU_ITM%SMB_year( j,i)
        ELSE
          SMB%SMB( j,i) = 0._dp
        END IF
      END DO
      END DO
      CALL sync

    ELSEIF (C%choice_SMB_model == 'IMAU-ITM_wrongrefreezing') THEN
      ! Run the IMAU-ITM SMB model with the old wrong refreezing parameterisation from ANICE

      CALL run_SMB_model_IMAUITM_wrongrefreezing( grid, ice, climate, SMB%IMAU_ITM, mask_noice)

      ! Copy final SMB
      DO i = grid%i1, grid%i2
      DO j = 1, grid%ny
        IF (mask_noice( j,i) == 0) THEN
          SMB%SMB( j,i) = SMB%IMAU_ITM%SMB_year( j,i)
        ELSE
          SMB%SMB( j,i) = 0._dp
        END IF
      END DO
      END DO
      CALL sync

    ELSE
      CALL crash('unknown choice_SMB_model "' // TRIM( C%choice_SMB_model) // '"!')
    END IF

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE run_SMB_model
  SUBROUTINE initialise_SMB_model( grid, ice, SMB, region_name)
    ! Allocate memory for the data fields of the SMB model.

    IMPLICIT NONE

    ! In/output variables
    TYPE(type_grid),                     INTENT(IN)    :: grid
    TYPE(type_ice_model),                INTENT(IN)    :: ice
    TYPE(type_SMB_model),                INTENT(INOUT) :: SMB
    CHARACTER(LEN=3),                    INTENT(IN)    :: region_name

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'initialise_SMB_model'

    ! Add routine to path
    CALL init_routine( routine_name)

    IF (par%master) WRITE (0,*) '  Initialising regional SMB model "', TRIM(C%choice_SMB_model), '"...'

    ! Always allocate memory for the applied SMB
    CALL allocate_shared_dp_2D( grid%ny, grid%nx, SMB%SMB, SMB%wSMB)

    ! Allocate shared memory
    IF     (C%choice_SMB_model == 'uniform' .OR. &
            C%choice_SMB_model == 'idealised') THEN
      ! No need to initialise anything other than the applied SMB

    ELSEIF (C%choice_SMB_model == 'direct') THEN
      ! Use a directly prescribed SMB

      CALL initialise_SMB_model_direct( grid, SMB)

    ELSEIF( C%choice_SMB_model == 'ISMIP-style') THEN
      ! Use the ISMIP-style (SMB + aSMB + dSMBdz + ST + aST + dSTdz) forcing

      ! NOTE: only works when choice_climate_model is also set to 'ISMIP-style'!
      IF (.NOT. C%choice_climate_model == 'ISMIP-style') CALL crash('choice_SMB_model "ISMIP-style" only works when choice_climate_model is also set to "ISMIP-style"!')

      ! No need to initialise anything other than the applied SMB

    ELSEIF (C%choice_SMB_model == 'IMAU-ITM' .OR. &
            C%choice_SMB_model == 'IMAU-ITM_wrongrefreezing') THEN
      ! Allocate memory and initialise some fields for the IMAU-ITM SMB model

      CALL initialise_SMB_model_IMAU_ITM( grid, ice, SMB%IMAU_ITM, region_name)

    ELSE
      CALL crash('unknown choice_SMB_model "' // TRIM( C%choice_SMB_model) // '"!')
    END IF

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE initialise_SMB_model

! == Idealised SMB parameterisations
! ==================================

  SUBROUTINE run_SMB_model_idealised( grid, SMB, time, mask_noice)
    ! Run the selected SMB model.

    IMPLICIT NONE

    ! In/output variables
    TYPE(type_grid),                      INTENT(IN)    :: grid
    TYPE(type_SMB_model),                 INTENT(INOUT) :: SMB
    REAL(dp),                             INTENT(IN)    :: time
    INTEGER,  DIMENSION(:,:  ),           INTENT(IN)    :: mask_noice

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                       :: routine_name = 'run_SMB_model_idealised'

    ! Add routine to path
    CALL init_routine( routine_name)

    IF     (C%choice_idealised_SMB == 'EISMINT1_A' .OR. &
            C%choice_idealised_SMB == 'EISMINT1_B' .OR. &
            C%choice_idealised_SMB == 'EISMINT1_C' .OR. &
            C%choice_idealised_SMB == 'EISMINT1_D' .OR. &
            C%choice_idealised_SMB == 'EISMINT1_E' .OR. &
            C%choice_idealised_SMB == 'EISMINT1_F') THEN
      CALL run_SMB_model_idealised_EISMINT1( grid, SMB, time, mask_noice)
    ELSEIF (C%choice_idealised_SMB == 'Bueler') THEN
      CALL run_SMB_model_idealised_Bueler( grid, SMB, time, mask_noice)
    ELSE
      CALL crash('unknown choice_idealised_SMB "' // TRIM( C%choice_idealised_SMB) // '"!')
    END IF

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE run_SMB_model_idealised
  SUBROUTINE run_SMB_model_idealised_EISMINT1( grid, SMB, time, mask_noice)

    IMPLICIT NONE

    ! In/output variables
    TYPE(type_grid),                     INTENT(IN)    :: grid
    TYPE(type_SMB_model),                INTENT(INOUT) :: SMB
    REAL(dp),                            INTENT(IN)    :: time
    INTEGER,  DIMENSION(:,:  ),          INTENT(IN)    :: mask_noice

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'run_SMB_model_idealised_EISMINT1'
    INTEGER                                            :: i,j

    REAL(dp)                                           :: E               ! Radius of circle where accumulation is M_max
    REAL(dp)                                           :: dist            ! distance to centre of circle
    REAL(dp)                                           :: S_b             ! Gradient of accumulation-rate change with horizontal distance
    REAL(dp)                                           :: M_max           ! Maximum accumulation rate

    ! Add routine to path
    CALL init_routine( routine_name)

    ! Default EISMINT configuration
    E         = 450000._dp
    S_b       = 0.01_dp / 1000._dp
    M_max     = 0.5_dp

    IF     (C%choice_idealised_SMB == 'EISMINT1_A') THEN ! Moving margin, steady state
      ! No changes
    ELSEIF (C%choice_idealised_SMB == 'EISMINT1_B') THEN ! Moving margin, 20 kyr
      IF (time < 0._dp) THEN
        ! No changes; first 120 kyr are initialised with EISMINT_1
      ELSE
        E         = 450000._dp + 100000._dp * SIN( 2._dp * pi * time / 20000._dp)
      END IF
    ELSEIF (C%choice_idealised_SMB == 'EISMINT1_C') THEN ! Moving margin, 40 kyr
      IF (time < 0._dp) THEN
        ! No changes; first 120 kyr are initialised with EISMINT_1
      ELSE
        E         = 450000._dp + 100000._dp * SIN( 2._dp * pi * time / 40000._dp)
      END IF
    ELSEIF (C%choice_idealised_SMB == 'EISMINT1_D') THEN ! Fixed margin, steady state
      M_max       = 0.3_dp
      E           = 999000._dp
    ELSEIF (C%choice_idealised_SMB == 'EISMINT1_E') THEN ! Fixed margin, 20 kyr
      IF (time < 0._dp) THEN
        M_max     = 0.3_dp
        E         = 999000._dp
      ELSE
        M_max     = 0.3_dp + 0.2_dp * SIN( 2._dp * pi * time / 20000._dp)
        E         = 999000._dp
      END IF
    ELSEIF (C%choice_idealised_SMB == 'EISMINT1_F') THEN ! Fixed margin, 40 kyr
      IF (time < 0._dp) THEN
        M_max     = 0.3_dp
        E         = 999000._dp
      ELSE
        M_max     = 0.3_dp + 0.2_dp * SIN( 2._dp * pi * time / 40000._dp)
        E         = 999000._dp
      END IF
    END IF

    DO i = grid%i1, grid%i2
    DO j = 1, grid%ny
      IF (mask_noice( j,i) == 0) THEN
        dist = SQRT(grid%x(i)**2+grid%y(j)**2)
        SMB%SMB( j,i) = MIN( M_max, S_b * (E - dist))
      ELSE
        SMB%SMB( j,i) = 0._dp
      END IF
    END DO
    END DO
    CALL sync

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE run_SMB_model_idealised_EISMINT1
  SUBROUTINE run_SMB_model_idealised_Bueler( grid, SMB, time, mask_noice)

    IMPLICIT NONE

    ! In/output variables
    TYPE(type_grid),                     INTENT(IN)    :: grid
    TYPE(type_SMB_model),                INTENT(INOUT) :: SMB
    REAL(dp),                            INTENT(IN)    :: time
    INTEGER,  DIMENSION(:,:  ),          INTENT(IN)    :: mask_noice

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'run_SMB_model_idealised_Bueler'
    INTEGER                                            :: i,j

    ! Add routine to path
    CALL init_routine( routine_name)

    DO i = grid%i1, grid%i2
    DO j = 1, grid%ny
      IF (mask_noice( j,i) == 0) THEN
        SMB%SMB( j,i) = Bueler_solution_MB( grid%x(i), grid%y(j), time)
      ELSE
        SMB%SMB( j,i) = 0._dp
      END IF
    END DO
    END DO
    CALL sync

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE run_SMB_model_idealised_Bueler

! == Directly prescribed SMB
! ==========================

  SUBROUTINE run_SMB_model_direct( grid, SMB, time, mask_noice, region_name)
    ! Run the selected SMB model: direct SMB forcing.

    IMPLICIT NONE

    ! In/output variables
    TYPE(type_grid),                     INTENT(IN)    :: grid
    TYPE(type_SMB_model),                INTENT(INOUT) :: SMB
    REAL(dp),                            INTENT(IN)    :: time
    INTEGER,  DIMENSION(:,:  ),          INTENT(IN)    :: mask_noice
    CHARACTER(LEN=3),                    INTENT(IN)    :: region_name

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'run_SMB_model_direct'
    REAL(dp)                                           :: wt0, wt1
    INTEGER                                            :: i,j

    ! Add routine to path
    CALL init_routine( routine_name)

    ! If needed, update the two timeframes
    IF (time < SMB%direct%t0 .OR. time > SMB%direct%t1) THEN
      CALL sync
      CALL run_SMB_model_direct_update_timeframes( grid, SMB, time, region_name)
    END IF

    ! Interpolate the two timeframes in time
    wt0 = (SMB%direct%t1 - time) / (SMB%direct%t1 - SMB%direct%t0)
    wt1 = 1._dp - wt0

    DO i = grid%i1, grid%i2
    DO j = 1, grid%ny
      IF (mask_noice( j,i) == 0) THEN
        SMB%SMB( j,i) = (wt0 * SMB%direct%timeframe0%SMB( j,i)) + (wt1 * SMB%direct%timeframe1%SMB( j,i))
      ELSE
        SMB%SMB( j,i) = 0._dp
      END IF
    END DO
    END DO
    CALL sync

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE run_SMB_model_direct
  SUBROUTINE run_SMB_model_direct_update_timeframes( grid, SMB, time, region_name)
    ! Run the selected SMB model: direct SMB forcing.

    USE netcdf_module, ONLY: open_netcdf_file, inquire_dim, inquire_single_or_double_var, handle_error, close_netcdf_file
    USE netcdf, ONLY: nf90_get_var

    IMPLICIT NONE

    ! In/output variables
    TYPE(type_grid),                     INTENT(IN)    :: grid
    TYPE(type_SMB_model),                INTENT(INOUT) :: SMB
    REAL(dp),                            INTENT(IN)    :: time
    CHARACTER(LEN=3),                    INTENT(IN)    :: region_name

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'run_SMB_model_direct_update_timeframes'
    TYPE(type_netcdf_SMB_snapshot)                     :: netcdf
    INTEGER                                            :: ntime_from_file
    REAL(dp), DIMENSION(:    ), ALLOCATABLE            ::  time_from_file
    INTEGER                                            :: ti
    REAL(dp), DIMENSION(:    ), POINTER                :: x_raw, y_raw
    INTEGER                                            :: wx_raw, wy_raw, nx_raw, ny_raw
    REAL(dp), DIMENSION(:,:  ), POINTER                ::  SMB0_raw,  SMB1_raw
    INTEGER                                            :: wSMB0_raw, wSMB1_raw
    REAL(dp), DIMENSION(:,:  ), POINTER                ::  T2m0_raw,  T2m1_raw,  T2m0,  T2m1
    INTEGER                                            :: wT2m0_raw, wT2m1_raw, wT2m0, wT2m1
    INTEGER                                            :: i,j

    ! Add routine to path
    CALL init_routine( routine_name)

    ! Get filename
    IF     (region_name == 'NAM') THEN
      netcdf%filename   = C%filename_direct_SMB_NAM
    ELSEIF (region_name == 'EAS') THEN
      netcdf%filename   = C%filename_direct_SMB_EAS
    ELSEIF (region_name == 'GRL') THEN
      netcdf%filename   = C%filename_direct_SMB_GRL
    ELSEIF (region_name == 'ANT') THEN
      netcdf%filename   = C%filename_direct_SMB_ANT
    ELSE
      CALL crash('unknown model region "' // TRIM( region_name) // '"!')
    END IF

    ! Find times of two timeframes
    IF (par%master) THEN

      ! Open the netcdf file
      CALL open_netcdf_file( TRIM( netcdf%filename), netcdf%ncid)

      ! Read time from netcdf file
      CALL inquire_dim( netcdf%ncid, netcdf%name_dim_time, ntime_from_file, netcdf%id_dim_time)

      CALL inquire_single_or_double_var( netcdf%ncid, netcdf%name_var_time, [netcdf%id_dim_time], netcdf%id_var_time)

      ALLOCATE( time_from_file( ntime_from_file))

      CALL handle_error( nf90_get_var( netcdf%ncid, netcdf%id_var_time, time_from_file))

      CALL close_netcdf_file( netcdf%ncid)

      ti = 1
      DO WHILE (time_from_file( ti) < time)
        ti = ti + 1
      END DO
      ti = MIN( ntime_from_file-1, MAX( 1, ti - 1))
      SMB%direct%t0 = time_from_file( ti)

      ti = ntime_from_file
      DO WHILE (time_from_file( ti) > time)
        ti = ti - 1
      END DO
      ti = MIN( ntime_from_file  , MAX( 2, ti + 1))
      SMB%direct%t1 = time_from_file( ti)

      DEALLOCATE( time_from_file)

    END IF ! IF (par%master) THEN
    CALL MPI_BCAST( SMB%direct%t0, 1, MPI_DOUBLE_PRECISION, 0, MPI_COMM_WORLD, ierr)
    CALL MPI_BCAST( SMB%direct%t1, 1, MPI_DOUBLE_PRECISION, 0, MPI_COMM_WORLD, ierr)

    ! Read both snapshots
    CALL read_SMB_snapshot_file( netcdf, SMB%direct%t0, nx_raw, x_raw, wx_raw, ny_raw, y_raw, wy_raw, SMB0_raw, wSMB0_raw, T2m0_raw, wT2m0_raw)
    CALL deallocate_shared( wx_raw)
    CALL deallocate_shared( wy_raw)
    CALL read_SMB_snapshot_file( netcdf, SMB%direct%t1, nx_raw, x_raw, wx_raw, ny_raw, y_raw, wy_raw, SMB1_raw, wSMB1_raw, T2m1_raw, wT2m1_raw)

    ! Tranpose data to go from [i,j] to [j,i] indexing
    CALL transpose_dp_2D( SMB0_raw, wSMB0_raw)
    CALL transpose_dp_2D( SMB1_raw, wSMB1_raw)
    CALL transpose_dp_2D( T2m0_raw, wT2m0_raw)
    CALL transpose_dp_2D( T2m1_raw, wT2m1_raw)

    ! Map data to model grid
    CALL allocate_shared_dp_2D( grid%ny, grid%nx, T2m0, wT2m0)
    CALL allocate_shared_dp_2D( grid%ny, grid%nx, T2m1, wT2m1)
    CALL map_square_to_square_cons_2nd_order_2D( nx_raw, ny_raw, x_raw, y_raw, grid%nx, grid%ny, grid%x, grid%y, SMB0_raw, SMB%direct%timeframe0%SMB)
    CALL map_square_to_square_cons_2nd_order_2D( nx_raw, ny_raw, x_raw, y_raw, grid%nx, grid%ny, grid%x, grid%y, SMB1_raw, SMB%direct%timeframe1%SMB)
    CALL map_square_to_square_cons_2nd_order_2D( nx_raw, ny_raw, x_raw, y_raw, grid%nx, grid%ny, grid%x, grid%y, T2m0_raw, T2m0)
    CALL map_square_to_square_cons_2nd_order_2D( nx_raw, ny_raw, x_raw, y_raw, grid%nx, grid%ny, grid%x, grid%y, T2m1_raw, T2m1)

    DO i = grid%i1, grid%i2
    DO j = 1, grid%ny
      SMB%direct%timeframe0%T2m( :,j,i) = T2m0( j,i)
      SMB%direct%timeframe1%T2m( :,j,i) = T2m1( j,i)
    END DO
    END DO
    CALL sync

    ! Clean up after yourself
    CALL deallocate_shared( wx_raw)
    CALL deallocate_shared( wy_raw)
    CALL deallocate_shared( wSMB0_raw)
    CALL deallocate_shared( wSMB1_raw)
    CALL deallocate_shared( wT2m0_raw)
    CALL deallocate_shared( wT2m1_raw)
    CALL deallocate_shared( wT2m0)
    CALL deallocate_shared( wT2m1)

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE run_SMB_model_direct_update_timeframes
  SUBROUTINE initialise_SMB_model_direct( grid, SMB)
    ! Allocate memory for the data fields of the SMB model.

    IMPLICIT NONE

    ! In/output variables
    TYPE(type_grid),                     INTENT(IN)    :: grid
    TYPE(type_SMB_model),                INTENT(INOUT) :: SMB

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'initialise_SMB_model_direct'

    ! Add routine to path
    CALL init_routine( routine_name)

    ! Set timeframes timestamps to impossible values, so that the first call to run_climate_model_direct
    ! is guaranteed to first read two new timeframes from the NetCDF file
    SMB%direct%t0 = C%start_time_of_run - 100._dp
    SMB%direct%t1 = C%start_time_of_run - 90._dp

    ! Allocate shared memory
    CALL allocate_shared_dp_2D(     grid%ny, grid%nx, SMB%direct%timeframe0%SMB, SMB%direct%timeframe0%wSMB)
    CALL allocate_shared_dp_2D(     grid%ny, grid%nx, SMB%direct%timeframe1%SMB, SMB%direct%timeframe1%wSMB)
    CALL allocate_shared_dp_3D( 12, grid%ny, grid%nx, SMB%direct%timeframe0%T2m, SMB%direct%timeframe0%wT2m)
    CALL allocate_shared_dp_3D( 12, grid%ny, grid%nx, SMB%direct%timeframe1%T2m, SMB%direct%timeframe1%wT2m)

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE initialise_SMB_model_direct

! == ISMIP-style (SMB + aSMB + dSMBdz + ST + aST + dSTdz) forcing
! =================================================================

  SUBROUTINE run_SMB_model_ISMIP_style( grid, ice, climate, SMB, time)
    ! Run the selected SMB model
    !
    ! Use the ISMIP-style (SMB + aSMB + dSMBdz + ST + aST + dSTdz) forcing

    IMPLICIT NONE

    ! In/output variables
    TYPE(type_grid),                     INTENT(IN)    :: grid
    TYPE(type_ice_model),                INTENT(IN)    :: ice
    TYPE(type_climate_model),            INTENT(IN)    :: climate
    TYPE(type_SMB_model),                INTENT(INOUT) :: SMB
    REAL(dp),                            INTENT(IN)    :: time

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'run_SMB_model_ISMIP_style'
    REAL(dp)                                           :: wt0, wt1
    INTEGER                                            :: i,j
    REAL(dp)                                           :: aSMB, dSMBdz, dz

    ! Add routine to path
    CALL init_routine( routine_name)

    ! Calculate interpolation weights for interpolating the two timeframes in time
    wt0 = (climate%ISMIP_style%t1 - time) / (climate%ISMIP_style%t1 - climate%ISMIP_style%t0)
    wt1 = 1._dp - wt0

    DO i = grid%i1, grid%i2
    DO j = 1, grid%ny

      ! Interpolate the two timeframes in time
      aSMB   = (wt0 * climate%ISMIP_style%timeframe0%aSMB(   j,i)) + (wt1 * climate%ISMIP_style%timeframe1%aSMB(   j,i))
      dSMBdz = (wt0 * climate%ISMIP_style%timeframe0%dSMBdz( j,i)) + (wt1 * climate%ISMIP_style%timeframe1%dSMBdz( j,i))

      ! Calculate the applied SMB
      dz = ice%Hs_a( j,i) - climate%ISMIP_style%Hs_ref( j,i)
      SMB%SMB( j,i) = climate%ISMIP_style%SMB_ref( j,i) + aSMB + dSMBdz * dz

    END DO
    END DO
    CALL sync

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE run_SMB_model_ISMIP_style

! == The IMAU-ITM SMB model
! =========================

  SUBROUTINE run_SMB_model_IMAUITM( grid, ice, climate, SMB, mask_noice)
    ! Run the IMAU-ITM SMB model.

    ! NOTE: all the SMB components are in meters of water equivalent;
    !       the end result (SMB and SMB_year) are in meters of ice equivalent.

    IMPLICIT NONE

    ! In/output variables
    TYPE(type_grid),                      INTENT(IN)    :: grid
    TYPE(type_ice_model),                 INTENT(IN)    :: ice
    TYPE(type_climate_model),             INTENT(IN)    :: climate
    TYPE(type_SMB_model_IMAU_ITM),        INTENT(INOUT) :: SMB
    INTEGER,  DIMENSION(:,:  ),           INTENT(IN)    :: mask_noice

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                       :: routine_name = 'run_SMB_model_IMAUITM'
    INTEGER                                             :: i,j,m
    INTEGER                                             :: mprev
    REAL(dp)                                            :: snowfrac, liquid_water, sup_imp_wat

    ! Add routine to path
    CALL init_routine( routine_name)

    ! Safety
    IF (.NOT. C%choice_SMB_model == 'IMAU-ITM') THEN
      CALL crash('should only be called when choice_SMB_model == "IMAU-ITM"!')
    END IF

    DO i = grid%i1, grid%i2
    DO j = 1, grid%ny

      ! Background albedo
      SMB%AlbedoSurf( j,i) = albedo_soil
      IF ((ice%mask_ocean_a( j,i) == 1 .AND. ice%mask_shelf_a( j,i) == 0) .OR. mask_noice( j,i) == 1) SMB%AlbedoSurf( j,i) = albedo_water
      IF (ice%mask_ice_a(    j,i) == 1) SMB%AlbedoSurf( j,i) = albedo_ice

      DO m = 1, 12  ! Month loop

        mprev = m - 1
        IF (mprev==0) mprev = 12

        SMB%Albedo( m,j,i) = MIN(albedo_snow, MAX( SMB%AlbedoSurf( j,i), albedo_snow - (albedo_snow - SMB%AlbedoSurf( j,i))  * &
                             EXP(-15._dp * SMB%FirnDepth( mprev,j,i)) - 0.015_dp * SMB%MeltPreviousYear( j,i)))
        IF ((ice%mask_ocean_a( j,i) == 1 .AND. ice%mask_shelf_a( j,i) == 0) .OR. mask_noice( j,i) == 1) SMB%Albedo( m,j,i) = albedo_water

        ! Determine albation as function af surface temperature and albedo/insolation
        ! according to Bintanja et al. (2002)

        SMB%Melt( m,j,i) = MAX(0._dp, ( SMB%C_abl_Ts         * (climate%T2m( m,j,i) - T0) + &
                                        SMB%C_abl_Q          * (1.0_dp - SMB%Albedo( m,j,i)) * climate%Q_TOA( m,j,i) - &
                                        SMB%C_abl_constant)  * sec_per_year / (L_fusion * 1000._dp * 12._dp))

        ! Determine accumulation with snow/rain fraction from Ohmura et al. (1999),
        ! liquid water content (rain and melt water) and snowdepth

        ! NOTE: commented version is the old ANICE version, supposedly based on "physics" (which we cant check), but
        !       the new version was tuned to RACMO output and produced significantly better snow fractions...

  !      snowfrac = MAX(0._dp, MIN(1._dp, 0.5_dp   * (1 - ATAN((climate%T2m(vi,m) - T0) / 3.5_dp)  / 1.25664_dp)))
        snowfrac = MAX(0._dp, MIN(1._dp, 0.725_dp * (1 - ATAN((climate%T2m( m,j,i) - T0) / 5.95_dp) / 1.8566_dp)))

        SMB%Snowfall( m,j,i) = climate%Precip( m,j,i) *          snowfrac
        SMB%Rainfall( m,j,i) = climate%Precip( m,j,i) * (1._dp - snowfrac)

        ! Refreezing, according to Janssens & Huybrechts, 2000)
        ! The refreezing (=effective retention) is the minimum value of the amount of super imposed
        ! water and the available liquid water, with a maximum value of the total precipitation.
        ! (see also Huybrechts & de Wolde, 1999)

        ! Add this month's snow accumulation to next month's initial snow depth.
        SMB%AddedFirn( m,j,i) = SMB%Snowfall( m,j,i) - SMB%Melt( m,j,i)
        SMB%FirnDepth( m,j,i) = MIN(10._dp, MAX(0._dp, SMB%FirnDepth( mprev,j,i) + SMB%AddedFirn( m,j,i) ))

      END DO ! DO m = 1, 12

      ! Calculate refrezzing for the whole year, divide equally over the 12 months, then calculate resulting runoff and SMB.
      ! This resolves the problem with refreezing, where liquid water is mostly available in summer
      ! but "refreezing potential" mostly in winter, and there is no proper meltwater retention.

      sup_imp_wat  = SMB%C_refr * MAX(0._dp, T0 - SUM(climate%T2m( :,j,i))/12._dp)
      liquid_water = SUM(SMB%Rainfall( :,j,i)) + SUM(SMB%Melt( :,j,i))

      SMB%Refreezing_year( j,i) = MIN( MIN( sup_imp_wat, liquid_water), SUM(climate%Precip( :,j,i)))
      IF (ice%mask_ice_a( j,i)==0) SMB%Refreezing_year( j,i) = 0._dp

      DO m = 1, 12
        SMB%Refreezing( m,j,i) = SMB%Refreezing_year( j,i) / 12._dp
        SMB%Runoff(     m,j,i) = SMB%Melt( m,j,i) + SMB%Rainfall( m,j,i) - SMB%Refreezing( m,j,i)
        SMB%SMB(        m,j,i) = SMB%Snowfall( m,j,i) + SMB%Refreezing( m,j,i) - SMB%Melt( m,j,i)
      END DO

      SMB%SMB_year( j,i) = SUM(SMB%SMB( :,j,i))

      ! Calculate total melt over this year, to be used for determining next year's albedo
      SMB%MeltPreviousYear( j,i) = SUM(SMB%Melt( :,j,i))

    END DO
    END DO
    CALL sync

    ! Convert final SMB from water to ice equivalent
    SMB%SMB(      :,:,grid%i1:grid%i2) = SMB%SMB(      :,:,grid%i1:grid%i2) * 1000._dp / ice_density
    SMB%SMB_year(   :,grid%i1:grid%i2) = SMB%SMB_year(   :,grid%i1:grid%i2) * 1000._dp / ice_density
    CALL sync

    ! Safety
    CALL check_for_NaN_dp_2D( SMB%AlbedoSurf      , 'SMB%AlbedoSurf'      )
    CALL check_for_NaN_dp_3D( SMB%Albedo          , 'SMB%Albedo'          )
    CALL check_for_NaN_dp_3D( SMB%Melt            , 'SMB%Melt'            )
    CALL check_for_NaN_dp_3D( SMB%Snowfall        , 'SMB%Snowfall'        )
    CALL check_for_NaN_dp_3D( SMB%Rainfall        , 'SMB%Rainfall'        )
    CALL check_for_NaN_dp_3D( SMB%Refreezing      , 'SMB%Refreezing'      )
    CALL check_for_NaN_dp_3D( SMB%Runoff          , 'SMB%Runoff'          )
    CALL check_for_NaN_dp_3D( SMB%SMB             , 'SMB%SMB'             )
    CALL check_for_NaN_dp_3D( SMB%AddedFirn       , 'SMB%AddedFirn'       )
    CALL check_for_NaN_dp_3D( SMB%FirnDepth       , 'SMB%FirnDepth'       )
    CALL check_for_NaN_dp_2D( SMB%SMB_year        , 'SMB%SMB_year'        )
    CALL check_for_NaN_dp_2D( SMB%MeltPreviousYear, 'SMB%MeltPreviousYear')
    CALL check_for_NaN_dp_2D( SMB%Albedo_year     , 'SMB%Albedo_year'     )

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE run_SMB_model_IMAUITM
  SUBROUTINE run_SMB_model_IMAUITM_wrongrefreezing( grid, ice, climate, SMB, mask_noice)
    ! Run the IMAU-ITM SMB model. Old version, exactly as it was in ANICE2.1 (so with the "wrong" refreezing)

    ! NOTE: all the SMB components and the total are in meters of water equivalent

    IMPLICIT NONE

    ! In/output variables
    TYPE(type_grid),                      INTENT(IN)    :: grid
    TYPE(type_ice_model),                 INTENT(IN)    :: ice
    TYPE(type_climate_model),             INTENT(IN)    :: climate
    TYPE(type_SMB_model_IMAU_ITM),        INTENT(INOUT) :: SMB
    INTEGER,  DIMENSION(:,:  ),           INTENT(IN)    :: mask_noice

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                       :: routine_name = 'run_SMB_model_IMAUITM_wrongrefreezing'
    INTEGER                                             :: i,j,m
    INTEGER                                             :: mprev
    REAL(dp)                                            :: snowfrac, liquid_water, sup_imp_wat

    ! Add routine to path
    CALL init_routine( routine_name)

    ! Make sure this routine is called correctly
    IF (.NOT. C%choice_SMB_model == 'IMAU-ITM_wrongrefreezing') THEN
      CALL crash('should only be called when choice_SMB_model == "IMAU-ITM_wrongrefreezing"!')
    END IF

    DO i = grid%i1, grid%i2
    DO j = 1, grid%ny

      ! "Background" albedo (= surface without any firn, so either ice, soil, or water)
      SMB%AlbedoSurf( j,i) = albedo_soil
      IF ((ice%mask_ocean_a( j,i) == 1 .AND. ice%mask_shelf_a( j,i) == 0) .OR. mask_noice( j,i) == 1) SMB%AlbedoSurf( j,i) = albedo_water
      IF (ice%mask_ice_a(    j,i) == 1) SMB%AlbedoSurf( j,i) = albedo_ice

      DO m = 1, 12  ! Month loop

        mprev = m - 1
        IF (mprev == 0) mprev = 12

        SMB%Albedo( m,j,i) = MIN(albedo_snow, MAX( SMB%AlbedoSurf( j,i), albedo_snow - (albedo_snow - SMB%AlbedoSurf( j,i))  * &
                             EXP(-15._dp * SMB%FirnDepth( mprev,j,i)) - 0.015_dp * SMB%MeltPreviousYear( j,i)))
        IF ((ice%mask_ocean_a( j,i) == 1 .AND. ice%mask_shelf_a( j,i) == 0) .OR. mask_noice( j,i) == 1) SMB%Albedo( m,j,i) = albedo_water

        ! Determine ablation as function af surface temperature and albedo/insolation
        ! according to Bintanja et al. (2002)

        SMB%Melt( m,j,i) = MAX(0._dp, ( SMB%C_abl_Ts         * (climate%T2m( m,j,i) - T0) + &
                                        SMB%C_abl_Q          * (1.0_dp - SMB%Albedo( m,j,i)) * climate%Q_TOA( m,j,i) - &
                                        SMB%C_abl_constant)  * sec_per_year / (L_fusion * 1000._dp * 12._dp))

        ! Determine accumulation with snow/rain fraction from Ohmura et al. (1999),
        ! liquid water content (rain and melt water) and snowdepth
        snowfrac = MAX(0._dp, MIN(1._dp, 0.5_dp   * (1 - ATAN((climate%T2m( m,j,i) - T0) / 3.5_dp)  / 1.25664_dp)))

        SMB%Snowfall( m,j,i) = climate%Precip( m,j,i) *          snowfrac
        SMB%Rainfall( m,j,i) = climate%Precip( m,j,i) * (1._dp - snowfrac)

        ! Refreezing, according to Janssens & Huybrechts, 2000)
        ! The refreezing (=effective retention) is the minimum value of the amount of super imposed
        ! water and the available liquid water, with a maximum value of the total precipitation.
        ! (see also Huybrechts & de Wolde, 1999)
        sup_imp_wat  = 0.012_dp * MAX(0._dp, T0 - climate%T2m( m,j,i))
        liquid_water = SMB%Rainfall( m,j,i) + SMB%Melt( m,j,i)
        SMB%Refreezing( m,j,i) = MIN( MIN( sup_imp_wat, liquid_water), climate%Precip( m,j,i))
        IF (ice%mask_ice_a( j,i) == 0 .OR. mask_noice( j,i) == 1) SMB%Refreezing( m,j,i) = 0._dp

        ! Calculate runoff and total SMB
        SMB%Runoff( m,j,i) = SMB%Melt(     m,j,i) + SMB%Rainfall(   m,j,i) - SMB%Refreezing( m,j,i)
        SMB%SMB(    m,j,i) = SMB%Snowfall( m,j,i) + SMB%Refreezing( m,j,i) - SMB%Melt(       m,j,i)

        ! Add this month's snow accumulation to next month's initial snow depth.
        SMB%AddedFirn( m,j,i) = SMB%Snowfall( m,j,i) - SMB%Melt( m,j,i)
        SMB%FirnDepth( m,j,i) = MIN(10._dp, MAX(0._dp, SMB%FirnDepth( mprev,j,i) + SMB%AddedFirn( m,j,i) ))

      END DO ! DO m = 1, 12

      ! Calculate total SMB for the entire year
      SMB%SMB_year( j,i) = SUM(SMB%SMB( :,j,i))

      ! Calculate total melt over this year, to be used for determining next year's albedo
      SMB%MeltPreviousYear( j,i) = SUM(SMB%Melt( :,j,i))

      ! Calculate yearly mean albedo (diagnostic only)
      SMB%Albedo_year( j,i) = SUM(SMB%Albedo( :,j,i)) / 12._dp

    END DO
    END DO
    CALL sync

    ! Convert final SMB from water to ice equivalent
    SMB%SMB(      :,:,grid%i1:grid%i2) = SMB%SMB(      :,:,grid%i1:grid%i2) * 1000._dp / ice_density
    SMB%SMB_year(   :,grid%i1:grid%i2) = SMB%SMB_year(   :,grid%i1:grid%i2) * 1000._dp / ice_density
    CALL sync

    ! Safety
    CALL check_for_NaN_dp_2D( SMB%AlbedoSurf      , 'SMB%AlbedoSurf'      )
    CALL check_for_NaN_dp_3D( SMB%Albedo          , 'SMB%Albedo'          )
    CALL check_for_NaN_dp_3D( SMB%Melt            , 'SMB%Melt'            )
    CALL check_for_NaN_dp_3D( SMB%Snowfall        , 'SMB%Snowfall'        )
    CALL check_for_NaN_dp_3D( SMB%Rainfall        , 'SMB%Rainfall'        )
    CALL check_for_NaN_dp_3D( SMB%Refreezing      , 'SMB%Refreezing'      )
    CALL check_for_NaN_dp_3D( SMB%Runoff          , 'SMB%Runoff'          )
    CALL check_for_NaN_dp_3D( SMB%SMB             , 'SMB%SMB'             )
    CALL check_for_NaN_dp_3D( SMB%AddedFirn       , 'SMB%AddedFirn'       )
    CALL check_for_NaN_dp_3D( SMB%FirnDepth       , 'SMB%FirnDepth'       )
    CALL check_for_NaN_dp_2D( SMB%SMB_year        , 'SMB%SMB_year'        )
    CALL check_for_NaN_dp_2D( SMB%MeltPreviousYear, 'SMB%MeltPreviousYear')
    CALL check_for_NaN_dp_2D( SMB%Albedo_year     , 'SMB%Albedo_year'     )

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE run_SMB_model_IMAUITM_wrongrefreezing
  SUBROUTINE initialise_SMB_model_IMAU_ITM( grid, ice, SMB, region_name)
    ! Allocate memory for the data fields of the SMB model.

    IMPLICIT NONE

    ! In/output variables
    TYPE(type_grid),                     INTENT(IN)    :: grid
    TYPE(type_ice_model),                INTENT(IN)    :: ice
    TYPE(type_SMB_model_IMAU_ITM),       INTENT(INOUT) :: SMB
    CHARACTER(LEN=3),                    INTENT(IN)    :: region_name

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'initialise_SMB_model_IMAU_ITM'
    INTEGER                                            :: i,j
    CHARACTER(LEN=256)                                 :: SMB_IMAUITM_choice_init_firn

    ! Add routine to path
    CALL init_routine( routine_name)

    IF (par%master) WRITE (0,*) '  Initialising the IMAU-ITM SMB model...'

    ! Data fields
    CALL allocate_shared_dp_2D(     grid%ny, grid%nx, SMB%AlbedoSurf      , SMB%wAlbedoSurf      )
    CALL allocate_shared_dp_2D(     grid%ny, grid%nx, SMB%MeltPreviousYear, SMB%wMeltPreviousYear)
    CALL allocate_shared_dp_3D( 12, grid%ny, grid%nx, SMB%FirnDepth       , SMB%wFirnDepth       )
    CALL allocate_shared_dp_3D( 12, grid%ny, grid%nx, SMB%Rainfall        , SMB%wRainfall        )
    CALL allocate_shared_dp_3D( 12, grid%ny, grid%nx, SMB%Snowfall        , SMB%wSnowfall        )
    CALL allocate_shared_dp_3D( 12, grid%ny, grid%nx, SMB%AddedFirn       , SMB%wAddedFirn       )
    CALL allocate_shared_dp_3D( 12, grid%ny, grid%nx, SMB%Melt            , SMB%wMelt            )
    CALL allocate_shared_dp_3D( 12, grid%ny, grid%nx, SMB%Refreezing      , SMB%wRefreezing      )
    CALL allocate_shared_dp_2D(     grid%ny, grid%nx, SMB%Refreezing_year , SMB%wRefreezing_year )
    CALL allocate_shared_dp_3D( 12, grid%ny, grid%nx, SMB%Runoff          , SMB%wRunoff          )
    CALL allocate_shared_dp_3D( 12, grid%ny, grid%nx, SMB%Albedo          , SMB%wAlbedo          )
    CALL allocate_shared_dp_2D(     grid%ny, grid%nx, SMB%Albedo_year     , SMB%wAlbedo_year     )
    CALL allocate_shared_dp_3D( 12, grid%ny, grid%nx, SMB%SMB             , SMB%wSMB             )
    CALL allocate_shared_dp_2D(     grid%ny, grid%nx, SMB%SMB_year        , SMB%wSMB_year        )

    ! Tuning parameters
    CALL allocate_shared_dp_0D( SMB%C_abl_constant, SMB%wC_abl_constant)
    CALL allocate_shared_dp_0D( SMB%C_abl_Ts,       SMB%wC_abl_Ts      )
    CALL allocate_shared_dp_0D( SMB%C_abl_Q,        SMB%wC_abl_Q       )
    CALL allocate_shared_dp_0D( SMB%C_refr,         SMB%wC_refr        )

    IF (par%master) THEN
      IF     (region_name == 'NAM') THEN
        SMB%C_abl_constant           = C%SMB_IMAUITM_C_abl_constant_NAM
        SMB%C_abl_Ts                 = C%SMB_IMAUITM_C_abl_Ts_NAM
        SMB%C_abl_Q                  = C%SMB_IMAUITM_C_abl_Q_NAM
        SMB%C_refr                   = C%SMB_IMAUITM_C_refr_NAM
      ELSEIF (region_name == 'EAS') THEN
        SMB%C_abl_constant           = C%SMB_IMAUITM_C_abl_constant_EAS
        SMB%C_abl_Ts                 = C%SMB_IMAUITM_C_abl_Ts_EAS
        SMB%C_abl_Q                  = C%SMB_IMAUITM_C_abl_Q_EAS
        SMB%C_refr                   = C%SMB_IMAUITM_C_refr_EAS
      ELSEIF (region_name == 'GRL') THEN
        SMB%C_abl_constant           = C%SMB_IMAUITM_C_abl_constant_GRL
        SMB%C_abl_Ts                 = C%SMB_IMAUITM_C_abl_Ts_GRL
        SMB%C_abl_Q                  = C%SMB_IMAUITM_C_abl_Q_GRL
        SMB%C_refr                   = C%SMB_IMAUITM_C_refr_GRL
      ELSEIF (region_name == 'ANT') THEN
        SMB%C_abl_constant           = C%SMB_IMAUITM_C_abl_constant_ANT
        SMB%C_abl_Ts                 = C%SMB_IMAUITM_C_abl_Ts_ANT
        SMB%C_abl_Q                  = C%SMB_IMAUITM_C_abl_Q_ANT
        SMB%C_refr                   = C%SMB_IMAUITM_C_refr_ANT
      END IF
    END IF ! IF (par%master) THEN
    CALL sync

    ! Initialisation choice
    IF     (region_name == 'NAM') THEN
      SMB_IMAUITM_choice_init_firn = C%SMB_IMAUITM_choice_init_firn_NAM
    ELSEIF (region_name == 'EAS') THEN
      SMB_IMAUITM_choice_init_firn = C%SMB_IMAUITM_choice_init_firn_EAS
    ELSEIF (region_name == 'GRL') THEN
      SMB_IMAUITM_choice_init_firn = C%SMB_IMAUITM_choice_init_firn_GRL
    ELSEIF (region_name == 'ANT') THEN
      SMB_IMAUITM_choice_init_firn = C%SMB_IMAUITM_choice_init_firn_ANT
    END IF

    ! Initialise the firn layer
    IF     (SMB_IMAUITM_choice_init_firn == 'uniform') THEN
      ! Initialise with a uniform firn layer over the ice sheet

      DO i = grid%i1, grid%i2
      DO j = 1, grid%ny
        IF (ice%Hi_a( j,i) > 0._dp) THEN
          SMB%FirnDepth(        :,j,i) = C%SMB_IMAUITM_initial_firn_thickness
          SMB%MeltPreviousYear(   j,i) = 0._dp
        ELSE
          SMB%FirnDepth(        :,j,i) = 0._dp
          SMB%MeltPreviousYear(   j,i) = 0._dp
        END IF
      END DO
      END DO
      CALL sync

    ELSEIF (SMB_IMAUITM_choice_init_firn == 'restart') THEN
      ! Initialise with the firn layer of a previous run

      CALL initialise_IMAU_ITM_firn_restart( grid, SMB, region_name)

    ELSE
      CALL crash('unknown SMB_IMAUITM_choice_init_firn "' // TRIM( SMB_IMAUITM_choice_init_firn) // '"!')
    END IF

    ! Initialise albedo
    DO i = grid%i1, grid%i2
    DO j = 1, grid%ny

      ! Background albedo
      IF (ice%Hb_a( j,i) < 0._dp) THEN
        SMB%AlbedoSurf( j,i) = albedo_water
      ELSE
        SMB%AlbedoSurf( j,i) = albedo_soil
      END IF
      IF (ice%Hi_a( j,i) > 0._dp) THEN
        SMB%AlbedoSurf(  j,i) = albedo_snow
      END IF

      SMB%Albedo( :,j,i) = SMB%AlbedoSurf( j,i)

    END DO
    END DO
    CALL sync

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE initialise_SMB_model_IMAU_ITM
  SUBROUTINE initialise_IMAU_ITM_firn_restart( grid, SMB, region_name)
    ! If this is a restarted run, read the firn depth and meltpreviousyear data from the restart file

    IMPLICIT NONE

    ! In/output variables
    TYPE(type_grid),                     INTENT(IN)    :: grid
    TYPE(type_SMB_model_IMAU_ITM),       INTENT(INOUT) :: SMB
    CHARACTER(LEN=3),                    INTENT(IN)    :: region_name

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'initialise_IMAU_ITM_firn_restart'
    CHARACTER(LEN=256)                                 :: filename_restart
    REAL(dp)                                           :: time_to_restart_from
    TYPE(type_restart_data)                            :: restart

    ! Add routine to path
    CALL init_routine( routine_name)

    ! Assume that SMB and geometry are read from the same restart file
    IF     (region_name == 'NAM') THEN
      filename_restart     = C%filename_refgeo_init_NAM
      time_to_restart_from = C%time_to_restart_from_NAM
    ELSEIF (region_name == 'EAS') THEN
      filename_restart     = C%filename_refgeo_init_EAS
      time_to_restart_from = C%time_to_restart_from_EAS
    ELSEIF (region_name == 'GRL') THEN
      filename_restart     = C%filename_refgeo_init_GRL
      time_to_restart_from = C%time_to_restart_from_GRL
    ELSEIF (region_name == 'ANT') THEN
      filename_restart     = C%filename_refgeo_init_ANT
      time_to_restart_from = C%time_to_restart_from_ANT
    END IF

    ! Inquire if all the required fields are present in the specified NetCDF file,
    ! and determine the dimensions of the memory to be allocated.
    CALL allocate_shared_int_0D( restart%nx, restart%wnx)
    CALL allocate_shared_int_0D( restart%ny, restart%wny)
    CALL allocate_shared_int_0D( restart%nt, restart%wnt)
    IF (par%master) THEN
      restart%netcdf%filename = filename_restart
      CALL inquire_restart_file_SMB( restart)
    END IF
    CALL sync

    ! Allocate memory for raw data
    CALL allocate_shared_dp_1D( restart%nx, restart%x,    restart%wx   )
    CALL allocate_shared_dp_1D( restart%ny, restart%y,    restart%wy   )
    CALL allocate_shared_dp_1D( restart%nt, restart%time, restart%wtime)

    CALL allocate_shared_dp_3D( restart%nx, restart%ny, 12,         restart%FirnDepth,        restart%wFirnDepth       )
    CALL allocate_shared_dp_2D( restart%nx, restart%ny,             restart%MeltPreviousYear, restart%wMeltPreviousYear)

    ! Read data from input file
    IF (par%master) CALL read_restart_file_SMB( restart, time_to_restart_from)
    CALL sync

    ! Safety
    CALL check_for_NaN_dp_3D( restart%FirnDepth,        'restart%FirnDepth'       )
    CALL check_for_NaN_dp_2D( restart%MeltPreviousYear, 'restart%MeltPreviousYear')

    ! Since we want data represented as [j,i] internally, transpose the data we just read.
    CALL transpose_dp_3D( restart%FirnDepth,        restart%wFirnDepth       )
    CALL transpose_dp_2D( restart%MeltPreviousYear, restart%wMeltPreviousYear)

    ! Map (transposed) raw data to the model grid
    CALL map_square_to_square_cons_2nd_order_3D( restart%nx, restart%ny, restart%x, restart%y, grid%nx, grid%ny, grid%x, grid%y, restart%FirnDepth,        SMB%FirnDepth       )
    CALL map_square_to_square_cons_2nd_order_2D( restart%nx, restart%ny, restart%x, restart%y, grid%nx, grid%ny, grid%x, grid%y, restart%MeltPreviousYear, SMB%MeltPreviousYear)

    ! Deallocate raw data
    CALL deallocate_shared( restart%wnx              )
    CALL deallocate_shared( restart%wny              )
    CALL deallocate_shared( restart%wnt              )
    CALL deallocate_shared( restart%wx               )
    CALL deallocate_shared( restart%wy               )
    CALL deallocate_shared( restart%wtime            )
    CALL deallocate_shared( restart%wFirnDepth       )
    CALL deallocate_shared( restart%wMeltPreviousYear)

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE initialise_IMAU_ITM_firn_restart

! == Some generally useful tools
! ==============================

  FUNCTION Bueler_solution_MB( x, y, t) RESULT(M)
    ! Describes an ice-sheet at time t (in years) conforming to the Bueler solution
    ! with dome thickness H0 and margin radius R0 at t0, with a surface mass balance
    ! determined by lambda.

    ! Input variables
    REAL(dp), INTENT(IN) :: x       ! x coordinate [m]
    REAL(dp), INTENT(IN) :: y       ! y coordinate [m]
    REAL(dp), INTENT(IN) :: t       ! Time from t0 [years]

    ! Result
    REAL(dp)             :: M

    ! Local variables
    REAL(dp) :: A_flow, rho, g, n, alpha, beta, Gamma, f1, f2, t0, tp, f3, f4, H

    REAL(dp), PARAMETER :: H0     = 3000._dp    ! Ice dome thickness at t=0 [m]
    REAL(dp), PARAMETER :: R0     = 500000._dp  ! Ice margin radius  at t=0 [m]
    REAL(dp), PARAMETER :: lambda = 5.0_dp      ! Mass balance parameter

    A_flow  = 1E-16_dp
    rho     = 910._dp
    g       = 9.81_dp
    n       = 3._dp

    alpha = (2._dp - (n+1._dp)*lambda) / ((5._dp*n)+3._dp)
    beta  = (1._dp + ((2._dp*n)+1._dp)*lambda) / ((5._dp*n)+3._dp)
    Gamma = 2._dp/5._dp * (A_flow/sec_per_year) * (rho * g)**n

    f1 = ((2._dp*n)+1)/(n+1._dp)
    f2 = (R0**(n+1._dp))/(H0**((2._dp*n)+1._dp))
    t0 = (beta / Gamma) * (f1**n) * f2

    !tp = (t * sec_per_year) + t0; % Acutal equation needs t in seconds from zero , but we want to supply t in years from t0
    tp = t * sec_per_year

    f1 = (tp / t0)**(-alpha)
    f2 = (tp / t0)**(-beta)
    f3 = SQRT( (x**2._dp) + (y**2._dp) )/R0
    f4 = MAX(0._dp, 1._dp - (f2*f3)**((n+1._dp)/n))
    H = H0 * f1 * f4**(n/((2._dp*n)+1._dp))

    M = (lambda / tp) * H * sec_per_year

  END FUNCTION Bueler_solution_MB

END MODULE SMB_module
