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

\chapter{Limitations}

\sect{netCDF limitations}

NetCDF does not support multi-dimensional attributes.  The module will
write such an array as a single dimensional array with the same number
of elements.  For example, a 3x7 array will be written as a 21 element
1-d array.  After reading the attributes value, the \ifun{reshape} function
may be used to convert it to the desired multi-dimensional shape.

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
In this scenario, it might be more natural to read one image and
process one image from the cube.  For example, the mean of the images
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
