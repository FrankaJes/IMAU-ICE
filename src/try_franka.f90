!In data_types_netcdf_module.f90 
  TYPE type_netcdf_BMB_data

    CHARACTER(LEN=256) :: filename

    ! ID for NetCDF file:
    INTEGER :: ncid

    ! Index of time frame to be written to
    INTEGER :: ti

  ! ID's for dimensions:
  ! ===================

    ! Dimensions
    INTEGER :: id_dim_x
    INTEGER :: id_dim_y
    !INTEGER :: id_dim_month

    CHARACTER(LEN=256) :: name_dim_x                     = 'x'
    CHARACTER(LEN=256) :: name_dim_y                     = 'y'
    !CHARACTER(LEN=256) :: name_dim_month                 = 'month                '

    INTEGER :: id_var_x
    INTEGER :: id_var_y
    !INTEGER :: id_var_month

    CHARACTER(LEN=256) :: name_var_x                     = 'x'
    CHARACTER(LEN=256) :: name_var_y                     = 'y'
    !CHARACTER(LEN=256) :: name_var_month                 = 'month                '

  ! File data - melt ice shelf
  ! =================================================================

    ! Ice dynamics
    INTEGER :: id_var_melt

    CHARACTER(LEN=256) :: name_var_melt                  = 'melt'

  END TYPE type_netcdf_BMB_data



!In data_types_module.f90 
TYPE type_BMB_data
    ! Restart data and NetCDF file

    ! NetCDF file
    TYPE(type_netcdf_BMB_data)              :: netcdf

    ! Grid
    INTEGER,                    POINTER     :: nx, ny
    REAL(dp), DIMENSION(:    ), POINTER     :: x, y
    INTEGER :: wnx, wny, wx, wy

    ! Melt field
    REAL(dp), DIMENSION(:,:  ), POINTER     :: melt

    INTEGER :: wmelt

  END TYPE type_BMB_data




! In netcdf module
  SUBROUTINE inquire_BMB_data_file(     BMB_data)
    ! Check if the right dimensions and variables are present in the file.

    IMPLICIT NONE

    ! Input variables:
    TYPE(type_BMB_data),        INTENT(INOUT) :: BMB_data

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                 :: routine_name = 'inquire_BMB_data_file'
    INTEGER                                       :: x, y

    ! Add routine to path
    CALL init_routine( routine_name)

    IF (.NOT. par%master) THEN
      CALL finalise_routine( routine_name)
      RETURN
    END IF

    ! Open the netcdf file
    CALL open_netcdf_file( BMB_data%netcdf%filename, BMB_data%netcdf%ncid)

    ! Inquire dimensions id's. Check that all required dimensions exist, return their lengths.
    CALL inquire_dim( BMB_data%netcdf%ncid, BMB_data%netcdf%name_dim_x,     BMB_data%nx, BMB_data%netcdf%id_dim_x    )
    CALL inquire_dim( BMB_data%netcdf%ncid, BMB_data%netcdf%name_dim_y,     BMB_data%ny, BMB_data%netcdf%id_dim_y    )

    ! Abbreviations for shorter code
    x = BMB_data%netcdf%id_dim_x
    y = BMB_data%netcdf%id_dim_y

    ! Inquire variable ID's; make sure that each variable has the correct dimensions.

    ! Dimensions
    CALL inquire_double_var( BMB_data%netcdf%ncid, BMB_data%netcdf%name_var_x,                (/ x             /), restart%netcdf%id_var_x   )
    CALL inquire_double_var( BMB_data%netcdf%ncid, BMB_data%netcdf%name_var_y,                (/    y          /), restart%netcdf%id_var_y   )

    ! Data
    CALL inquire_double_var( BMB_data%netcdf%ncid, BMB_data%netcdf%name_var_melt,              (/ x, y,       t /), BMB_data%netcdf%id_var_melt)

    ! Close the netcdf file
    CALL close_netcdf_file( BMB_data%netcdf%ncid)

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE inquire_BMB_data_file


  SUBROUTINE read_BMB_data_file(      BMB_data)
    ! Read the restart netcdf file

    IMPLICIT NONE

    ! Input variables:
    TYPE(type_restart_data),        INTENT(INOUT) :: BMB_data

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                 :: routine_name = 'read_BMB_data_file'
    !INTEGER                                       :: ti, ti_min
    !REAL(dp)                                      :: dt, dt_min

    ! Add routine to path
    CALL init_routine( routine_name)

    IF (.NOT. par%master) THEN
      CALL finalise_routine( routine_name)
      RETURN
    END IF

    ! Open the netcdf file
    CALL open_netcdf_file( BMB_data%netcdf%filename, BMB_data%netcdf%ncid)

    ! Read x,y
    CALL handle_error(nf90_get_var( BMB_data%netcdf%ncid, BMB_data%netcdf%id_var_x, BMB_data%x, start=(/1/) ))
    CALL handle_error(nf90_get_var( BMB_data%netcdf%ncid, BMB_data%netcdf%id_var_y, BMB_data%y, start=(/1/) ))

    ! Read the data
    CALL handle_error(nf90_get_var( BMB_data%netcdf%ncid, BMB_data%netcdf%id_var_melt, BMB_data%melt, start = (/ 1, 1 /), count = (/ BMB_data%nx, BMB_data%ny/) ))

    ! Close the netcdf file
    CALL close_netcdf_file( BMB_data%netcdf%ncid)

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE read_BMB_data_file




! LADDIE output for identical geometry
  SUBROUTINE inquire_LADDIE_output_file( ocn)
    ! Check if the right dimensions and variables are present in the file.

    IMPLICIT NONE

    ! Input variables:
    TYPE(type_BMB_model), INTENT(INOUT) :: ocn

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                 :: routine_name = 'inquire_LADDIE_output_file'

    ! Add routine to path
    CALL init_routine( routine_name)

    IF (.NOT. par%master) THEN
      CALL finalise_routine( routine_name)
      RETURN
    END IF

    ! Open the netcdf file
    CALL open_netcdf_file( ocn%netcdf%filename, ocn%netcdf%ncid)

    ! Inquire dimensions id's. Check that all required dimensions exist return their lengths.
    CALL inquire_dim( ocn%netcdf%ncid, ocn%netcdf%name_dim_lat,     ocn%nlat,         ocn%netcdf%id_dim_lat    )
    CALL inquire_dim( ocn%netcdf%ncid, ocn%netcdf%name_dim_lon,     ocn%nlon,         ocn%netcdf%id_dim_lon    )
    CALL inquire_dim( ocn%netcdf%ncid, ocn%netcdf%name_dim_z_ocean, ocn%nz_ocean_raw, ocn%netcdf%id_dim_z_ocean)

    ! Inquire variable id's. Make sure that each variable has the correct dimensions:
    CALL inquire_double_var( ocn%netcdf%ncid, ocn%netcdf%name_var_lat,     (/ ocn%netcdf%id_dim_lat     /), ocn%netcdf%id_var_lat    )
    CALL inquire_double_var( ocn%netcdf%ncid, ocn%netcdf%name_var_lon,     (/ ocn%netcdf%id_dim_lon     /), ocn%netcdf%id_var_lon    )
    CALL inquire_double_var( ocn%netcdf%ncid, ocn%netcdf%name_var_z_ocean, (/ ocn%netcdf%id_dim_z_ocean /), ocn%netcdf%id_var_z_ocean)

    CALL inquire_double_var( ocn%netcdf%ncid, TRIM(C%name_ocean_temperature_obs), (/ ocn%netcdf%id_dim_lon, ocn%netcdf%id_dim_lat, ocn%netcdf%id_dim_z_ocean /),  ocn%netcdf%id_var_T_ocean)
    CALL inquire_double_var( ocn%netcdf%ncid, TRIM(C%name_ocean_salinity_obs)   , (/ ocn%netcdf%id_dim_lon, ocn%netcdf%id_dim_lat, ocn%netcdf%id_dim_z_ocean /),  ocn%netcdf%id_var_S_ocean)

    ! Close the netcdf file
    CALL close_netcdf_file( ocn%netcdf%ncid)

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE inquire_LADDIE_output_file
  SUBROUTINE read_LADDIE_output_file(    ocn)

    IMPLICIT NONE

    ! Input variables:
    TYPE(type_BMB_model), INTENT(INOUT) :: ocn

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                 :: routine_name = 'read_PD_obs_global_ocean_file'

    ! Add routine to path
    CALL init_routine( routine_name)

    IF (.NOT. par%master) THEN
      CALL finalise_routine( routine_name)
      RETURN
    END IF

    ! Open the netcdf file
    CALL open_netcdf_file( ocn%netcdf%filename, ocn%netcdf%ncid)

    ! Read the data
    CALL handle_error(nf90_get_var( ocn%netcdf%ncid, ocn%netcdf%id_var_lon,     ocn%lon,         start = (/ 1       /) ))
    CALL handle_error(nf90_get_var( ocn%netcdf%ncid, ocn%netcdf%id_var_lat,     ocn%lat,         start = (/ 1       /) ))
    CALL handle_error(nf90_get_var( ocn%netcdf%ncid, ocn%netcdf%id_var_z_ocean, ocn%z_ocean_raw, start = (/ 1       /) ))

    CALL handle_error(nf90_get_var( ocn%netcdf%ncid, ocn%netcdf%id_var_T_ocean, ocn%T_ocean_raw, start = (/ 1, 1, 1 /) ))
    CALL handle_error(nf90_get_var( ocn%netcdf%ncid, ocn%netcdf%id_var_S_ocean, ocn%S_ocean_raw, start = (/ 1, 1, 1 /) ))

    ! Close the netcdf file
    CALL close_netcdf_file( ocn%netcdf%ncid)

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE read_PD_obs_global_ocean_file