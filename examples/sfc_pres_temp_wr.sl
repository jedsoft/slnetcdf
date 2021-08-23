require ("netcdf");
define slsh_main ()
{
   variable
     file = "sfc_pres_temp.nc",
     nlat = 6, nlon = 12,
     lat_name = "latitude", lon_name = "longitude",
     pres_name = "pressure", temp_name =  "temperature";

   % Create some pretend data
   variable
     sample_pressure = 900, sample_temp = 9.0,
     start_lat = 25, start_lon = -125.0;

   variable lats = start_lat + 5.0*[0:nlat-1];
   variable lons = start_lon + 5.0*[0:nlon-1];

   variable
     pres_out = Float_Type[nlat, nlon],
     temp_out = Float_Type[nlat, nlon],
     lat;

   foreach lat ([0:nlat-1])
     {
	pres_out[lat, *] = sample_pressure + nlat*[0:nlon-1] + lat;
	temp_out[lat, *] = sample_temp + 0.25*(nlat*[0:nlon-1]+lat);
     }

   % Create the file
   variable nc = netcdf_open (file, "c");

   % Add dimensions and make them coordinate variables by specifying
   % the grid points
   nc.def_dim(lat_name, lats);
   nc.def_dim(lon_name, lons);

   % And attach units to them
   nc.put_att (lat_name, "units", "degrees_north");
   nc.put_att (lon_name, "units", "degrees_east");

   % Similarly define the pressure and temperature variables
   nc.def_var (pres_name, Float_Type, [lat_name, lon_name]);
   nc.def_var (temp_name, Float_Type, [lat_name, lon_name]);
   nc.put_att (pres_name, "units", "hPa");
   nc.put_att (temp_name, "units", "celsius");

   % Write the pretend data
   nc.put (pres_name, pres_out);
   nc.put (temp_name, temp_out);

   nc.close ();
   vmessage ("*** SUCCESS writing example file %s!\n", file);
}
