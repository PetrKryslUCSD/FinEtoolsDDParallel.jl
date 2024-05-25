"""
    PartitionSchurDDModule  

Module for operations on partitions of finite element models four solves based
on the Schur complement.
"""
module PartitionSchurDDModule

__precompile__(true)

using FinEtools
using SparseArrays
using Krylov
using LinearOperators
import Base: size, eltype
import LinearAlgebra: mul!
using ..FENodeToPartitionMapModule: FENodeToPartitionMap

# function spy_matrix(A::SparseMatrixCSC, name="")
#     I, J, V = findnz(A)
#     p = PlotlyLight.Plot()
#     p(x=J, y=I, mode="markers")
#     p.layout.title = name
#     p.layout.yaxis.title = "Row"
#     p.layout.yaxis.range = [size(A, 1) + 1, 0]
#     p.layout.xaxis.title = "Column"
#     p.layout.xaxis.range = [0, size(A, 2) + 1]
#     p.layout.xaxis.side = "top"
#     p.layout.margin.pad = 10
#     display(p)
# end

struct SLinearOperator{T, IT}
    temp_f::Vector{T}
    temp_i::Vector{T}
    b_i::Vector{T}
    K_ii::SparseMatrixCSC{T, IT}
    K_fi::SparseMatrixCSC{T, IT}
    K_if::SparseMatrixCSC{T, IT}
    K_ff_factor::SparseArrays.CHOLMOD.Factor{T, IT}
    K_ii_factor::SparseArrays.CHOLMOD.Factor{T, IT}
end

function SLinearOperator(K::SparseMatrixCSC{T, IT}, u::F) where {F<:NodalField,T, IT}
    fr = dofrange(u, DOF_KIND_FREE)
    ir = dofrange(u, DOF_KIND_INTERFACE)
    dr = dofrange(u, DOF_KIND_DATA)
    K_ff = K[fr, fr]
    K_ii = K[ir, ir]
    K_ff_factor = cholesky(K_ff)
    K_ii_factor = cholesky(K_ii)
    temp_f, temp_i = zeros(T, size(K_ff, 1)), zeros(T, size(K_ii, 1))
    u_d = gathersysvec(u, DOF_KIND_DATA)
    K_fd = K[fr, dr]
    K_id = K[ir, dr]
    b_i = (F_i - K_id * u_d - K_if * (K_ff_factor \ (F_f - K_fd * u_d)))
    SLinearOperator{T, IT}(temp_f, temp_i, b_i, K_ii, K_fi, K_if, K_ff_factor, K_ii_factor)
end

function mul!(y, Sop::SLinearOperator{T}, v) where {T}
    mul!(Sop.temp_f, Sop.K_fi, v)
    mul!(Sop.temp_i, Sop.K_if, (Sop.K_ff_factor \ Sop.temp_f))
    mul!(y, Sop.K_ii, v) 
    y .-= Sop.tempi
    y
end

size(Sop::SLinearOperator) = size(Sop.K_ii)
eltype(Sop::SLinearOperator) = eltype(Sop.K_ii)

# function mul!(y::Vector{Float64}, F::SparseArrays.CHOLMOD.Factor{Float64, Int64}, v::Vector{Float64})
#     y .= F \ v
# end

const DOF_KIND_INTERFACE::KIND_INT = 3

"""
    PartitionSchurDD

Map from finite element nodes to the partitions to which they belong.

- `map` = map as a vector of vectors. If a node belongs to a single partition,
  the inner vector will have a single element.
"""
struct PartitionSchurDD{T, IT, FES<:FESet, F<:NodalField}
    fens::FENodeSet
    fes::FES 
    u::F
    global_node_numbers::Vector{IT}
    global_u::F
    Sop::SLinearOperator{T, IT}
end

function PartitionSchurDD{T, IT}(fens::FENodeSet, fes::FES, global_node_numbers::Vector{IT}, global_u::F) where {T<:Number,IT<:Integer,F<:NodalField}
    geom, u = make_partition_fields(fens)
    transfer_dofs!(u, global_u, global_node_numbers)
    femm = make_partition_femm(fens, fes, u)
    K = make_partition_matrix(femm, geom, u)
    I = make_partition_interior_load(femm, geom, u, global_node_numbers)
    B = make_partition_interior_load(geom, u, global_node_numbers)
    Sop = SLinearOperator(K, u)
end 

function transfer_dofs!(u, global_u, global_node_numbers)
    for i in 1:nents(u)
        u.kind[i, :] .= global_u.kind[global_node_numbers[i], :]
        u.dofnums[i, :] .= global_u.dofnums[global_node_numbers[i], :]
        u.values[i, :] .= global_u.values[global_node_numbers[i], :]
    end
    return u
end

function mark_interfaces!(u::F, n2p::FENodeToPartitionMap) where {F<:NodalField}
    for i in eachindex(n2p.map)
        if length(n2p.map[i]) > 1
            u.kind[i, :] .= DOF_KIND_INTERFACE
        end
    end
end

end # module PartitionSchurDDModule
