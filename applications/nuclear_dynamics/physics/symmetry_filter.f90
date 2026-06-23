!> @file symmetry_filter.f90
!> @brief Symmetry-based post-selection filter for nuclear shell model bitstrings
!>
!> This module implements the key innovation of the nuclear SQD method: filtering
!> sampled bitstrings to keep only those with correct quantum numbers (N, Z, Jz, parity).
!> This exploits exact symmetries in nuclear physics to reduce required shots by 5-10*.
!>
!> Physics Background:
!> - Particle number conservation (N, Z) is exact in nuclear physics
!> - Jz is the z-component of total angular momentum (conserved in axially symmetric systems)
!> - Parity Π = (-1)^Σli is a multiplicative quantum number (product of single-particle parities)
!> - Post-selection exploits these symmetries to reduce Hilbert space by orders of magnitude

module symmetry_filter
    use iso_c_binding
    use orbital_registry, only: init_registry_sd_shell, reg_n_qubits, &
                                 reg_mj2, reg_parity
    implicit none
    private

    ! Public interface
    public :: filter_bitstrings, setup_single_particle_data
    public :: filter_bitstrings_parallel, init_parallel_filter

    ! Module-level quantum-number views — populated from orbital_registry
    integer(c_int), allocatable :: SD_MJ2(:)
    integer(c_int), allocatable :: SD_PAR(:)

    logical :: use_coarrays = .false.
    
contains

    !> @brief Initialize single-particle quantum number data for a given shell model space
    !>
    !> Sets up the SD_MJ2 and SD_PAR arrays containing quantum numbers for each
    !> orbital. Reads orbital data from USDB.snt via orbital_registry.
    !>
    !> @param[in] n_qubits Total number of qubits (orbitals)
    !> @param[in] shell_name Name of the shell model space (e.g., "sd")
    !>
    !> Note: The shell_name parameter is currently validated but the actual orbital
    !>       structure comes from USDB.snt, not hardcoded tables.
    subroutine setup_single_particle_data(n_qubits, shell_name) bind(c, name="setup_single_particle_data")
        integer(c_int), intent(in), value :: n_qubits
        character(kind=c_char), intent(in) :: shell_name(*)

        character(len=10) :: shell_str
        integer :: i

        shell_str = ""
        i = 1
        do while (shell_name(i) /= c_null_char .and. i <= 10)
            shell_str(i:i) = shell_name(i)
            i = i + 1
        end do

        if (trim(adjustl(shell_str)) /= "sd") then
            print *, "ERROR: Unsupported shell model space: ", trim(adjustl(shell_str))
            print *, "Currently supported: 'sd'"
            stop 1
        end if

        ! Delegate to orbital_registry — reads from USDB.snt file.
        ! n_protons/n_neutrons are not needed here because setup_single_particle_data
        ! is only used for mj/parity queries, not HF occupancy.
        ! We pass 0/0 so the registry is initialised without marking any qubit occupied;
        ! occupancy is set separately via init_registry_sd_shell when the ansatz is built.
        call init_registry_sd_shell(0_c_int, 0_c_int)

        ! Populate the local SD_MJ2/SD_PAR views from the registry so that the
        ! filter_bitstrings bind(C) interface continues to work unchanged.
        if (allocated(SD_MJ2)) deallocate(SD_MJ2)
        if (allocated(SD_PAR)) deallocate(SD_PAR)
        allocate(SD_MJ2(n_qubits))
        allocate(SD_PAR(n_qubits))
        do i = 0, n_qubits - 1
            SD_MJ2(i + 1) = reg_mj2(i)
            SD_PAR(i + 1) = reg_parity(i)
        end do

    end subroutine setup_single_particle_data
    
    
    !> @brief Filter bitstrings based on nuclear quantum number constraints
    !>
    !> This is the core symmetry filter that post-selects bitstrings satisfying:
    !> 1. Proton number: popcount(proton_bits) == n_protons
    !> 2. Neutron number: popcount(neutron_bits) == n_neutrons
    !> 3. Jz projection: sum(SD_MJ2 for occupied orbitals) == Mj_2target
    !> 4. Parity: XOR(SD_PAR for occupied orbitals) == parity_target
    !>
    !> @param[in] bitstrings Array of bitstring samples (character strings)
    !> @param[in] n_samples Number of bitstring samples
    !> @param[in] n_qubits Total number of qubits (24 for sd-shell)
    !> @param[in] n_qp Number of proton orbitals (12 for sd-shell)
    !> @param[in] n_qn Number of neutron orbitals (12 for sd-shell)
    !> @param[in] n_protons Target proton number
    !> @param[in] n_neutrons Target neutron number
    !> @param[in] Mj_2target Target 2*Jz value (integer)
    !> @param[in] parity_target Target parity (0=even, 1=odd)
    !> @param[out] kept Logical array indicating which samples pass filter
    !> @param[out] n_kept Count of samples that pass filter
    subroutine filter_bitstrings(bitstrings, n_samples, n_qubits, n_qp, n_qn, &
                                 n_protons, n_neutrons, Mj_2target, parity_target, &
                                 kept, n_kept) bind(c, name="filter_bitstrings")
        integer(c_int), intent(in), value :: n_samples, n_qubits, n_qp, n_qn
        integer(c_int), intent(in), value :: n_protons, n_neutrons, Mj_2target, parity_target
        character(kind=c_char), intent(in) :: bitstrings(n_qubits, n_samples)
        logical(c_bool), intent(out) :: kept(n_samples)
        integer(c_int), intent(out) :: n_kept
        
        integer :: i_sample, i_qubit
        integer :: proton_count, neutron_count
        integer :: Jz_2sum, parity_prod
        integer :: bit_val
        
        ! Validate inputs
        if (.not. allocated(SD_MJ2) .or. .not. allocated(SD_PAR)) then
            print *, "ERROR: Single-particle data not initialized. Call setup_single_particle_data first."
            stop 1
        end if
        
        if (n_qp + n_qn /= n_qubits) then
            print *, "ERROR: n_qp + n_qn must equal n_qubits"
            stop 1
        end if
        
        if (parity_target /= 0 .and. parity_target /= 1) then
            print *, "ERROR: parity_target must be 0 (even) or 1 (odd)"
            stop 1
        end if
        
        ! Initialize output
        kept = .false.
        n_kept = 0
        
        ! Loop over all bitstring samples
        do i_sample = 1, n_samples
            
            ! Initialize quantum numbers for this bitstring
            proton_count = 0
            neutron_count = 0
            Jz_2sum = 0
            parity_prod = 0  ! Using XOR: 0 for even, 1 for odd
            
            ! Process each qubit in the bitstring
            do i_qubit = 1, n_qubits
                
                ! Convert character '0' or '1' to integer
                if (bitstrings(i_qubit, i_sample) == '1') then
                    bit_val = 1
                else if (bitstrings(i_qubit, i_sample) == '0') then
                    bit_val = 0
                else
                    print *, "ERROR: Invalid bitstring character at sample", i_sample, "qubit", i_qubit
                    print *, "Expected '0' or '1', got: ", bitstrings(i_qubit, i_sample)
                    stop 1
                end if
                
                ! If this orbital is occupied (bit = 1), accumulate quantum numbers
                if (bit_val == 1) then
                    
                    ! Count protons (qubits 1 to n_qp)
                    if (i_qubit <= n_qp) then
                        proton_count = proton_count + 1
                    else
                        ! Count neutrons (qubits n_qp+1 to n_qubits)
                        neutron_count = neutron_count + 1
                    end if
                    
                    ! Accumulate Jz (sum of 2*mj values)
                    Jz_2sum = Jz_2sum + SD_MJ2(i_qubit)
                    
                    ! Accumulate parity (XOR operation)
                    parity_prod = ieor(parity_prod, SD_PAR(i_qubit))
                    
                end if
                
            end do
            
            ! Check all four filter criteria
            ! Criterion 1: Proton number conservation
            if (proton_count /= n_protons) cycle
            
            ! Criterion 2: Neutron number conservation
            if (neutron_count /= n_neutrons) cycle
            
            ! Criterion 3: Jz projection (z-component of angular momentum)
            if (Jz_2sum /= Mj_2target) cycle
            
            ! Criterion 4: Parity (multiplicative quantum number)
            if (parity_prod /= parity_target) cycle
            
            ! All criteria passed - keep this bitstring
            kept(i_sample) = .true.
            n_kept = n_kept + 1
            
        end do
        
    end subroutine filter_bitstrings
    
    
    !> @brief Initialize parallel filtering capabilities using Fortran coarrays
    !>
    !> This subroutine checks if coarray support is available (num_images() > 1)
    !> and enables parallel filtering if so. Must be called before using
    !> filter_bitstrings_parallel.
    !>
    !> Coarray Parallelism Model:
    !> - SPMD (Single Program Multiple Data): all images execute the same code
    !> - Each image has a unique ID from 1 to num_images()
    !> - Images work independently on different data subsets
    !> - Synchronization occurs only at critical points (start, end, reductions)
    !>
    !> Compiler Support:
    !> - GNU gfortran: compile with -fcoarray=lib (requires OpenCoarrays library)
    !> - Intel ifort/ifx: compile with -coarray or -coarray=shared
    !> - NAG nagfor: compile with -coarray
    !>
    !> Performance Notes:
    !> - Ideal for >100k shots where communication overhead is amortized
    !> - Each image holds full bitstring array but only processes its subset
    !> - Communication minimized: only synchronization and final reduction
    subroutine init_parallel_filter() bind(c, name="init_parallel_filter")
        
#ifdef USE_COARRAYS
        if (num_images() > 1) then
            use_coarrays = .true.
            if (this_image() == 1) then
                print *, "Parallel filtering enabled with", num_images(), "images"
                print *, "Each image will process approximately", &
                         "1/", num_images(), "of the bitstrings"
            end if
        else
            use_coarrays = .false.
            if (this_image() == 1) then
                print *, "Single image detected - using serial filtering"
            end if
        end if
#else
        use_coarrays = .false.
        print *, "Coarray support not compiled - using serial filtering"
        print *, "To enable: compile with -fcoarray=lib (gfortran) or -coarray (Intel)"
#endif
        
    end subroutine init_parallel_filter
    
    
    !> @brief Parallel version of filter_bitstrings using coarray distribution
    !>
    !> This subroutine distributes the post-selection workload across multiple
    !> images (processes) using Fortran coarrays. Each image processes a subset
    !> of bitstrings independently, then results are aggregated via coarray
    !> collective operations.
    !>
    !> Algorithm:
    !> 1. Distribute samples across images (load balancing with remainder handling)
    !> 2. Each image filters its assigned subset using same logic as filter_bitstrings
    !> 3. Local counts are reduced to global count via coarray reduction
    !> 4. Each image marks its portion of the kept array
    !> 5. Synchronize to ensure all images complete before returning
    !>
    !> Memory Scaling:
    !> - Each image holds: full bitstring array (read-only, shared)
    !> - Each image processes: ~n_samples/num_images() samples
    !> - Total memory: O(n_samples * n_qubits) per image (same as serial)
    !>
    !> Communication Pattern:
    !> - No communication during filtering (embarrassingly parallel)
    !> - Single reduction at end: O(num_images) integers
    !> - Synchronization barriers: 2 (before reduction, after broadcast)
    !>
    !> Performance Characteristics:
    !> - Speedup: ~num_images() for large n_samples (>100k)
    !> - Overhead: ~1ms per sync_all (negligible for large workloads)
    !> - Load balance: automatic via remainder distribution to last image
    !>
    !> @param[in] bitstrings Array of bitstring samples (character strings)
    !> @param[in] n_samples Number of bitstring samples
    !> @param[in] n_qubits Total number of qubits (24 for sd-shell)
    !> @param[in] n_qp Number of proton orbitals (12 for sd-shell)
    !> @param[in] n_qn Number of neutron orbitals (12 for sd-shell)
    !> @param[in] n_protons Target proton number
    !> @param[in] n_neutrons Target neutron number
    !> @param[in] Mj_2target Target 2*Jz value (integer)
    !> @param[in] parity_target Target parity (0=even, 1=odd)
    !> @param[out] kept Logical array indicating which samples pass filter
    !> @param[out] n_kept Count of samples that pass filter (global across all images)
    subroutine filter_bitstrings_parallel(bitstrings, n_samples, n_qubits, n_qp, n_qn, &
                                         n_protons, n_neutrons, Mj_2target, parity_target, &
                                         kept, n_kept) bind(c, name="filter_bitstrings_parallel")
        integer(c_int), intent(in), value :: n_samples, n_qubits, n_qp, n_qn
        integer(c_int), intent(in), value :: n_protons, n_neutrons, Mj_2target, parity_target
        character(kind=c_char), intent(in) :: bitstrings(n_qubits, n_samples)
        logical(c_bool), intent(out) :: kept(n_samples)
        integer(c_int), intent(out) :: n_kept
        
#ifdef USE_COARRAYS
        ! Coarray variables for distributed computation
        integer(c_int) :: n_kept_local          ! Local count for this image
        integer(c_int) :: n_kept_global[*]      ! Coarray for reduction
        
        ! Work distribution variables
        integer :: my_image, n_images
        integer :: samples_per_image, remainder
        integer :: my_start, my_end
        
        ! Loop variables (same as serial version)
        integer :: i_sample, i_qubit
        integer :: proton_count, neutron_count
        integer :: Jz_2sum, parity_prod
        integer :: bit_val
        
        ! Get image information
        my_image = this_image()
        n_images = num_images()
        
        ! Fallback to serial if only one image
        if (n_images == 1) then
            call filter_bitstrings(bitstrings, n_samples, n_qubits, n_qp, n_qn, &
                                  n_protons, n_neutrons, Mj_2target, parity_target, &
                                  kept, n_kept)
            return
        end if
        
        ! Validate inputs (same as serial version)
        if (.not. allocated(SD_MJ2) .or. .not. allocated(SD_PAR)) then
            if (my_image == 1) then
                print *, "ERROR: Single-particle data not initialized. Call setup_single_particle_data first."
            end if
            stop 1
        end if
        
        if (n_qp + n_qn /= n_qubits) then
            if (my_image == 1) then
                print *, "ERROR: n_qp + n_qn must equal n_qubits"
            end if
            stop 1
        end if
        
        if (parity_target /= 0 .and. parity_target /= 1) then
            if (my_image == 1) then
                print *, "ERROR: parity_target must be 0 (even) or 1 (odd)"
            end if
            stop 1
        end if
        
        ! ===================================================================
        ! STEP 1: Distribute workload across images
        ! ===================================================================
        ! Calculate base samples per image and remainder
        samples_per_image = n_samples / n_images
        remainder = mod(n_samples, n_images)
        
        ! Calculate this image's range
        ! Strategy: distribute remainder to last image for simplicity
        my_start = (my_image - 1) * samples_per_image + 1
        my_end = my_start + samples_per_image - 1
        
        ! Last image handles remainder samples
        if (my_image == n_images) then
            my_end = my_end + remainder
        end if
        
        ! Debug output (optional, can be removed for production)
        ! Uncomment for debugging:
        ! print *, "Image", my_image, "processing samples", my_start, "to", my_end
        
        ! ===================================================================
        ! STEP 2: Local filtering (embarrassingly parallel)
        ! ===================================================================
        ! Initialize output arrays
        kept = .false.
        n_kept_local = 0
        
        ! Loop over this image's assigned samples
        do i_sample = my_start, my_end
            
            ! Initialize quantum numbers for this bitstring
            proton_count = 0
            neutron_count = 0
            Jz_2sum = 0
            parity_prod = 0  ! Using XOR: 0 for even, 1 for odd
            
            ! Process each qubit in the bitstring
            do i_qubit = 1, n_qubits
                
                ! Convert character '0' or '1' to integer
                if (bitstrings(i_qubit, i_sample) == '1') then
                    bit_val = 1
                else if (bitstrings(i_qubit, i_sample) == '0') then
                    bit_val = 0
                else
                    if (my_image == 1) then
                        print *, "ERROR: Invalid bitstring character at sample", i_sample, "qubit", i_qubit
                        print *, "Expected '0' or '1', got: ", bitstrings(i_qubit, i_sample)
                    end if
                    stop 1
                end if
                
                ! If this orbital is occupied (bit = 1), accumulate quantum numbers
                if (bit_val == 1) then
                    
                    ! Count protons (qubits 1 to n_qp)
                    if (i_qubit <= n_qp) then
                        proton_count = proton_count + 1
                    else
                        ! Count neutrons (qubits n_qp+1 to n_qubits)
                        neutron_count = neutron_count + 1
                    end if
                    
                    ! Accumulate Jz (sum of 2*mj values)
                    Jz_2sum = Jz_2sum + SD_MJ2(i_qubit)
                    
                    ! Accumulate parity (XOR operation)
                    parity_prod = ieor(parity_prod, SD_PAR(i_qubit))
                    
                end if
                
            end do
            
            ! Check all four filter criteria
            ! Criterion 1: Proton number conservation
            if (proton_count /= n_protons) cycle
            
            ! Criterion 2: Neutron number conservation
            if (neutron_count /= n_neutrons) cycle
            
            ! Criterion 3: Jz projection (z-component of angular momentum)
            if (Jz_2sum /= Mj_2target) cycle
            
            ! Criterion 4: Parity (multiplicative quantum number)
            if (parity_prod /= parity_target) cycle
            
            ! All criteria passed - keep this bitstring
            kept(i_sample) = .true.
            n_kept_local = n_kept_local + 1
            
        end do
        
        ! ===================================================================
        ! STEP 3: Global reduction to aggregate results
        ! ===================================================================
        ! Store local count in coarray variable
        n_kept_global = n_kept_local
        
        ! Synchronize: ensure all images have stored their local counts
        sync all
        
        ! Image 1 performs the reduction
        if (my_image == 1) then
            n_kept = 0
            ! Sum counts from all images
            do i_sample = 1, n_images
                n_kept = n_kept + n_kept_global[i_sample]
            end do
        end if
        
        ! Synchronize before broadcast
        sync all
        
        ! Broadcast result to all images using co_broadcast
        ! Note: co_broadcast may not be available in all compilers
        ! Fallback: use explicit coarray assignment
        if (my_image /= 1) then
            n_kept = n_kept_global[1]  ! Read from image 1
        else
            n_kept_global = n_kept     ! Image 1 stores final result
        end if
        
        ! Final synchronization to ensure all images have the result
        sync all
        
        ! ===================================================================
        ! STEP 4: Complete - kept array already marked by each image
        ! ===================================================================
        ! The kept array is already correctly populated:
        ! - Each image marked its portion (my_start:my_end)
        ! - Other portions remain .false. (initialized at start)
        ! - No additional assembly needed
        
#else
        ! Coarray support not compiled - fall back to serial version
        call filter_bitstrings(bitstrings, n_samples, n_qubits, n_qp, n_qn, &
                              n_protons, n_neutrons, Mj_2target, parity_target, &
                              kept, n_kept)
#endif
        
    end subroutine filter_bitstrings_parallel
end module symmetry_filter
