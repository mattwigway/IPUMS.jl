# IPUMS.jl

This is a small Julia package, currently in beta, for reading [IPUMS USA](https://usa.ipums.org) data. It exports a single function, `read_ipums`, which reads data from an IPUMS data file (and corresponding DDI XML codebook).  This returns an `IPUMSTable`, which is a Tables.jl compatible table. It is lazy, meaning no data is read until you access the table, and the table must be closed when done:

```{julia}
using IPUMS

table = read_ipums("path/to/ddi.xml", "path/to/data.dat.gz")

# .. do things with table ..

close(table)
```

Generally, you'll want to convert the table to a DataFrame, etc, to bring IPUMS data into memory, which can be done by providing a sink argument to `read_ipums`. In this case, the table will be closed automatically.

```{julia}
using DataFrames, IPUMS

table = read_ipums("path/to/ddi.xml", "path/to/data.dat.gz", DataFrame)
```

It supports reading directly from IPUMS gzipped `.dat.gz` files, but will also read from uncompressed `.dat` files.

By default, coded variables will be imported as strings using the value labels; you can disable this for specific columns by passing a Vector of column names to the `no_labels` named argument, or globally by setting `no_labels=false`.
