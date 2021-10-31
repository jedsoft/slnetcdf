require ("netcdf");

define store_voltage_samples1 (file, t, v)
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

define store_voltage_samples2 (file, t, v)
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

define slsh_main ()
{
   variable t = [0:100.0:1];
   variable omega = PI/10;
   variable v = exp (1i*omega*t);

   store_voltage_samples1 ("voltage1.nc", t, v);
   store_voltage_samples2 ("voltage2.nc", t, v);
}
