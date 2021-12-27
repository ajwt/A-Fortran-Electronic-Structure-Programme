module mp2
   
   use const

   implicit none

   contains
      subroutine do_mp2_naive(sys, int_store)
         use system, only: system_t
         use integrals, only: int_store_t, eri_ind

         type(system_t), intent(inout) :: sys
         type(int_store_t), intent(inout) :: int_store

         integer :: i, j, k, l ! AO indices
         integer :: p, q, r, s ! MO indices
         integer :: pqrs, ij, kl
         integer :: s_up
         integer :: n, nocc
         integer :: a, b
         integer :: ia, ja, jb, ib

         allocate(int_store%eri_mo, mold=int_store%eri)

         ! The N^8 way to do it...
         n = sys%nbasis
         pqrs = 0
         associate(C=>sys%canon_coeff,eri=>int_store%eri)
         do p = 1, n
            do q = 1, p
               ! If r>p,  rs>pq, and we want rs <= pq
               do r = 1, p
                  if (p==r) then
                     ! If p==r, then s must be smaller than q for rs <= pq
                     s_up = q
                  else
                     ! Default rules
                     s_up = r
                  end if
                  do s = 1, s_up
                     pqrs = pqrs + 1
                     do i = 1, n
                        do j = 1, n
                           ij = eri_ind(i,j)
                           do k = 1, n
                              do l = 1, n
                                 kl = eri_ind(k,l)
                                 int_store%eri_mo(pqrs) = int_store%eri_mo(pqrs) &
                                 + C(p,i)*C(q,j)*C(r,k)*C(s,l)*eri(eri_ind(ij,kl))
                              end do
                           end do
                        end do
                     end do
                  end do
               end do
            end do
         end do
         end associate

         nocc = sys%nel/2
         associate(e=>sys%canon_levels, eri=>int_store%eri_mo, emp=>sys%e_mp2)
         do i = 1, nocc
            do j = 1, nocc
               do a = nocc+1, n
                  ia = eri_ind(i,a)
                  ja = eri_ind(j,a)
                  do b = nocc+1, n
                     jb = eri_ind(j,b)
                     ib = eri_ind(i,b)
                     emp = emp+(eri(eri_ind(ia,jb))*(2*eri(eri_ind(ia,jb))-eri(eri_ind(ib,ja))))&
                           / (e(i)+e(j)-e(a)-e(b))
                  end do
               end do
            end do
         end do
         end associate
         print*, sys%e_mp2

      end subroutine do_mp2_naive

      subroutine do_mp2(sys, int_store)

         use system, only: system_t
         use integrals, only: int_store_t, eri_ind

         type(system_t), intent(inout) :: sys
         type(int_store_t), intent(inout) :: int_store

         real(dp), allocatable :: tmp_a(:,:,:,:)
         real(dp), allocatable :: tmp_b(:,:,:,:) ! mixed integrals like (ij|rs)
         integer :: tmpdim, n, nocc
         integer :: i, j, k, l, p, q, r, s, a, b
         integer :: kl, ij, pq, rs, pqrs, s_up
         integer :: ia, ja, jb, ib
         integer, parameter :: iunit = 6

         n = sys%nbasis
         tmpdim = n*(n+1)/2

         write(iunit, '(1X, 10("-"))')
         write(iunit, '(1X, A)') 'MP2'
         write(iunit, '(1X, 10("-"))')

         write(iunit, '(1X, A)') 'Performing AO to MO ERI transformation...'
         ! dp used because 'p' is already a variable here
         allocate(tmp_a(n, n, n, n), source=0.0_dp)
         allocate(tmp_b(n, n, n, n), source=0.0_dp)

         allocate(int_store%eri_mo, mold=int_store%eri)

         
         !$omp parallel default(none) &
         !$omp private(kl, ij, pq, rs, pqrs, s_up, ia, ja, jb, ib) &
         !$omp shared(sys, int_store, tmp_a, tmp_b, nocc, n)
         associate(C=>sys%canon_coeff, eri_mo=>int_store%eri_mo, eri=>int_store%eri)
         !$omp do schedule(dynamic, 2) collapse(2)
         ! (ij|kl) -> (pj|kl)
         do k = 1, n
            do l = 1, n
               kl = eri_ind(k,l)
               do j = 1, n
                  do i = 1, n
                     ij = eri_ind(i,j)
                     do p = 1, n
                        tmp_a(p,j,k,l) = tmp_a(p,j,k,l) + eri(eri_ind(ij,kl))*C(p,i)
                     end do 
                  end do
               end do
            end do
         end do
         !$omp end do

         !$omp do schedule(dynamic, 2) collapse(2)
         ! (pj|kl) -> (pq|kl)
         do k = 1, n
            do l = 1, n
               kl = eri_ind(k,l)
               do p = 1, n
                  do j = 1, n
                     do q = 1, n
                        tmp_b(p,q,k,l) = tmp_b(p,q,k,l) + tmp_a(p,j,k,l)*C(q,j)
                     end do 
                  end do
               end do
            end do
         end do
         !$omp end do

         ! (pq|kl) -> (pq|rl)
         !$omp master
         tmp_a(:,:,:,:) = 0.0_dp
         !$omp end master

         !$omp do schedule(dynamic, 2) collapse(2)
         do p = 1, n
            do q = 1, n
               pq = eri_ind(p,q)
               do k = 1, n
                  do l = 1, n
                     kl = eri_ind(k,l)
                     do r = 1, n
                        tmp_a(p,q,r,l) = tmp_a(p,q,r,l) + tmp_b(p,q,k,l)*C(r,k)
                     end do 
                  end do
               end do
            end do
         end do
         !$omp end do

         ! (pq|rl) -> (pq|rs)
         !$omp master
         tmp_b(:,:,:,:) = 0.0_dp
         !$omp end master
         !$omp do schedule(dynamic, 2) collapse(2)
         do p = 1, n
            do q = 1, n
               pq = eri_ind(p,q)
               do r = 1, n
                  do l = 1, n
                     do s = 1, n
                        rs = eri_ind(r,s)
                        tmp_b(p,q,r,s) = tmp_b(p,q,r,s) + tmp_a(p,q,r,l)*C(s,l)
                     end do 
                  end do
               end do
            end do
         end do
         !$omp end do

         !$omp master
         pq = 0
         pqrs = 0
         do p = 1, n
            do q = 1, p
               pq = pq + 1
               do r = 1, p
                  if (p==r) then
                     ! If p==r, then s must be smaller than q for rs <= pq
                     s_up = q
                  else
                     ! Default rules
                     s_up = r
                  end if
                  do s = 1, s_up
                     pqrs = pqrs + 1
                     eri_mo(pqrs) = tmp_b(p,q,r,s)
                  end do
               end do
            end do
         end do
         !$omp end master
         end associate
         !$omp end parallel


         deallocate(tmp_a, tmp_b)
         write(iunit, '(1X, A)') 'Calculating MP2 energy...'

         nocc = sys%nel/2
         associate(e=>sys%canon_levels, eri=>int_store%eri_mo, emp=>sys%e_mp2)
         emp = 0.0_dp
         do i = 1, nocc
            do j = 1, nocc
               do a = nocc+1, n
                  ia = eri_ind(i,a)
                  ja = eri_ind(j,a)
                  do b = nocc+1, n
                     jb = eri_ind(j,b)
                     ib = eri_ind(i,b)
                     emp = emp+(eri(eri_ind(ia,jb))*(2*eri(eri_ind(ia,jb))-eri(eri_ind(ib,ja))))&
                           / (e(i)+e(j)-e(a)-e(b))
                  end do
               end do
            end do
         end do
         end associate

         write(iunit, '(1X, A, 1X, F15.8)') 'MP2 correlation energy (Hartree):', sys%e_mp2

      end subroutine do_mp2
         


end module mp2