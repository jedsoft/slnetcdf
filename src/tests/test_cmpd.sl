() = evalfile(path_dirname(__FILE__) + "/common.sl");
require ("netcdf");

define slsh_main ()
{
   variable file = "ca2.nc";
   variable nc = netcdf_open (file, "c");

   variable rec_type = struct
     {
	counter = Int_Type,
	county_id = UInt16_Type,
	year = UInt16_Type,
	prac_code = UChar_Type,
	planted_acres = UInt16_Type[3],
	harvested_acres = UInt16_Type[3],
	yield = Float_Type[3],
	percent_comp = Float_Type[3],
     };
   nc.def_compound ("crop_harvesting_acreage", rec_type);

   variable npractices_len = 2, nyears_len = 2;
   nc.def_dim ("ncounty_ids", 0);      %  unlimited
   nc.def_dim ("npractices", npractices_len);
   nc.def_dim ("nyears", nyears_len);

   nc.def_var ("crop_harvest", "crop_harvesting_acreage", ["ncounty_ids", "nyears", "npractices"]);

   variable county_ids = [111, 222, 333];
   variable years = [2011, 2012];
   variable prac_codes = [13, 14];

   variable i, j, k, counter = 0;
   variable cell = @rec_type;	       % Make a copy
   _for i (0, length(county_ids)-1, 1)
     {
	cell.county_id = county_ids[i];
	_for j (0, nyears_len-1, 1)
	  {
	     cell.year = years[j];
	     _for k (0, npractices_len-1, 1)
	       {
		  cell.prac_code = prac_codes[k];

		  % Make up the rest of the data.  In practice it
		  % would be a function of county_id, year, and prac_code
		  cell.planted_acres = [11, 12, 13];
		  cell.harvested_acres = [101, 102, 103];
		  cell.yield = [11.5, 12.5, 13.5];
		  cell.percent_comp = [0.11, 0.12, 0.13];
		  cell.counter = counter; counter++;
		  % Write the cell
		  variable start = [i, j, k];
		  variable count = [1, 1, 1];
		  nc.put ("crop_harvest", cell, start, count);
	       }
	  }
     }
   nc.close ();

   nc = netcdf_open (file, "r");
   variable cells = nc.get ("crop_harvest");
   nc.close ();
   counter = 0;
   foreach cell (cells)
     {
	if (cell.counter != counter)
	  {
	     () = fprintf (stderr, "cell.counter=%S, expected %S\n", cell.counter, counter);
	     exit (1);
	  }
	counter++;
     }
}
