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
\seealso{netcdf.def_var, netcdf.def_var, netcdf.def_grp, netcdf.put,
  netcdf.get, netcdf.put_att, netcdf.get_att, netcdf.group, netcdf.info,
  netcdf.close}
\done
