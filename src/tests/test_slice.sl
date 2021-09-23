() = evalfile(path_dirname(__FILE__) + "/common.sl");

require ("netcdf");

define slsh_main ()
{
   variable file = "test_slice.nc";

   variable data = _reshape ([1:13*17*11*23], [13, 17, 11, 23]);
   variable tgrid = [1:13];
   variable nc = netcdf_open (file, "c");
   nc.def_dim ("time", tgrid);
   nc.def_dim ("x", 17);
   nc.def_dim ("y", 11);
   nc.def_dim ("z", 23);
   nc.def_var ("txyz", Int_Type, ["time", "x", "y", "z"]);
   nc.put ("txyz", data);
   nc.close ();

   nc = netcdf_open (file, "r");
   variable i = 4;
   variable t = nc.get_slices ("time", i);
   if (t != tgrid[i])
     {
	() = fprintf (stderr, "Failed to read a single point from time");
	exit (1);
     }

   foreach i ({4, [4], [4,5], [0:12], [12:0:-1]})
     {
	t = nc.get_slices ("time", i);
	ifnot (_eqs (tgrid[i], t))
	  {
	     () = fprintf (stderr, "Failed to read time[%S]", i);
	     exit (1);
	  }
	variable txyz = nc.get_slices ("txyz", i);
	ifnot (_eqs (data[i, *, *, *], txyz))
	  {
	     () = fprintf (stderr, "Failed to read txyz[%S]", i);
	     exit (1);
	  }
	variable j;
	foreach j ({2, [3:7], [3], 10})
	  {
	     txyz = nc.get_slices ("txyz", i, j; dims=[0,2]);
	     ifnot (_eqs (data[i, *, j, *], txyz))
	       {
		  () = fprintf (stderr, "Failed to read txyz[%S,%S]", i, j);
		  exit (1);
	       }
	  }
     }
}
