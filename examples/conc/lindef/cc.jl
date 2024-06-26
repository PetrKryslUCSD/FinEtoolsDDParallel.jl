println("Current folder: $(pwd())")

using Pkg

Pkg.activate(".")
Pkg.instantiate()

using ArgParse

function parse_commandline()
    s = ArgParseSettings()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--nelperpart"
        help = "Number of elements per partition"
        arg_type = Int
        default = 200
        "--nbf1max"
        help = "Number 1D basis functions"
        arg_type = Int
        default = 5
        "--nfpartitions"
        help = "Number fine grid partitions"
        arg_type = Int
        default = 2
        "--overlap"
        help = "Overlap"
        arg_type = Int
        default = 1
        "--ref"
        help = "Refinement factor"
        arg_type = Int
        default = 2
        "--kind"
        help = "hex or tet"
        arg_type = String
        default = "hex"
        "--Ef"
        help = "Young's modulus of the fibres"
        arg_type = Float64
        default = 1.00e5
        "--nuf"
        help = "Poisson ratio of the fibres"
        arg_type = Float64
        default = 0.3
        "--Em"
        help = "Young's modulus of the matrix"
        arg_type = Float64
        default = 1.00e3
        "--num"
        help = "Poisson ratio of the matrix"
        arg_type = Float64
        default = 0.4

    end
    return parse_args(s)
end

p = parse_commandline()

include(raw"fibers_overlapped_examples.jl")
using .fibers_overlapped_examples; 

fibers_overlapped_examples.test("cc";
    kind=p["kind"], 
    Em=p["Em"], num=p["num"], Ef=p["Ef"], nuf=p["nuf"],
    nelperpart=p["nelperpart"], nbf1max=p["nbf1max"], 
    nfpartitions=p["nfpartitions"], overlap=p["overlap"], ref=p["ref"])

