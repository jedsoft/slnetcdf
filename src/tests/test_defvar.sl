() = evalfile(path_dirname(__FILE__) + "/common.sl");

require ("netcdf");

define slsh_main ()
{
   variable file = "test_defvar.nc";
   variable nc = netcdf_open (file, "c");

   nc.def_dim ("xdim", 0);
   nc.def_var ("intvar", Int_Type, "xdim"; fill=-99, chunking=30,
	       cache_preemp = 0.9, deflate=1, deflate_shuffle=1);
   variable s = nc.inq_var_storage ("intvar");
   nc.close ();

   if ((s.chunking[0] != 30) || (s.fill != -99) || fneqs(s.cache_preemp, 0.9)
       || (s.deflate != 1))
     {
	print (s);
	() = fprintf (stderr, "nc.inq_var_storage failed\n");
	exit (1);
     }
   () = remove (file);
}
