/* -*- mode: C; mode: fold; -*- */
/*
Copyright (C) 2021 John E. Davis <jed@jedsoft.org>

This file is part of the S-Lang netcdf Module

The S-Lang netcdf Module is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the
License, or (at your option) any later version.

The S-Lang netcdf Module is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this library; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307,
USA.  
*/

#define HAVE_LONG_LONG 1
#define ENABLE_SLFUTURE_VOID 1
#include "config.h"
#include <stdio.h>
#include <string.h>
#include <stddef.h>
#include <stdint.h>
#include <slang.h>

#include <netcdf.h>

#ifdef __cplusplus
extern "C"
{
#endif
SLANG_MODULE(netcdf);
#ifdef __cplusplus
}
#endif

#include "version.h"

static int sl_NC_Error;
static int NC_Errno;

static void throw_nc_error (const char *name, int err)
{
   NC_Errno = err;
   SLang_verror (sl_NC_Error, "%s returned error code %d: %s", name, err, nc_strerror(err));
}

/*{{{ Utility Functions */

/* Convert the elements of an array to slsstrings */
static int convert_str_array_to_slstr_array (SLang_Array_Type *at, int free_strs)
{
   char **sp;
   SLuindex_Type i, num;
   int status = 0;

   sp = (char **)at->data;
   num = at->num_elements;

   for (i = 0; i < num; i++)
     {
	char *s0 = sp[i], *s1;

	if (s0 == NULL) continue;
	if (status == 0)
	  {
	     s1 = SLang_create_slstring (s0);
	     if (s1 == NULL) status = -1;
	  }
	else s1 = NULL;

	if (free_strs) SLfree (s0);
	sp[i] = s1;
     }

   return status;
}

static int pop_array_of_type_or_null (SLang_Array_Type **at, SLtype t)
{
   if (SLang_peek_at_stack () == SLANG_NULL_TYPE)
     {
	*at = NULL;
	return SLdo_pop ();
     }
   return SLang_pop_array_of_type (at, t);
}

static void free_slstring_array (char **sp, unsigned int n)
{
   unsigned int i;

   if (sp == NULL) return;
   for (i = 0; i < n; i++)
     SLang_free_slstring (sp[i]);

   SLfree (sp);
}

/*}}}*/

/*{{{ Data Type functions */

#define _SL_SIZE_T_TYPE SLANG_ULLONG_TYPE
#define _SL_PTRDIFF_T_TYPE SLANG_LLONG_TYPE

static int NCid_Dim_Type_Id = 0;
typedef struct
{
   SLindex_Type dim_size;	       /* 0 if unlimited */
   int ncid;
   int dim_id;
   unsigned int numrefs;
}
NCid_Dim_Type;

static int NCid_Var_Type_Id = 0;
typedef struct
{
   SLang_Array_Type *at_ncdims;	       /* contains NCid_Dim_Type dim objects */
   size_t var_num_elements;	       /* total number of elements in the variable */
   size_t *dims;
   unsigned int num_dims;
   nc_type xtype;
   int var_id;
   unsigned int numrefs;
}
NCid_Var_Type;

static int NCid_Type_Id = 0;		       /* file or group */
typedef struct
{
   int ncid;
   int is_group;
   int is_closed;
   unsigned int numrefs;
}
NCid_Type;

static int NCid_DataType_Type_Id = 0;
typedef struct
{
   int is_sltype;
   SLtype sltype;
   nc_type xtype;		       /* always valid */

   /* These values are from nc_inq_user_type */
   char *xname;
   size_t xsize;
   size_t xnfields;
   int xclass;
   int xbase;
   unsigned int numrefs;
}
NCid_DataType_Type;

static void free_ncid_datatype_type (NCid_DataType_Type *dtype)
{
   if (dtype == NULL) return;
   if (dtype->numrefs > 1)
     {
	dtype->numrefs--;
	return;
     }
   if (dtype->xname != NULL)
     SLang_free_slstring (dtype->xname);
   SLfree (dtype);
}

static int map_base_sltype_to_xtype (SLtype s, nc_type *xp)
{
   switch (s)
     {
      case SLANG_CHAR_TYPE: *xp = NC_BYTE; break;
      case SLANG_UCHAR_TYPE: *xp = NC_UBYTE; break;
      case SLANG_SHORT_TYPE: *xp = NC_SHORT; break;
      case SLANG_USHORT_TYPE: *xp = NC_USHORT; break;
      case SLANG_INT_TYPE: *xp = NC_INT; break;
      case SLANG_UINT_TYPE: *xp = NC_UINT; break;
#if (SIZEOF_LONG == 8)
      case SLANG_LONG_TYPE: *xp = NC_INT64; break;
      case SLANG_ULONG_TYPE: *xp = NC_UINT64; break;
#else
      case SLANG_LONG_TYPE: *xp = NC_INT; break;
      case SLANG_ULONG_TYPE: *xp = NC_UINT; break;
#endif
      case SLANG_LLONG_TYPE: *xp = NC_INT64; break;
      case SLANG_ULLONG_TYPE: *xp = NC_UINT64; break;

      case SLANG_FLOAT_TYPE: *xp = NC_FLOAT; break;
      case SLANG_DOUBLE_TYPE: *xp = NC_DOUBLE; break;

      case SLANG_STRING_TYPE: *xp = NC_STRING; break;

      default:
	SLang_verror (SL_NotImplemented_Error, "Unable to map %s to a native netcdf type",
		      SLclass_get_datatype_name (s));
	return -1;
     }

   return 0;
}

static NCid_DataType_Type *alloc_ncid_datatype_type (int ncid, nc_type xtype, SLtype sltype, int is_sltype)
{
   NCid_DataType_Type *dtype;
   int status;
   char name[NC_MAX_NAME+1];

   if (NULL == (dtype = (NCid_DataType_Type *) SLmalloc (sizeof (NCid_DataType_Type))))
     return NULL;
   memset (dtype, 0, sizeof (NCid_DataType_Type));

   dtype->sltype = sltype;
   dtype->numrefs = 1;
   dtype->is_sltype = is_sltype;
   if (is_sltype)
     {
	if (xtype == -1)
	  {
	     if (-1 == map_base_sltype_to_xtype (sltype, &xtype))
	       {
		  SLfree (dtype);
		  return NULL;
	       }
	  }
	dtype->xtype = xtype;
	return dtype;
     }

   /* From here on it not an atomic type */
   dtype->xtype = xtype;

   status = nc_inq_user_type (ncid, xtype, name, &dtype->xsize, &dtype->xbase, &dtype->xnfields, &dtype->xclass);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_inq_user_type", xtype);
	free_ncid_datatype_type (dtype);
	return NULL;
     }
   name[NC_MAX_NAME] = 0;
   if (NULL == (dtype->xname = SLang_create_slstring (name)))
     {
	free_ncid_datatype_type (dtype);
	return NULL;
     }

   return dtype;
}

static int push_ncid_datatype_type (NCid_DataType_Type *dtype)
{
   dtype->numrefs++;
   if (0 == SLclass_push_ptr_obj (NCid_DataType_Type_Id, (VOID_STAR) dtype))
     return 0;
   dtype->numrefs--;
   return -1;
}

static int map_base_xtype_to_sltype (nc_type x, SLtype *sp)
{
   switch (x)
     {
      case NC_BYTE: *sp = SLANG_CHAR_TYPE; break;
      case NC_UBYTE: *sp = SLANG_UCHAR_TYPE; break;
      case NC_SHORT: *sp = SLANG_SHORT_TYPE; break;
      case NC_USHORT: *sp = SLANG_USHORT_TYPE; break;
      case NC_INT: *sp = SLANG_INT_TYPE; break;
      case NC_UINT: *sp = SLANG_UINT_TYPE; break;
#if (SIZEOF_LONG == 8)
      case NC_INT64: *sp = SLANG_LONG_TYPE; break;
      case NC_UINT64: *sp = SLANG_ULONG_TYPE; break;
#else
      case NC_INT64: *sp = SLANG_LLONG_TYPE; break;
      case NC_UINT64: *sp = SLANG_ULLONG_TYPE; break;
#endif
      case NC_FLOAT: *sp = SLANG_FLOAT_TYPE; break;
      case NC_DOUBLE: *sp = SLANG_DOUBLE_TYPE; break;

      case NC_STRING: *sp = SLANG_STRING_TYPE; break;

      /* case NC_CHAR: *sp = SLANG_BSTRING_TYPE; break; */

      default:
	SLang_verror (SL_NotImplemented_Error, "Unable to map native netcdf type %d to slang", (int) x);
	return -1;
     }

   return 0;
}

static int push_nc_datatype (int ncid, nc_type xtype)
{
   NCid_DataType_Type *dtype;
   int status;

   if (xtype <= NC_MAX_ATOMIC_TYPE)
     {
	SLtype sltype;

	if (-1 == map_base_xtype_to_sltype (xtype, &sltype))
	  return -1;

	return SLang_push_datatype (sltype);
     }
   if (NULL == (dtype = alloc_ncid_datatype_type (ncid, xtype, SLANG_VOID_TYPE, 0)))
     return -1;

   status = push_ncid_datatype_type (dtype);
   free_ncid_datatype_type (dtype);
   return status;
}

static int cl_ncid_datatype_pop (SLtype type, void *ptr);
static int pop_nc_datatype (nc_type *xp)
{
   NCid_DataType_Type *dtype;
   int status;

   if (-1 == cl_ncid_datatype_pop (NCid_DataType_Type_Id, &dtype))
     return -1;

   status = 0;
#if 0
   if (dtype->is_sltype)
     status = map_base_sltype_to_xtype (dtype->sltype, xp);
   else
#endif
     *xp = dtype->xtype;

   free_ncid_datatype_type (dtype);
   return status;
}

/*}}}*/

/*{{{ Dimension Type functions */

static void free_ncid_dim_type (NCid_Dim_Type *ncdim)
{
   if (ncdim == NULL) return;
   if (ncdim->numrefs > 1)
     {
	ncdim->numrefs--;
	return;
     }

   SLfree ((char *)ncdim);
}

static NCid_Dim_Type *alloc_ncid_dim_type (int ncid, int dim_id, size_t dim_size)
{
   NCid_Dim_Type *ncdim;

   if (NULL == (ncdim = (NCid_Dim_Type *) SLmalloc (sizeof (NCid_Dim_Type))))
     return NULL;

   ncdim->ncid = ncid;
   ncdim->dim_id = dim_id;
   ncdim->dim_size = dim_size;
   ncdim->numrefs = 1;

   return ncdim;
}

static int push_ncid_dim_type (NCid_Dim_Type *ncdim)
{
   ncdim->numrefs++;
   if (0 == SLclass_push_ptr_obj (NCid_Dim_Type_Id, (VOID_STAR) ncdim))
     return 0;
   ncdim->numrefs--;
   return -1;
}

/*}}}*/

/*{{{ Variable Type Functions */

static void free_ncid_var_type (NCid_Var_Type *ncvar)
{
   if (ncvar == NULL) return;
   if (ncvar->numrefs > 1)
     {
	ncvar->numrefs--;
	return;
     }

   SLang_free_array (ncvar->at_ncdims);
   SLfree ((char *)ncvar->dims);	       /* NULL ok */
   SLfree ((char *)ncvar);
}

static NCid_Var_Type *alloc_ncid_var_type (int var_id, nc_type xtype, SLang_Array_Type *at_ncdims)
{
   NCid_Var_Type *ncvar;
   NCid_Dim_Type **ncdims;
   size_t *dims;
   size_t num_elements;
   unsigned int i, num_dims;

   if (NULL == (ncvar = (NCid_Var_Type *)SLmalloc(sizeof(NCid_Var_Type))))
     return NULL;
   memset (ncvar, 0, sizeof(NCid_Var_Type));

   num_dims = at_ncdims->num_elements;
   if (NULL == (dims = (size_t *)SLmalloc(num_dims * sizeof(size_t))))
     {
	SLfree ((char *)ncvar);
	return NULL;
     }

   ncdims = (NCid_Dim_Type **)at_ncdims->data;
   num_elements = 1;
   for (i = 0; i < num_dims; i++)
     {
	dims[i] = ncdims[i]->dim_size;
	num_elements = num_elements * dims[i];
     }

   at_ncdims->num_refs++;
   ncvar->at_ncdims = at_ncdims;
   ncvar->var_num_elements = num_elements;
   ncvar->dims = dims;
   ncvar->num_dims = num_dims;
   ncvar->xtype = xtype;
   ncvar->var_id = var_id;
   ncvar->numrefs = 1;
   return ncvar;
}

static int push_ncid_var_type (NCid_Var_Type *ncvar)
{
   ncvar->numrefs++;
   if (0 == SLclass_push_ptr_obj (NCid_Var_Type_Id, (VOID_STAR) ncvar))
     return 0;
   ncvar->numrefs--;
   return -1;
}


/*}}}*/

/*{{{ Functions that open/close files (NCid_Type) */
static void free_ncid_type (NCid_Type *nc)
{
   if (nc == NULL) return;
   if (nc->numrefs > 1)
     {
	nc->numrefs--;
	return;
     }

   if (nc->is_group == 0) (void) nc_close (nc->ncid);
   SLfree ((char *)nc);
}

static NCid_Type *alloc_ncid_type (int ncid, int is_group)
{
   NCid_Type *nc;

   if (NULL == (nc = (NCid_Type *) SLmalloc (sizeof (NCid_Type))))
     return NULL;

   nc->ncid = ncid;
   nc->is_group = is_group;
   nc->is_closed = 0;
   nc->numrefs = 1;

   return nc;
}

static int check_ncid_type (NCid_Type *nc)
{
   if (nc->is_closed)
     {
	SLang_verror (SL_InvalidParm_Error, "%s", "netcdf handle is invalid");
	return -1;
     }
   return 0;
}

static int pop_ncid_type (NCid_Type **ncp)
{
   if (-1 == SLclass_pop_ptr_obj (NCid_Type_Id, (VOID_STAR *)ncp))
     {
	*ncp = NULL;
	return -1;
     }
   return 0;
}

static int push_ncid_type (NCid_Type *nc)
{
   nc->numrefs++;
   if (0 == SLclass_push_ptr_obj (NCid_Type_Id, (VOID_STAR) nc))
     return 0;
   nc->numrefs--;
   return -1;
}

/* Push an NCid_Type with descriptor ncid.  If a failure occurs, and
 * the descriptor is not a group, then it will be closed.
 */
static int push_ncid (int ncid, int is_group)
{
   NCid_Type *nc;
   int status;

   if (NULL == (nc = alloc_ncid_type (ncid, is_group)))
     {
	if (is_group == 0)
	  (void) nc_close (ncid);
	return -1;
     }

   status = push_ncid_type (nc);
   free_ncid_type (nc);
   return status;
}

static void sl_nc_create (const char *file, int *cmodep)
{
   int status;
   int ncid;

   status = nc_create (file, *cmodep, &ncid);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_create", status);
	return;
     }
   (void) push_ncid (ncid, 0);
}

static void sl_nc_open (const char *file, int *modep)
{
   int status;
   int ncid;

   status = nc_open (file, *modep, &ncid);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_open", status);
	return;
     }
   (void) push_ncid (ncid, 0);
}

static void sl_nc_redef (NCid_Type *nc)
{
   int status;

   if (-1 == check_ncid_type (nc))
     return;

   status = nc_redef (nc->ncid);
   if (status != NC_NOERR)
     throw_nc_error ("nc_redef", status);
}

static void sl_nc_enddef (NCid_Type *nc)
{
   int status;

   if (-1 == check_ncid_type (nc))
     return;

   status = nc_enddef (nc->ncid);
   if (status != NC_NOERR)
     throw_nc_error ("nc_enddef", status);
}

static void sl_nc_close (NCid_Type *nc)
{
   int status;

   if (-1 == check_ncid_type (nc))
     return;

   status = nc_close (nc->ncid);
   if (status != NC_NOERR)
     throw_nc_error ("nc_close", status);

   nc->is_closed = 1;
}


/*}}}*/

static void sl_nc_def_dim (NCid_Type *nc, const char *name, SLindex_Type *np)
{
   NCid_Dim_Type *ncdim;
   int status, dim_id;

   if (-1 == check_ncid_type (nc))
     return;

   status = nc_def_dim (nc->ncid, name, *np, &dim_id);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_def_dim", status);
	return;
     }
   if (NULL == (ncdim = alloc_ncid_dim_type (nc->ncid, dim_id, *np)))
     return;

   (void) push_ncid_dim_type (ncdim);
   free_ncid_dim_type (ncdim);
}

static int *extract_dim_ids (SLang_Array_Type *at_ncdims)
{
   NCid_Dim_Type **ncdims;
   int *dim_ids;
   SLuindex_Type i, n;

   ncdims = (NCid_Dim_Type **) at_ncdims->data;
   n = at_ncdims->num_elements;
   if (NULL == (dim_ids = (int *)SLmalloc(n * sizeof (int))))
     return NULL;

   for (i = 0; i < n; i++)
     dim_ids[i] = ncdims[i]->dim_id;

   return dim_ids;
}


/* Usage: varid = _nc_def_var (nc, name, type, ncdims) */
static void sl_nc_def_var (void)
{
   NCid_Type *nc = NULL;
   NCid_Var_Type *ncvar = NULL;
   SLang_Array_Type *at_ncdims = NULL;
   char *name = NULL;
   int *dim_ids = NULL;
   nc_type xtype;
   int status, varid;

   if (-1 == SLang_pop_array_of_type (&at_ncdims, NCid_Dim_Type_Id))
     return;

   if ((-1 == pop_nc_datatype (&xtype))
       || (-1 == SLang_pop_slstring (&name))
       || (-1 == pop_ncid_type (&nc))
       || (-1 == check_ncid_type (nc))
       || (NULL == (dim_ids = extract_dim_ids (at_ncdims))))
     goto free_and_return;

   status = nc_def_var (nc->ncid, name, xtype, at_ncdims->num_elements, dim_ids, &varid);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_def_var", status);
	goto free_and_return;
     }

   if (NULL != (ncvar = alloc_ncid_var_type (varid, xtype, at_ncdims)))
     (void) push_ncid_var_type (ncvar);

   /* drop */

free_and_return:
   free_ncid_var_type (ncvar);	       /* NULL ok */
   SLang_free_slstring (name);	       /* NULL ok */
   SLang_free_array (at_ncdims);       /* NULL ok */
   free_ncid_type (nc);		       /* NULL ok */
   if (dim_ids != NULL) SLfree (dim_ids);
}


static int pop_slice_args (NCid_Type *nc, NCid_Var_Type *ncvar, int is_read,
			   SLang_Array_Type **at_startp, SLang_Array_Type **at_countp,
			   SLang_Array_Type **at_stridep,
			   size_t *totalp)
{
   SLang_Array_Type *at_count, *at_stride, *at_start;
   ptrdiff_t *stride;
   size_t *start, *count;
   size_t total = 0;
   unsigned int i, num_dims;

   at_stride = NULL;
   at_count = NULL;
   at_start = NULL;

   if ((-1 == pop_array_of_type_or_null (&at_stride, _SL_PTRDIFF_T_TYPE))
       || (-1 == SLang_pop_array_of_type (&at_count, _SL_SIZE_T_TYPE))
       || (-1 == SLang_pop_array_of_type (&at_start, _SL_SIZE_T_TYPE)))
     goto free_and_return;

   num_dims = ncvar->num_dims;

   if ((at_start->num_elements != num_dims)
       || (at_count->num_elements != num_dims)
       || ((NULL != at_stride) && (at_stride->num_elements != num_dims)))
     {
	SLang_verror (SL_InvalidParm_Error, "The number of elements in the start, slice, and stride parameters are inconsistent with the size of the netcdf variable");
	goto free_and_return;
     }

   start = (size_t *)at_start->data;
   count = (size_t *)at_count->data;
   if (at_stride == NULL)
     {
	/* I have seen netcdf segv when stride is NULL.  So do not rely upon it handling a NULL stride */
	at_stride = SLang_create_array (_SL_PTRDIFF_T_TYPE, 0, NULL, at_start->dims, 1);
	if (at_stride == NULL)
	  goto free_and_return;
	stride = (ptrdiff_t *)at_stride->data;
	for (i = 0; i < num_dims; i++)
	  stride[i] = 1;
     }
   else stride = (ptrdiff_t *)at_stride->data;

   total = 1;
   for (i = 0; i < num_dims; i++)
     {
	ptrdiff_t stride_i;
	size_t dim_i = ncvar->dims[i];

	if ((dim_i == 0) && is_read)
	  {
	     NCid_Dim_Type **ncdims = (NCid_Dim_Type **)ncvar->at_ncdims->data;

	     /* Reading an unlimited dimension.  We need to know the actual size */
	     int status = nc_inq_dimlen (nc->ncid, ncdims[i]->dim_id, &dim_i);
	     if (status != NC_NOERR)
	       {
		  throw_nc_error ("nc_inq_dimlen", status);
		  goto free_and_return;
	       }
	  }
	stride_i = stride[i];
	if (((stride_i < 0)
	     && (start[i] < -stride_i * count[i]))
	    || ((dim_i != 0)
		&& (start[i] + stride_i*count[i] > dim_i)))
	  {
	     SLang_verror (SL_InvalidParm_Error, "The slice parameters for dimension %u are inconsistent with the size of the dimension", i);
	     goto free_and_return;
	  }

	total = total * count[i];
     }

   *totalp = total;
   *at_startp = at_start;
   *at_stridep = at_stride;
   *at_countp = at_count;
   return 0;

free_and_return:
   SLang_free_array (at_start);	       /* NULL ok */
   SLang_free_array (at_stride);       /* NULL ok */
   SLang_free_array (at_count);	       /* NULL ok */
   return -1;
}

static int get_var_type (int ncid, int varid, nc_type *xtypep)
{
   int status;

   status = nc_inq_vartype (ncid, varid, xtypep);
   if (status == NC_NOERR) return 0;
   throw_nc_error ("nc_inq_vartype", status);
   return -1;
}

static int get_nc_xclass (int ncid, nc_type xtype, int *xclassp)
{
   int status = nc_inq_user_type (ncid, xtype, NULL, NULL, NULL, NULL, xclassp);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_inq_user_type", xtype);
	return -1;
     }
   return 0;
}


typedef struct
{
   /* Basic information -- set by init_compound_info */
   size_t size;			       /* total size of the compound */
   size_t nfields;
   char **field_names;
   nc_type xtype;

   /* Full information */
   size_t align;
   size_t *field_offsets;
   size_t *field_num_elems;	       /* number of elements in each field */
   nc_type *field_xtypes;
}
Compound_Info_Type;

static void free_compound_info (Compound_Info_Type *cinfo)
{
   if (cinfo->field_names != NULL)
     free_slstring_array (cinfo->field_names, cinfo->nfields);
   SLfree (cinfo->field_num_elems);	       /* NULL ok */
   SLfree (cinfo->field_xtypes);	       /* NULL ok */
   SLfree (cinfo->field_offsets);	       /* NULL ok */
}

/* Forward declaration */
static int compute_compound_align_and_size (int ncid, nc_type xtype, size_t *alignp, size_t *sizep,
					    size_t *xnfieldsp, size_t **field_offsetsp, nc_type **field_xtypesp,
					    size_t **field_num_elemsp);

static int get_compound_field_info (int ncid, int xtype, int idx, char *name,
				    size_t *field_ofsp, nc_type *field_xtypep, int *ndimsp,
				    size_t *num_elemsp, SLindex_Type *at_dims)
{
   size_t ofs, num_elems;
   int *dims;
   nc_type field_xtype;
   int status, i, ndims;

   status = nc_inq_compound_field (ncid, xtype, idx, name, &ofs, &field_xtype, &ndims, NULL);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_inq_compound_field", status);
	return -1;
     }
   if (name == NULL) name = ""; else name[NC_MAX_NAME] = 0;

   if (ndims > SLARRAY_MAX_DIMS)
     {
	SLang_verror (SL_LimitExceeded_Error, "slang arrays are currently limited to %d dimensions.  The compound field %s has %d dimensions",
		      SLARRAY_MAX_DIMS, name, ndims);
	return -1;
     }
   if (field_xtypep != NULL) *field_xtypep = field_xtype;
   if (field_ofsp != NULL) *field_ofsp = ofs;
   if (ndimsp != NULL) *ndimsp = ndims;

   if ((at_dims == NULL) && (num_elemsp == NULL))
     return 0;

   /* otherwise dims is needed */

   if (NULL == (dims = (int *)SLmalloc ((ndims+1) * sizeof(int))))
     return -1;

   status = nc_inq_compound_field (ncid, xtype, idx, NULL, NULL, NULL, &ndims, dims);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_inq_compound_field", status);
	SLfree (dims);
	return -1;
     }

   num_elems = 1;
   for (i = 0; i < ndims; i++)
     {
	if (at_dims != NULL) at_dims[i] = dims[i];
	num_elems *= dims[i];
     }
   if (num_elemsp != NULL) *num_elemsp = num_elems;

   SLfree (dims);
   return 0;
}


static int init_compound_info (int ncid, nc_type xtype, Compound_Info_Type *cinfo, int full_info)
{
   size_t nfields, size;
   char **field_names;
   unsigned int i;
   int status;

   memset (cinfo, 0, sizeof(Compound_Info_Type));

   status = nc_inq_compound (ncid, xtype, NULL, &size, &nfields);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_inq_compound", status);
	return -1;
     }

   if (NULL == (field_names = (char **)SLcalloc (nfields, sizeof(char *))))
     return -1;

   for (i = 0; i < nfields; i++)
     {
	char name[NC_MAX_NAME+1];

	if (-1 == get_compound_field_info (ncid, xtype, i, name, NULL, NULL, NULL, NULL, NULL))
	  {
	     free_slstring_array (field_names, nfields);
	     return -1;
	  }

	if (NULL == (field_names[i] = SLang_create_slstring (name)))
	  {
	     free_slstring_array (field_names, nfields);
	     return -1;
	  }
     }

   cinfo->xtype = xtype;
   cinfo->nfields = nfields;
   cinfo->field_names = field_names;
   cinfo->size = size;

   if (full_info == 0) return 0;

   if (-1 == compute_compound_align_and_size (ncid, xtype, &cinfo->align, &size, &nfields,
					      &cinfo->field_offsets, &cinfo->field_xtypes, &cinfo->field_num_elems))
     {
	free_compound_info (cinfo);
	return -1;
     }

   return 0;
}


/* Forward declaration */
static int put_compound (int ncid, int varid, nc_type xtype, size_t *start, size_t *count, ptrdiff_t *stride,
			 SLang_Array_Type *at, const char *attr_name);

/* Usage: _nc_put_vars (start, count, stride, data, ncid, varid) */
static void sl_nc_put_vars (NCid_Type *nc, NCid_Var_Type *ncvar)
{
   size_t total;
   SLang_Array_Type *at, *at_start, *at_count, *at_stride;
   size_t *start, *count;
   ptrdiff_t *stride;
   int ncid, varid, status;
   nc_type xtype;

   if (-1 == check_ncid_type (nc))
     return;

   if (-1 == SLang_pop_array (&at, 1))
     return;

   if (ncvar->num_dims == 0)
     {
	if (SLang_Num_Function_Args != 3)
	  {
	     SLang_verror (SL_Usage_Error, "_nc_put_vars: scalar variables do not permit slice arguments");
	     return;
	  }
	total = 1;
	at_start = NULL; start = NULL;
	at_count = NULL; count = NULL;
	at_stride = NULL; stride = NULL;
     }
   else
     {
	if (-1 == pop_slice_args (nc, ncvar, 0, &at_start, &at_count, &at_stride, &total))
	  {
	     SLang_free_array (at);
	     return;
	  }
	start = (size_t *) at_start->data;
	count = (size_t *) at_count->data;
	stride = NULL;
	if (at_stride != NULL)
	  {
	     ptrdiff_t *s = (ptrdiff_t *) at_stride->data;
	     SLindex_Type i, n = at_stride->num_elements;
	     for (i = 0; i < n; i++)
	       {
		  if (s[i] == 1) continue;
		  stride = s;
		  break;
	       }
	  }
     }

   if (total != at->num_elements)
     {
	SLang_verror (SL_InvalidParm_Error, "_nc_put_vars: the slice parameters are inconsistent with the provided array: %lu values provided, %lu expected",
		      (unsigned long) at->num_elements, (unsigned long) total);
	goto free_and_return;
     }

   ncid = nc->ncid;
   varid = ncvar->var_id;

   if (at->data_type == SLANG_STRUCT_TYPE)
     {
	int xclass;

	if ((-1 == get_var_type (ncid, varid, &xtype))
	    || (-1 == get_nc_xclass (ncid, xtype, &xclass)))
	  goto free_and_return;

	if (xclass != NC_COMPOUND)
	  {
	     SLang_verror (SL_InvalidParm_Error, "Variable is not compound type");
	     goto free_and_return;
	  }

	(void) put_compound (ncid, varid, xtype, start, count, stride, at, NULL);
	goto free_and_return;
     }


   if (-1 == map_base_sltype_to_xtype (at->data_type, &xtype))
     goto free_and_return;

   switch (xtype)
     {
      case NC_BYTE:
	if (stride != NULL)
	  status = nc_put_vars_schar (ncid, varid, start, count, stride, (signed char *)at->data);
	else
	  status = nc_put_vara_schar (ncid, varid, start, count, (signed char *)at->data);
	break;
      case NC_UBYTE:
	if (stride != NULL)
	  status = nc_put_vars_uchar (ncid, varid, start, count, stride, (unsigned char *)at->data);
	else
	  status = nc_put_vara_uchar (ncid, varid, start, count, (unsigned char *)at->data);
	break;
      case NC_SHORT:
	if (stride != NULL)
	  status = nc_put_vars_short (ncid, varid, start, count, stride, (short *)at->data);
	else
	  status = nc_put_vara_short (ncid, varid, start, count, (short *)at->data);
	break;
      case NC_USHORT:
	if (stride != NULL)
	  status = nc_put_vars_ushort (ncid, varid, start, count, stride, (unsigned short *)at->data);
	else
	  status = nc_put_vara_ushort (ncid, varid, start, count, (unsigned short *)at->data);
	break;
      case NC_INT:
	if (stride != NULL)
	  status = nc_put_vars_int (ncid, varid, start, count, stride, (int *)at->data);
	else
	  status = nc_put_vara_int (ncid, varid, start, count, (int *)at->data);
	break;
      case NC_UINT:
	if (stride != NULL)
	  status = nc_put_vars_uint (ncid, varid, start, count, stride, (unsigned int *)at->data);
	else
	  status = nc_put_vara_uint (ncid, varid, start, count, (unsigned int *)at->data);
	break;
      case NC_INT64:
	if (stride != NULL)
	  status = nc_put_vars_longlong (ncid, varid, start, count, stride, (long long *)at->data);
	else
	  status = nc_put_vara_longlong (ncid, varid, start, count, (long long *)at->data);
	break;
      case NC_UINT64:
	if (stride != NULL)
	  status = nc_put_vars_ulonglong (ncid, varid, start, count, stride, (unsigned long long *)at->data);
	else
	  status = nc_put_vara_ulonglong (ncid, varid, start, count, (unsigned long long *)at->data);
	break;
      case NC_FLOAT:
	if (stride != NULL)
	  status = nc_put_vars_float (ncid, varid, start, count, stride, (float *)at->data);
	else
	  status = nc_put_vara_float (ncid, varid, start, count, (float *)at->data);
	break;
      case NC_DOUBLE:
	if (stride != NULL)
	  status = nc_put_vars_double (ncid, varid, start, count, stride, (double *)at->data);
	else
	  status = nc_put_vara_double (ncid, varid, start, count, (double *)at->data);
	break;

      default:
	SLang_verror (SL_NotImplemented_Error, "_nc_put_vars: %s is not yet supported",
		      SLclass_get_datatype_name (at->data_type));
	goto free_and_return;
     }

   if (status != NC_NOERR)
     {
	throw_nc_error ("_nc_put_vars", status);
	/* drop */
     }

free_and_return:
   SLang_free_array (at);
   SLang_free_array (at_count);
   SLang_free_array (at_stride);
   SLang_free_array (at_start);
}


static int compute_align_and_size (int ncid, nc_type xtype, size_t *alignp, size_t *sizep);
static int extract_compounds (int ncid, Compound_Info_Type *cinfo, unsigned char *data, size_t num_elements, SLang_Struct_Type **);

static SLang_Struct_Type *extract_compound (int ncid, nc_type xtype, char **field_names, size_t nfields,
					    unsigned char *data);

static int push_compound_element (int ncid, nc_type xtype, int idx, unsigned char *data)
{
   char name[NC_MAX_NAME+1];
   SLindex_Type at_dims[SLARRAY_MAX_DIMS];
   size_t num_elements, size, ofs, align;
   SLang_Array_Type *at;
   nc_type field_xtype;
   int ndims, status;
   SLtype sltype;

   if (-1 == get_compound_field_info (ncid, xtype, idx, name, &ofs, &field_xtype, &ndims, &num_elements, at_dims))
     return -1;

   /* Consistency check: Check that the offset is consistent with the the module's computed version.
    * If they are not consistent, bail out to avoid a possible BUS error.
    */
   if (-1 == compute_align_and_size (ncid, field_xtype, &align, &size))
     return -1;

   if (ofs % align)
     {
	SLang_verror (SL_RunTime_Error, "compound type %u, field %s, xtype %u: netCDF reports offset=%lu, but module align=%lu",
		      xtype, name, field_xtype, (unsigned long) ofs, (unsigned long) align);
	return -1;
     }

   if (field_xtype > NC_MAX_ATOMIC_TYPE)
     {
	int xclass;
	if (-1 == get_nc_xclass (ncid, field_xtype, &xclass))
	  return -1;
	if (xclass != NC_COMPOUND)
	  {
	     SLang_vmessage ("Compound of vlen or opaque types not implemented; setting compound field %s to NULL", name);
	     return SLang_push_null ();
	  }
	sltype = SLANG_STRUCT_TYPE;
     }
   else if (-1 == map_base_xtype_to_sltype (field_xtype, &sltype))
     return -1;


   if (num_elements == 1)
     at = NULL;
   else
     {
	at = SLang_create_array (sltype, 0, NULL, at_dims, ndims);
	if (at == NULL)
	  return -1;
     }

   /* Move the data pointer to the field value location */
   data = data + ofs;
   status = -1;

   switch (sltype)
     {
      case SLANG_STRUCT_TYPE:
	  {
	     Compound_Info_Type cinfo;

	     if (-1 == init_compound_info (ncid, field_xtype, &cinfo, 0))
	       break;
	     if (num_elements == 1)
	       {
		  SLang_Struct_Type *s;
		  if (0 == (status = extract_compounds (ncid, &cinfo, data, num_elements, &s)))
		    {
		       status = SLang_push_struct (s);
		       SLang_free_struct (s);
		    }
	       }
	     else
	       status = extract_compounds (ncid, &cinfo, data, num_elements, (SLang_Struct_Type **) at->data);

	     free_compound_info (&cinfo);
	  }
	break;

      case SLANG_STRING_TYPE:
	if (num_elements == 1)
	  {
	     status = SLang_push_string (*(char **)data);
	     SLfree (*(char **)data);
	  }
	else
	  {
	     size_t j;
	     char **sp = (char **)at->data;
	     char **sp1 = (char **)data;

	     status = 0;
	     for (j = 0; j < num_elements; j++)
	       {
		  char *s = sp1[j];
		  if (s == NULL) continue;
		  if ((status == 0)
		      && (NULL == (sp[j] = SLang_create_slstring (s))))
		    status = -1;
		  SLfree (s);
	       }
	  }
	break;

      default:
	if (num_elements == 1)
	  status = SLang_push_value (sltype, data);
	else
	  {
	     memcpy (at->data, data, num_elements*at->sizeof_type);
	     status = 0;
	  }
     }

   if (at != NULL)
     {
	if (status == 0)
	  status = SLang_push_array (at, 0);
	SLang_free_array (at);
     }
   return status;
}

/* This function assumes that the arguments have already been validated */
static SLang_Struct_Type *extract_compound (int ncid, nc_type xtype, char **field_names, size_t nfields,
					    unsigned char *data)
{
   SLang_Struct_Type *s;
   unsigned int j;

   if (NULL == (s = SLang_create_struct (field_names, nfields)))
     return NULL;

   for (j = 0; j < nfields; j++)
     {
	if (-1 == push_compound_element (ncid, xtype, j, data))
	  {
	     SLang_free_struct (s);
	     return NULL;
	  }
     }

   /* nfield values are on the stack.  Pop them and set the struct fields. */
   if (-1 == SLang_pop_struct_fields (s, nfields))
     {
	SLang_free_struct (s);
	return NULL;
     }
   return s;
}

static int extract_compounds (int ncid, Compound_Info_Type *cinfo, unsigned char *data, size_t num_elements,
			      SLang_Struct_Type **sp)

{
   size_t i, size;
   int status = 0;

   size = cinfo->size;
   for (i = 0; i < num_elements; i++)
     {
	SLang_Struct_Type *s = extract_compound (ncid, cinfo->xtype, cinfo->field_names, cinfo->nfields, data);
	if (s == NULL)
	  {
	     status = -1;
	     while (i > 0)
	       {
		  i--;
		  SLang_free_struct (sp[i]);
		  sp[i] = NULL;
	       }
	     break;
	  }
	sp[i] = s;
	data += size;
     }
   return status;
}

static int get_compound (int ncid, int varid, nc_type xtype,
			 size_t *start, size_t *count, ptrdiff_t *stride,
			 SLang_Array_Type *at, const char *attname)
{
   Compound_Info_Type cinfo;
   unsigned char *data;
   int status, return_status;

   if (-1 == init_compound_info (ncid, xtype, &cinfo, 0))
     return -1;

   return_status = -1;

   if (NULL == (data = (unsigned char *) SLmalloc (at->num_elements*cinfo.size)))
     goto free_and_return;

   if (attname != NULL)
     status = nc_get_att (ncid, varid, attname, data);
   else if (stride == NULL)
     status = nc_get_vara (ncid, varid, start, count, data);
   else
     status = nc_get_vars (ncid, varid, start, count, stride, data);

   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_get_xxx", status);
	goto free_and_return;
     }

   return_status = extract_compounds (ncid, &cinfo, data, at->num_elements, (SLang_Struct_Type **)at->data);

   /* drop */

free_and_return:

   SLfree (data);
   free_compound_info (&cinfo);
   return return_status;
}

/* Usage: at = _nc_get_vars (start, count, stride, ncid, varid) */
static void sl_nc_get_vars (NCid_Type *nc, NCid_Var_Type *ncvar)
{
   size_t total;
   SLindex_Type at_dims[SLARRAY_MAX_DIMS];
   SLang_Array_Type *at, *at_start, *at_count, *at_stride;
   size_t *start, *count;
   ptrdiff_t *stride;
   SLuindex_Type i, num_dims;
   int ncid, varid, status, is_scalar;
   nc_type xtype;
   SLtype sltype;

   if (-1 == check_ncid_type (nc))
     return;

   ncid = nc->ncid;
   varid = ncvar->var_id;

   if (-1 == get_var_type (ncid, varid, &xtype))
     return;

   if (xtype <= NC_MAX_ATOMIC_TYPE)
     {
	if (-1 == map_base_xtype_to_sltype (xtype, &sltype))
	  return;
     }
   else
     {
	int xclass;

	if (-1 == get_nc_xclass (ncid, xtype, &xclass))
	  return;

	switch (xclass)
	  {
	   case NC_COMPOUND:
	     sltype = SLANG_STRUCT_TYPE;
	     break;

	   case NC_ENUM:
	     SLang_verror (SL_NotImplemented_Error, "ENUM types are not yet implemented");
	     return;
	   case NC_OPAQUE:
	     SLang_verror (SL_NotImplemented_Error, "OPAQUE types are not yet implemented");
	     return;
	   case NC_VLEN:
	     SLang_verror (SL_NotImplemented_Error, "VLEN types are not yet implemented");
	     return;
	   default:
	     SLang_verror (SL_NotImplemented_Error, "Unknown class %d", xclass);
	     return;
	  }
     }

   if (ncvar->num_dims == 0)
     {
	if (SLang_Num_Function_Args != 2)
	  {
	     SLang_verror (SL_Usage_Error, "_nc_get_vars: scalar variables do not permit slice arguments");
	     return;
	  }
	total = 1;
	at_start = NULL; start = NULL;
	at_count = NULL; count = NULL;
	at_stride = NULL; stride = NULL;
	at_dims[0] = 1;
	num_dims = 1;
	is_scalar = 1;
     }
   else
     {
	if (-1 == pop_slice_args (nc, ncvar, 1, &at_start, &at_count, &at_stride, &total))
	  return;

	if (at_count->num_elements > SLARRAY_MAX_DIMS)
	  {
	     SLang_verror (SL_LimitExceeded_Error, "slang arrays are currently limited to %d dimensions.  The netcdf variable has %d dimensions",
			   SLARRAY_MAX_DIMS, at_count->num_elements);
	     return;
	  }

	start = (size_t *) at_start->data;
	count = (size_t *) at_count->data;
	stride = (ptrdiff_t *) at_stride->data;

	num_dims = at_count->num_elements;
	for (i = 0; i < num_dims; i++)
	  at_dims[i] = count[i];
	is_scalar = 0;
     }

   if (NULL == (at = SLang_create_array (sltype, 0, NULL, at_dims, num_dims)))
     goto free_and_return;

   switch (sltype)
     {
      case SLANG_CHAR_TYPE:
	status = nc_get_vars_schar (ncid, varid, start, count, stride, (signed char *)at->data);
	break;
      case SLANG_UCHAR_TYPE:
	status = nc_get_vars_uchar (ncid, varid, start, count, stride, (unsigned char *)at->data);
	break;
      case SLANG_SHORT_TYPE:
	status = nc_get_vars_short (ncid, varid, start, count, stride, (short *)at->data);
	break;
      case SLANG_USHORT_TYPE:
	status = nc_get_vars_ushort (ncid, varid, start, count, stride, (unsigned short *)at->data);
	break;
      case SLANG_INT_TYPE:
	status = nc_get_vars_int (ncid, varid, start, count, stride, (int *)at->data);
	break;
      case SLANG_UINT_TYPE:
	status = nc_get_vars_uint (ncid, varid, start, count, stride, (unsigned int *)at->data);
	break;
#if (SIZEOF_LONG == 4)
      case SLANG_LONG_TYPE:
	status = nc_get_vars_int (ncid, varid, start, count, stride, (long *)at->data);
	break;
      case SLANG_ULONG_TYPE:
	status = nc_get_vars_uint (ncid, varid, start, count, stride, (unsigned long *)at->data);
	break;
#else
      case SLANG_LONG_TYPE:
	status = nc_get_vars_longlong (ncid, varid, start, count, stride, (long long *)at->data);
	break;
      case SLANG_ULONG_TYPE:
	status = nc_get_vars_ulonglong (ncid, varid, start, count, stride, (unsigned long long *)at->data);
	break;
#endif
      case SLANG_LLONG_TYPE:
	status = nc_get_vars_longlong (ncid, varid, start, count, stride, (long long *)at->data);
	break;
      case SLANG_ULLONG_TYPE:
	status = nc_get_vars_ulonglong (ncid, varid, start, count, stride, (unsigned long long *)at->data);
	break;
      case SLANG_FLOAT_TYPE:
	status = nc_get_vars_float (ncid, varid, start, count, stride, (float *)at->data);
	break;
      case SLANG_DOUBLE_TYPE:
	status = nc_get_vars_double (ncid, varid, start, count, stride, (double *)at->data);
	break;

      case SLANG_STRUCT_TYPE:
	if (-1 == get_compound (ncid, varid, xtype, start, count, stride, at, NULL))
	  goto free_and_return;
	status = NC_NOERR;
	break;

      default:
	SLang_verror (SL_NotImplemented_Error, "_nc_get_vars: %s is not yet supported",
		      SLclass_get_datatype_name (at->data_type));
	goto free_and_return;
     }

   if (status != NC_NOERR)
     {
	throw_nc_error ("_nc_get_vars", status);
	/* drop */
     }

   if (is_scalar)
     (void) SLang_push_value (at->data_type, at->data);
   else
     (void) SLang_push_array (at, 0);
   /* drop */
free_and_return:
   SLang_free_array (at);
   SLang_free_array (at_count);
   SLang_free_array (at_stride);
   SLang_free_array (at_start);
}

static int embed_compound (int ncid, Compound_Info_Type *cinfo, SLang_Struct_Type **sp, size_t num_elements, unsigned char *data);

/* Pop the item of type field_xtypes from the stack and embed it in the data buffer */
static int pop_compound_element (int ncid, unsigned char *data, int idx, nc_type field_xtype,
				 const char *field_name, size_t field_num_elems)
{
   SLang_Array_Type *at;
   SLtype sltype;
   int status;

   (void) idx;

   if (field_xtype > NC_MAX_ATOMIC_TYPE)
     {
	int xclass;
	if (-1 == get_nc_xclass (ncid, field_xtype, &xclass))
	  return -1;
	if (xclass != NC_COMPOUND)
	  {
	     SLang_verror (SL_NotImplemented_Error, "Compound of vlen or opaque types not implemented");
	     return -1;
	  }
	sltype = SLANG_STRUCT_TYPE;
     }
   else if (-1 == map_base_xtype_to_sltype (field_xtype, &sltype))
     return -1;

   if (field_num_elems == 1)
     at = NULL;
   else
     {
	if (-1 == SLang_pop_array_of_type (&at, sltype))
	  return -1;
	if (field_num_elems != at->num_elements)
	  {
	     SLang_verror (SL_InvalidParm_Error, "Compound field %s requires %lu elements, %lu provided",
			   field_name, (unsigned long) field_num_elems, (unsigned long) at->num_elements);
	     SLang_free_array (at);
	     return -1;
	  }
     }

   status = 0;
   switch (sltype)
     {
      case SLANG_STRUCT_TYPE:
	  {
	     Compound_Info_Type cinfo;

	     if (-1 == init_compound_info (ncid, field_xtype, &cinfo, 1))
	       {
		  SLang_free_array (at);   /* NULL ok */
		  return -1;
	       }
	     if (at == NULL)
	       {
		  SLang_Struct_Type *s;
		  if (-1 == SLang_pop_struct (&s))
		    return -1;
		  status = embed_compound (ncid, &cinfo, &s, 1, data);
		  SLang_free_struct (s);
	       }
	     else
	       status = embed_compound (ncid, &cinfo, (SLang_Struct_Type **) at->data, at->num_elements, data);
	     free_compound_info (&cinfo);
	  }
	break;

      case SLANG_STRING_TYPE:
	if (at == NULL)
	  {
	     char *str;
	     if (-1 == SLang_pop_slstring (&str))
	       return -1;
	     *(char **) data = str;
	  }
	else
	  {
	     char **sp = (char **)data, **at_sp = (char **) at->data;
	     size_t i;

	     for (i = 0; i < field_num_elems; i++)
	       {
		  if (NULL == (sp[i] = SLang_create_slstring (at_sp[i])))
		    {
		       while (i != 0)
			 {
			    i--;
			    SLang_free_slstring (sp[i]);
			    sp[i] = NULL;
			 }
		       status = -1;
		       break;
		    }
	       }
	  }
	break;

      default:
	if (at == NULL)
	  return SLang_pop_value (sltype, data);
	memcpy (data, at->data, field_num_elems*at->sizeof_type);
     }
   if (at != NULL) SLang_free_array (at);
   return status;
}

static void free_compound (int ncid, nc_type xtype, size_t num_elements, unsigned char *data);

static void free_compound_fields (unsigned char *compound_data, int ncid, Compound_Info_Type *cinfo)
{
   size_t i, nfields;

   nfields = cinfo->nfields;

   for (i = 0; i < nfields; i++)
     {
	size_t j, num_elements;
	unsigned char *data;
	nc_type field_xtype = cinfo->field_xtypes[i];
	int xclass;

	data = compound_data + cinfo->field_offsets[i];
	num_elements = cinfo->field_num_elems[i];
	if (field_xtype == NC_STRING)
	  {
	     char **sp = (char **)(data);

	     for (j = 0; j < num_elements; j++)
	       SLang_free_slstring (sp[j]);   /* NULL ok */

	     continue;
	  }

	if (field_xtype <= NC_MAX_ATOMIC_TYPE)
	  continue;

	if (-1 == get_nc_xclass (ncid, field_xtype, &xclass))
	  continue;	       /* ???? */
	if (xclass == NC_COMPOUND)
	  {
	     free_compound (ncid, field_xtype, num_elements, data);
	     continue;
	  }
     }
}

static void free_compound_data_items (int ncid, Compound_Info_Type *cinfo, unsigned char *data, size_t num_elements)
{
   size_t i;

   for (i = 0; i < num_elements; i++)
     {
	free_compound_fields (data, ncid, cinfo);
	data += cinfo->size;
     }
}

/* Free the items on the compound data list */
static void free_compound (int ncid, nc_type xtype, size_t num_elements, unsigned char *data)
{
   Compound_Info_Type cinfo;

   if (-1 == init_compound_info (ncid, xtype, &cinfo, 1))
     return;
   free_compound_data_items (ncid, &cinfo, data, num_elements);
   free_compound_info (&cinfo);
}


/*
 * This function embeds the field values of an array of slang structs into the data buffer.
 */
static int embed_compound (int ncid, Compound_Info_Type *cinfo, SLang_Struct_Type **sp, size_t num_elements, unsigned char *data)
{
   size_t nfields, i, size;
   size_t *field_offsets = NULL, *field_num_elems = NULL;
   char **field_names;
   nc_type *field_xtypes = NULL;
   unsigned char *compound_data;

   for (i = 0; i < num_elements; i++)
     {
	if (sp[i] == NULL)
	  {
	     SLang_verror (SL_InvalidParm_Error, "A compound array-element cannot be NULL");
	     return -1;
	  }
     }

   size = cinfo->size;
   memset (data, 0, size*num_elements);

   field_offsets = cinfo->field_offsets;
   field_xtypes = cinfo->field_xtypes;
   field_names = cinfo->field_names;
   field_num_elems = cinfo->field_num_elems;
   nfields = cinfo->nfields;

   compound_data = data;
   for (i = 0; i < num_elements; i++)
     {
	SLang_Struct_Type *s = sp[i];
	size_t j;

	for (j = 0; j < nfields; j++)
	  {
	     if (-1 == SLang_push_struct_field (s, field_names[j]))
	       goto return_error;
	     if (-1 == pop_compound_element (ncid, compound_data + field_offsets[j], j, field_xtypes[j], field_names[j], field_num_elems[j]))
	       goto return_error;
	  }
	compound_data += size;
     }
   return 0;

return_error:

   free_compound_data_items (ncid, cinfo, data, num_elements);
   return -1;
}


/* This gets called with at->data_type == SLANG_STRUCT_TYPE */
static int put_compound (int ncid, int varid, nc_type xtype, size_t *start, size_t *count, ptrdiff_t *stride,
			 SLang_Array_Type *at, const char *attr_name)
{
   Compound_Info_Type cinfo;
   size_t size;
   unsigned char *compound_data;
   SLuindex_Type num_elements;
   int status;

   if (-1 == init_compound_info (ncid, xtype, &cinfo, 1))
     return -1;
   size = cinfo.size;

   num_elements = at->num_elements;
   if ((NULL == (compound_data = (unsigned char *)SLmalloc(num_elements*size)))
       || (-1 == embed_compound (ncid, &cinfo, (SLang_Struct_Type **)at->data, at->num_elements, compound_data)))
     {
	free_compound_info (&cinfo);
	return -1;
     }

   if (attr_name != NULL)
     status = nc_put_att (ncid, varid, attr_name, xtype, num_elements, compound_data);
   else if (stride == NULL)
     status = nc_put_vara (ncid, varid, start, count, compound_data);
   else
     status = nc_put_vars (ncid, varid, start, count, stride, compound_data);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_put_xxx", status);
	status = -1;
     }
   else status = 0;

   free_compound_data_items (ncid, &cinfo, compound_data, num_elements);
   SLfree (compound_data);
   free_compound_info (&cinfo);

   return status;
}


/* If there are no unlimited dims, *unlim_dimsp will be NULL. */
static int get_unlimited_dim_ids (int ncid, int **unlim_dimsp, int *num_unlimp)
{
   int *unlim_dims;
   int num_unlim, status;

   *unlim_dimsp = unlim_dims = NULL;
   *num_unlimp = 0;
   if (NC_NOERR != (status = nc_inq_unlimdims (ncid, &num_unlim, unlim_dims)))
     {
	throw_nc_error ("nc_inq_unlimdims", status);
	return -1;
     }
   if (num_unlim <= 0) return 0;

   if (NULL == (unlim_dims = (int *)SLmalloc(num_unlim * sizeof(int))))
     return -1;

   if (NC_NOERR != (status = nc_inq_unlimdims (ncid, NULL, unlim_dims)))
     {
	throw_nc_error ("nc_inq_unlimdims", status);
	SLfree (unlim_dims);
	return -1;
     }
   *unlim_dimsp = unlim_dims;
   *num_unlimp = num_unlim;
   return 0;
}

/* unlim_dims could be NULL indicating that there are no unlimited dimensions */
static NCid_Dim_Type *inq_and_create_dim (int ncid, int dimid, int *unlim_dims, int num_unlim)
{
   size_t len;
   int is_unlim, status;

   is_unlim = 0;
   if (unlim_dims != NULL)
     {
	int i;

	for (i = 0; i < num_unlim; i++)
	  {
	     if (dimid == unlim_dims[i])
	       {
		  len = 0;
		  is_unlim = 1;
		  break;
	       }
	  }
     }

   if ((is_unlim == 0)
       && (NC_NOERR != (status = nc_inq_dimlen (ncid, dimid, &len))))
     {
	throw_nc_error ("nc_inq_dimlen", status);
	return NULL;
     }

   return alloc_ncid_dim_type (ncid, dimid, len);
}

#if 0
/* You would think that nc_inq_grp_full_ncid(ncid, "/", &root_ncid)
 * would suffice.  But,....no.
 */
static int get_root_ncid (NCid_Type *nc, int *ncidp)
{
   int ncid = nc->ncid;
   if (0 == nc->is_group)
     {
	*ncidp = ncid;
	return 0;
     }

   while (1)
     {
	int status, root;
	status = nc_inq_grp_parent (ncid, &root);
	if (status == NC_ENOGRP)
	  break;
	if (status != NC_NOERR)
	  {
	     throw_nc_error ("nc_inq_grp_parent", status);
	     return -1;
	  }
	if (root == ncid) break;
	ncid = root;
     }
   *ncidp = ncid;
   return 0;
}
#endif

/*{{{ Attribute Functions */

/* Attributes for a variable are numbered from 0 to natts-1 */
static SLang_Array_Type *get_var_at_atts (int ncid, int varid)
{
   SLang_Array_Type *at;
   char **names;
   SLindex_Type i, n;
   int status, natts;

   status = nc_inq_varnatts (ncid, varid, &natts);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_inq_varnatts", status);
	return NULL;
     }
   n = natts;
   at = SLang_create_array (SLANG_STRING_TYPE, 0, NULL, &n, 1);
   if (at == NULL) return NULL;

   names = (char **)at->data;

   for (i = 0; i < n; i++)
     {
	char name[NC_MAX_NAME+1];

	if (NC_NOERR != (status = nc_inq_attname (ncid, varid, i, name)))
	  {
	     throw_nc_error ("nc_inq_attname", status);
	     SLang_free_array (at);
	     return NULL;
	  }
	name[NC_MAX_NAME] = 0;
	if (NULL == (names[i] = SLang_create_slstring (name)))
	  {
	     SLang_free_array (at);
	     return NULL;
	  }
     }

   return at;
}

/*}}}*/

static SLang_Array_Type *get_at_ncdims2 (NCid_Type *nc, int inc_parents)
{
   NCid_Dim_Type **ncdims;
   SLang_Array_Type *at_ncdims = NULL;
   int *dimids, *unlim_dims;
   SLindex_Type num_dims;
   int status, i, num_unlim, ndims;

   dimids = NULL;
   status = nc_inq_dimids (nc->ncid, &ndims, dimids, inc_parents);
   if (status != NC_NOERR)
     {
	throw_nc_error ("_nc_inq_dimids", status);
	return NULL;
     }
   if (NULL == (dimids = (int *)SLmalloc ((ndims+1) * sizeof(int))))
     return NULL;

   status = nc_inq_dimids (nc->ncid, &ndims, dimids, inc_parents);
   if (status != NC_NOERR)
     {
	throw_nc_error ("_nc_inq_dimids", status);
	SLfree (dimids);
	return NULL;
     }
   if (-1 == get_unlimited_dim_ids (nc->ncid, &unlim_dims, &num_unlim))
     {
	SLfree (dimids);
	return NULL;
     }
   /* unlim_dims could be NULL with num_unlim set to 0.  The call to SLfree is safe */
   num_dims = ndims;
   if (NULL == (at_ncdims = SLang_create_array (NCid_Dim_Type_Id, 0, NULL, &num_dims, 1)))
     goto return_error;

   ncdims = (NCid_Dim_Type **) at_ncdims->data;
   for (i = 0; i < ndims; i++)
     {
	if (NULL == (ncdims[i] = inq_and_create_dim (nc->ncid, dimids[i], unlim_dims, num_unlim)))
	  goto return_error;
     }

   SLfree (unlim_dims);
   SLfree (dimids);
   return at_ncdims;

return_error:
   SLang_free_array (at_ncdims);
   SLfree (unlim_dims);
   SLfree (dimids);
   return NULL;
}


static int *get_var_dimids (int ncid, int varid, SLindex_Type *num_dimsp, nc_type *xtypep)
{
   int *dimids;
   int status, ndims;

   dimids = NULL;
   status = nc_inq_var (ncid, varid, NULL, NULL, &ndims, dimids, NULL);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_inq_var", status);
	return NULL;
     }
   if (NULL == (dimids = (int *)SLmalloc(ndims*sizeof(int))))
     return NULL;

   status = nc_inq_var (ncid, varid, NULL, xtypep, &ndims, dimids, NULL);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_inq_var", status);
	SLfree (dimids);
	return NULL;
     }
   *num_dimsp = ndims;
   return dimids;
}

/* Get a slang array of NCid_Dim_Type objects for the specifid variable.
 * The objects are copied from the full list of dim objects
 */
static SLang_Array_Type *get_var_at_ncdims (int ncid, int varid, SLang_Array_Type *all_at_ncdims, nc_type *xtypep)
{
   NCid_Dim_Type **ncdims, **all_ncdims;
   SLang_Array_Type *at_ncdims;
   SLuindex_Type num_all_ncdims;
   SLindex_Type i, num_dims;
   int *dimids;
   nc_type xtype;

   if (NULL == (dimids = get_var_dimids (ncid, varid, &num_dims, &xtype)))
     return NULL;

   if (NULL == (at_ncdims = SLang_create_array (NCid_Dim_Type_Id, 0, NULL, &num_dims, 1)))
     {
	SLfree (dimids);
	return NULL;
     }

   ncdims = (NCid_Dim_Type **)at_ncdims->data;
   all_ncdims = (NCid_Dim_Type **)all_at_ncdims->data;
   num_all_ncdims = all_at_ncdims->num_elements;

   for (i = 0; i < num_dims; i++)
     {
	SLuindex_Type j;
	int dim_id_i = dimids[i];

	for (j = 0; j < num_all_ncdims; j++)
	  {
	     NCid_Dim_Type *ncdim = all_ncdims[j];
	     if (ncdim->dim_id == dim_id_i)
	       {
		  ncdims[i] = ncdim;
		  ncdim->numrefs++;
		  break;
	       }
	  }
	if (j == num_all_ncdims)
	  {
	     SLang_verror (SL_Application_Error, "NETCDF variable #%d has no dimension matching id #%d",
			   varid, dim_id_i);
	     SLang_free_array (at_ncdims);
	     SLfree (dimids);
	     return NULL;
	  }
     }

   SLfree (dimids);
   *xtypep = xtype;
   return at_ncdims;
}

static NCid_Var_Type *inq_and_create_var (int ncid, int varid, SLang_Array_Type *all_at_ncdims)
{
   SLang_Array_Type *at_ncdims;
   NCid_Var_Type *ncvar = NULL;
   nc_type xtype;

   if (NULL == (at_ncdims = get_var_at_ncdims (ncid, varid, all_at_ncdims, &xtype)))
     return NULL;

   ncvar = alloc_ncid_var_type (varid, xtype, at_ncdims);
   SLang_free_array (at_ncdims);
   return ncvar;
}

static SLang_Array_Type *get_at_ncvars (int ncid, SLang_Array_Type *all_at_ncdims)
{
   SLang_Array_Type *at_ncvars;
   NCid_Var_Type **ncvars;
   SLindex_Type num_vars;
   int *varids;
   int status, i, nvars;

   if (NC_NOERR != (status = nc_inq_varids (ncid, &nvars, NULL)))
     {
	throw_nc_error ("nc_inq_varids", status);
	return NULL;
     }
   if (NULL == (varids = (int *)SLmalloc (nvars * sizeof(int))))
     return NULL;

   if (NC_NOERR != (status = nc_inq_varids (ncid, &nvars, varids)))
     {
	throw_nc_error ("nc_inq_varids", status);
	SLfree (varids);
	return NULL;
     }

   num_vars = nvars;
   if (NULL == (at_ncvars = SLang_create_array (NCid_Var_Type_Id, 0, NULL, &num_vars, 1)))
     {
	SLfree (varids);
	return NULL;
     }

   ncvars = (NCid_Var_Type **)at_ncvars->data;
   for (i = 0; i < nvars; i++)
     {
	NCid_Var_Type *ncvar = inq_and_create_var (ncid, varids[i], all_at_ncdims);
	if (ncvar == NULL) goto free_and_return;
	ncvars[i] = ncvar;
     }

   SLfree (varids);
   return at_ncvars;

free_and_return:
   SLang_free_array (at_ncvars);       /* NULL ok */
   SLfree (varids);		       /* NULL ok */
   return NULL;
}



static void sl_nc_inq (NCid_Type *nc)
{
   SLang_Array_Type *all_at_ncdims, *at_ncvars;
   int status, ndims, nvars, natts, nunlim;

   if (-1 == check_ncid_type (nc))
     return;

   status = nc_inq (nc->ncid, &ndims, &nvars, &natts, &nunlim);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_inq", status);
	return;
     }

   if (NULL == (all_at_ncdims = get_at_ncdims2 (nc, 1)))
     return;

   if (NULL == (at_ncvars = get_at_ncvars (nc->ncid, all_at_ncdims)))
     {
	SLang_free_array (all_at_ncdims);
	return;
     }
   (void) SLang_push_array (all_at_ncdims, 1);
   (void) SLang_push_array (at_ncvars, 1);
}

static char *get_varname (int ncid, int varid)
{
   char name[NC_MAX_NAME+1];
   int status;

   status = nc_inq_varname (ncid, varid, name);
   if (status != NC_NOERR)
     {
	throw_nc_error ("_nc_inq_varname", status);
	return NULL;
     }
   name[NC_MAX_NAME] = 0;
   return SLang_create_slstring (name);
}

/* usage: (name, type, dimids, attids) = nc_inq_var (nc, ncvar) */
static void sl_nc_inq_var (NCid_Type *nc, NCid_Var_Type *ncvar)
{
   SLang_Array_Type *all_at_ncdims, *at_ncdims, *at_atts;
   char *name = NULL;
   int status, ndims, nvars, natts, nunlim;
   nc_type xtype;

   if (-1 == check_ncid_type (nc))
     return;

   status = nc_inq (nc->ncid, &ndims, &nvars, &natts, &nunlim);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_inq", status);
	return;
     }

   if (NULL == (all_at_ncdims = get_at_ncdims2 (nc, 1)))
     return;

   at_ncdims = get_var_at_ncdims (nc->ncid, ncvar->var_id, all_at_ncdims, &xtype);

   SLang_free_array (all_at_ncdims);
   if (at_ncdims == NULL) return;

   at_atts = get_var_at_atts (nc->ncid, ncvar->var_id);
   if ((at_atts == NULL)
       || (NULL == (name = get_varname (nc->ncid, ncvar->var_id))))
     goto free_and_return;

   (void) SLang_push_string (name);
   (void) push_nc_datatype (nc->ncid, xtype);
   (void) SLang_push_array (at_ncdims, 0);
   (void) SLang_push_array (at_atts, 0);
   /* drop */
free_and_return:
   SLang_free_slstring (name);
   SLang_free_array (at_ncdims);
   SLang_free_array (at_atts);
}

/* usage: (name, len, is_unlimited) = _nc_inq_dim (nc, ncdim) */
static void sl_nc_inq_dim (NCid_Type *nc, NCid_Dim_Type *ncdim)
{
   char name[NC_MAX_NAME+1];
   size_t len;
   int status;

   if (-1 == check_ncid_type (nc))
     return;

   status = nc_inq_dim (nc->ncid, ncdim->dim_id, name, &len);
   if (status != NC_NOERR)
     {
	throw_nc_error ("_nc_inq_dim", status);
	return;
     }
   name[NC_MAX_NAME] = 0;

   (void) SLang_push_string (name);
   (void) SLang_push_long_long (len);
   (void) SLang_push_int (ncdim->dim_size == 0);
}

static void sl_nc_inq_varname (NCid_Type *nc, NCid_Var_Type *ncvar)
{
   char *name = get_varname (nc->ncid, ncvar->var_id);
   if (name == NULL) return;
   (void) SLang_push_string (name);
   SLang_free_slstring (name);
}

static void sl_nc_inq_varshape (NCid_Type *nc, NCid_Var_Type *ncvar)
{
   SLang_Array_Type *at_shape;
   size_t *shape;
   int *dimids;
   SLindex_Type i, num_dims;

   if (-1 == check_ncid_type (nc))
     return;

   if (NULL == (dimids = get_var_dimids (nc->ncid, ncvar->var_id, &num_dims, NULL)))
     return;

   if (NULL == (at_shape = SLang_create_array (_SL_SIZE_T_TYPE, 0, NULL, &num_dims, 1)))
     {
	SLfree (dimids);
	return;
     }

   shape = (size_t *) at_shape->data;
   for (i = 0; i < num_dims; i++)
     {
	int status = nc_inq_dim (nc->ncid, dimids[i], NULL, shape+i);
	if (status != NC_NOERR)
	  {
	     throw_nc_error ("_nc_inq_dim", status);
	     goto free_and_return;
	  }
     }

   SLang_push_array (at_shape, 0);
   /* drop */
free_and_return:
   SLang_free_array (at_shape);
   SLfree (dimids);
}

/* Usage: .put_att (data, nc, varid, name, datatype);
 */
static void put_att (NCid_Type *nc, int varid, const char *name, NCid_DataType_Type *dtype)
{
   SLang_Array_Type *at;
   nc_type xtype;
   int status;

   if (-1 == check_ncid_type (nc))
     return;

   if (SLang_peek_at_stack () == SLANG_STRING_TYPE)
     {
	char *s;
	if (-1 == SLang_pop_slstring (&s))
	  return;
	status = nc_put_att_text(nc->ncid, varid, name, strlen(s), s);
	if (status != NC_NOERR)
	  throw_nc_error ("nc_put_att_text", status);
	SLang_free_slstring (s);
	return;
     }

   /* Otherwise an array */
   if (dtype->is_sltype == 0)
     {
	switch (dtype->xclass)
	  {
	   case NC_COMPOUND:
	     if (-1 == SLang_pop_array_of_type (&at, SLANG_STRUCT_TYPE))
	       return;
	     (void) put_compound (nc->ncid, varid, dtype->xtype, NULL, NULL, NULL, at, name);
	     SLang_free_array (at);
	     break;

	   case NC_VLEN:
	   case NC_OPAQUE:
	   case NC_ENUM:
	   default:
	     SLang_verror (SL_NotImplemented_Error, "netCDF OPAQUE, VLEN, and ENUM not implemented");
	  }
	return;
     }

   if (-1 == SLang_pop_array_of_type (&at, dtype->sltype))
     return;
   xtype = dtype->xtype;

   switch (xtype)
     {
      case NC_STRING:
	  {
	     /* The array consists of slstrings.  Make sure that there are no
	      * NULL elements
	      */
	     char **sp = (char **) at->data, **spmax = sp + at->num_elements;
	     while (sp < spmax)
	       {
		  if (*sp == NULL)
		    {
		       SLang_verror (SL_InvalidParm_Error, "_nc_put_att: NULL values in the string array are not allowed");
		       SLang_free_array (at);
		       return;
		    }
		  sp++;
	       }
	  }
	/* fall through */
      case NC_BYTE:
      case NC_UBYTE:
      case NC_SHORT:
      case NC_USHORT:
      case NC_INT:
      case NC_UINT:
      case NC_INT64:
      case NC_UINT64:
      case NC_FLOAT:
      case NC_DOUBLE:
	status = nc_put_att (nc->ncid, varid, name, xtype, at->num_elements, at->data);
	break;

      default:
	SLang_verror (SL_NotImplemented_Error, "nc_put_att: %s type is not supported",
		      SLclass_get_datatype_name (at->data_type));
	status = NC_NOERR;
     }
   if (status != NC_NOERR)
     throw_nc_error ("nc_put_att", status);

   SLang_free_array (at);
}

/* Usage: _nc_put_att (value, ncid, varid, name) */
static void sl_nc_put_att (NCid_Type *nc, NCid_Var_Type *ncvar, const char *name, NCid_DataType_Type *dtype)
{
   put_att (nc, ncvar->var_id, name, dtype);
}

static void sl_nc_put_global_att (NCid_Type *nc, const char *name, NCid_DataType_Type *dtype)
{
   put_att (nc, NC_GLOBAL, name, dtype);
}

/* This function returns type information about the variable and its length.
 * If the type is not a user-defined type (VLEN, COMPOUND, etc), it also returns
 * the equivalent slang base-type, otherwise it will return SLANG_VOID_TYPE.
 */
static int inq_att (int ncid, int varid, const char *name, SLtype *sltypep, nc_type *xtypep, size_t *lenp)
{
   nc_type xtype;
   SLtype sltype;
   int status;

   status = nc_inq_att (ncid, varid, name, &xtype, lenp);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_inq_att", status);
	return -1;
     }

   *xtypep = xtype;

   if (xtype == NC_CHAR)
     {
	*sltypep = SLANG_BSTRING_TYPE;
	return 0;
     }

   if (xtype > NC_MAX_ATOMIC_TYPE)
     {
	*sltypep = SLANG_VOID_TYPE;
	return 0;
     }

   if (-1 == map_base_xtype_to_sltype (xtype, &sltype))
     return -1;

   switch (sltype)
     {
      case SLANG_CHAR_TYPE:
      case SLANG_UCHAR_TYPE:
      case SLANG_SHORT_TYPE:
      case SLANG_USHORT_TYPE:
      case SLANG_INT_TYPE:
      case SLANG_UINT_TYPE:
      case SLANG_LONG_TYPE:
      case SLANG_ULONG_TYPE:
      case SLANG_LLONG_TYPE:
      case SLANG_ULLONG_TYPE:
      case SLANG_FLOAT_TYPE:
      case SLANG_DOUBLE_TYPE:
      case SLANG_STRING_TYPE:
	break;

      default:
	SLang_verror (SL_NotImplemented_Error, "nc_put_att: %s type is not supported",
		      SLclass_get_datatype_name (sltype));
	return -1;
     }
   *sltypep = sltype;

   return 0;
}

static void get_att (NCid_Type *nc, int varid, const char *name)
{
   SLang_Array_Type *at;
   size_t len;
   SLindex_Type num;
   int status;
   nc_type xtype;
   SLtype sltype;

   if (-1 == check_ncid_type (nc))
     return;

   if (-1 == inq_att (nc->ncid, varid, name, &sltype, &xtype, &len))
     return;

   num = (SLindex_Type) len;

   if (sltype == SLANG_VOID_TYPE)
     {
	int xclass;

	if (-1 == get_nc_xclass (nc->ncid, xtype, &xclass))
	  return;

	switch (xclass)
	  {
	   case NC_COMPOUND:
	     sltype = SLANG_STRUCT_TYPE;
	     if (NULL == (at = SLang_create_array (sltype, 0, NULL, &num, 1)))
	       return;
	     if (-1 == get_compound (nc->ncid, varid, xtype, NULL, NULL, NULL, at, name))
	       {
		  SLang_free_array (at);
		  return;
	       }
	     if (num == 1)
	       (void) SLang_push_value (at->data_type, at->data);
	     else
	       (void) SLang_push_array (at, 0);
	     SLang_free_array (at);
	     break;

	   case NC_ENUM:
	     SLang_verror (SL_NotImplemented_Error, "ENUM types are not yet implemented");
	     break;
	   case NC_OPAQUE:
	     SLang_verror (SL_NotImplemented_Error, "OPAQUE types are not yet implemented");
	     break;
	   case NC_VLEN:
	     SLang_verror (SL_NotImplemented_Error, "VLEN types are not yet implemented");
	     break;
	   default:
	     SLang_verror (SL_NotImplemented_Error, "Unknown class %d", xclass);
	     break;
	  }
	return;
     }

   if (sltype == SLANG_BSTRING_TYPE)
     {
	/* According to the documentation, the string may or may not include
	 * the terminating \0 character.  Assume that it does not.
	 */
	SLang_BString_Type *bstr;
	char *s = (char *)SLmalloc (len+1);
	if (s == NULL) return;
	status = nc_get_att_text (nc->ncid, varid, name, s);
	if (status != NC_NOERR)
	  {
	     throw_nc_error ("nc_get_att_text", status);
	     SLfree (s);
	     return;
	  }
	s[len] = 0;

	if (NULL == (bstr = SLbstring_create_malloced ((unsigned char *)s, len, 1)))
	  return;		       /* frees s */

	(void) SLang_push_bstring (bstr);
	SLbstring_free (bstr);
	return;
     }

   if (NULL == (at = SLang_create_array (sltype, 0, NULL, &num, 1)))
     return;

   status = nc_get_att (nc->ncid, varid, name, at->data);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_put_att", status);
	SLang_free_array (at);
	return;
     }

   if (sltype == SLANG_STRING_TYPE)
     {
	/* We need to convert the strings into slstrings */
	if (-1 == convert_str_array_to_slstr_array (at, 1))
	  {
	     SLang_free_array (at);
	     return;
	  }
     }

   (void) SLang_push_array (at, 1);
}

/* Usage: _nc_get_att (ncid, varid, name) */
static void sl_nc_get_att (NCid_Type *nc, NCid_Var_Type *ncvar, const char *name)
{
   get_att (nc, ncvar->var_id, name);
}

static void sl_nc_get_global_att (NCid_Type *nc, const char *name)
{
   get_att (nc, NC_GLOBAL, name);
}

static void sl_nc_inq_global_atts (NCid_Type *nc)
{
   SLang_Array_Type *at;

   at = get_var_at_atts (nc->ncid, NC_GLOBAL);
   if (at != NULL)
     SLang_push_array (at, 1);
}

static void sl_nc_def_grp (NCid_Type *nc, const char *name)
{
   int grpid;
   int status = nc_def_grp (nc->ncid, name, &grpid);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_def_grp", status);
	return;
     }
   (void) push_ncid (grpid, 1);
}

static void sl_nc_inq_grp_ncid (NCid_Type *nc, const char *name)
{
   int grpid;
   int status = nc_inq_grp_ncid (nc->ncid, name, &grpid);

   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_inq_grp_ncid", status);
	return;
     }
   (void) push_ncid (grpid, 1);
}

static void sl_nc_inq_grps (NCid_Type *nc)
{
   SLang_Array_Type *at;
   int *grpids;
   char **grp_names;
   SLindex_Type n;
   int status, i, numgrps;

   status = nc_inq_grps (nc->ncid, &numgrps, NULL);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_inq_grps", status);
	return;
     }
   if (NULL == (grpids = (int *)SLmalloc((numgrps+1) * sizeof(int))))
     return;

   status = nc_inq_grps (nc->ncid, &numgrps, grpids);
   if (status != NC_NOERR)
     {
	SLfree (grpids);
	throw_nc_error ("nc_inq_grps", status);
	return;
     }
   n = numgrps;
   if (NULL == (at = SLang_create_array (SLANG_STRING_TYPE, 0, NULL, &n, 1)))
     {
	SLfree (grpids);
	return;
     }
   grp_names = (char **)at->data;

   for (i = 0; i < n; i++)
     {
	char name[NC_MAX_NAME+1];

	if (NC_NOERR != (status = nc_inq_grpname (grpids[i], name)))
	  {
	     throw_nc_error ("nc_inq_grpname", status);
	     goto free_and_return;
	  }
	if (NULL == (grp_names[i] = SLang_create_slstring (name)))
	  goto free_and_return;
     }

   (void) SLang_push_array (at, 0);
   /* drop */

free_and_return:
   SLfree (grpids);
   SLang_free_array (at);
}

static void sl_nc_inq_dimid (NCid_Type *nc, const char *name)
{
   NCid_Dim_Type *ncdim;
   int *unlim_dims;
   size_t len;
   int status, dimid, i, num_unlim, is_unlim;

   status = nc_inq_dimid (nc->ncid, name, &dimid);
   if (status != NC_NOERR)
     {
	(void) SLang_push_null ();
	return;
     }

   /* Why is there no API function to determine if a dim id is limited???
    * I was unable to find one.
    */
   if (-1 == get_unlimited_dim_ids (nc->ncid, &unlim_dims, &num_unlim))
     return;

   /* unlim_dims could be NULL with num_unlim set to 0.  The call to SLfree is safe */
   is_unlim = 0;
   for (i = 0; i < num_unlim; i++)
     {
	if (unlim_dims[i] == dimid)
	  {
	     is_unlim = 1;
	     break;
	  }
     }
   SLfree (unlim_dims);		       /* NULL ok */

   len = 0;
   if ((is_unlim == 0)
       && (NC_NOERR != (status = nc_inq_dimlen (nc->ncid, dimid, &len))))
     {
	throw_nc_error ("nc_inq_dimlen", status);
	return;
     }

   if (NULL == (ncdim = alloc_ncid_dim_type (nc->ncid, dimid, len)))
     return;

   (void) push_ncid_dim_type (ncdim);
   free_ncid_dim_type (ncdim);
}


static void sl_nc_inq_dimids (NCid_Type *nc, int *include_parentsp)
{
   SLang_Array_Type *at;

   at = get_at_ncdims2 (nc, *include_parentsp);
   if (at != NULL)
     (void) SLang_push_array (at, 1);
}

/* Upon success, if *ntypesp is 0, then **typeidp will be NULL */
static int get_typeids (int ncid, int **typeidsp, int *ntypesp)
{
   int *typeids;
   int ntypes;
   int status;

   if (NC_NOERR != (status = nc_inq_typeids (ncid, &ntypes, NULL)))
     {
	throw_nc_error ("nc_inq_typeids", status);
	return -1;
     }
   if (ntypes == 0)
     {
	*ntypesp = 0;
	*typeidsp = NULL;
	return 0;
     }
   if (NULL == (typeids = (int *)SLmalloc ((ntypes+1)*sizeof(int))))
     return -1;

   if (NC_NOERR != (status = nc_inq_typeids (ncid, &ntypes, typeids)))
     {
	throw_nc_error ("nc_inq_typeids", status);
	SLfree (typeids);
	return -1;
     }

   *ntypesp = ntypes;
   *typeidsp = typeids;
   return 0;
}


/* Compound Types */

static int compute_align_and_size (int ncid, nc_type xtype, size_t *alignp, size_t *sizep)
{
   char name[NC_MAX_NAME+1];
   size_t xsize, xnfields;
   nc_type xbase;
   int status, xclass;

#define GET_OFFSET_AND_SIZE(_type) \
   { \
      struct s { char a; _type b; }; \
      *alignp = offsetof(struct s, b); \
      *sizep = sizeof(_type); \
   } (void)0

   switch (xtype)
     {
      case NC_BYTE: GET_OFFSET_AND_SIZE(char); return 0;
      case NC_UBYTE: GET_OFFSET_AND_SIZE(unsigned char); return 0;
      case NC_SHORT: GET_OFFSET_AND_SIZE(short); return 0;
      case NC_USHORT: GET_OFFSET_AND_SIZE(unsigned short); return 0;
      case NC_INT: GET_OFFSET_AND_SIZE(int); return 0;
      case NC_UINT: GET_OFFSET_AND_SIZE(unsigned int); return 0;
      case NC_INT64: GET_OFFSET_AND_SIZE(int64_t); return 0;
      case NC_UINT64: GET_OFFSET_AND_SIZE(uint64_t); return 0;
      case NC_FLOAT: GET_OFFSET_AND_SIZE(float); return 0;
      case NC_DOUBLE: GET_OFFSET_AND_SIZE(double); return 0;
      case NC_STRING: GET_OFFSET_AND_SIZE(char *); return 0;
      case NC_CHAR: GET_OFFSET_AND_SIZE(char); return 0;
      default:
	break;
     }

   if (xtype <= NC_MAX_ATOMIC_TYPE)
     {
	SLang_verror (SL_NotImplemented_Error, "NC Type %d not implemented for netCDF compound", (int) xtype);
	return -1;
     }

   status = nc_inq_user_type (ncid, xtype, name, &xsize, &xbase, &xnfields, &xclass);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_inq_user_type", status);
	return -1;
     }
   switch (xclass)
     {
      case NC_COMPOUND:
	return compute_compound_align_and_size (ncid, xtype, alignp, sizep, NULL, NULL, NULL, NULL);

      case NC_ENUM:
	return compute_align_and_size (ncid, xbase, alignp, sizep);

      case NC_VLEN:
	GET_OFFSET_AND_SIZE(nc_vlen_t); return 0;

      case NC_OPAQUE:
	/* I am assuming that an opaque is stored as a bunch of bytes */
	GET_OFFSET_AND_SIZE(char);
	*sizep = xsize;
	return 0;
     }

   SLang_verror (SL_NotImplemented_Error, "Unknown/Unsupported netCDF class %d", xclass);
   return -1;
}

static int compute_compound_size_and_offsets (int ncid, int num_xtypes, nc_type *xtypes, size_t *num_elems,
					      size_t *offsets, size_t *alignp, size_t *sizep)
{
   size_t max_align, offset;
   int i;

   max_align = 0;
   offset = 0;
   for (i = 0; i < num_xtypes; i++)
     {
	size_t align, size;

	if (-1 == compute_align_and_size (ncid, xtypes[i], &align, &size))
	  return -1;

	if (align > max_align) max_align = align;

	if (offset % align)
	  offset += align - (offset % align);

	offsets[i] = offset;
	offset += num_elems[i] * size;
     }

   /* Now compute the pad */
   if (offset % max_align)
     offset += max_align - (offset % max_align);

   *sizep = offset;
   *alignp = max_align;

   return 0;
}

static int compute_compound_align_and_size (int ncid, nc_type xtype, size_t *alignp, size_t *sizep,
					    size_t *xnfieldsp, size_t **field_offsetsp, nc_type **field_xtypesp,
					    size_t **field_num_elemsp)
{
   size_t xnfields, size;
   size_t *field_offsets = NULL;
   size_t *field_num_elems = NULL;
   nc_type *field_xtypes = NULL;
   unsigned int i;
   int status, return_status = -1;

   if (field_offsetsp != NULL) *field_offsetsp = NULL;
   if (field_xtypesp != NULL) *field_xtypesp = NULL;
   if (field_num_elemsp != NULL) *field_num_elemsp = NULL;

   status = nc_inq_compound (ncid, xtype, NULL, &size, &xnfields);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_inq_compound", status);
	return -1;
     }

   if ((NULL == (field_offsets = (size_t *)SLmalloc(sizeof(size_t)*(xnfields+1))))
       || (NULL == (field_num_elems = (size_t *)SLmalloc(sizeof(size_t)*(xnfields+1))))
       || (NULL == (field_xtypes = (nc_type *)SLmalloc(sizeof(nc_type)*(xnfields+1)))))
     goto free_and_return;

   for (i = 0; i < xnfields; i++)
     {
	if (-1 == get_compound_field_info (ncid, xtype, i, NULL, NULL, field_xtypes+i, NULL, field_num_elems+i, NULL))
	  goto free_and_return;
     }

   return_status = compute_compound_size_and_offsets (ncid, xnfields, field_xtypes, field_num_elems,
						      field_offsets, alignp, sizep);

   if (return_status == 0)
     {
	if (size == *sizep)
	  {
	     if (xnfieldsp != NULL) *xnfieldsp = xnfields;
	     if (field_offsetsp != NULL)
	       {
		  *field_offsetsp = field_offsets;
		  field_offsets = NULL;
	       }
	     if (field_xtypesp != NULL)
	       {
		  *field_xtypesp = field_xtypes;
		  field_xtypes = NULL;
	       }
	     if (field_num_elemsp != NULL)
	       {
		  *field_num_elemsp = field_num_elems;
		  field_num_elems = NULL;
	       }
	  }
	else
	  {
	     SLang_verror (SL_Application_Error, "Compound size expected to be %lu but computed %lu bytes",
			   size, *sizep);
	     return_status = -1;
	  }
     }

   /* drop */

free_and_return:

   SLfree (field_xtypes);	       /* NULL ok */
   SLfree (field_num_elems);
   SLfree (field_offsets);
   return return_status;
}

/* Usage: _nc_def_compound (field-names, field-types, array-of-array-dims, ncid, name) */
static void sl_nc_def_compound (NCid_Type *nc, const char *name)
{
   SLang_Array_Type *at_dims = NULL, *at_types = NULL, *at_field_names = NULL;
   nc_type *xtypes = NULL;
   size_t *offsets = NULL, *num_elems = NULL;
   char **field_names;
   size_t total_size, align;
   SLuindex_Type i, num_fields;
   nc_type comp_xtype;
   int ncid, status;

   ncid = nc->ncid;

   if ((-1 == SLang_pop_array_of_type (&at_dims, SLANG_ARRAY_TYPE))
       || (-1 == SLang_pop_array_of_type (&at_types, NCid_DataType_Type_Id))
       || (-1 == SLang_pop_array_of_type (&at_field_names, SLANG_STRING_TYPE)))
     goto free_and_return;

   num_fields = at_dims->num_elements;
   if ((num_fields != at_types->num_elements)
       || (num_fields != at_field_names->num_elements)
       || (num_fields == 0))
     {
	SLang_verror (SL_InvalidParm_Error, "_nc_def_compound: The number of fields must be > 0 and the same for all array args");
	goto free_and_return;
     }

   if ((NULL == (offsets = (size_t *)SLmalloc (num_fields*sizeof(size_t))))
       || (NULL == (num_elems = (size_t *)SLmalloc (num_fields*sizeof(size_t))))
       || (NULL == (xtypes = (nc_type *)SLmalloc (num_fields*sizeof(nc_type)))))
     goto free_and_return;

   field_names = (char **)at_field_names->data;
   for (i = 0; i < num_fields; i++)
     {
	SLang_Array_Type *at;
	NCid_DataType_Type *dtype;

	if (field_names[i] == NULL)
	  {
	     SLang_verror (SL_InvalidParm_Error, "_nc_def_compound: A compound field name cannot be NULL");
	     goto free_and_return;
	  }

	if (NULL == (at = ((SLang_Array_Type **)at_dims->data)[i]))
	  num_elems[i] = 1;
	else
	  {
	     SLang_Array_Type *bt;
	     size_t num;
	     int *dims, *dims_max;

	     if (at->num_elements == 0)
	       {
		  SLang_verror (SL_InvalidParm_Error, "_nc_def_compound: The dimension of field %s cannot be 0", field_names[i]);
		  goto free_and_return;
	       }
	     bt = NULL;
	     dims = (int *)at->data;
	     if (at->data_type != SLANG_INT_TYPE)
	       {
		  /* Make sure that we can typecast this to an int type before defining the compound */
		  if ((-1 == SLang_push_array (at, 0))
		      || (-1 == SLang_pop_array_of_type (&bt, SLANG_INT_TYPE)))
		    goto free_and_return;
		  dims = (int *)bt->data;
	       }
	     num = 1;
	     dims_max = dims + at->num_elements;
	     while (dims < dims_max)
	       {
		  if (*dims <= 0)
		    {
		       SLang_verror (SL_InvalidParm_Error, "_nc_def_compound: The dimension of field %s must be greater than 0", field_names[i]);
		       if (bt != NULL) SLang_free_array (bt);
		       goto free_and_return;
		    }
		  num = num * (size_t) *dims;
		  dims++;
	       }
	     num_elems[i] = num;
	     if (bt != NULL) SLang_free_array (bt);
	  }
	dtype = ((NCid_DataType_Type **)at_types->data)[i];
	if (dtype == NULL)
	  {
	     SLang_verror (SL_InvalidParm_Error, "_nc_def_compound: No data type for field %s specified", field_names[i]);
	     goto free_and_return;
	  }
#if 0
	if (dtype->is_sltype)
	  {
	     if (-1 == map_base_sltype_to_xtype (dtype->sltype, xtypes + i))
	       goto free_and_return;
	  }
	else
#endif
	  xtypes[i] = dtype->xtype;
     }

   if (-1 == compute_compound_size_and_offsets (ncid, num_fields, xtypes, num_elems,
						offsets, &align, &total_size))
     goto free_and_return;

   status = nc_def_compound (ncid, total_size, name, &comp_xtype);
   if (status != NC_NOERR)
     {
	throw_nc_error ("nc_def_compound", status);
	goto free_and_return;
     }

   for (i = 0; i < num_fields; i++)
     {
	SLang_Array_Type *at;
	if (num_elems[i] == 1)
	  {
	     status = nc_insert_compound (ncid, comp_xtype, field_names[i], offsets[i], xtypes[i]);
	     if (status != NC_NOERR)
	       {
		  throw_nc_error ("nc_insert_compound", status);
		  goto free_and_return;
	       }
	     continue;
	  }

	at = ((SLang_Array_Type **)at_dims->data)[i];   /* not NULL per above loop */
	if (at->data_type == SLANG_INT_TYPE)
	  status = nc_insert_array_compound (ncid, comp_xtype, field_names[i], offsets[i], xtypes[i], at->num_dims, (int *)at->data);
	else
	  {
	     if ((-1 == SLang_push_array (at, 0))
		 || (-1 == SLang_pop_array_of_type (&at, SLANG_INT_TYPE)))
	       goto free_and_return;

	     status = nc_insert_array_compound (ncid, comp_xtype, field_names[i], offsets[i], xtypes[i], at->num_dims, (int *)at->data);
	     SLang_free_array (at);
	  }
	if (status != NC_NOERR)
	  {
	     throw_nc_error ("nc_insert_array_compound", status);
	     goto free_and_return;
	  }
     }

   (void) push_nc_datatype (ncid, comp_xtype);

   /* drop */

free_and_return:

   SLfree (xtypes);
   SLfree (num_elems);
   SLfree (offsets);
   SLang_free_array (at_field_names);
   SLang_free_array (at_types);
   SLang_free_array (at_dims);
}


#define NCID_DUMMY ((SLtype)-1)
#define NCID_VAR_DUMMY ((SLtype)-2)
#define NCID_DIM_DUMMY ((SLtype)-3)
#define NCID_DATATYPE_DUMMY ((SLtype)-4)
#undef V
#undef S
#undef U
#define V SLANG_VOID_TYPE
#define S SLANG_STRING_TYPE
#define I SLANG_INT_TYPE
#define IA SLANG_ARRAY_INDEX_TYPE

static SLang_Intrin_Fun_Type Module_Intrinsics [] =
{
   MAKE_INTRINSIC_2("_nc_create", sl_nc_create, V, S, I),
   MAKE_INTRINSIC_2("_nc_open", sl_nc_open, V, S, I),
   MAKE_INTRINSIC_1("_nc_refdef", sl_nc_redef, V, NCID_DUMMY),
   MAKE_INTRINSIC_1("_nc_enddef", sl_nc_enddef, V, NCID_DUMMY),
   MAKE_INTRINSIC_1("_nc_close", sl_nc_close, V, NCID_DUMMY),
   MAKE_INTRINSIC_3("_nc_def_dim", sl_nc_def_dim, V, NCID_DUMMY, S, IA),
   MAKE_INTRINSIC_0("_nc_def_var", sl_nc_def_var, V),
   MAKE_INTRINSIC_2("_nc_def_compound", sl_nc_def_compound, V, NCID_DUMMY, S),
   /* MAKE_INTRINSIC_2("_nc_put_var", sl_nc_put_var, V, NCID_DUMMY, NCID_VAR_DUMMY), */
   MAKE_INTRINSIC_2("_nc_put_vars", sl_nc_put_vars, V, NCID_DUMMY, NCID_VAR_DUMMY),
   MAKE_INTRINSIC_2("_nc_get_vars", sl_nc_get_vars, V, NCID_DUMMY, NCID_VAR_DUMMY),

   MAKE_INTRINSIC_2("_nc_inq_dim", sl_nc_inq_dim, V, NCID_DUMMY, NCID_DIM_DUMMY),
   MAKE_INTRINSIC_2("_nc_inq_dimid", sl_nc_inq_dimid, V, NCID_DUMMY, S),
   MAKE_INTRINSIC_2("_nc_inq_dimids", sl_nc_inq_dimids, V, NCID_DUMMY, I),
   MAKE_INTRINSIC_1("_nc_inq", sl_nc_inq, V, NCID_DUMMY),
   MAKE_INTRINSIC_2("_nc_inq_var", sl_nc_inq_var, V, NCID_DUMMY, NCID_VAR_DUMMY),
   MAKE_INTRINSIC_2("_nc_inq_varname", sl_nc_inq_varname, V, NCID_DUMMY, NCID_VAR_DUMMY),
   MAKE_INTRINSIC_2("_nc_inq_varshape", sl_nc_inq_varshape, V, NCID_DUMMY, NCID_VAR_DUMMY),
   MAKE_INTRINSIC_1("_nc_inq_global_atts", sl_nc_inq_global_atts, V, NCID_DUMMY),

   MAKE_INTRINSIC_4("_nc_put_att", sl_nc_put_att, V, NCID_DUMMY, NCID_VAR_DUMMY, S, NCID_DATATYPE_DUMMY),
   MAKE_INTRINSIC_3("_nc_put_global_att", sl_nc_put_global_att, V, NCID_DUMMY, S, NCID_DATATYPE_DUMMY),
   MAKE_INTRINSIC_3("_nc_get_att", sl_nc_get_att, V, NCID_DUMMY, NCID_VAR_DUMMY, S),
   MAKE_INTRINSIC_2("_nc_get_global_att", sl_nc_get_global_att, V, NCID_DUMMY, S),
   /* MAKE_INTRINSIC_2("_nc_inq_varatts", sl_nc_inq_varatts, V, NCID_DUMMY, S), */

   MAKE_INTRINSIC_2("_nc_def_grp", sl_nc_def_grp, V, NCID_DUMMY, S),
   MAKE_INTRINSIC_2("_nc_inq_grp_ncid", sl_nc_inq_grp_ncid, V, NCID_DUMMY, S),
   MAKE_INTRINSIC_1("_nc_inq_grps", sl_nc_inq_grps, V, NCID_DUMMY),
   SLANG_END_INTRIN_FUN_TABLE
};

static SLang_Intrin_Var_Type Module_Variables [] =
{
   MAKE_VARIABLE("_nc_errno", &NC_Errno, SLANG_INT_TYPE, 0),
   MAKE_VARIABLE("_netcdf_module_version_string", &Module_Version_String, SLANG_STRING_TYPE, 1),
   SLANG_END_INTRIN_VAR_TABLE
};

static SLang_IConstant_Type Module_IConstants [] =
{
   MAKE_ICONSTANT("NC_NOWRITE",NC_NOWRITE),
   MAKE_ICONSTANT("NC_WRITE",NC_WRITE),
   MAKE_ICONSTANT("NC_CLOBBER",NC_CLOBBER),
   MAKE_ICONSTANT("NC_NOCLOBBER",NC_NOCLOBBER),
   MAKE_ICONSTANT("NC_DISKLESS",NC_DISKLESS),
   MAKE_ICONSTANT("NC_MMAP",NC_MMAP),
   MAKE_ICONSTANT("NC_CLASSIC_MODEL",NC_CLASSIC_MODEL),
   MAKE_ICONSTANT("NC_LOCK",NC_LOCK),
   MAKE_ICONSTANT("NC_SHARE",NC_SHARE),
   MAKE_ICONSTANT("NC_NETCDF4",NC_NETCDF4),
   MAKE_ICONSTANT("NC_64BIT_DATA", NC_64BIT_DATA),
   MAKE_ICONSTANT("NC_64BIT_OFFSET", NC_64BIT_OFFSET),
#ifdef NC_PERSIST
   MAKE_ICONSTANT("NC_PERSIST",NC_PERSIST),
#endif
#ifdef NC_INMEMORY
   MAKE_ICONSTANT("NC_INMEMORY",NC_INMEMORY),
#endif
   MAKE_ICONSTANT("_netcdf_module_version", MODULE_VERSION_NUMBER),
   SLANG_END_ICONST_TABLE
};

static SLang_DConstant_Type Module_DConstants [] =
{
   SLANG_END_DCONST_TABLE
};


static void cl_ncid_dim_type_destroy (SLtype type, VOID_STAR ptr)
{
   (void) type;
   free_ncid_dim_type (*(NCid_Dim_Type **)ptr);
}

static int cl_ncid_dim_type_push (SLtype type, VOID_STAR ptr)
{
   (void) type;
   return push_ncid_dim_type (*(NCid_Dim_Type **)ptr);
}

static void cl_ncid_var_type_destroy (SLtype type, VOID_STAR ptr)
{
   (void) type;
   free_ncid_var_type (*(NCid_Var_Type **)ptr);
}

static int cl_ncid_var_type_push (SLtype type, VOID_STAR ptr)
{
   (void) type;
   return push_ncid_var_type (*(NCid_Var_Type **)ptr);
}

static void cl_ncid_type_destroy (SLtype type, VOID_STAR ptr)
{
   (void) type;
   free_ncid_type (*(NCid_Type **)ptr);
}

static int cl_ncid_type_push (SLtype type, VOID_STAR ptr)
{
   (void) type;
   return push_ncid_type (*(NCid_Type **)ptr);
}

static void cl_ncid_datatype_type_destroy (SLtype type, VOID_STAR ptr)
{
   (void) type;
   free_ncid_datatype_type (*(NCid_DataType_Type **)ptr);
}

static int cl_ncid_datatype_type_push (SLtype type, VOID_STAR ptr)
{
   (void) type;
   return push_ncid_datatype_type (*(NCid_DataType_Type **)ptr);
}

static int cl_ncid_datatype_pop (SLtype type, void *ptr)
{
   NCid_DataType_Type *dtype;
   SLtype sltype;

   if (SLang_peek_at_stack () == SLANG_DATATYPE_TYPE)
     {
	if (-1 == SLang_pop_datatype (&sltype))
	  return -1;

	if (NULL == (dtype = alloc_ncid_datatype_type (-1, -1, sltype, 1)))
	  return -1;
     }
   else if (-1 == SLclass_pop_ptr_obj (type, (void **)&dtype))
     return -1;

   *(void **)ptr = (void *) dtype;
   return 0;
}

static char *cl_ncid_datatype_string (SLtype type, void *ptr)
{
   NCid_DataType_Type *dtype;
   size_t len;
   char *str;

   (void) type;
   dtype = *(NCid_DataType_Type **)ptr;
   if (dtype->is_sltype)
     return SLmake_string (SLclass_get_datatype_name (dtype->sltype));

   len = strlen (dtype->xname);
   switch (dtype->xclass)
     {
      case NC_VLEN:
	len += 5 + 1;
	if (NULL == (str = (char *)SLmalloc (len))) return NULL;
	(void) SLsnprintf (str, len, "VLEN:%s", dtype->xname);
	return str;

      case NC_OPAQUE:
	len += 7 + 1;
	if (NULL == (str = (char *)SLmalloc (len))) return NULL;
	(void) SLsnprintf (str, len, "OPAQUE:%s", dtype->xname);
	return str;

      case NC_ENUM:
	len += 5 + 1;
	if (NULL == (str = (char *)SLmalloc (len))) return NULL;
	(void) SLsnprintf (str, len, "ENUM:%s", dtype->xname);
	return str;

      case NC_COMPOUND:
	len += 9 + 1;
	if (NULL == (str = (char *)SLmalloc (len))) return NULL;
	(void) SLsnprintf (str, len, "COMPOUND:%s", dtype->xname);
	return str;

      default:
	break;
     }

   len += 8 + 1;
   if (NULL == (str = (char *)SLmalloc (len))) return NULL;
   (void) SLsnprintf (str, len, "UNKNOWN:%s", dtype->xname);
   return str;
}

static int cl_sltype_to_ncid_datatype (SLtype a_type, VOID_STAR ap, SLuindex_Type na,
				       SLtype b_type, VOID_STAR bp)
{
   SLtype *sltypes;
   NCid_DataType_Type **dtypes;
   SLuindex_Type i;

   (void) a_type; (void) b_type;
   sltypes = (SLtype *)ap;
   dtypes = (NCid_DataType_Type **)bp;

   for (i = 0; i < na; i++)
     {
	if (NULL != (dtypes[i] = alloc_ncid_datatype_type (-1, -1, sltypes[i], 1)))
	  continue;

	while (i != 0)
	  {
	     i--;
	     free_ncid_datatype_type (dtypes[i]);
	     dtypes[i] = NULL;
	  }
	return -1;
     }

   return 1;
}

static int register_types (void)
{
   SLang_Class_Type *cl;

   /* (void) H5dont_atexit (); */

   if (NCid_Type_Id == 0)
     {
	if (NULL == (cl = SLclass_allocate_class ("NetCDF_Type")))
	  return -1;
	(void) SLclass_set_destroy_function (cl, cl_ncid_type_destroy);
	(void) SLclass_set_push_function (cl, cl_ncid_type_push);
	if (-1 == SLclass_register_class (cl, SLANG_VOID_TYPE, sizeof (NCid_Type), SLANG_CLASS_TYPE_PTR))
	  return -1;
	NCid_Type_Id = SLclass_get_class_id (cl);
	if (-1 == SLclass_patch_intrin_fun_table1 (Module_Intrinsics, NCID_DUMMY, NCid_Type_Id))
	  return -1;
     }

   if (NCid_Var_Type_Id == 0)
     {
	if (NULL == (cl = SLclass_allocate_class ("NetCDF_Var_Type")))
	  return -1;
	(void) SLclass_set_destroy_function (cl, cl_ncid_var_type_destroy);
	(void) SLclass_set_push_function (cl, cl_ncid_var_type_push);
	if (-1 == SLclass_register_class (cl, SLANG_VOID_TYPE, sizeof (NCid_Var_Type), SLANG_CLASS_TYPE_PTR))
	  return -1;
	NCid_Var_Type_Id = SLclass_get_class_id (cl);
	if (-1 == SLclass_patch_intrin_fun_table1 (Module_Intrinsics, NCID_VAR_DUMMY, NCid_Var_Type_Id))
	  return -1;
     }

   if (NCid_Dim_Type_Id == 0)
     {
	if (NULL == (cl = SLclass_allocate_class ("NetCDF_Dim_Type")))
	  return -1;
	(void) SLclass_set_destroy_function (cl, cl_ncid_dim_type_destroy);
	(void) SLclass_set_push_function (cl, cl_ncid_dim_type_push);
	if (-1 == SLclass_register_class (cl, SLANG_VOID_TYPE, sizeof (NCid_Dim_Type), SLANG_CLASS_TYPE_PTR))
	  return -1;
	NCid_Dim_Type_Id = SLclass_get_class_id (cl);
	if (-1 == SLclass_patch_intrin_fun_table1 (Module_Intrinsics, NCID_DIM_DUMMY, NCid_Dim_Type_Id))
	  return -1;
     }

   if (NCid_DataType_Type_Id == 0)
     {
	if (NULL == (cl = SLclass_allocate_class ("NetCDF_DataType_Type")))
	  return -1;
	(void) SLclass_set_destroy_function (cl, cl_ncid_datatype_type_destroy);
	(void) SLclass_set_push_function (cl, cl_ncid_datatype_type_push);
	(void) SLclass_set_pop_function (cl, cl_ncid_datatype_pop);
	(void) SLclass_set_string_function (cl, cl_ncid_datatype_string);
	if (-1 == SLclass_register_class (cl, SLANG_VOID_TYPE, sizeof (NCid_DataType_Type), SLANG_CLASS_TYPE_PTR))
	  return -1;
	NCid_DataType_Type_Id = SLclass_get_class_id (cl);
	(void) SLclass_add_typecast (SLANG_DATATYPE_TYPE, NCid_DataType_Type_Id, cl_sltype_to_ncid_datatype, 1);
	if (-1 == SLclass_patch_intrin_fun_table1 (Module_Intrinsics, NCID_DATATYPE_DUMMY, NCid_DataType_Type_Id))
	  return -1;
     }

   if (sl_NC_Error == 0)
     {
	if (-1 == (sl_NC_Error = SLerr_new_exception (SL_RunTime_Error, "NetCDFError", "NetCDF Error")))
	  return -1;
     }

   return 0;
}

int init_netcdf_module_ns (char *ns_name)
{
   SLang_NameSpace_Type *ns;

   if (-1 == register_types ())
     return -1;

   ns = SLns_create_namespace (ns_name);
   if (ns == NULL)
     return -1;

   if (
       (-1 == SLns_add_intrin_var_table (ns, Module_Variables, NULL))
       || (-1 == SLns_add_intrin_fun_table (ns, Module_Intrinsics, NULL))
       || (-1 == SLns_add_iconstant_table (ns, Module_IConstants, NULL))
       || (-1 == SLns_add_dconstant_table (ns, Module_DConstants, NULL))
       )
     return -1;

   return 0;
}

/* This function is optional */
void deinit_netcdf_module (void)
{
}
