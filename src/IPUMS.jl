module IPUMS

import Tables
import EzXML: readxml, findall, namespace, findfirst, root
import GZip
import Logging: @warn

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

struct CategoricalField <: DDIField
    name::Symbol
    startcol::Int64
    endcol::Int64
    labels::Dict{String, String}
end

# TODO labels

function parse_numeric(T, f, line)
    val = @view line[f.startcol:f.endcol]
    # empty or whitespace
    if !isnothing(match(r"^\s*$", val))
        return missing
    else
        return parse(T, val)
    end
end

parse_col(f::IntField, line, _)::Union{Int64, Missing} = parse_numeric(Int64, f, line)

# if missing, missing * number = missing
parse_col(f::DoubleField, line, _)::Union{Float64, Missing} = parse_numeric(Float64, f, line) * 10.0^(-f.decimals)

function parse_col(f::CategoricalField, line, lineno)::String
    val = @view line[f.startcol:f.endcol]
    return if haskey(f.labels, val)
        f.labels[val]
    else
        @warn "At line $lineno, found value \"$val\" in field \"$(f.name)\", which is not in value labels"
        # de-substring it
        String(val)
    end
end

Base.eltype(::IntField) = Union{Int64, Missing}
Base.eltype(::DoubleField) = Union{Float64, Missing}
Base.eltype(::CategoricalField) = String


struct IPUMSTable{T <: NamedTuple}
    io::IO
    columns::Vector{DDIField}
end

Base.close(t::IPUMSTable) = Base.close(t.io)

should_parse_labels(_, no_labels::Bool) = !no_labels
should_parse_labels(name, no_labels::AbstractVector) = name ∉ no_labels && String(name) ∉ no_labels

"""
Read an IPUMS data file. By default, categorical fields are parsed to categories.
If this is undesirable, you can set `no_labels` to `false`, or to a list of columns
that you do not want categories parsed for.
"""
function read_ipums(ddi, dat; no_labels=false)
    isfile(ddi) || error("DDI file $ddi does not exist")
    isfile(dat) || error("Data file $dat does not exist")

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
        
        categories = findall("ns:catgry", node, nsremap)

        if decimal > 0
            DoubleField(name, startcol, endcol, decimal)
        elseif should_parse_labels(name, no_labels) && !isempty(categories)
            catlabels = Dict(map(categories) do cat
                value = findfirst("ns:catValu", cat, nsremap)
                label = findfirst("ns:labl", cat, nsremap)

                value.content => label.content
            end)

            CategoricalField(name, startcol, endcol, catlabels)
        else
            IntField(name, startcol, endcol)
        end
    end

    # construct the type
    rowtype = NamedTuple{tuple(map(c -> c.name, cols)...), Tuple{map(eltype, cols)...}}

    return if isgzfile(dat)
        IPUMSTable{rowtype}(GZip.open(dat, "r"), cols)
    else
        IPUMSTable{rowtype}(open(dat, "r"), cols)
    end
end

"""
Check for the GZip magic number to see if something is a GZipped file.
"""
function isgzfile(filename)
    open(filename, "r") do file
        return read(file, UInt8) == 0x1f && read(file, UInt8) == 0x8b
    end
end

function read_ipums(ddi, dat, sink; kwargs...)
    ipums = read_ipums(ddi, dat; kwargs...)
    output = sink(ipums)
    close(ipums)
    return output
end

Tables.istable(::IPUMSTable{<:Any}) = true
Tables.rowaccess(::IPUMSTable{<:Any}) = true

function Tables.rows(t::IPUMSTable{R}) where R
    map(enumerate(eachline(t.io))) do (lineno, line)
        vals = map(c -> parse_col(c, line, lineno), t.columns)
        R(tuple(vals...))
    end
end

export read_ipums

end
