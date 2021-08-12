/* -*- mode: C; mode: fold; -*- */
/*
Copyright (C) 2005 John E. Davis

This file is part of the S-Lang <template> Module

The S-Lang <template> Module is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the
License, or (at your option) any later version.

The S-Lang <template> Module is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this library; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307,
USA.  
*/

#include <stdio.h>
#include <slang.h>

<MODULE_INCLUDES>

#ifdef __cplusplus
extern "C" 
{
#endif
SLANG_MODULE(netcdf);
#ifdef __cplusplus
}
#endif

#include "version.h"

<MODULE_DEFINES>

<INTRINSIC_DEFINITIONS>

static SLang_Intrin_Fun_Type Module_Intrinsics [] =
{
<MODULE_INTRINSICS>
   SLANG_END_INTRIN_FUN_TABLE
};

static SLang_Intrin_Var_Type Module_Variables [] =
{
<MODULE_VARIABLES>
   MAKE_VARIABLE("_netcdf_module_version_string", &Module_Version_String, SLANG_STRING_TYPE, 1),
   SLANG_END_INTRIN_VAR_TABLE
};

static SLang_IConstant_Type Module_IConstants [] =
{
<MODULE_ICONSTANTS>
   MAKE_ICONSTANT("_netcdf_module_version", MODULE_VERSION_NUMBER),
   SLANG_END_ICONST_TABLE
};

static SLang_DConstant_Type Module_DConstants [] =
{
<MODULE_DCONSTANTS>
   SLANG_END_DCONST_TABLE
};

int init_netcdf_module_ns (char *ns_name)
{
   SLang_NameSpace_Type *ns = SLns_create_namespace (ns_name);
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
