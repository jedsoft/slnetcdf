require ("netcdf");

private define make_complex_t (z)
{
   return struct
     {
	re = Real(z),
	im = Imag(z)
     };
}

private define make_pauli_t (z00, z01, z10, z11)
{
   variable p = _reshape (Struct_Type[4], [2,2]);
   p[0,0] = make_complex_t (z00);
   p[0,1] = make_complex_t (z01);
   p[1,0] = make_complex_t (z10);
   p[1,1] = make_complex_t (z11);
   return struct { matrix = p };
}

define slsh_main ()
{
   variable
     pauli_1 = make_pauli_t (0, 1, 1, 0),
     pauli_2 = make_pauli_t (0, -1i, 1i, 0),
     pauli_3 = make_pauli_t (1, 0, 0, -1);

   variable nc = netcdf_open ("pauli.nc", "c");
   nc.def_dim ("dim3", 3);

   nc.def_compound ("complex_t", struct {re=Double_Type, im=Double_Type});
   nc.def_compound ("pauli_t", struct {matrix = {"complex_t", 2, 2}});
   nc.def_compound ("pauli_matrices_t",
      struct {
	 pauli_x = "pauli_t",
	 pauli_y = "pauli_t",
	 pauli_z = "pauli_t",
      });

   nc.def_var ("pauli_xyz", "pauli_t", ["dim3"]);
   nc.def_var ("pauli_matrices", "pauli_matrices_t", NULL);   %  scalar

   nc.put ("pauli_xyz", [pauli_1, pauli_2, pauli_3]);
   nc.put ("pauli_matrices",
	   struct {pauli_x = pauli_1, pauli_y = pauli_2, pauli_z = pauli_3});

   nc.close ();
}
