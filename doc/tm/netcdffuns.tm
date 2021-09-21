#d netcdf netCDF
\function{netcdf_open}
\synopsis{Create a new  file or open an existing one}
\usage{nc = netcdf_open (filename, mode)}
\description
  This function will create a new \netcdf file or open an existing one,
  depending upon the \exmp{mode} argument, which must be one of the
  following values:
#v+
   "c"    Create a new file with the specified name
   "w"    Open an existing file with read/write access
   "r"    Open an existing file with read-only access
#v-
  Upon success, a \netcdf object is returned.  Upon failure, a exception
  will be thrown.

  The supported methods include:
#v+
  .def_dim  : Define a netCDF dimension
  .def_var  : Define a netCDF variable
  .def_grp  : Define a netCDF group
  .put      : Write data to netCDF variable
  .get      : Read data from a netCDF variable
  .put_att  : Write an netCDF attribute
  .get_att  : Read a netCDF attribute
  .group    : Instantiate a netCDF object corresponding to a specified group
  .info     : Print some information about the netCDF object
  .close    : Close a netCDF file
#v-
  See the documentation for the specific methods for additional
  information about them.
\qualifiers
\qualifier{noclobber}{When creating a new file, do not overwrite an existing one}
\qualifier{share}{Open the file with \netcdf \var{NC_SHARE} semantics}
\example
  This is a simple example that creates a \netcdf file and writes a 6x4
  array with dimension names \exmp{x} and \exmp{y} to a \netcdf variable called
  \exmp{mydata}.
#v+
   nx = 6, ny = 4;
   data = _reshape ([1:nx*ny], [nx, ny]);  % Create the data
   nc = netcdf_open ("file.nc", "c");
   nc.def_dim("x", nx);
   nc.def_dim("y", ny);
   nc.def_var("mydata", ["x", "y"]);
   nc.put("mydata", data);
   nc.close ();
#v-
\seealso{netcdf.def_dim, netcdf.def_var, netcdf.def_grp, netcdf.put,
  netcdf.get, netcdf.put_att, netcdf.get_att, netcdf.group, netcdf.info,
  netcdf.close}
\done


\function{netcdf.def_var}
\synopsis{Define a new netCDF variable}
\usage{nc.def_var (String_Type varname, DataType_Type type, Array_Type dim_names)}
\description
 This function is used to define a new netCDF variable with name
 \exmp{vname}, and whose type and dimensions are given by the
 \exmp{type} and \exmp{dim_names} parameters, respectively.  The
 \exmp{type} parameter must be one of the following values:
#v+
   Char_Type (Signed 8-bit integer)
   UChar_Type (Unsigned 8-bit integer)
   Short_Type, Int16_Type (Signed 16 bit integer)
   UShort_Type, UInt16_Type (Unsigned 16 bit integer)
   Int_Type, Int32_Type (Signed 32 bit integer)
   UInt_Type, UInt32_Type (Unsigned 32 bit integer)
   LLong_Type, Int64_Type (Signed 64 bit integer)
   ULLong_Type, UInt64_Type (Unsigned 64 bit integer)
   Float_Type (32 bit float)
   Double_Type (64 bit float)
   String_Type (string)
#v-
 The \exmp{dim_names} array is a 1-d array of previously defined
 dimension names.
\example
 The following example results in the creation of a netCDF array 20x30
 array of 32 bit floating point values.
#v+
    nc.def_dim ("x", 20);
    nc.def_dim ("y", 30);
    nc.def_var ("xy_image", Float_Type, ["x", "y"]);
#v-
\seealso{netcdf.def_dim, netcdf.def_grp, netcdf.put,
  netcdf.get, netcdf.put_att, netcdf.get_att, netcdf.group, netcdf.info,
  netcdf.close}
\done


\function{netcdf.def_dim}
\synopsis{Create a netCDF dimension variable}
\usage{nc.def_dim (String_Type dimname, Int_Type len | Array_Type grid)}
\description
  The \var{.def_dim} method creates a netCDF dimension named with the
  name give by the \exmp{dimname} parameter.  The second parameter
  specifies the length of the dimension.  It may be either an integer
  or an array of values.  If the second parameter is an integer, then
  the dimension will have the size given by the integer.  A dimension
  whose size is defined to be 0 is called an unlimited dimension.
  NetCDF variables using such a dimension may grow in the unlimited
  dimenson as more elements are added to the variable.

  If the second parameter is an array, then the dimension size will be
  set to the length of the array.  In addition, the function will
  create a variable of the same name as the dimension and assign it
  the values of the array.  NetCDF calls such a variable a
  ``coordinate-variable''.
\example
  Consider the the creation of a netCDF variable \exmp{"position"}
  that represents the 3-d position of a particle as it moves in time.
  At some time \exmp{t}, the position of the particle is given by the 3
  spatial values \exmp{x}, \exmp{y}, and \exmp{z}, which may be
  arranged as an array of 3 values \exmp{[x,y,z]}.  A time-series of
  such an array may be represented in netCDF as follows:
#v+
   nc.def_dim("time", 0);
   nc.def_dim("space", 3);
   nc.def_var("position", ["time", "space"]);
#v-
  Here, the time dimension has been defined to be unlimited, and the
  space dimension has been define to be a length of 3, corresponding
  to the 3 spatial dimensions.
\notes
  NetCDF dimensions are scoped such that they are visible to the group
  where they have been defined, and all child groups.
\seealso{netcdf.def_var, netcdf.def_grp, netcdf.put,
  netcdf.get, netcdf.put_att, netcdf.get_att, netcdf.group, netcdf.info,
  netcdf.close}
\done


\function{netcdf.def_grp}
\synopsis{Create a new netCDF group}
\usage{ncgrp = nc.def_grp (String_Type grpname)}
\description
  This method create a new group of the specified name and returns an
  object representing it.  All operations on the group should take
  place via the methods defined by object.
\example
  Suppose that a netCDF file has a dimension called "longitude"
\seealso{netcdf_open, netcdf.group}
\done
