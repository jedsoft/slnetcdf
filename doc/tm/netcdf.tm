#% -*- mode: tm; mode: fold -*-

#%{{{Macros 

#i linuxdoc.tm
#d it#1 <it>$1</it>

#d slang \bf{S-lang}
#d exmp#1 \tt{$1}
#d var#1 \tt{$1}

#d ivar#1 \tt{$1}
#d ifun#1 \tt{$1}
#d cvar#1 \tt{$1}
#d cfun#1 \tt{$1}
#d svar#1 \tt{$1}
#d sfun#1 \tt{$1}
#d icon#1 \tt{$1}
#d dtype#1 \tt{$1}
#d exc#1 \tt{$1}

#d chapter#1 <chapt>$1<p>
#d preface <preface>
#d tag#1 <tag>$1</tag>

#d function#1 \sect{<bf>$1</bf>\label{$1}}<descrip>
#d variable#1 \sect{<bf>$1</bf>\label{$1}}<descrip>
#d function_sect#1 \sect{$1}
#d begin_constant_sect#1 \sect{$1}<itemize>
#d constant#1 <item><tt>$1</tt>
#d end_constant_sect </itemize>

#d synopsis#1 <tag> Synopsis </tag> $1
#d keywords#1 <tag> Keywords </tag> $1
#d usage#1 <tag> Usage </tag> <tt>$1</tt>
#d description <tag> Description </tag>
#d qualifiers <tag> Qualifiers </tag>
#d qualifier#2:3 ; \tt{$1}: $2 \ifarg{$3}{(default: \tt{$3})}<newline>
#d example <tag> Example </tag>
#d notes <tag> Notes </tag>
#d seealso#1 <tag> See Also </tag> <tt>\linuxdoc_list_to_ref{$1}</tt>
#d done </descrip><p>
#d -1 <tt>-1</tt>
#d 0 <tt>0</tt>
#d 1 <tt>1</tt>
#d 2 <tt>2</tt>
#d 3 <tt>3</tt>
#d 4 <tt>4</tt>
#d 5 <tt>5</tt>
#d 6 <tt>6</tt>
#d 7 <tt>7</tt>
#d 8 <tt>8</tt>
#d 9 <tt>9</tt>
#d NULL <tt>NULL</tt>
#d documentstyle book

#%}}}

#d module#1 \tt{$1}
#d file#1 \tt{$1}
#d slang-documentation \
 \url{http://www.s-lang.org/doc/html/slang.html}{S-Lang documentation}

\linuxdoc
\begin{\documentstyle}

\title S-Lang netCDF Module Reference
\author John E. Davis, \tt{jed@jedsoft.org}
\date \__today__

#i local.tm

\toc

\chapter{Introduction to the \slang netCDF Module}

The \slang netCDF module provides a high-level object-oriented
interface and a low-level interface to the netCDF-4 library.  The
low-level interface was designed mainly to support the high-level
interface.  As such, only the high-level interface is described in
this document.

The module supports the following netCDF features:
\begin{itemize}
\item Attributes
\item Groups
\end{itemize}

\chapter{Getting Started}

Before the module can be used it must first be loaded into the
interpreter using a line such as
#v+
    require ("netcdf");
#v-

This will bring a function called \sfun{netcdf_open} into the
interpreter's namesspace.   The \sfun{netcdf_open} function
is used to open an existing netCDF file for reading and writing, or to
create a new one.  For example,
#v+
   nc = netcdf_open ("myfile.nc", "r");
#v-
will open an existing file called \exmp{myfile.nc} for reading and
assigns an object representing the file to a variable called \exmp{nc}.
Interacting with the contents of the file take place via the \exmp{nc}
variable, e.g.,
#v+
   p = nc.get("pressure");
#v-
will read the value of a netCDF variable called \exmp{pressure} and
assign it to \exmp{p}.

Calling \sfun{netcdf_open} without any arguments will cause a usage
messsage to be displayed showing the methods supported by the object:
#v+
Usage: nc = netcdf_open (file, mode [; qualifiers]);
 mode:
  "r" (read-only existing),
  "w" (read-write existing),
  "c" (create)
Qualifiers:
 noclobber, share, lock
Methods:
  .get       Read a netCDF variable
  .put       Write to a netCDF variable
  .def_dim   Define a netCDF dimension
  .def_var   Define a netCDF variable
  .put_att   Write a netCDF attribute
  .get_att   Read a netCDF attribute
  .def_grp   Define a netCDF group
  .group     Open a netCDF group
  .info      Print some information about the object
  .close     Close the underlying netCDF file
#v-
Similarly, calling one of the methods with the incorrect number of
arguments will display a usage for the method, e.g.,
#v+
  nc.get();
  Usage: <ncobj>.get (varname, [start, [count [,stride]]])
#v-
Here and in all of the usage messages displayed by the module,
\exmp{<ncobj>} represents the variable name through which the method
was invoked.  In this example, it is \exmp{nc}.

\chapter{Limitations and Workarounds}

\sect{netCDF limitations}

NetCDF does not support multi-dimensional attributes.  The module will
write such an array as a single dimensional array with the same number
of elements.  For example, a 3x7 array will be written as a 21 element
1-d array.  After reading the attributes value, the \ifun{reshape} function
may be used to convert it to the desired multi-dimensional shape.

NetCDF supports I/O to subsets of arrays; however, its indexing is limited to
reading/writing slices of an array via a triplet of \exmp{start},
\exmp{count}, and \exmp{stride} index specifiers.  In contrast, \slang
supports a much richer variety of indexing.

To illustrate this, consider the task of clipping an array in a netCDF
file such that array values less than a threshold value are set to the
threshold value.  Suppose the array is has the name \exmp{"images"}
and represents a set of 100 2d images 2048x2048 images and stored as a
100x2048x2048 cube of 32 bit floating point values.  Values less than
0 are to be set to 0.  To carry out the clipping operation, it is
necessary to read in the array to a \slang variable, perform the
clipping operation, and then write out the array:
#v+
  nc = netcdf_open ("images.nc", "w");
  images = nc.get (images);
  i = where (images < 0);
  images[i] = 0;
  nc.put (images);
  nc.close ();
#v-
Note that this involves writing the entire array back to the netCDF
file, regardless of whether the values have changed or not.  Ideally
one would prefer to only update those values in the file that are
below the threshold.  However, netCDF does not have an equivalent of
the \exmp{images[i] = 0} statement used above.

This indexing limitation has nothing to do with the dimensionality of
the netCDF array.  It also applies to simple 1-d array.  For example,
consider setting the values of every other element of a 100 element
1-d array X to 0.  This is something that netCDF supports via its
``start-count-stride'' indexing paradigm:
#v+
  zeros = Int_Type[50];    % An array of 50 0s
  nc.put("X", zeros, [0], [50], [2]);
#v-
However, setting the 1st, 3rd, and 9th element of X to 0 is not
possible since the indices 1, 3, and 9 cannot be specified in the form
of a single ``start-count-stride'' triplet.

As indicated above, netCDF lacks support for random indexing of
arrays.  Although the netCDF library supports reading/writing a single
array element via the C interface \exmp{nc_put/get_var1} functions,
repeatedly calling these for each value incurs significant overhead
since netCDF must validate each of its arguments.  For this reason, it
may be faster to simply to read/write entire arrays or array slices.
As such, the module does not wrap these functions.

With these considerations in mind, consider the example presented
above that involved setting elements of an array to 0.  For
simplicity, let us assume that it is desired to set all of the
elements of a 500x1024x1024 array to 0.  Since the netCDF library
does not have a function that sets whole arrays or specified slices to
a fixed value, it is necessary to create an array of corresponding
value and write it to the array, e.g.,
#v+
   zeros = Int_Type[500,1024,1024];
   nc.put ("X", zeros);
#v-
The obvious downside of this approach is the memory used by the
auxillary array (\exmp{zeros} in this case), which could be
arbitrarily large.  Moreover, as discussed in the next section,
interpreter may not support such a large array.  For this reason, it
would be better to use a much smaller auxillary array and write it in
slices.  For example,
#v+
   zeros = Int_Type[1024, 1024];
   start = [0, 0, 0];
   count = [1, 1024, 1024];
   for (i = 0; i < 500; i++)
     {
        start[0] = i;
        nc.put ("X", zeros, start, count);
     }
#v-

Once again consider the case of a time-series sequence of images
stored in the netCDF file as an 100x2048x2048 array of 32 bit floats.
Suppose that the dimension coordinate of the first index is time, and
it is desire to extract only those images capture during an interval
\exmp{t0 <= t < t1}:
#v+
   nc = netcdf_open ("images.nc", "r");
   t = nc.get ("time");
   inds = where (t0 <= t < t1);
#v-
Here, \exmp{inds} would be an array whose values correspond to those
indices of the \exmp{time} array that correspond to the desired range.
Reading the correponding images can accomplished using the
``start-count-stride'' netCDF method:
#v+
  images = nc.get ("images", [inds[0], 0, 0], [length(inds), 2048, 2048]);
#v-
But suppose that each image is tagged with some additional indicator
that one wants to filter on.  Then in this case, the index array
\exmp{inds} will unlikely to be a simple range, and would not permit
indexing via a ``start-count-stride'' triplet.  In this case, one 
resort to reading the images as individual slices:
#v+
   images = Float_Type[length(inds),2048,2048];
   _for i (0, length(inds)-1, 1)
      {
        images[i,*,*] = nc.get ("images", [inds[i], 0, 0], [1, 2048, 2048]);
      }
#v-
Since this can be cumbersome, the module includes a netCDF object
method called \exmp{.get_slices} that faciliates this type of operation:
#v+
   images = nc.get_slices ("images", inds);
#v-

\sect{\slang limitations}

The main limitaton that the user needs to be aware is that netCDF
array sizes can be larger than a single \slang version 2 array can
support.  \slang version 2 arrays are limited to 7 dimensions, and
support only a total of 2147483647 elements.  The reason for this is
that \slang arrays are indexed by signed 32 bit integers, with
negative indices representing offsets from the last element of an
array.

For netCDF variables that contain more than 2147483647 elements, array
slicing must be used.  For example, suppose that a netCDF file
contains a data cube with dimensions \exmp{[1024, 2048, 2048]}.  Such
an array contains 4294967296 elements, which exceeds the maximum
number supported by the interpreter.  Often such objects have the
dimensions that have some physical meaning.  For example, this data
cube might represent a 2048x2048 image of a scene observed 1024 times.
In this scenario, it might be more natural to read one image at a time
from the cube and process it.  For example, the mean of the images
may be compute using:
#v+
    nt = 1024, nx = 2048, ny = 2048;
    avg_image = Double_Type[nx, ny];
    for (i = 0; i < nt; i++)
      {
         avg_image += nc.get ("cube", [i,0,0], [1, nx, ny]);
      }
    avg_image /= nt;
#v-

\chapter{NetCDF Module Function Reference}
#i netcdffuns.tm

\end{\documentstyle}
