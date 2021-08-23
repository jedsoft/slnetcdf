require ("netcdf");

private define create_data ()
{
   variable nlon = 12, nlat = 6, nlvl = 2;
   variable start_lat = 25.0, start_lon = -125.0;
   variable sample_pressure = 900.0, sample_temp = 9.0;

   variable lats = start_lat + [0:nlat-1]*5.0;
   variable lons = start_lon + [0:nlon-1]*5.0;

   variable pres = sample_pressure + [0:nlvl*nlat*nlon-1];
   variable temp = sample_temp + [0:nlvl*nlat*nlon-1];
   reshape (pres, [nlvl, nlat, nlon]);
   reshape (temp, [nlvl, nlat, nlon]);

   return struct
     {
	nlvl = nlvl, nrec = 2,
	lons = lons,
	lats = lats,
	pres = pres,
	temp = temp,
     };
}

private define pres_temp_4D_wr (file, data)
{
   variable nc = netcdf_open (file, "c");

   nc.def_dim ("level", data.nlvl);
   nc.def_dim ("latitude", data.lats); %  coordinate dim
   nc.def_dim ("longitude", data.lons); %  coordinate dim
   nc.def_dim ("time", 0);	       %  unlimited

   nc.put_att ("latitude", "units", "degrees_north");
   nc.put_att ("longitude", "units", "degrees_east");

   variable dims = ["time", "level", "latitude", "longitude"];
   nc.def_var ("pressure", Float_Type, dims);
   nc.def_var ("temperature", Float_Type, dims);
   nc.put_att ("pressure", "units", "hPa");
   nc.put_att ("temperature", "units", "celsius");

   % Write the data
   variable rec, nrec = data.nrec, start = [0,0,0,0];
   for (rec = 0; rec < nrec; rec++)
     {
	start[0] = rec;
	nc.put ("pressure", data.pres, start);
	nc.put ("temperature", data.temp, start);
     }

   nc.put_att ("Global-Array-of-Strings",
		["This is line 1", "This is line 2", "This is line 3"]);
   nc.close ();
   return 0;
}

private define pres_temp_4D_rd (file, data)
{
   return 0;
}

define slsh_main ()
{
   variable file = "pres_temp_4D.nc";
   variable data = create_data ();
   if (-1 == pres_temp_4D_wr (file, data))
     exit (1);
   if (-1 == pres_temp_4D_rd (file, data))
     exit (1);
}
