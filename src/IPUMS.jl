module IPUMS

import Tables
import EzXML: readxml, findall, namespace, findfirst, root

abstract type DDIField end

struct IntField <: DDIField
    name::Symbol
    startcol::Int64
    endcol::Int64
end

struct DoubleField <: DDIField
    name::Symbol
    startcol::Int64
    endcol::Int64
    decimals::Int64
end

# TODO labels

parse_col(f::IntField, line) = parse(Int64, @view line[f.startcol:f.endcol])
parse_col(f::DoubleField, line) = parse(Float64, @view line[f.startcol:f.endcol]) * 10.0^(-f.decimals)

Base.eltype(::IntField) = Int64
Base.eltype(::DoubleField) = Float64

struct IPUMSTable{T <: NamedTuple}
    io::IO
    columns::Vector{DDIField}
end

Base.close(t::IPUMSTable) = Base.close(t.io)

function read_ipums(ddi, dat)
    # read the ddi file
    ddixml = readxml(ddi)

    # remap empty namespace: https://juliaio.github.io/EzXML.jl/stable/manual/#XPath-1
    nsremap = ["ns"=>namespace(root(ddixml))]
    cols = map(findall("//ns:var", root(ddixml), nsremap)) do node
        name = Symbol(node["ID"])
        decimal = parse(Int64, node["dcml"])
        # get the start and end
        loc = findfirst("ns:location", node, nsremap)
        # DDI and Julia are both one-based
        startcol = parse(Int64, loc["StartPos"])
        endcol = parse(Int64, loc["EndPos"])
        
        if decimal > 0
            DoubleField(name, startcol, endcol, decimal)
        else
            IntField(name, startcol, endcol)
        end
    end

    # construct the type
    rowtype = NamedTuple{tuple(map(c -> c.name, cols)...), Tuple{map(eltype, cols)...}}

    # TODO gzipped dat

    return IPUMSTable{rowtype}(open(dat, "r"), cols)
end

function read_ipums(ddi, dat, sink)
    ipums = read_ipums(ddi, dat)
    output = sink(ipums)
    close(ipums)
    return output
end

Tables.istable(::IPUMSTable{<:Any}) = true
Tables.rowaccess(::IPUMSTable{<:Any}) = true

function Tables.rows(t::IPUMSTable{R}) where R
    map(eachline(t.io)) do line
        vals = map(c -> parse_col(c, line), t.columns)
        R(tuple(vals...))
    end
end

export read_ipums

end
