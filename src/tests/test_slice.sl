() = evalfile(path_dirname(__FILE__) + "/common.sl");

require ("netcdf");

private define test_get_slices (file, data, tgrid)
{
   variable nc = netcdf_open (file, "r");
   variable i = 4;
   variable t = nc.get_slices ("time", i);
   if (t != tgrid[i])
     {
	() = fprintf (stderr, "Failed to read a single point from time\n");
	exit (1);
     }

   variable txyz = nc.get_slices ("txyz", [*], [*], [*], [*]);
   ifnot (_eqs (data, txyz))
     {
	() = fprintf (stderr, "Failed to read txyz[*,*,*,*]\n");
	exit (1);
     }

   foreach i ({4, [4], [4,5], [0:12], [12:0:-1]})
     {
	t = nc.get_slices ("time", i);
	ifnot (_eqs (tgrid[i], t))
	  {
	     () = fprintf (stderr, "Failed to read time[%S]\n", i);
	     exit (1);
	  }
	txyz = nc.get_slices ("txyz", i);
	ifnot (_eqs (data[i, *, *, *], txyz))
	  {
	     () = fprintf (stderr, "Failed to read txyz[%S]\n", i);
	     exit (1);
	  }
	variable j;
	foreach j ({2, [3:7], [3], 10})
	  {
	     txyz = nc.get_slices ("txyz", i, j; dims=[0,2]);
	     ifnot (_eqs (data[i, *, j, *], txyz))
	       {
		  () = fprintf (stderr, "Failed to read txyz[%S,%S]\n", i, j);
		  exit (1);
	       }
	  }
     }
}

private define test_put_slices (file, data, tgrid, index_list)
{
   variable nc = netcdf_open (file, "c");
   nc.def_dim ("time", tgrid);
   nc.def_dim ("x", 17);
   nc.def_dim ("y", 11);
   nc.def_dim ("z", 23);
   nc.def_var ("txyz", Int_Type, ["time", "x", "y", "z"]);

   variable i, idx, dims = Int_Type[0], index_args = {};
   _for i (0, length(index_list)-1, 1)
     {
	idx = index_list[i];
	if (length (idx) == 0) continue;
	dims = [dims, i];
	list_append (index_args, idx);
     }

   variable out_data = data[__push_list(index_list)];
   nc.put_slices ("txyz", __push_list (index_args), out_data; dims=dims);
   nc.close ();

   nc = netcdf_open (file, "r");
   variable in_data = nc.get_slices ("txyz", __push_list(index_args); dims=dims);
   nc.close ();

   ifnot (_eqs (in_data, out_data))
     {
	() = fprintf (stderr, "test_put_slices failed");
     }
}

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

   test_get_slices (file, data, tgrid);

   nc = netcdf_open (file, "c");
   nc.def_dim ("time", tgrid);
   nc.def_dim ("x", 17);
   nc.def_dim ("y", 11);
   nc.def_dim ("z", 23);
   nc.def_var ("txyz", Int_Type, ["time", "x", "y", "z"]);

   variable i0 = [0::2], i1 = [1::2];
   nc.put_slices ("txyz", i0, data[*,i0,*,*]; dims=[1]);
   nc.put_slices ("txyz", i1, data[*,i1,*,*]; dims=[1]);
   nc.close ();
   nc = netcdf_open (file, "r");
   variable txyz = nc.get ("txyz");
   ifnot (_eqs (txyz, data))
     {
	print (txyz != data);
	() = fprintf (stderr, "put_slices failed\n");
	print (txyz);
	exit (1);
     }
   nc.close ();

   test_put_slices (file, data, tgrid, {[*], [*], [*], [0:10]});
   test_put_slices (file, data, tgrid, {[*], 0, [*], 1});
   test_put_slices (file, data, tgrid, {0, 0, 0, 1});

   () = remove (file);
}
