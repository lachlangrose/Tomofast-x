
!========================================================================
!
!                    T O M O F A S T X  Version 1.0
!                  ----------------------------------
!
!              Main authors: Vitaliy Ogarko, Roland Martin,
!                   Jeremie Giraud, Dimitri Komatitsch.
! CNRS, France, and University of Western Australia.
! (c) CNRS, France, and University of Western Australia. January 2018
!
! This software is a computer program whose purpose is to perform
! capacitance, gravity, magnetic, or joint gravity and magnetic tomography.
!
! This program is free software; you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 2 of the License, or
! (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License along
! with this program; if not, write to the Free Software Foundation, Inc.,
! 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
!
! The full text of the license is available in file "LICENSE".
!
!========================================================================

!===============================================================================================
! A class to work with data for parallel inversion.
!
! Vitaliy Ogarko, UWA, CET, Australia, 2015.
!===============================================================================================
module data_gravmag

  use global_typedefs
  use mpi_tools, only: exit_MPI
  use string

  implicit none

  private

  type, public :: t_data

    ! Number of data points.
    integer :: ndata

    ! Data positions.
    real(kind=CUSTOM_REAL), dimension(:), allocatable :: X, Y, Z

    ! Data values measured and calculated (using a model from inversion).
    real(kind=CUSTOM_REAL), allocatable :: val_meas(:)
    real(kind=CUSTOM_REAL), allocatable :: val_calc(:)

  contains
    private

    procedure, public, pass :: initialize => data_initialize
    procedure, public, pass :: read => data_read
    procedure, public, pass :: write => data_write

    procedure, pass :: broadcast => data_broadcast
    procedure, pass :: read_points_format => data_read_points_format

  end type t_data

contains

!============================================================================================================
! Initialize data object.
!============================================================================================================
subroutine data_initialize(this, ndata, myrank)
  class(t_data), intent(inout) :: this
  integer, intent(in) :: ndata, myrank
  integer :: ierr

  this%ndata = ndata

  ierr = 0

  if (.not. allocated(this%X)) allocate(this%X(this%ndata), source=0._CUSTOM_REAL, stat=ierr)
  if (.not. allocated(this%Y)) allocate(this%Y(this%ndata), source=0._CUSTOM_REAL, stat=ierr)
  if (.not. allocated(this%Z)) allocate(this%Z(this%ndata), source=0._CUSTOM_REAL, stat=ierr)
  if (.not. allocated(this%val_meas)) allocate(this%val_meas(this%ndata), source=0._CUSTOM_REAL, stat=ierr)
  if (.not. allocated(this%val_calc)) allocate(this%val_calc(this%ndata), source=0._CUSTOM_REAL, stat=ierr)

  if (ierr /= 0) call exit_MPI("Dynamic memory allocation error in data_initialize!", myrank, ierr)

end subroutine data_initialize

!============================================================================================================
! Broadcasts data arrays.
!============================================================================================================
subroutine data_broadcast(this, myrank)
  class(t_data), intent(inout) :: this
  integer, intent(in) :: myrank
  integer :: ierr

  ierr = 0

  call MPI_Bcast(this%X, this%ndata, CUSTOM_MPI_TYPE, 0, MPI_COMM_WORLD, ierr)
  call MPI_Bcast(this%Y, this%ndata, CUSTOM_MPI_TYPE, 0, MPI_COMM_WORLD, ierr)
  call MPI_Bcast(this%Z, this%ndata, CUSTOM_MPI_TYPE, 0, MPI_COMM_WORLD, ierr)
  call MPI_Bcast(this%val_meas, this%ndata, CUSTOM_MPI_TYPE, 0, MPI_COMM_WORLD, ierr)

  if (ierr /= 0) call exit_MPI("MPI_Bcast error in data_broadcast!", myrank, ierr)

end subroutine data_broadcast

!============================================================================================================
! Read data (coordinates and values) in Universal Transverse Mercator (UTM)
! geographic map coordinate system.
!============================================================================================================
subroutine data_read(this, file_name, myrank)
  class(t_data), intent(inout) :: this
  character(len=*), intent(in) :: file_name
  integer, intent(in) :: myrank

  if (myrank == 0) then
    print *, 'Reading data from file '//trim(file_name)
    call this%read_points_format(file_name, myrank)
  endif

  ! MPI broadcast data arrays.
  call this%broadcast(myrank)

end subroutine data_read

!============================================================================================================
! Read data in points format.
!============================================================================================================
subroutine data_read_points_format(this, file_name, myrank)
  class(t_data), intent(inout) :: this
  character(len=*), intent(in) :: file_name
  integer, intent(in) :: myrank

  integer :: i, ierr
  integer :: ndata_in_file

  ! Reading my master CPU only.
  if (myrank /= 0) return

  open(unit=10, file=file_name, status='old', form='formatted', action='read', iostat=ierr)
  if (ierr /= 0) call exit_MPI("Error in opening the data file!", myrank, ierr)

  read(10, *) ndata_in_file

  if (ndata_in_file /= this%ndata) &
    call exit_MPI("The number of data in Parfile differs from the number of data in data file!", myrank, ndata_in_file)

  do i = 1, this%ndata
    read(10, *, end=20, err=11) this%X(i), this%Y(i), this%Z(i), this%val_meas(i)
  enddo

20 close(unit=10)

  return

11 call exit_MPI("Problem while reading the data!", myrank, 0)

end subroutine data_read_points_format

!================================================================================================
! Writes the data in two formats:
!   (1) to read by read_data();
!   (2) for Paraview visualization.
!
! which=1 - for measured data,
! which=2 - for calculated data.

! name_prefix = prefix for the file name.
!================================================================================================
subroutine data_write(this, name_prefix, which, myrank)
  class(t_data), intent(in) :: this
  character(len=*), intent(in) :: name_prefix
  integer, intent(in) :: which, myrank

  real(kind=CUSTOM_REAL) :: X, Y, Z, val
  integer :: i
  character(len=512) :: file_name, file_name2

  ! Write file by master CPU only.
  if (myrank /= 0) return

  file_name  = trim(path_output)//'/'//name_prefix//'data.txt'
  file_name2 = trim(path_output)//'/'//name_prefix//'data_csv.txt'

  print *, 'Writing data to file '//trim(file_name)

  ! TODO: add error check for file writing.
  open(10, file=trim(file_name), access='stream', form='formatted', status='unknown', action='write')
  ! For Paraview.
  open(20, file=trim(file_name2), access='stream', form='formatted', status='unknown', action='write')

  ! Writing a header line.
  write(10, *) this%ndata
  write(20, *) "x,y,z,f"

  ! Write data.
  do i = 1, this%ndata
    X = this%X(i)
    Y = this%Y(i)
    Z = this%Z(i)

    if (which == 1) then
      val = this%val_meas(i)
    else
      val = this%val_calc(i)
    endif

    write(10, *) X, Y, Z, val
    write(20, *) X, ", ", Y, ", ", Z, ", ", val
  enddo

  close(10)
  close(20)

end subroutine data_write

end module data_gravmag
