MODULE calving_module

  ! Contains all the routines for calving.

  USE mpi
  USE configuration_module,            ONLY: dp, C           
  USE parameters_module
  USE parallel_module,                 ONLY: par, sync, cerr, ierr, &
                                             allocate_shared_int_0D, allocate_shared_dp_0D, &
                                             allocate_shared_int_1D, allocate_shared_dp_1D, &
                                             allocate_shared_int_2D, allocate_shared_dp_2D, &
                                             allocate_shared_int_3D, allocate_shared_dp_3D, &
                                             deallocate_shared, partition_list
  USE data_types_module,               ONLY: type_grid, type_ice_model, type_reference_geometry
  USE netcdf_module,                   ONLY: debug, write_to_debug_file
  USE utilities_module,                ONLY: check_for_NaN_dp_1D,  check_for_NaN_dp_2D,  check_for_NaN_dp_3D, &
                                             check_for_NaN_int_1D, check_for_NaN_int_2D, check_for_NaN_int_3D, &
                                             is_floating

  IMPLICIT NONE
  
CONTAINS

  ! The main routine that's called from the IMAU_ICE_main_model
  SUBROUTINE apply_calving_law( grid, ice, refgeo_PD, refgeo_GIAeq)
    ! Apply the selected calving law, plus some calving-related operations

    IMPLICIT NONE

    ! Input variables:
    TYPE(type_grid),                     INTENT(IN)    :: grid
    TYPE(type_ice_model),                INTENT(INOUT) :: ice
    TYPE(type_reference_geometry),       INTENT(IN)    :: refgeo_PD 
    TYPE(type_reference_geometry),       INTENT(IN)    :: refgeo_GIAeq
    
    ! Local variables:
    INTEGER                                            :: i,j
    
    ! If so specified, remove all floating ice
    IF (C%do_remove_shelves) THEN
      DO i = grid%i1, grid%i2
      DO j = 1, grid%ny
        IF (is_floating( ice%Hi_a( j,i), ice%Hb_a( j,i), ice%SL_a( j,i))) THEN
          ice%Hi_a( j,i) = 0._dp
        END IF
      END DO
      END DO
      CALL sync
      RETURN
    END IF ! IF (C%do_remove_shelves) THEN
    
    ! If so specified, remove all floating ice beyond the present-day calving front
    IF (C%remove_shelves_larger_than_PD) THEN
      DO i = grid%i1, grid%i2
      DO j = 1, grid%ny
        IF (refgeo_PD%Hi( j,i) == 0._dp .AND. refgeo_PD%Hb( j,i) < 0._dp) THEN
          ice%Hi_a( j,i) = 0._dp
        END IF
      END DO
      END DO
      CALL sync
    END IF ! IF (C%remove_shelves_larger_than_PD) THEN
    
    ! If so specified, remove all floating ice crossing the continental shelf edge
    IF (C%continental_shelf_calving) THEN
      DO i = grid%i1, grid%i2
      DO j = 1, grid%ny
        IF (refgeo_GIAeq%Hi( j,i) == 0._dp .AND. refgeo_GIAeq%Hb( j,i) < C%continental_shelf_min_height) THEN
          ice%Hi_a( j,i) = 0._dp
        END IF
      END DO
      END DO
      CALL sync
    END IF ! IF (C%continental_shelf_calving) THEN
    
    ! Apply the selected calving law
    IF     (C%choice_calving_law == 'none') THEN
      ! No calving at all
    ELSEIF (C%choice_calving_law == 'threshold_thickness') THEN
      CALL threshold_thickness_calving( grid, ice)
    ELSE
      IF (par%master) WRITE(0,*) '  ERROR: choice_calving_law "', TRIM(C%choice_calving_law), '" not implemented in calculate_calving_flux!'
      CALL MPI_ABORT( MPI_COMM_WORLD, cerr, ierr)
    END IF
    
  END SUBROUTINE apply_calving_law
  
  ! Routines for different calving laws
  SUBROUTINE threshold_thickness_calving( grid, ice)
    ! A simple threshold thickness calving law

    IMPLICIT NONE

    ! Input variables:
    TYPE(type_grid),                     INTENT(IN)    :: grid
    TYPE(type_ice_model),                INTENT(INOUT) :: ice
    
    ! Local variables:
    INTEGER                                            :: i,j
    
    DO i = grid%i1, grid%i2
    DO j = 1, grid%ny
      
      IF (ice%mask_cf_a( j,i) == 1 .AND. ice%Hi_actual_cf_a( j,i) < C%calving_threshold_thickness) THEN
        ice%Hi_a( j,i) = 0._dp
      END IF
      
    END DO
    END DO
    CALL sync
    
  END SUBROUTINE threshold_thickness_calving
  
END MODULE calving_module
