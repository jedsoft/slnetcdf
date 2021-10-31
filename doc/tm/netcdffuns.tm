#d netcdf netCDF
\function{netcdf_open}
\synopsis{Create a new file or open an existing one}
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

  The supported netCDF object methods include:
#v+
  .def_dim          Define a netCDF dimension
  .def_var          Define a netCDF variable
  .def_grp          Define a netCDF group
  .def_compound     Define a netCDF compound
  .put              Write data to a netCDF variable
  .get              Read data from a netCDF variable
  .get_slices       Read slices from a netCDF variable
  .put_slices       Write slices to a netCDF variable
  .put_att          Write a netCDF attribute
  .get_att          Read a netCDF attribute
  .group            Instantiate a netCDF object for a group
  .def_grp          Define a netCDF group
  .subgrps          Get the subgroups of the current group\n\
  .inq_var_storage  Get cache, compression, and chunking info
  .info             Print some information about the netCDF object
  .close            Close a netCDF file
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
\usage{nc.def_var (varname, type, dim_names)}
\description
 This function is used to define a new netCDF variable with name given
 by the \exmp{varname} parameter, and whose type and dimensions are given by the
 \exmp{type} and \exmp{dim_names} parameters, respectively.  The
 \exmp{type} parameter may be the name of a compound type, or one one
 be one of the following values:
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
\qualifiers
 The storage properties of the variable may be specified by qualifiers.
\qualifier{storage=NC_CONTIGUOUS|NC_CHUNKED|NC_COMPACT}{Storage type}
\qualifier{chunking=array}{1-d array of chunk sizes}
\qualifier{fill=value}{Fill value}
\qualifier{cache_size=int}{Cache size in bytes}
\qualifier{cache_nelems=int}{Number of chunk slots}
\qualifier{cache_preemp=float}{Preemption (a value from 0.0 to 1.0)}
\qualifier{deflate=0|1}{1 to enable compression, 0 to disable}
\qualifier{deflate_level=0-9}{0 = no compression, 9 = maximum compression}
\qualifier{deflate_shuffle=0|1}{0 : No shuffle, 1: Enable shuffling}
\example
 The following example results in the creation of a netCDF array 20x30
 array of 32 bit floating point values.
#v+
    nc.def_dim ("x", 20);
    nc.def_dim ("y", 30);
    nc.def_var ("xy_image", Float_Type, ["x", "y"]);
#v-
 This example defines a 512x1024x2048 16-bit integer array with chunking and
 compression enabled.
#v+
    nc.def_dim("frames", 512);
    nc.def_dim("xtrack", 1024);
    nc.def_dim("wavelength", 2048);
    nc.def_var("images", Int16_Type, ["frames", "xtrack", "wavelength"]
               ; chunking=[11,156,305], deflate_level=1);
#v-
\seealso{netcdf.def_dim, netcdf.def_grp, netcdf.put,
  netcdf.get, netcdf.put_att, netcdf.get_att, netcdf.group, netcdf.info,
  netcdf.close}
\done


\function{netcdf.def_dim}
\synopsis{Create a netCDF dimension variable}
\usage{nc.def_dim (dimname, len | grid)}
\description
  The \var{.def_dim} method creates a netCDF dimension whose
  name is specified by the \exmp{dimname} parameter.  The second parameter
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
  space dimension has been defined to have a length of 3, corresponding
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
  This method creates a new group of the specified name and returns an
  object representing it.  All operations on the group should take
  place via the methods defined by object.
\seealso{netcdf_open, netcdf.group}
\done


\function{netcdf.def_compound}
\synopsis{Define a netCDF compound}
\usage{nc.def_compound(cmpname, cmpdef)}
\description
  This method is used to define a new compound object with the type
  name given by the \exmp{cmpname} parameter.  The compound field
  names and the corresponding data types and dimensions are specified
  by the \exmp{cmpdef} parameter in the form of a structure.  Each
  field name of the structure gives the corresponding compound field
  name.  The value of the field specifies the data type and dimensions
  of the corresponding compound field.  This value must be specified
  as either a data type array, or a list giving the data type and
  dimensions:
#v+
     datatype [dim0, dim1,...]
     {datatype, dim0, dim1, ...}
#v-
  The latter form using the list is the preferred form and is required
  for compound types with array-valued fields.  This
  is illustrated in the second example below.
\example
  Suppose that it is desired to store 100 samples of a time-dependent
  complex-valued voltage V in a netCDF file as two variables:
  \exmp{timestamp} and \exmp{complex_voltage}.  Since netCDF does not
  support complex variables, this example creates compound type that
  represents a complex variable.
#v+
    define store_voltage_samples (file, t, v)
    {
       % v is an array of complex voltage samples
       % t is an array of time values
       variable i, nsamples = length(v);
       variable v_real = Real(v), v_imag = Imag(v);

       variable nc = netcdf_open (file, "c");
       nc.def_compound ("complex_t",
                        struct {re=Double_Type,im=Double_Type});
       nc.def_dim ("time", nsamples);
       nc.def_var ("timestamp", Double_Type, ["time"]);
       nc.def_var ("complex_voltage", "complex_t", ["time"]);

       variable complex_voltages = Struct_Type[nsamples];
       for (i = 0; i < nsamples; i++)
          {
             complex_voltages[i]
               = struct { re = v_real[i], im = v_imag[i] };
          }

        nc.put ("timestamp", t);
        nc.put ("complex_voltage", complex_voltages);
        nc.close ();
    }
#v-

  Here is an alternative that stores all the voltage samples in a
  single scalar variable called \exmp{samples} that has two fields:
  \exmp{timestamp} and \exmp{voltage}.
#v+
    define store_voltage_samples (file, t, v)
    {
       % v is an array of complex voltage samples
       % t is an array of time values
       variable i, nsamples = length(v);
       variable v_real = Real(v), v_imag = Imag(v);

       variable nc = netcdf_open (file, "c");
       nc.def_compound ("complex_t",
                        struct {re=Double_Type,im=Double_Type});
       nc.def_compound ("sample_t",
           struct {
              timestamp = {Double_Type, nsamples},
              voltage = {"complex_t", nsamples}
           });

       nc.def_var ("samples", "sample_t", NULL);

       variable complex_voltages = Struct_Type[nsamples];
       for (i = 0; i < nsamples; i++)
          {
             complex_voltages[i]
               = struct { re = v_real[i], im = v_imag[i] };
          }
        variable samples = struct
            { timestamp = t, voltage = complex_voltages };
        nc.put ("samples", samples);
        nc.close ();
    }
#v-
\seealso{netcdf.def_var, netcdf.def_dim, netcdf.put}
\done


\function{netcdf.put}
\synopsis{Write to a netCDF variable}
\usage{nc.put (varname, datavalues [,start [,count [,stride]]])}
\description
  The \exmp{.put} method may be used to write one or more data values
  to the netCDF variable whose name is given by \exmp{varname}.  The
  optional parameters (\exmp{start}, \exmp{count}, and \exmp{stride})
  may be used to specify where the data values are to be written.
\notes
  The \exmp{.put_slices} method may be easier to use when writing data
  to one or more subarrays of a netCDF array.
\seealso{netcdf.get, netcdf.put_slices, netcdf.def_var, netcdf.put_att}
\done


\function{netcdf.get}
\synopsis{Read values from a netCDF variable}
\usage{vals = nc.get (varname [,start [,count [,stride]]])}
\description
  The \exmp{.get} method may be use to read one or more values from
  the netCDF variable whose name is given by \exmp{varname}.  The
  optional paramters (\exmp{start}, \exmp{count}, and \exmp{stride})
  may be used to specify that the data values are to be read from
  the specified subset of the netCDF variable.
\notes
  The \exmp{.get_slices} method may be easier to use when reading data
  from one or more subarrays of a netCDF array.
\seealso{netcdf.put, netcdf.get_slices, netcdf.def_var, netcdf.get_att}
\done


\function{netcdf.get_slices}
\synopsis{Read a specified sub-array of a netCDF variable}
\usage{val = nc.get_slices (varname, i [,j ...] ; qualifiers)}
\description
 The \exmp{.get_slices} method reads a sub-array from the netcdf
 variable whose name is given by \exmp{varname}.  The sub-array is
 defined by one or more indices, \exmp{i, j...}, whose usage is best
 described by some examples.  If \exmp{A} represents the elements of a
 multi-dimensional variable named \exmp{"A"}, then:
#v+
   X = nc.get_slices ("A", i);                 % ==> X = A[i,*,*,...]
   X = nc.get_slices ("A", i; dims=1);         % ==> X = A[*,i,*,...]
   X = nc.get_slices ("A", i, j);              % ==> X = A[i,j,*,...]
   X = nc.get_slices ("A", i, j; dims=[2,0]);  % ==> X = A[j,*,i,...]
#v-
 The indices \exmp{i, j, ...} may be index-arrays or simple scalars, e.g.,
#v+
   X = nc.get_slices ("A", [3:5], 4);          % ==> X = A[[3:5],4,*,...]
#v-
\qualifiers
\qualifier{dims=[d0,...]}{Specifies the dimensions that correspond to
     the index variables.  The default is [0,1,...]}
\seealso{netcdf.get, netcdf.put_slices}
\done

\function{netcdf.put_slices}
\synopsis{Write values to a specified sub-array of a netCDF variable}
\usage{nc.put_slices (varname, i [,j ...], X ; qualifiers)}
\description
 The \exmp{.put_slices} method writes set of values \exmp{X} to a
 specified sub-array of the netcdf variable whose name is given by
 \exmp{varname}.  The sub-array is defined by one or more indices,
 \exmp{i, j...}, whose usage is best described by some examples.  If
 \exmp{A} represents the elements of a multi-dimensional netCDF
 variable named \exmp{"A"}, and X repesents the array of values to be
 written, then:
#v+
   nc.put_slices ("A", i, X);                  % ==> A[i,*,*,...] = X
   nc.put_slices ("A", i, X; dims=1);          % ==> A[*,i,*,...] = X
   nc.put_slices ("A", i, j, X);               % ==> A[i,j,*,...] = X
   nc.put_slices ("A", i, j, X; dims=[2,0]);   % ==> A[j,*,i,...] = X
#v-
 The indices \exmp{i, j, ...} may be index-arrays or simple scalars, e.g.,
#v+
   nc.put_slices ("A", [3:5], 4, X);           % ==> A[[3:5],4,*,...] = X
#v-
\qualifiers
\qualifier{dims=[d0,...]}{Specifies the dimensions that correspond to
the index variables}
\seealso{netcdf.put, netcdf.get_slices}
\done


\function{netcdf.put_att}
\synopsis{Write a netCDF attribute}
\usage{nc.put_att ([varname,] attname, value)}
\description
  This function may be used to write a value to a netCDF attribute.
  If the optional paramter \exmp{varname} is given, then it specifies
  the name of the variable whose attribute is to be written.
  Otherwise, the attribute will be written to the group represented by
  the netCDF object \exmp{nc}.

  If the value is an instance of a netCDF compound type, then the
  \exmp{dtype} qualifier must be used to specifiy the compound type.
\qualifiers
\qualifier{dtype=type}{The data type of the attribute}
\example
  This example writes a complex value to a global attribute named
  \exmp{impedance} as a netCDF compound.
#v+
   nc.def_compound ("complex_t", struct {re=Double_Type, im=Double_Type});
   z = struct {re = 3.0, im = 4.0};
   nc.put_att ("impedance", value; dtype="complex_t");
#v-
\seealso{netcdf.get_att, netcdf.put}
\done


\function{netcdf.get_att}
\synopsis{Get the value of a netCDF attribute}
\usage{value = nc.get_att ([varname,] attname}}
\description
  This function gets the value of the attribute whose name is given by
  \exmp{attname}.  If present, \exmp{varname} specifies the name of
  the variable associated with the attribute.  Otherwise the attribute
  is that of the group associated with the netCDF object \exmp{nc}
\seealso{netcdf.put_att, netcdf.get, netcdf.get_slices}
\done


\function{netcdf.group}
\synopsis{Instantiate a netCDF object for a specified group}
\usage{ncgrp = nc.group (group_name)}
\description
  The function returns a netCDF object for the group whose name is
  given by \exmp{group_name}.
\example
  Suppose that \exmp{"images"} is a netCDF subgroup of the object
  represented by \exmp{nc}.  Then an attribute {"scene_id"} may be
  created in the subgroup via
#v+
    nc_images = nc.group("images");
    nc_images.put_att ("scene_id", 7734);
#v-
\notes
  This function assumes that the specified group already exists.  To
  create a new group, use the \exmp{.def_grp} function.
\seealso{netcdf_open, netcdf.def_grp, netcdf.subgrps}
\done

\function{netcdf.subgrps}
\synopsis{Get the subgroups associated with a netCDF object}
\usage{subgroup_names = nc.subgrps ()}
\description
  This function returns the names of the subgroups associated with the
  netCDF object \exmp{nc}
\seealso{netcdf.group, netcdf.def_grp}
\done


\function{netcdf.inq_var_storage}
\synopsis{Get information about how a variable is stored}
\usage{s = nc.inq_var_storage(varname)}
\description
  This function returns a structure that provides information about
  how the specified variable is stored.  This includes
  compression and chunking information, as well as information about
  the cache, and the fill value.  The field names include:
#v+
    fill            : fill-value
    storage         : NC_CONTIGUOUS (no chunking), NC_CHUNKED, NC_COMPACT
    chunking        : 1-d array of chunk sizes
    cache_size      : size of the cache in bytes
    cache_nelems    : The number of chunk slots
    cache_preemp    : Cache preemption value
    deflate         : 1 if compression is enabled, 0 if not
    deflate_level   : compression level (0-9)
    deflate_shuffle : 1 if shuffling is enabled, 0 if not
#v-
\notes
  These values can be set as qualifiers to the \exmp{def_var} method.

  This function is a wrapper around the netCDF API functions
  \exmp{nc_inq_var_chunking}, \exmp{nc_get_var_chunk_cache},
  \exmp{nc_inq_var_deflate}, and \exmp{nc_inq_var_fill}.  For more
  information, see the netCDF documentation.
\seealso{netcdf.def_var}
\done


\function{netcdf.info}
\synopsis{List variables and attributes of a netCDF object}
\usage{nc.info()}
\description
 The \exmp{.info} method prints information about the netCDF object.
 The information includes the name of the group, the dimensions, group
 attributes, variables and their attributes, and subgroups of the
 netCDF object.
\seealso{netcdf.subgrps}
\done


\function{netcdf.close}
\synopsis{Close the underlying netCDF file}
\usage{nc.close ()}
\description
 This function may be used to close the underlying netCDF file.
\notes
 The interpreter will silently close the file when all references to it have
 gone out of scope.  Nevertheless it is always good practice to
 explicitly call the \exmp{.close} method.
\seealso{netcdf_open}
\done
