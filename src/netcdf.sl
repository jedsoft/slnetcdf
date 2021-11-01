% Copyright (C) 2021 John E. Davis <jed@jedsoft.org>
%
% This file is part of the S-Lang netcdf module
%
% The S-Lang netcdf module is free software: you can redistribute it
% and/or modify it under the terms of the GNU General Public License
% as published by the Free Software Foundation, either version 3 of
% the License, or (at your option) any later version.
%
% The S-Lang netcdf module is distributed in the hope that it will be
% useful, but WITHOUT ANY WARRANTY; without even the implied warranty
% of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
% General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with the S-Lang netcdf module.  If not, see
% <https://www.gnu.org/licenses/>.
%

import ("netcdf");

private define get_varid (ncobj, varname)
{
   try
     {
	return ncobj.group_info.varids[varname];
     }
   catch AnyError;

   throw UndefinedNameError, "netcdf variable $varname is undefined"$;
}


% On stack: ncobj, varname
% returns (ncobj, ncid, varid, varname, varshape)
private define pop_ncobj_var_info ()
{
   variable ncobj, varname;
   (ncobj, varname) = ();

   variable varid = get_varid (ncobj, varname);
   variable group_info = ncobj.group_info;

   ifnot (assoc_key_exists (group_info.varids, varname))
     throw InvalidParmError, "Variable name `$varname' does not exist or has not been defined"$;

   variable ncid = group_info.ncid;
   return (ncobj, ncid, varid, varname, _nc_inq_varshape (ncid, varid));
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
	usage ("<ncobj>.put (varname, data [,start [,count [,stride]]])");
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
   variable start = NULL, count = NULL, stride = NULL;

   if (_NARGS == 5)
     (start, count, stride) = ();
   else if (_NARGS == 4)
     (start, count) = ();
   else if (_NARGS == 3)
     start = ();
   else if (_NARGS != 2)
     {
	_pop_n(_NARGS);
	usage ("<ncobj>.get (varname, [start, [count [,stride]]])");
     }
   variable ncobj, ncid, varid, varname, shape;
   (ncobj, ncid, varid, varname, shape) = pop_ncobj_var_info ();

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

   variable is_scalar = 0;
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

private define inc_counter (c, cmax, n)
{
   variable i = n;
   while (i != 0)
     {
	i--;
	if (c[i] != cmax[i])
	  {
	     c[i]++;
	     return 1;
	  }
	c[i] = 0;
     }
   return 0;
}

% This function maps rubber ranges such as [*] or [5:*] to non-rubber
% ranges
private define adjust_fixed_indices (var_shape, fixed_index_list, fixed_dims)
{
   if (max(fixed_dims) >= length (var_shape))
     throw InvalidParmError, "Invalid dims qualifier for slice";

   variable new_index_list = {}, new_fixed_dims = Int_Type[0];
   variable max_indices = var_shape[fixed_dims];
   _for (0, length (fixed_index_list)-1, 1)
     {
	variable i = ();
	variable idx = fixed_index_list[i];
	if ((length (idx) == 0) || any (idx < 0))
	  {
	     % we have some sort of rubber range, e.g., [*], or [5:].
	     try
	       {
		  variable new_idx = [0:max_indices[i]-1];
		  idx = new_idx[idx];
		  if (_eqs (new_idx, idx))
		    {
		       % This index is equivalent to [*].  Omit it.
		       continue;
		    }
	       }
	     catch AnyError:
	       throw IndexError, "slice index $i is is invalid for the variable's shape"$;
	  }
	list_append (new_index_list, idx);
	new_fixed_dims = [new_fixed_dims, fixed_dims[i]];
     }

   return new_index_list, new_fixed_dims;
}


private define netcdf_get_slices ()
{
   if (_NARGS < 3)
     usage ("value = <ncobj>.get_slices(varname, i [,j ...] ; dims=[dim_i, ...]");

   % The comments below are given in the context of an array A whose shape
   % is [n0, n1, n2, n3] and it is desired to get the subarray
   % [*, i1, i2, *] where i1 and i2 are index-arrays.  The resulting
   % array B will have the shape [n0, length(i1), length(i2), n3]

   variable fixed_index_list = __pop_list (_NARGS-2);   %  {i1, i2}
   variable ncobj, ncid, varid, varname, var_shape;
   (ncobj, ncid, varid, varname, var_shape) = pop_ncobj_var_info ();
   % varname = A, var_shape = [n0, n1, n2, n3]

   variable fixed_dims = qualifier ("dims", [0:length(fixed_index_list)-1]);
   % dims = [1, 2]
   variable nfixed_dims = length(fixed_dims); % 2
   if (nfixed_dims != length (fixed_index_list))
     {
	throw InvalidParmError, "Expected the dims qualifier to have a length equal to the number of slice indices";
     }

   (fixed_index_list, fixed_dims) = adjust_fixed_indices (var_shape, fixed_index_list, fixed_dims);
   nfixed_dims = length (fixed_dims);
   if (nfixed_dims == 0)
     return ncobj.get (varname);

   variable out_shape = @var_shape; % [n0, n1, n2, n3]

   variable i, j, idx;
   variable counter = Int_Type[nfixed_dims];  % [0, 0]
   variable counter_max = Int_Type[nfixed_dims]; % [0, 0]
   variable final_out_shape = @out_shape;    %  [n0,n1,n2,n3]
   _for i (0, nfixed_dims-1, 1)
     {
	idx = fixed_index_list[i];
	j = fixed_dims[i];
	variable n_i = length (idx);  % n_0,1 = length(i1,i2)
	counter_max[i] = n_i-1;
	out_shape[j] = n_i;
	final_out_shape[j] = n_i;
	if (typeof (idx) != Array_Type)
	  final_out_shape[j] = -1;     %  mark a degenerate dim
     }
   final_out_shape = final_out_shape[where(final_out_shape != -1)];
   if (length (final_out_shape) == 0) final_out_shape = NULL;   %  scalar

   % Now counter_max = [length(i1)-1, length(i2)-1]
   % and out_shape = [n0, length(i1), length(i2), n3]

   variable start = Int_Type[length (var_shape)];   %  start = [0, 0, 0, 0]
   variable count = @var_shape;	       %  count = [n0, n1, n2, n3]
   count[fixed_dims] = 1;		       %  count[[1,2]] = 1 ==> count = [n0, 1, 1, n3]

   variable outdata;
   % If only a single slice is to be retrieved, do that now and return.
   if (all(counter_max == 0))
     {
	start[fixed_dims] = [__push_list (fixed_index_list)];
	outdata = _nc_get_vars (start, count, NULL, ncid, varid);
	if (final_out_shape == NULL) return outdata[[0:]][0];   %  maps X[0,0,...0] to [X[0]] to X[0]
	reshape (outdata, final_out_shape);
	return outdata;
     }

   variable out_index_array_list = {};
   _for i (0, length (out_shape)-1, 1)
     {
	list_append (out_index_array_list, [*]);
     }
   % out_index_array_list = {[*], ...}

   outdata = NULL;
   do
     {
	_for i (0, nfixed_dims-1, 1)
	  {
	     idx = fixed_dims[i];
	     j = counter[i];
	     out_index_array_list[idx] = [j];
	     start[idx] = fixed_index_list[i][j];
	  }
	% out_index_array_list = {[*], [counter[0]], [counter[1]], [*]}
	% start = [0, i1[counter[0]], i2[counter[1]], 0];
	variable slice = _nc_get_vars (start, count, NULL, ncid, varid);
	if (outdata == NULL)
	  outdata = @Array_Type(_typeof(slice), out_shape);
	outdata[__push_list(out_index_array_list)] = __tmp(slice);
     }
   while (inc_counter (counter, counter_max, nfixed_dims));

   if (final_out_shape == NULL) return outdata[[0:]][0];   %  maps X[0,0,...0] to [X[0]] to X[0]
   reshape (outdata, final_out_shape);
   return outdata;
}

private define promote_scalar_to_array (x, dims)
{
   variable a = @Array_Type(typeof(x), dims);
   a[*] = x;
   return a;
}

private define netcdf_put_slices ()
{
   if (_NARGS < 4)
     usage ("<ncobj>.put_slices(varname, i [,j ...], data ; dims=[dim_i, ...]");

   % The comments below are given in the context of a variable V whose shape
   % is [n0, n1, n2, n3] and it is desired to put the data in the subarray
   % [*, i1, i2, *] where i1 and i2 are index-arrays.  The resulting
   % array B will have the shape [n0, length(i1), length(i2), n3]

   variable data = ();
   variable fixed_index_list = __pop_list (_NARGS-3);   %  {i1, i2}
   variable ncobj, ncid, varid, varname, var_shape;
   (ncobj, ncid, varid, varname, var_shape) = pop_ncobj_var_info ();
   % varname = A, var_shape = [n0, n1, n2, n3]

   variable fixed_dims = qualifier ("dims", [0:length(fixed_index_list)-1]);
   % dims = [1, 2]
   variable nfixed_dims = length(fixed_dims); % 2
   if (nfixed_dims != length (fixed_index_list))
     {
	throw InvalidParmError, "Expected the dims qualifier to have a length equal to the number of slice indices";
     }

   variable is_scalar = (typeof (data) != Array_Type);
   variable data_array = data;

   (fixed_index_list, fixed_dims) = adjust_fixed_indices (var_shape, fixed_index_list, fixed_dims);
   nfixed_dims = length (fixed_dims);
   if (nfixed_dims == 0)
     {
	if (is_scalar)
	  data_array = promote_scalar_to_array (data, var_shape);
	return ncobj.put (varname, __tmp(data_array));
     }

   variable in_shape = @var_shape;
   variable i, j, idx;
   variable counter = Int_Type[nfixed_dims];  % [0, 0]
   variable counter_max = Int_Type[nfixed_dims]; % [0, 0]
   _for i (0, nfixed_dims-1, 1)
     {
	idx = fixed_index_list[i];
	variable n_i = length (idx);  % n_0,1 = length(i1,i2)
	counter_max[i] = n_i-1;
	in_shape[fixed_dims[i]] = n_i;
     }

   % Now counter_max = [length(i1)-1, length(i2)-1]
   % in_shape = [n0, length(i1), length(i2), n3]

   variable start = Int_Type[length (var_shape)];   %  start = [0, 0, 0, 0]
   variable count = @var_shape;	       %  count = [n0, n1, n2, n3]
   count[fixed_dims] = 1;		       %  count[[1,2]] = 1 ==> count = [n0, 1, 1, n3]

   % If only a single slice is to be put, do that now and return.
   if (all(counter_max == 0))
     {
	if (is_scalar) data_array = promote_scalar_to_array (data, count);
	start[fixed_dims] = [__push_list (fixed_index_list)];
	_nc_put_vars (start, count, NULL, data_array, ncid, varid);
	return;
     }
   variable data_index_list = {};
   _for i (0, length (var_shape)-1, 1)
     {
	list_append (data_index_list, [*]);
     }

   variable data_shape = array_shape (data);
   try
     {
	ifnot (is_scalar) reshape (data, in_shape);
	do
	  {
	     _for i (0, nfixed_dims-1, 1)
	       {
		  idx = fixed_dims[i];
		  j = counter[i];
		  data_index_list[idx] = [j];
		  start[idx] = fixed_index_list[i][j];
	       }
	     % start = [0, i1[counter[0]], i2[counter[1]], 0];
	     if (is_scalar)
	       data_array = promote_scalar_to_array (data, count);
	     else
	       data_array = data[__push_list(data_index_list)];
	     _nc_put_vars (start, count, NULL, data_array, ncid, varid);
	  }
	while (inc_counter (counter, counter_max, nfixed_dims));
     }
   finally: reshape(data, data_shape);
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

private define map_string_to_type (ncobj, s)
{
   if (typeof(s) != String_Type) return s;
   variable user_types = ncobj.shared_info.user_types;
   if (assoc_key_exists (user_types, s))
     return user_types[s];

   throw InvalidParmError, "Unable to map $s to a NetCDF_DataType"$;
}

private define set_var_chunking (ncid, varid, varname, dims, ndims, storage, chunking)
{
   if (chunking != NULL)
     {
	if (length (chunking) != ndims)
	  throw InvalidParmError, "The chunking array for variable $name must contain $ndims elements"$;
	if (storage == NULL) storage = NC_CHUNKED;
     }

   if ((storage != NULL) || (chunking != NULL))
     _nc_def_var_chunking (chunking, ncid, varid, storage);   %  note order
}

private define set_var_fill (ncid, varid, name, fill)
{
   variable code = (fill == NULL) ? NC_NOFILL : NC_FILL;
   _nc_def_var_fill (fill, ncid, varid, code);
}

private define handle_def_var_qualifiers (ncid, varid, varname, dims, ndims)
{
   variable storage = qualifier ("storage");
   variable chunking = qualifier ("chunking");
   set_var_chunking (ncid, varid, varname, ndims, ndims, storage, chunking);

   if (qualifier_exists ("fill"))
     set_var_fill (ncid, varid, varname, qualifier ("fill"));

   variable a, b, c;
   variable
     cache_size = qualifier("cache_size"),
     cache_nelems = qualifier ("cache_nelems"),
     cache_preemp = qualifier ("cache_preemp");
   if ((cache_size != NULL) || (cache_nelems != NULL) || (cache_preemp != NULL))
     {
	(a, b, c) = _nc_get_var_chunk_cache (ncid, varid);
	if (cache_size == NULL) cache_size = a;
	if (cache_nelems == NULL) cache_nelems = b;
	if (cache_preemp == NULL) cache_preemp = c;
	_nc_set_var_chunk_cache (ncid, varid, cache_size, cache_nelems, cache_preemp);
     }
   variable
     deflate_shuffle = qualifier ("deflate_shuffle"),
     deflate = qualifier ("deflate"),
     deflate_level = qualifier ("deflate_level");
   if ((deflate != NULL) || (deflate_level != NULL) || (deflate_shuffle != NULL))
     {
	(a, b, c) = _nc_inq_var_deflate (ncid, varid);
	if (deflate_shuffle == NULL) deflate_shuffle = a;
	if (deflate == NULL) deflate = 1;
	if (deflate_level == NULL) deflate_level = c;
	_nc_def_var_deflate (ncid, varid, deflate_shuffle, deflate, deflate_level);
     }
}

private define netcdf_def_var ()
{
   variable ncobj, name, type, dims;

   if (_NARGS != 4)
     {
	_pop_n (_NARGS);
	usage ("\
<ncobj>.def_var (name, type, array-of-dim-names|NULL] ; qualifiers)\n\
qualifiers:\n\
   storage=NC_CONTIGUOUS|NC_CHUNKED\n\
   chunking=Array of chunk sizes | NULL\n\
   fill=fill_val\n\
   cache_size=val, cache_nelems=val, cache_preemp=val\n\
   deflate=0|1, deflate_shuffle=0|1, deflate_level=0-9\n\
"
	      );
     }

   (ncobj, name, type, dims) = ();

   variable group_info = ncobj.group_info;
   variable varids = group_info.varids;
   if (assoc_key_exists (varids, name))
     throw InvalidParmError, "Variable name `$name' already exists"$;

   variable ndims = 0;
   if (dims != NULL)		       %  NULL indicates a scalar
     {
	if (typeof (dims) != Array_Type) dims = [dims];
	ndims = length(dims);
     }

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

   type = map_string_to_type (ncobj, type);
   variable varid = _nc_def_var (ncid, name, type, dimids);
   varids[name] = varid;

   handle_def_var_qualifiers (ncid, varid, name, dims, ndims ;; __qualifiers);
}

private define netcdf_inq_var_storage ()
{
   if (_NARGS != 2)
     {
	usage ("s = <ncobj>.inq_var_storage (varname)");
     }
   variable ncobj, varname;
   (ncobj, varname) = ();

   variable group_info = ncobj.group_info;
   variable varids = group_info.varids;
   ifnot (assoc_key_exists (varids, varname))
     throw InvalidParmError, "Variable name `$varname' in unknown"$;
   variable varid = varids[varname];
   variable ncid = group_info.ncid;

   variable s = struct
     {
	fill = _nc_inq_var_fill (ncid, varid),
	storage,
	chunking,
	cache_size,
	cache_nelems,
	cache_preemp,
	deflate, deflate_level, deflate_shuffle,
     };
   (s.storage, s.chunking) = _nc_inq_var_chunking (ncid, varid);
   (s.cache_size, s.cache_nelems, s.cache_preemp) = _nc_get_var_chunk_cache (ncid, varid);
   (s.deflate_shuffle, s.deflate, s.deflate_level) = _nc_inq_var_deflate (ncid, varid);
   return s;
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

   variable dtype = _typeof (value);
   if (_is_struct_type (value))
     {
	dtype = qualifier ("type");
	if (dtype == NULL)
	  usage ("put_att method require type qualifier for compound attributes");
	if (typeof (dtype) == String_Type)
	  {
	     ifnot (assoc_key_exists (ncobj.shared_info.user_types, dtype))
	       {
		  throw TypeMismatchError, "Unknown user-type $dtype"$;
	       }
	     dtype = ncobj.shared_info.user_types[dtype];
	  }
     }

   variable ncid = ncobj.group_info.ncid;
   if (varname == NULL)
     return _nc_put_global_att (value, ncid, attname, dtype);

   variable varid = get_varid (ncobj, varname);
   _nc_put_att (value, ncid, varid, attname, dtype);
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

private define netcdf_def_compound ()
{
   variable ncobj, name, s;
   if (_NARGS != 3)
     {
	_pop_n (_NARGS);
	usage ("<ncobj>.def_compound (name, Struct_Type");
     }
   (ncobj, name, s) = ();
   variable group_info = ncobj.group_info;
   variable ncid = group_info.ncid;
   variable shared_info = ncobj.shared_info;

   if (assoc_key_exists (shared_info.user_types, name))
     {
	throw DuplicateDefinitionError, "netCDF type `$name' already exists";
     }

#if (0)
   if (_nc_user_type_exists (ncid, name));
#endif

   variable
     field_names = get_struct_field_names (s),
     i, n = length (field_names),
     field_types = NetCDF_DataType_Type[n],
     field_dims = Array_Type[n];

   _for i (0, n-1, 1)
     {
	variable field_name = field_names[i];
	variable val = get_struct_field (s, field_name);
	variable val_type = typeof (val);
	if (val_type == Array_Type)
	  {
	     field_dims[i] = array_shape (val);
	     val = _typeof (val);
	  }
	else if (val_type == List_Type)
	  {
	     % val = { DataType|string [,dims...]}
	     if (length (val) > 1)
	       field_dims[i] = [__push_list (val[[1:]])];
	     val = map_string_to_type (ncobj, val[0]);
	  }
	else
	  val = map_string_to_type (ncobj, val);

	val_type = typeof (val);
	if ((val_type != DataType_Type) && (val_type != NetCDF_DataType_Type))
	  throw InvalidParmError, sprintf ("Expected compound field `%S' value to be a datatype, found %S", field_names[i], val_type);
	field_types[i] = val;     %  implicit typecast
     }

   variable dtype = _nc_def_compound (field_names, field_types, field_dims, group_info.ncid, name);
   shared_info.user_types[name] = dtype;
}

% TODO: return this information in the form of a json-like structure
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

   variable name, id, i, n, names, val;     %  generic vars used below

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

   str = str + "Group attributes:\n";
   try
     {
	foreach name (_nc_inq_global_atts (ncid))
	  {
	     val = _nc_get_global_att (ncid, name);
	     str = str + sprintf ("\t%s = %S\n", name, val);
	  }
     }
   catch AnyError;

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
		  val = _nc_get_att (ncid, id, name);
		  str = str + sprintf ("\t\t%s=%S\n", name, val);
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

private define netcdf_typeid (ncobj, name)
{
   return map_string_to_type (ncobj, name);
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
   user_types,			       %  global to all groups
   groups,			       %  assoc array of Netcdf_Group_Type  
};

private define netcdf_def_grp ();      %  forward decl
private define netcdf_group ();      %  forward decl

private variable Netcdf_Obj = struct
{
   group_info,			       %  poiner to Netcdf_Group_Type
   shared_info,			       %  pointer to Netcdf_Shared_Type
   get = &netcdf_get,
   get_slices = &netcdf_get_slices,
   put_slices = &netcdf_put_slices,
   put = &netcdf_put,
   def_dim = &netcdf_def_dim,
   def_var = &netcdf_def_var,
   put_att = &netcdf_put_att,
   get_att = &netcdf_get_att,
   def_grp = &netcdf_def_grp,
   inq_var_storage = &netcdf_inq_var_storage,
   def_compound  = &netcdf_def_compound,
   typeid = &netcdf_typeid,
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
  .get                 Read a netCDF variable\n\
  .put                 Write to a netCDF variable\n\
  .get_slices          Read slices from a netCDF variable\n\
  .put_slices          Write slices to a netCDF variable\n\
  .def_dim             Define a netCDF dimension\n\
  .def_var             Define a netCDF variable\n\
  .def_compound        Define a netCDF compound\n\
  .put_att             Write a netCDF attribute\n\
  .get_att             Read a netCDF attribute\n\
  .def_grp             Define a netCDF group\n\
  .group               Open a netCDF group\n\
  .subgrps             Get the subgroups of the current group\n\
  .inq_var_storage     Get cache, compression, and chunking info\n\
  .info                Print some information about the object\n\
  .close               Close the underlying netCDF file\n\
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
   shared_info.user_types = Assoc_Type[NetCDF_DataType_Type];
   shared_info.root_ncid = ncid;

   return create_new_group_instance (shared_info, ncid, "/");
}
