require ("netcdf");

define slsh_main ()
{
   variable file = "sfc_pres_temp.nc";
   variable nc = netcdf_open (file, "r");

   % Read the coordinate variable data
   variable lats = nc.get ("latitude");
   variable lons = nc.get ("longitude");

   % Check the coordinate data
   variable nlat = 6, nlon = 12, start_lat = 25.0, start_lon = -125.0;
   if (any (lats != start_lat + 5.0*[0:nlat-1]))
     exit (2);
   if (any (lons != start_lon + 5.0*[0:nlon-1]))
     exit (2);

   % Read the temperature and pressure arrays
   variable temp = nc.get ("temperature");
   variable pressure = nc.get ("pressure");

   % Check the values
   variable sample_pressure = 900, sample_temp = 9.0, lat, lon;
   _for lat (0, nlat-1, 1)
     {
	lon = [0:nlon-1];
	if (any (pressure[lat,*] != sample_pressure + (lon * nlat + lat)))
	  exit (2);
	if (any (temp[lat,*] != sample_temp + 0.25*(lon * nlat + lat)))
	  exit (2);
     }
   % Read and check attributes
   if ("degrees_north" != nc.get_att("latitude", "units")) exit(2);
   if ("degrees_east" !=  nc.get_att("longitude", "units")) exit(2);
   if ("hPa" != nc.get_att ("pressure", "units")) exit (2);
   if ("celsius" != nc.get_att ("temperature", "units")) exit(2);

   nc.close ();
   vmessage ("*** SUCCESS reading example file %s!\n", file);
}
