import ("netcdf");

% netCDF-4/HDF5 data model:
%
%    Contains 1 or more hierarchically related groups.  The top-level
%    group is anonymous ("root")
%
%    Each group has its own dimensions, variables, and attributes.
%    The scope of a dimension object includes all of the groups
%    subgroups.
%

private define get_varid (ncobj, varname)
{
   try
     {
	return ncobj.varids[varname];
     }
   catch AnyError;

   throw UndefinedNameError, "netcdf variable $varname is undefined"$;
}

private define netcdf_put ()
{
   variable ncobj, varname, data, start = NULL, count = NULL, stride = NULL;

   if (_NARGS == 6)
     (ncobj, varname, data, start, count, stride) = ();
   else if (_NARGS == 5)
     (ncobj, varname, data, start, count) = ();
   else if (_NARGS == 4)
     (ncobj, varname, data, start) = ();
   else if (_NARGS == 3)
     (ncobj, varname, data) = ();
   else usage ("ncobj.nc_put (varname, data, [start, [count [,stride]]])");

   variable varid = get_varid (ncobj, varname);
   variable shape = _nc_inq_varshape (ncobj.ncid, varid);
   variable ndims = length (shape);
   if (start == NULL) start = ULong_Type[ndims];
   if (count == NULL)
     {
	variable data_shape = array_shape (data);
	variable data_ndims = length(data_shape);
	if (data_ndims == ndims)
	  count = data_shape;
	else
	  {
	     % Assume that data corresponds to the fastest varying dimensions
	     count = Int_Type[ndims] + 1;
	     count[[ndims-data_ndims:]] = data_shape;
	  }
     }
   if (stride == NULL) stride = Long_Type[ndims]+1;

   ifnot (assoc_key_exists (ncobj.varids, varname))
     throw InvalidParmError, "Variable name `$varname' does not exist or has not been defined"$;

   _nc_put_vars (start, count, stride, data, ncobj.ncid, varid);
}

private define netcdf_get ()
{
   variable ncobj, varname, start = NULL, count = NULL, stride = NULL;
   variable is_scalar = 0;

   if (_NARGS == 5)
     (ncobj, varname, start, count, stride) = ();
   else if (_NARGS == 4)
     (ncobj, varname, start, count) = ();
   else if (_NARGS == 3)
     (ncobj, varname, start) = ();
   else if (_NARGS == 2)
     (ncobj, varname) = ();
   else usage ("ncobj.nc_get (varname, [start, [count [,stride]]])");

   variable varid = get_varid (ncobj, varname);
   variable shape = _nc_inq_varshape (ncobj.ncid, varid);
   variable ndims = length (shape);
   if (start == NULL)
     start = ULong_Type[ndims];
   else
     {
	if (any (start < 0)) try
	  {
	     start = (start + shape) mod shape;
	  }
	catch AnyError: throw IndexError, "Invalid negative index";
     }
   if (count == NULL)
     {
	count = shape - start;
	is_scalar = 1;
     }
   if (stride == NULL) stride = Long_Type[ndims]+1;

   ifnot (assoc_key_exists (ncobj.varids, varname))
     throw InvalidParmError, "Variable name `$varname' does not exist or has not been defined"$;

   variable data = _nc_get_vars (start, count, stride, ncobj.ncid, varid);
   if (is_scalar && (length (data) == 1))
     return data[[0]];

   return data;
}

private define netcdf_def_dim ()
{
   variable ncobj, name, val;

   if (_NARGS != 3)
     usage ("ncobj.def_dim (name, len | array-of-grid-points)");

   (ncobj, name, val) = ();
   if (assoc_key_exists (ncobj.dimids, name))
     throw InvalidParmError, "Dimension name `$name' has already exists"$, name;
   if (typeof (val) != Array_Type)
     {
	ncobj.dimids[name] = _nc_def_dim (ncobj.ncid, name, val);
	return;
     }
   % Otherwise it is a coordinate dimension
   variable len = length (val);
   ncobj.dimids[name] = _nc_def_dim (ncobj.ncid, name, len);
   ncobj.def_var (name, _typeof(val), [name]);
   ncobj.put (name, val);
}

private define netcdf_def_var ()
{
   variable ncobj, name, type, dims;

   if (_NARGS != 4)
     usage ("ncobj.def_var (name, type, array-of-dim-names])");

   (ncobj, name, type, dims) = ();
   if (assoc_key_exists (ncobj.varids, name))
     throw InvalidParmError, "Variable name `$name' already exists"$, name;

   variable ndims = length(dims);
   variable dimids = NetCDF_Dim_Type[ndims];
   _for (0, ndims-1, 1)
     {
	variable i = ();
	variable dim_i = dims[i];
	ifnot (assoc_key_exists (ncobj.dimids, dim_i))
	  throw InvalidParmError, "Dimension name `${dim_i}' does not exist"$;
	dimids[i] = ncobj.dimids[dim_i];
     }
   ncobj.varids[name] = _nc_def_var (ncobj.ncid, name, type, dimids);
}

private define netcdf_put_att ()
{
   variable ncobj, varname = NULL, attname, value;
   if (_NARGS == 3)
     (ncobj, attname, value) = ();
   else if (_NARGS == 4)
     (ncobj, varname, attname, value) = ();
   else
     usage ("ncobj.put_att([varname,] attname, value);");

   if (varname == NULL)
     return _nc_put_global_att (value, ncobj.ncid, attname);

   variable varid = get_varid (ncobj, varname);
   _nc_put_att (value, ncobj.ncid, varid, attname);
}

private define netcdf_get_att ()
{
   variable ncobj, varname = NULL, attname;
   if (_NARGS == 2)
     (ncobj, attname) = ();
   else if (_NARGS == 3)
     (ncobj, varname, attname) = ();
   else
     usage ("value = ncobj.get_att([varname,] attname)");

   if (varname == NULL)
     return _nc_get_global_att (ncobj.ncid, attname);

   variable varid = get_varid (ncobj, varname);
   _nc_get_att (ncobj.ncid, varid, attname);
}

private define netcdf_close (ncobj)
{
   _nc_close (ncobj.ncid);
   ncobj.ncid = NULL;
   ncobj.dimids = NULL;
   ncobj.varids = NULL;                             %  assoc array
   ncobj.group_name = NULL;
   ncobj.subgroups = NULL;
}

private define open_existing (ncobj, file, flags)
{
   variable ncid = _nc_open (file, flags);
   ncobj.ncid = ncid;

   % Now read the dimensions, variables, and attributes
   variable dims, vars, attrs, dimid, varid;

   (dims, vars) = _nc_inq (ncobj.ncid);

   foreach dimid (dims)
     {
	variable dim_name;
	(dim_name,) = _nc_inq_dim (ncid, dimid);
	ncobj.dimids[dim_name] = dimid;
     }

   foreach varid (vars)
     {
	variable var_name = _nc_inq_varname (ncid, varid);
	ncobj.varids[var_name] = varid;
     }
}

private define make_canonical_group_name (path)
{
   variable components = strtok (path, "/");
   components = components[where (components != ".")];

   variable new_components = {};
   foreach (components)
     {
        variable elem = ();
        if (elem == "..")
          {
             if (length (new_components))
               () = list_pop (new_components, -1);
             continue;
          }
        list_append (new_components, elem);
     }
   ifnot (length (new_components)) return "/";
   return "/" + strjoin (list_to_array(new_components), "/");
}

private define netcdf_def_grp ()
{
   throw NotImplementedError, ".def_grp has not been implemented";
   if (_NARGS != 2)
     usage ("ncobj.def_grp (group_name)");
   variable ncobj, name;
   (ncobj, name) = ();

   variable group_name = path_concat (ncobj.group_name, name);
   group_name = make_canonical_group_name (group_name);
   if (group_name == "/")
     {
     }
}

private define open_new (ncobj, file, flags)
{
   ncobj.ncid = _nc_create (file, flags);
}

private variable Netcdf_Obj = struct
{
   ncid,			       %  file or group
   dimids,			       %  assoc array
   varids,			       %  assoc array
   group_name,
   subgroups,
   get = &netcdf_get,
   put = &netcdf_put,
   def_dim = &netcdf_def_dim,
   def_var = &netcdf_def_var,
   put_att = &netcdf_put_att,
   get_att = &netcdf_get_att,
   def_grp = &netcdf_def_grp,
   close = &netcdf_close,
};

define netcdf_open ()
{
   if (_NARGS != 2)
     {
	usage ("\
ncobj = netcdf_open (file, mode [; qualifiers]);\n\
 mode:\n\
  \"r\" (read-only existing),\n\
  \"w\" (read-write existing),\n\
  \"c\" (create)\n\
Qualifiers:\n\
 noclobber, share, lock\n\
"
	      );
     }

   variable file, mode, flags = 0, open_func = &open_existing;
   (file, mode) = ();

   switch (mode)
     {
      case "c": open_func = &open_new;
	flags |= NC_NETCDF4;
     }
     {
      case "r":
	% default
     }
     {
      case "w":
	flags |= NC_WRITE;
     }
     {
	% default:
	throw InvalidParmError, "Invalid/Unsupported mode string (\"$mode\")"$;
     }

   if (qualifier_exists ("noclobber")) flags |= NC_NOCLOBBER;
   if (qualifier_exists ("share")) flags |= NC_SHARE;
   if (qualifier_exists ("lock")) flags |= NC_LOCK;

   variable obj = @Netcdf_Obj;
   obj.dimids = Assoc_Type[NetCDF_Dim_Type];
   obj.varids = Assoc_Type[NetCDF_Var_Type];
   (@open_func)(obj, file, flags);

   return obj;
}
