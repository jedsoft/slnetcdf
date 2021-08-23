require ("netcdf");

define slsh_main ()
{
   variable nx = 6, ny = 12;
   variable data = _reshape ([0:nx*ny-1], [nx,ny]);
   variable nc = netcdf_open ("simple_xy.nc", "c");
   nc.def_dim ("x", nx);
   nc.def_dim ("y", ny);
   nc.def_var ("data", _typeof(data), ["x", "y"]);
   nc.put ("data", data);
   nc.close ();
   message ("*** SUCCESS writing example file simple_xy.nc!\n");
}
