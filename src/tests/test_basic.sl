() = evalfile(path_dirname(__FILE__) + "/common.sl");

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
	scalar = 20.0,
     };
}

private define pres_temp_4D_wr (file, data, group)
{
   variable nc_root = netcdf_open (file, "c");

   nc_root.def_dim ("level", data.nlvl);
   nc_root.def_dim ("latitude", data.lats); %  coordinate dim
   nc_root.def_dim ("longitude", data.lons); %  coordinate dim
   nc_root.def_dim ("time", 0);	       %  unlimited

   nc_root.put_att ("latitude", "units", "degrees_north");
   nc_root.put_att ("longitude", "units", "degrees_east");

   variable nc = nc_root.def_grp (group);

   variable dims = ["time", "level", "latitude", "longitude"];
   nc.def_var ("pressure", Float_Type, dims);
   nc.def_var ("temperature", Float_Type, dims);
   nc.put_att ("pressure", "units", "hPa");
   nc.put_att ("temperature", "units", "celsius");
   nc.def_var ("scalar", Double_Type, NULL);

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
   nc.put_att ("A-2d-Array", _reshape ([1:77], [7,11]));
   nc.put ("scalar", data.scalar);
   nc.info ();

   nc_root.close ();
   return 0;
}

private define check_eqs (name, a, b)
{
   ifnot (_eqs (a, b))
     {
	if (name != NULL)
	  () = fprintf (stderr, "value of %S : %S != %S\n", name, a, b);
	return -1;
     }
   return 0;
}


private define check_get_att (nc, varname, attname, val)
{
   variable val1;

   val1 = nc.get_att (varname, attname);
   if (-1 == check_eqs (NULL, val, val1))
     {
	() = fprintf (stderr, "get_att %S->%S failed, expected %S got %S\n",
		      varname, attname, val, val1);
	return -1;
     }
   return 0;
}

private define check_get_var (nc, varname, val)
{
   variable val1 = nc.get (varname);
   if (-1 == check_eqs (NULL, val, val1))
     {
	() = fprintf (stderr, "get_var %S failed, expected %S got %S\n",
		      varname, val, val1);
	return -1;
     }
   return 0;
}

private define pres_temp_4D_rd (file, data, group)
{
   variable nc_root = netcdf_open (file, "r");

   if (-1 == check_get_att (nc_root, "latitude", "units", "degrees_north"))
     return -1;
   if (-1 == check_get_att (nc_root, "longitude", "units", "degrees_east"))
     return -1;
   if (-1 == check_get_var (nc_root, "longitude", data.lons))
     return -1;
   if (-1 == check_get_var (nc_root, "latitude", data.lats))
     return -1;

   variable nc = nc_root.group (group);
   if (-1 == check_get_att (nc, "pressure", "units", "hPa"))
     return -1;
   if (-1 == check_get_att (nc, "temperature", "units", "celsius"))
     return -1;
   if (-1 == check_get_att (nc, NULL, "A-2d-Array", [1:77]))
     return -1;

   variable x, rec, nrec = data.nrec,
     start = [0,0,0,0], count, shape;
   % Since slices are being read, both start and count must be specified
   _for rec (0, nrec-1, 1)
     {
	start[0] = rec;
	shape = array_shape (data.pres);
	count = [1, shape];
	x = nc.get ("pressure", start, count);
	reshape (x, shape);
	if (-1 == check_eqs ("pressure", x, data.pres))
	  return -1;

	shape = array_shape (data.temp);
	count = [1, shape];
	x = nc.get ("temperature", start, count);
	reshape (x, shape);
	if (-1 == check_eqs ("temperature", x, data.temp))
	  return -1;
     }

   if (-1 == check_get_var (nc, "scalar", data.scalar))
     return -1;

   nc_root.close();
   return 0;
}

define slsh_main ()
{
   variable file = "pres_temp_4D.nc";
   foreach (["/", "/subgroup", "/a/much/deeper/group"])
     {
	variable group = ();
	variable data = create_data ();
	if (-1 == pres_temp_4D_wr (file, data, group))
	  exit (1);
	if (-1 == pres_temp_4D_rd (file, data, group))
	  exit (1);
     }
   () = remove (file);
}
