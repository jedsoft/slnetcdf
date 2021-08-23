private variable dir = path_dirname (__FILE__) + "/..";
set_import_module_path (dir + ":" + get_import_module_path ());
prepend_to_slang_load_path (dir);

