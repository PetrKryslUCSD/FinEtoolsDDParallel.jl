module fibers_overlapped_examples
using FinEtools
using FinEtools.MeshExportModule: VTK
using FinEtools.MeshExportModule: CSV
using FinEtools.MeshTetrahedronModule: tetv
using FinEtoolsDeforLinear
using FinEtoolsDDParallel
using FinEtoolsDDParallel.CGModule: pcg_seq
using SymRCM
using Metis
using Test
using LinearAlgebra
using SparseArrays
using PlotlyLight
using Krylov
using LinearOperators
import Base: size, eltype
import LinearAlgebra: mul!
import CoNCMOR: CoNCData, transfmatrix, LegendreBasis
using Targe2
using DataDrop
using Statistics

function rotate(fens)
    Q = [cos(pi/2) -sin(pi/2); sin(pi/2) cos(pi/2)]
    for i in 1:count(fens)
        fens.xyz[i, :] .=  Q * fens.xyz[i, :]
    end
    fens 
end

function translate(fens, d)
    for i in 1:count(fens)
        fens.xyz[i, :] .+= d
    end
    fens
end

function matrix_unit(a, R, nL, nH, nW, tolerance)
    meshes = Array{Tuple{FENodeSet,AbstractFESet},1}()
    fens, fes = Q4elliphole(R, R, a + R, a + R, nL, nH, nW)
    push!(meshes, (fens, fes))
    fens, fes = Q4elliphole(R, R, a + R, a + R, nL, nH, nW)
    fens = rotate(fens)
    push!(meshes, (fens, fes))
    fens, fes = Q4elliphole(R, R, a + R, a + R, nL, nH, nW)
    fens = rotate(fens)
    fens = rotate(fens)
    push!(meshes, (fens, fes))
    fens, fes = Q4elliphole(R, R, a + R, a + R, nL, nH, nW)
    fens = rotate(fens)
    fens = rotate(fens)
    fens = rotate(fens)
    push!(meshes, (fens, fes))
    fens, fesa = mergenmeshes(meshes, tolerance)
    fes = fesa[1]
    for i in 2:length(fesa)
        fes = cat(fes, fesa[i])
    end
    setlabel!(fes, 0)
    return fens, fes
end

function fiber_unit(R, nr, tolerance, label)
    fens1, fes1 = Q4circlen(R, nr)
    fens1.xyz = fens1.xyz[:, 1:2]
    meshes = Array{Tuple{FENodeSet,AbstractFESet},1}()
    _fens, _fes = deepcopy(fens1), deepcopy(fes1)
    push!(meshes, (_fens, _fes))
    _fens, _fes = deepcopy(fens1), deepcopy(fes1)
    _fens = rotate(_fens)
    push!(meshes, (_fens, _fes))
    _fens, _fes = deepcopy(fens1), deepcopy(fes1)
    _fens = rotate(_fens)
    _fens = rotate(_fens)
    push!(meshes, (_fens, _fes))
    _fens, _fes = deepcopy(fens1), deepcopy(fes1)
    _fens = rotate(_fens)
    _fens = rotate(_fens)
    _fens = rotate(_fens)
    push!(meshes, (_fens, _fes))
    fens, fesa = mergenmeshes(meshes, tolerance)
    fes = fesa[1]
    for i in 2:length(fesa)
        fes = cat(fes, fesa[i])
    end
    setlabel!(fes, label)
    return fens, fes
end

function fibers_mesh_hex(ref = 1)
    nr = 3
    a = 1.0
    R = 1.0 
    d = a + R + (nr - 1) * 2 * (a + R) + a + R
    h = 2 * R / (2 + ref)
    nR = 2 * Int(round(R / h))
    nL = Int(round(nR / 2))
    nH = nL
    nW = 2 * Int(round(nR/2))
    Lz = 2.0 * d
    nlayers = ref + Int(ceil(Lz / (3 * h)))
    tolerance = R / nR / 5

    meshes = Array{Tuple{FENodeSet,AbstractFESet},1}()
    fens, fes = matrix_unit(a, R, nL, nH, nW, tolerance)
    push!(meshes, (fens, fes))
    fens, fes = fiber_unit(R, nR, tolerance, -1)
    push!(meshes, (fens, fes))
    fens, fesa = mergenmeshes(meshes, tolerance)
    fes = fesa[1]
    for i in 2:length(fesa)
        fes = cat(fes, fesa[i])
    end
    fens = translate(fens, [(a + R), (a + R)])
    
    fens1, fes1 = deepcopy(fens), deepcopy(fes)
    fel = selectelem(fens1, fes1, label = -1)
    labels = fes.label
    
    meshes = Array{Tuple{FENodeSet,AbstractFESet},1}()
    for r in 1:nr
        for c in 1:nr
            fens, fes = deepcopy(fens1), deepcopy(fes1)
            fens = translate(fens, [(c - 1) * (a + R) * 2, (r - 1) * (a + R) * 2])
            labels[fel] .= (r - 1) * nr + c
            setlabel!(fes, deepcopy(labels))
            push!(meshes, (fens, fes))
        end
    end

    fens, fesa = mergenmeshes(meshes, tolerance)
    fes = fesa[1]
    for i in 2:length(fesa)
        fes = cat(fes, fesa[i])
    end

    fens, fes = H8extrudeQ4(
        fens,
        fes,
        nlayers,
        (X, layer) -> [X[1], X[2], layer * Lz / nlayers],
    )

    # File =  "fibers_soft_hard_hex-mesh.vtk"
    # vtkexportmesh(File, fens, fes; scalars=[("label", fes.label)])
    # @async run(`"paraview.exe" $File`)

    return fens, fes
end # fibers_mesh

function fibers_mesh_tet(ref = 1)
    nr = 3
    a = 1.0
    R = 1.0 
    h = 2 * R / (2 + ref)
    d = a + R + (nr - 1) * 2 * (a + R) + a + R
    Lz = 2.0 * d
    nlayers = ref + Int(ceil(Lz / (5 * h)))
    input = """
    curve 1 line 0 0 $(d) 0
    curve 2 line $(d) 0 $(d) $(d)
    curve 3 line $(d) $(d) 0 $(d)  
    curve 4 line 0 $(d) 0 0 
    """ 
    p = 1
    for r in 1:nr
        for c in 1:nr 
            cx = a + R + (r - 1) * 2 * (a + R)
            cy = a + R + (c - 1) * 2 * (a + R)
            input *= "\n" * "curve $(4+p) circle center $(cx) $(cy) radius $R"
            p += 1
        end
    end
    input *= "\n" * 
    """
    subregion 1  property 1 boundary 1 2 3 4 hole """
    p = 1
    for r in 1:nr
        for c in 1:nr
            input *= " $(-(4+p))"
            p += 1
        end
    end
    input *= "\n" 
    p = 1
    for r in 1:nr
        for c in 1:nr
            input *= "subregion $(p+1) property 2 boundary  $(+(4+p))\n"
            p += 1
        end
    end
    input *= "\n" * 
    """    
    m-ctl-point constant $h
    """
    
    mesh = triangulate(input)
    
    fens = FENodeSet(mesh.xy)
    fes = FESetT3(mesh.triconn)
    labels = fill(0, count(fes)) # the matrix should have a label of 0
    for i in eachindex(mesh.trigroups)
        for j in mesh.trigroups[i]
            labels[j] = i - 1 # the fibers should have labels 1, 2, 3, ...
        end
    end
    setlabel!(fes, labels)
    @show fes.label

    fens, fes = T4extrudeT3(
        fens,
        fes,
        nlayers,
        (X, layer) -> [X[1], X[2], layer * Lz / nlayers],
    )
    
    # X = zeros(4, 3)
    # for i in eachindex(fes)
    #     X[1, :] = fens.xyz[fes.conn[i][1], :]
    #     X[2, :] = fens.xyz[fes.conn[i][2], :]
    #     X[3, :] = fens.xyz[fes.conn[i][3], :]
    #     X[4, :] = fens.xyz[fes.conn[i][4], :]
    #     @test  tetv(X) > 0.0
    # end

    fens, fes = T4toT10(fens, fes)
    
    # File =  "fibers_mesh.vtk"
    # vtkexportmesh(File, fens, fes; scalars=[("label", fes.label)])
    # @async run(`"paraview.exe" $File`)

    return fens, fes
end # fibers_mesh

function coarse_grid_partitioning(fens, fes, nelperpart)
    partitioning = zeros(Int, count(fens))
    nfiberparts = 0
    for p in 1:maximum(fes.label)
        fiberel = selectelem(fens, fes, label = p)
        femm = FEMMBase(IntegDomain(subset(fes, fiberel), PointRule()))
        C = dualconnectionmatrix(femm, fens, nodesperelem(boundaryfe(fes)))
        g = Metis.graph(C; check_hermitian=true)
        ndoms = Int(ceil(length(fiberel) / nelperpart))
        fiber_element_partitioning = Metis.partition(g, ndoms; alg=:KWAY)
        for e in eachindex(fiberel)
            for n in fes.conn[fiberel[e]]
                partitioning[n] = fiber_element_partitioning[e] + nfiberparts
            end
        end
        nfiberparts += maximum(fiber_element_partitioning)
    end
    matrixel = selectelem(fens, fes, label = 0)
    femm = FEMMBase(IntegDomain(subset(fes, matrixel), PointRule()))
    C = dualconnectionmatrix(femm, fens, nodesperelem(boundaryfe(fes)))
    g = Metis.graph(C; check_hermitian=true)
    ndoms = Int(ceil(length(matrixel) / nelperpart))
    matrix_element_partitioning = Metis.partition(g, ndoms; alg=:KWAY)
    for e in eachindex(matrixel)
        for n in fes.conn[matrixel[e]]
            if partitioning[n] == 0
                partitioning[n] = matrix_element_partitioning[e] + nfiberparts
            end
        end
    end
    npartitions = maximum(partitioning)
    partitioning, npartitions
end

function make_overlapping_partition(fens, fes, n2e, overlap, element_1st_partitioning, i)
    enl = findall(x -> x == i, element_1st_partitioning)
    touched = fill(false, count(fes)) 
    touched[enl] .= true 
    for ov in 1:overlap
        sfes = subset(fes, enl)
        bsfes = meshboundary(sfes)
        addenl = Int[]
        for e in eachindex(bsfes)
            for n in bsfes.conn[e]
                for ne in n2e.map[n]
                    if !touched[ne] 
                        touched[ne] = true
                        push!(addenl, ne)
                    end
                end
            end
        end
        enl = cat(enl, addenl; dims=1)
    end
    # vtkexportmesh("i=$i" * "-enl" * "-final" * ".vtk", fens, subset(fes, enl))
    return connectednodes(subset(fes, enl))
end

function fine_grid_node_lists(fens, fes, npartitions, overlap)
    femm = FEMMBase(IntegDomain(fes, PointRule()))
    C = dualconnectionmatrix(femm, fens, nodesperelem(boundaryfe(fes)))
    g = Metis.graph(C; check_hermitian=true)
    element_1st_partitioning = Metis.partition(g, npartitions; alg=:KWAY)
    n2e = FENodeToFEMap(fes, count(fens))
    npartitions = maximum(element_1st_partitioning)
    nodelists = []
    for i in 1:npartitions
        push!(nodelists, make_overlapping_partition(fens, fes, n2e, overlap, element_1st_partitioning, i))
    end
    nodelists
end

function _execute(label, kind, Em, num, Ef, nuf, nelperpart, nbf1max, nfpartitions, overlap, ref, mesh, boundary_rule, interior_rule, make_femm, itmax)
    CTE = 0.0
    magn = 1.0
    
    function getfrcL!(forceout, XYZ, tangents, feid, qpid)
        copyto!(forceout, [0.0; magn; 0.0])
    end
    fens, fes = mesh(ref)
    
    MR = DeforModelRed3D
    matf = MatDeforElastIso(MR, 0.0, Ef, nuf, CTE)
    matm = MatDeforElastIso(MR, 0.0, Em, num, CTE)

    # Material orientation matrix
    csmat = [i == j ? one(Float64) : zero(Float64) for i = 1:3, j = 1:3]

    function updatecs!(csmatout, XYZ, tangents, feid, qpid)
        copyto!(csmatout, csmat)
    end

    geom = NodalField(fens.xyz)
    u = NodalField(zeros(size(fens.xyz, 1), 3)) # displacement field

    # Renumber the nodes
    femm = FEMMBase(IntegDomain(fes, interior_rule))
    C = connectionmatrix(femm, count(fens))
    perm = symrcm(C)
    
    matrixel = selectelem(fens, fes, label = 0)
    fiberel = setdiff(1:count(fes), matrixel)
    bfes = meshboundary(subset(fes, fiberel))
    sectionL = selectelem(fens, bfes; facing = true, direction = [0.0 0.0 +1.0])
    loadfes = subset(bfes, sectionL)
    # end cross-section surface  for the shear loading
    # sectionL = selectelem(fens, bfes; facing = true, direction = [0.0 0.0 +1.0])
    # 0 cross-section surface  for the reactions
    bfes = meshboundary(fes)
    section0 = selectelem(fens, bfes; facing = true, direction = [0.0 0.0 -1.0])

    lx0 = connectednodes(subset(bfes, section0))
    setebc!(u, lx0, true, 1, 0.0)
    setebc!(u, lx0, true, 2, 0.0)
    setebc!(u, lx0, true, 3, 0.0)
    applyebc!(u)
    numberdofs!(u, perm)
    fr = dofrange(u, DOF_KIND_FREE)
    dr = dofrange(u, DOF_KIND_DATA)
    
    println("Kind: $(string(kind))")
    println("Materials: $(Ef), $(nuf), $(Em), $(num)")
    println("Refinement factor: $(ref)")
    println("Number of elements per partition: $(nelperpart)")
    println("Number of 1D basis functions: $(nbf1max)")
    println("Number of fine grid partitions: $(nfpartitions)")
    println("Overlap: $(overlap)")
    println("Number of elements: $(count(fes))")
    println("Number of free dofs = $(nfreedofs(u))")

    fi = ForceIntensity(Float64, 3, getfrcL!)
    el2femm = FEMMBase(IntegDomain(loadfes, boundary_rule))
    F = distribloads(el2femm, geom, u, fi, 2)
    F_f = F[fr]
    femmm = make_femm(MR, IntegDomain(subset(fes, matrixel), interior_rule), matm)
    associategeometry!(femmm, geom)
    K = stiffness(femmm, geom, u)
    femmf = make_femm(MR, IntegDomain(subset(fes, fiberel), interior_rule), matf)
    associategeometry!(femmf, geom)
    K += stiffness(femmf, geom, u)
    K_ff = K[fr, fr]

    # U_f = K_ff \ F_f
    # scattersysvec!(u, U_f)

    # VTK.vtkexportmesh("fibers-tet-sol.vtk", fens, fes; vectors=[("u", deepcopy(u.values),)])   

    cpartitioning, ncpartitions = coarse_grid_partitioning(fens, fes, nelperpart)
    println("Number coarse grid partitions: $(ncpartitions)")
        
    # f = "fibers_soft_hard_$(string(kind))" *
    #     "-rf=$(ref)" *
    #     "-ne=$(nelperpart)" *
    #     "-n1=$(nbf1max)" * "-partitioning"
    # partitionsfes = FESetP1(reshape(1:count(fens), count(fens), 1))
    # vtkexportmesh(f * ".vtk", fens, partitionsfes; scalars=[("partition", cpartitioning)])
    # @async run(`"paraview.exe" $File`)
    
    mor = CoNCData(fens, cpartitioning)
    Phi = transfmatrix(mor, LegendreBasis, nbf1max, u)
    Phi = Phi[fr, :]
    transfm(m, t, tT) = (tT * m * t)
    transfv(v, t, tT) = (tT * v)
    PhiT = Phi'
    Kr_ff = transfm(K_ff, Phi, PhiT)
    println("Size of the reduced problem: $(size(Kr_ff))")
    Krfactor = lu(Kr_ff)

    # U_f = Phi * (Krfactor \ (PhiT * F_f))
    # scattersysvec!(u, U_f)

    # VTK.vtkexportmesh("fibers-tet-red-sol.vtk", fens, fes; vectors=[("u", deepcopy(u.values),)])   
    
    # fpartitioning, nfpartitions = fine_grid_partitioning(fens, nfpartitions)
    nodelists = fine_grid_node_lists(fens, fes, nfpartitions, overlap)
    @assert length(nodelists) == nfpartitions
    
    partitions = []
    for nodelist in nodelists
        doflist = Int[]
        for n in nodelist
            for d in axes(u.dofnums, 2)
                if u.dofnums[n, d] in fr
                    push!(doflist, u.dofnums[n, d])
                end
            end
        end
        pK = K[doflist, doflist]
        pKfactor = lu(pK)
        part = (nodelist = nodelist, factor = pKfactor, doflist = doflist)
        push!(partitions, part)
    end

    meansize = mean([length(part.doflist) for part in partitions])
    println("Mean fine partition size: $(meansize)")

    function M!(q, p)
        q .= Phi * (Krfactor \ (PhiT * p))
        for part in partitions
            q[part.doflist] .+= (part.factor \ p[part.doflist])
        end
        q
    end

    t0 = time()
    norm_F_f = norm(F_f)
    (u_f, stats) = pcg_seq((q, p) -> mul!(q, K_ff, p), F_f, zeros(size(F_f));
        (M!)=(q, p) -> M!(q, p),
        itmax=itmax, atol=1e-6 * norm_F_f, rtol=0)
    t1 = time()
    println("Number of iterations:  $(stats.niter)")
    stats = (niter = stats.niter, residuals = stats.residuals ./ norm_F_f)
    data = Dict(
        "nfreedofs_u" => nfreedofs(u),
        "ncpartitions" => ncpartitions,
        "nfpartitions" => nfpartitions,
        "overlap" => overlap,
        "size_Kr_ff" => size(Kr_ff),
        "stats" => stats,
        "time" => t1 - t0,
    )
    f = "fibers-$(label)-$(string(kind))" *
        "-rf=$(ref)" *
        "-ne=$(nelperpart)" *
        "-n1=$(nbf1max)"  * 
        "-nf=$(nfpartitions)"  * 
        "-ov=$(overlap)"  
    DataDrop.store_json(f * ".json", data)
    scattersysvec!(u, u_f)
    
    # f = "fibers-$(label)-$(string(kind))" *
    #     "-rf=$(ref)" *
    #     "-ne=$(nelperpart)" *
    #     "-n1=$(nbf1max)" * 
    #     "-nf=$(nfpartitions)"  * 
    #     "-cg-sol"
    # VTK.vtkexportmesh(f * ".vtk", fens, fes; vectors=[("u", deepcopy(u.values),)])
    
    true
end
# test(ref = 1)

function test(label = "soft_hard"; kind = "hex", Em = 1.0e3, num = 0.4999, Ef = 1.0e5, nuf = 0.3, nelperpart = 200, nbf1max = 5, nfpartitions = 2, overlap = 1, ref = 1)
    mesh = fibers_mesh_tet
    boundary_rule = TriRule(6)
    interior_rule = TetRule(4)
    make_femm = FEMMDeforLinearMST10
    if kind == "hex"
        mesh = fibers_mesh_hex
        boundary_rule = GaussRule(2, 2)
        interior_rule = GaussRule(3, 2)
        make_femm = FEMMDeforLinearMSH8
    end
    itmax = 2000
    _execute(label, kind, Em, num, Ef, nuf, nelperpart, nbf1max, nfpartitions, overlap, ref, mesh, boundary_rule, interior_rule, make_femm, itmax)
end

nothing
end # module


