require ("netcdf");

define slsh_main ()
{
   variable file = "simple_xy.nc";
   variable nc = netcdf_open (file, "r");
   variable data = nc.get ("data");
   nc.close ();

   % Check the data
   variable nx = 6, ny = 12;
   variable expected_data = _reshape ([0:nx*ny-1], [nx,ny]);
   ifnot (_eqs (data, expected_data))
     {
	message ("Failed to read the correct values");
	exit (1);
     }
   vmessage ("*** SUCCESS reading example file %s!", file);
}
