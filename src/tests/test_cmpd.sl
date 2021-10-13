() = evalfile(path_dirname(__FILE__) + "/common.sl");
require ("netcdf");

private define set_foo (foo)
{
   foo = @foo;
   foo.x = 0;
   foo.y = [1:4];
   foo.s = ["Test", "123"];
   foo.z = struct {fill = 0, three_strings = ["a1", "b1", "c1"], num_strings = 3};
   return foo;
}

define write_file (file)
{
   variable nc = netcdf_open (file, "c");

   variable sub_rec_type = struct
     {
	fill = Char_Type,
	three_strings = {String_Type, 3},
	num_strings = Int_Type,
     };

   nc.def_compound ("crop_harvesting_sub_type", sub_rec_type);

   variable rec_type = struct
     {
	counter = Int_Type,
	county_id = UInt16_Type,
	year = UInt16_Type,
	prac_code = UChar_Type,
	county_name = String_Type,
	sub_compound = {"crop_harvesting_sub_type", 2},
	fill_char = UChar_Type,
	some_strings = String_Type[2],
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
   cell.fill_char = 0xFF;
   cell.some_strings = ["foo", "bar"];

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
		  cell.sub_compound =
		    [
		     struct {fill = 11, three_strings = "X"+[string(i), string(j), string(k)], num_strings = 3},
		     struct {fill = 12, three_strings = "Y"+[string(i), string(j), string(k)], num_strings = 3},
		    ];
		  cell.counter = counter; cell.county_name = string(counter);
		  counter++;
		  % Write the cell
		  nc.put ("crop_harvest", cell, [i,j,k]);
	       }
	  }
     }

   variable foo_t = struct
     {
	x = Char_Type,
	y = Int_Type[4],
	s = String_Type[2],
	z = "crop_harvesting_sub_type",
     };
   nc.def_compound ("foo_t", foo_t);

   variable foo = set_foo (foo_t);
   nc.put_att ("crop_harvest", "crop_harvest_attr", foo; type="foo_t");

   nc.close ();
}

define read_file (file)
{
   variable nc = netcdf_open (file, "r");
   variable cell, cells = nc.get ("crop_harvest");
   variable foo_t = struct
     {
	x = Char_Type,
	y = Int_Type[4],
	s = String_Type[2],
	z = "crop_harvesting_sub_type",
     };
   variable foo = set_foo (foo_t);

   variable counter = 0;
   foreach cell (cells)
     {
	if (cell.counter != counter)
	  {
	     () = fprintf (stderr, "cell.counter=%S, expected %S\n", cell.counter, counter);
	     exit (1);
	  }
	if (cell.county_name != string(counter))
	  {
	     () = fprintf (stderr, "cell.county_name=%S, expected %S\n", cell.county_name, string(counter));
	     exit (1);
	  }
	counter++;
     }

   variable foo_in = nc.get_att ("crop_harvest", "crop_harvest_attr");
   ifnot (_eqs (foo, foo_in))
     {
	() = fprintf (stderr, "Failed to read compound attribute");
     }

   nc.close ();
}

define slsh_main ()
{
   variable file = "test_cmpd.nc";
   write_file (file);
   read_file (file);
   () = remove (file);
}
