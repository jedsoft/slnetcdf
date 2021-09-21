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
	return ncobj.group_info.varids[varname];
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
   else
     {
	_pop_n (_NARGS);
	usage ("<ncobj>.put (varname, data, [start, [count [,stride]]])");
     }

   variable varid = get_varid (ncobj, varname);
   variable ncid = ncobj.group_info.ncid;
   variable shape = _nc_inq_varshape (ncid, varid);
   variable ndims = length (shape);
   if (ndims == 0)
     {
	_nc_put_vars (data, ncid, varid);   %  scalar
	return;
     }

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

   _nc_put_vars (start, count, stride, data, ncid, varid);
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
   else
     {
	_pop_n(_NARGS);
	usage ("<ncobj>.get (varname, [start, [count [,stride]]])");
     }

   variable varid = get_varid (ncobj, varname);
   variable group_info = ncobj.group_info;

   ifnot (assoc_key_exists (group_info.varids, varname))
     throw InvalidParmError, "Variable name `$varname' does not exist or has not been defined"$;

   variable ncid = group_info.ncid;
   variable shape = _nc_inq_varshape (ncid, varid);
   variable ndims = length (shape);
   if (ndims == 0)
     {
	return _nc_get_vars (ncid, varid);
     }

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

   variable data = _nc_get_vars (start, count, stride, ncid, varid);
   if (is_scalar && (length (data) == 1))
     return data[[0]];

   return data;
}

private define create_group_instance ();   %  forward decl
private define netcdf_def_dim ()
{
   variable ncobj, name, val;

   if (_NARGS != 3)
     {
	_pop_n (_NARGS);
	usage ("<ncobj>.def_dim (name, len | array-of-grid-points)");
     }

   (ncobj, name, val) = ();

   variable ncid = ncobj.group_info.ncid;
   variable dimid = _nc_inq_dimid (ncid, name);
   if (dimid != NULL)
     throw InvalidParmError, "Dimension name `$name' has already exists"$, name;

   if (typeof (val) != Array_Type)
     {
	dimid = _nc_def_dim (ncid, name, val);
	return;
     }

   % Otherwise it is a coordinate dimension
   variable len = length (val);
   dimid = _nc_def_dim (ncid, name, len);
   ncobj.def_var (name, _typeof(val), [name]);
   ncobj.put (name, val);
}

private define netcdf_def_var ()
{
   variable ncobj, name, type, dims;

   if (_NARGS != 4)
     {
	_pop_n (_NARGS);
	usage ("<ncobj>.def_var (name, type, array-of-dim-names|NULL])");
     }

   (ncobj, name, type, dims) = ();

   variable group_info = ncobj.group_info;
   variable varids = group_info.varids;
   if (assoc_key_exists (varids, name))
     throw InvalidParmError, "Variable name `$name' already exists"$, name;

   variable ndims = (dims == NULL) ? 0 : length(dims);
   variable dimids = NetCDF_Dim_Type[ndims];
   variable ncid = group_info.ncid;
   _for (0, ndims-1, 1)
     {
	variable i = ();
	variable dim_i = dims[i];
	variable dimid = _nc_inq_dimid (ncid, dim_i);
	if (dimid == NULL)
	  throw InvalidParmError, "Dimension name `${dim_i}' does not exist"$;
	dimids[i] = dimid;
     }
   varids[name] = _nc_def_var (ncid, name, type, dimids);
}

private define netcdf_put_att ()
{
   variable ncobj, varname = NULL, attname, value;
   if (_NARGS == 3)
     (ncobj, attname, value) = ();
   else if (_NARGS == 4)
     (ncobj, varname, attname, value) = ();
   else
     {
	_pop_n (_NARGS);
	usage ("<ncobj>.put_att([varname,] attname, value);");
     }

   variable ncid = ncobj.group_info.ncid;
   if (varname == NULL)
     return _nc_put_global_att (value, ncid, attname);

   variable varid = get_varid (ncobj, varname);
   _nc_put_att (value, ncid, varid, attname);
}

private define netcdf_get_att ()
{
   variable ncobj, varname = NULL, attname;
   if (_NARGS == 2)
     (ncobj, attname) = ();
   else if (_NARGS == 3)
     (ncobj, varname, attname) = ();
   else
     {
	_pop_n (_NARGS);
	usage ("value = <ncobj>.get_att([varname,] attname)");
     }

   variable ncid = ncobj.group_info.ncid;
   if (varname == NULL)
     return _nc_get_global_att (ncid, attname);

   variable varid = get_varid (ncobj, varname);
   return _nc_get_att (ncid, varid, attname);
}

private define netcdf_close (ncobj)
{
   variable ncid = ncobj.shared_info.root_ncid;
   if (ncid == NULL) return;
   _nc_close (ncid);
   ncobj.shared_info.root_ncid = NULL;
   ncobj.shared_info = NULL;
   ncobj.group_info = NULL;
}

private define netcdf_info ()
{
   if (_NARGS != 1)
     {
	_pop_n (_NARGS);
	usage ("<ncobj>.info()");
     }

   variable ncobj = ();
   variable shared_info = ncobj.shared_info, group_info = ncobj.group_info;
   variable ncid = group_info.ncid;

   variable name, id, i, n, names;     %  generic vars used below

   variable str = "";
   str = str + sprintf ("group-name: %S\n", group_info.group_name);
   str = str + "dimensions:\n";

   variable dimids = _nc_inq_dimids (ncid, 0);   %  no parents
   foreach id (dimids)
     {
	variable len, is_unlimited;
	(name, len, is_unlimited) = _nc_inq_dim (ncid, id);
	if (is_unlimited)
	  str = str + sprintf ("\t%S = UNLIMITED; // %S currently\n", name, len);
	else
	  str = str + sprintf ("\t%S = %S;\n", name, len);
     }

   str = str + "variables:\n";
   foreach id (group_info.varids) using ("values")
     {
	variable type, vardims, varatts, e;
	try (e)
	  {
	     (name, type, vardims, varatts) = _nc_inq_var (ncid, id);
	  }
	catch AnyError:
	  {
	     str = str + sprintf ("**** Unsupported variable: %S : %S\n", _nc_inq_varname (ncid, id), e.message);
	     continue;
	  }

	n = length (vardims);
	names = String_Type[n];
	_for i (0, n-1, 1)
	  {
	     (names[i],,) = _nc_inq_dim (ncid, vardims[i]);
	  }

	str = str + sprintf ("\t%S %S(%S);\n", type, name, strjoin(names, ", "));
	if (length (varatts))
	  {
	     str = str + "\tAttributes:\n";
	     foreach name (varatts)
	       {
		  str = str + sprintf ("\t\t%s\n", name);
	       }
	  }
     }

   str = str + "groups:\n";
   foreach name (_nc_inq_grps (ncid))
     {
	str = str + sprintf ("\t%s;\n", name);
     }
   () = fputs (str, stdout);
}

private define netcdf_subgrps (ncobj)
{
   return _nc_inq_grps (ncobj.group_info.ncid);
}

private variable Netcdf_Group_Type = struct
{
   ncid,
   varids,
   group_name,
   subgroup_names,
};

private variable Netcdf_Shared_Type = struct
{
   root_ncid,			       %  ncdid of the root groupd
%   dimids,			       %  dimids are global to all groups
   groups,			       %  assoc array of Netcdf_Group_Type  
};

private define netcdf_def_grp ();      %  forward decl
private define netcdf_group ();      %  forward decl

private variable Netcdf_Obj = struct
{
   group_info,			       %  poiner to Netcdf_Group_Type
   shared_info,			       %  pointer to Netcdf_Shared_Type
   get = &netcdf_get,
   put = &netcdf_put,
   def_dim = &netcdf_def_dim,
   def_var = &netcdf_def_var,
   put_att = &netcdf_put_att,
   get_att = &netcdf_get_att,
   def_grp = &netcdf_def_grp,
   subgrps = &netcdf_subgrps,
   group = &netcdf_group,
   info = &netcdf_info,
   close = &netcdf_close,
};

% This function returns a group instance of a group that already exists
private define create_group_instance (shared_info, group_name)
{
   variable ncobj = @Netcdf_Obj;
   ncobj.shared_info = shared_info;
   ncobj.group_info = shared_info.groups[group_name];
   return ncobj;
}

private define create_new_group_instance (shared_info, ncid, group_name)
{
   variable ncobj = @Netcdf_Obj;
   ncobj.shared_info = shared_info;

   variable group_info = @Netcdf_Group_Type;
   group_info.group_name = group_name;
   group_info.ncid = ncid;
   group_info.varids = Assoc_Type[NetCDF_Var_Type];
   ncobj.group_info = group_info;
   shared_info.groups[group_name] = group_info;

   % Now read the dimensions, variables, and attributes
   variable dims, vars, attrs, dimid, varid;

   (dims, vars) = _nc_inq (ncid);

#iffalse
   variable ids = shared_info.dimids;
   foreach dimid (dims)
     {
	variable dim_name;
	(dim_name,,) = _nc_inq_dim (ncid, dimid);
	ids[dim_name] = dimid;
     }
#endif

   variable ids = group_info.varids;
   foreach varid (vars)
     {
	variable var_name = _nc_inq_varname (ncid, varid);
	ids[var_name] = varid;
     }

   return ncobj;
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

private define find_group (ncobj, name, def_grp_ok)
{
   variable shared_info = ncobj.shared_info;
   variable group_info = ncobj.group_info;

   variable new_group_name = path_concat (group_info.group_name, name);
   new_group_name = make_canonical_group_name (new_group_name);

   % Find an ancestor that exists
   variable groups = shared_info.groups;
   variable ancestor_name = new_group_name;
   forever
     {
	ancestor_name = path_dirname (ancestor_name);
	if (assoc_key_exists (groups, ancestor_name))
	  break;
	if (ancestor_name == "/")
	  throw UnknownError, "Unable to find a common group ancestor";
     }

   % Change the ncobj to an instantiation of the ancestor
   % Create the intermediate groups
   if (ancestor_name != group_info.group_name)
     ncobj = create_group_instance (shared_info, ancestor_name);

   variable decendents = strtok (new_group_name, "/");
   decendents = decendents[[length(strtok(ancestor_name, "/")):]];

   foreach (decendents)
     {
	variable child_name = ();
	variable ncid = ncobj.group_info.ncid;
	variable child_ncid = NULL;
	try
	  {
	     if (def_grp_ok)
	       child_ncid = _nc_def_grp (ncid, child_name);
	  }
	catch AnyError;

	if (child_ncid == NULL)
	  {
	     % Failed to create it, maybe it already exists in the file.
	     child_ncid = _nc_inq_grp_ncid (ncid, child_name);
	  }

	ancestor_name = path_concat (ancestor_name, child_name);
	ncobj = create_new_group_instance (shared_info, child_ncid, ancestor_name);
     }

   return ncobj;
}

private define netcdf_def_grp ()
{
   if (_NARGS != 2)
     {
	_pop_n (_NARGS);
	usage ("ncgrp = <ncobj>.def_grp (group_name)");
     }
   variable ncobj, name;
   (ncobj, name) = ();
   return find_group (ncobj, name, 1);
}

private define netcdf_group ()
{
   if (_NARGS != 2)
     {
	_pop_n (_NARGS);
	usage ("ncgrp = <ncobj>.group (group_name)");
     }

   variable ncobj, name;
   (ncobj, name) = ();
   return find_group (ncobj, name, 0);
}



% shared_info is passed to capture additional metadata if needed
private define open_existing (file, flags, shared_info)
{
   return _nc_open (file, flags);
}

private define open_new (file, flags, shared_info)
{
   return _nc_create (file, flags);
}

define netcdf_open ()
{
   if (_NARGS != 2)
     {
	usage ("\
nc = netcdf_open (file, mode [; qualifiers]);\n\
 mode:\n\
  \"r\" (read-only existing),\n\
  \"w\" (read-write existing),\n\
  \"c\" (create)\n\
Qualifiers:\n\
 noclobber, share, lock\n\
Methods:\n\
  .get       Read a netCDF variable\n\
  .put       Write to a netCDF variable\n\
  .def_dim   Define a netCDF dimension\n\
  .def_var   Define a netCDF variable\n\
  .put_att   Write a netCDF attribute\n\
  .get_att   Read a netCDF attribute\n\
  .def_grp   Define a netCDF group\n\
  .group     Open a netCDF group\n\
  .info      Print some information about the object\n\
  .close     Close the underlying netCDF file\n\
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

   variable shared_info = @Netcdf_Shared_Type;
   variable ncid = (@open_func)(file, flags, shared_info);

   %shared_info.dimids = Assoc_Type[NetCDF_Dim_Type];
   shared_info.groups = Assoc_Type[Struct_Type];
   shared_info.root_ncid = ncid;

   return create_new_group_instance (shared_info, ncid, "/");
}
