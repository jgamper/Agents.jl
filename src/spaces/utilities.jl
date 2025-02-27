export edistance, get_direction, walk!

#######################################################################################
# %% Distances and directions in Grid/Continuous space
#######################################################################################
"""
    edistance(a, b, model::ABM)

Return the euclidean distance between `a` and `b` (either agents or agent positions),
respecting periodic boundary conditions (if in use). Works with any space where it makes
sense: currently `GridSpace` and `ContinuousSpace`.

Example usage in the [Flocking model](@ref).
"""
edistance(
    a::A,
    b::B,
    model::ABM{<:Union{ContinuousSpace,GridSpace}},
) where {A <: AbstractAgent,B <: AbstractAgent} = edistance(a.pos, b.pos, model)

function edistance(
    a::ValidPos,
    b::ValidPos,
    model::ABM{<:Union{ContinuousSpace{D,false},GridSpace{D,false}}},
) where {D}
    sqrt(sum(abs2.(a .- b)))
end

function edistance(
    p1::ValidPos,
    p2::ValidPos,
    model::ABM{<:ContinuousSpace{D,true}},
) where {D}
    total = 0.0
    for (a, b, d) in zip(p1, p2, model.space.extent)
        delta = abs(b - a)
        if delta > d - delta
            delta = d - delta
        end
        total += delta^2
    end
    sqrt(total)
end

function edistance(p1::ValidPos, p2::ValidPos, model::ABM{<:GridSpace{D,true}}) where {D}
    total = 0.0
    for (a, b, d) in zip(p1, p2, size(model.space))
        delta = abs(b - a)
        if delta > d - delta
            delta = d - delta
        end
        total += delta^2
    end
    sqrt(total)
end

"""
    get_direction(from, to, model::ABM)
Return the direction vector from the position `from` to position `to` taking into account
periodicity of the space.
"""
get_direction(from, to, model::ABM) = get_direction(from, to, model.space)

function get_direction(
    from::NTuple{D,Float64},
    to::NTuple{D,Float64},
    space::Union{ContinuousSpace{D,true},GridSpace{D,true}}
) where {D}
    best = to .- from
    for offset in Iterators.product([-1:1 for _ in 1:D]...)
        dir = to .+ offset .* size(space) .- from
        sum(dir.^2) < sum(best.^2) && (best = dir)
    end
    return best
end

function get_direction(from, to, ::Union{GridSpace,ContinuousSpace})
    return to .- from
end

#######################################################################################
# %% Utilities for graph-based spaces (Graph/OpenStreetMap)
#######################################################################################
GraphBasedSpace = Union{GraphSpace,OpenStreetMapSpace}
_get_graph(space::GraphSpace) = space.graph
_get_graph(space::OpenStreetMapSpace) = space.map.graph
"""
    nv(model::ABM)
Return the number of positions (vertices) in the `model` space.
"""
Graphs.nv(abm::ABM{<:GraphBasedSpace}) = Graphs.nv(_get_graph(abm.space))

"""
    ne(model::ABM)
Return the number of edges in the `model` space.
"""
Graphs.ne(abm::ABM{<:GraphBasedSpace}) = Graphs.ne(_get_graph(abm.space))

positions(model::ABM{<:GraphBasedSpace}) = 1:nv(model)

function nearby_positions(
    position::Integer,
    model::ABM{<:GraphBasedSpace},
    radius::Integer;
    kwargs...,
)
    output = copy(nearby_positions(position, model; kwargs...))
    for _ in 2:radius
        newnps = (nearby_positions(np, model; kwargs...) for np in output)
        append!(output, reduce(vcat, newnps))
        unique!(output)
    end
    filter!(i -> i ≠ position, output)
end

#######################################################################################
# %% Walking
#######################################################################################
"""
    walk!(agent, direction::NTuple, model; ifempty = false)

Move agent in the given `direction` respecting periodic boundary conditions.
If `periodic = false`, agents will walk to, but not exceed the boundary value.
Possible on both `GridSpace` and `ContinuousSpace`s.

The dimensionality of `direction` must be the same as the space. `GridSpace` asks for
`Int`, and `ContinuousSpace` for `Float64` vectors, describing the walk distance in
each direction. `direction = (2, -3)` is an example of a valid direction on a
`GridSpace`, which moves the agent to the right 2 positions and down 3 positions.
Velocity is ignored for this operation in `ContinuousSpace`.

## Keywords
- `ifempty` will check that the target position is unnocupied and only move if that's true. Available only on `GridSpace`.

Example usage in [Battle Royale](https://juliadynamics.github.io/AgentsExampleZoo.jl/dev/examples/battle/).
"""
function walk!(
    agent::AbstractAgent,
    direction::NTuple{D,Int},
    model::ABM{<:GridSpace{D,true}};
    kwargs...,
) where {D}
    target = mod1.(agent.pos .+ direction, size(model.space))
    walk_if_empty!(agent, target, model; kwargs...)
end

function walk!(
    agent::AbstractAgent,
    direction::NTuple{D,Int},
    model::ABM{<:GridSpace{D,false}};
    kwargs...,
) where {D}
    target = min.(max.(agent.pos .+ direction, 1), size(model.space))
    walk_if_empty!(agent, target, model; kwargs...)
end

function walk!(
    agent::AbstractAgent,
    direction::NTuple{D,Float64},
    model::ABM{<:ContinuousSpace{D,true}};
    kwargs...,
) where {D}
    target = mod1.(agent.pos .+ direction, model.space.extent)
    move_agent!(agent, target, model)
end

function walk!(
    agent::AbstractAgent,
    direction::NTuple{D,Float64},
    model::ABM{<:ContinuousSpace{D,false}};
    kwargs...,
) where {D}
    target = min.(max.(agent.pos .+ direction, 0.0), model.space.extent .- 1e-15)
    move_agent!(agent, target, model)
end

function walk_if_empty!(agent, target, model; ifempty::Bool = false)
    if ifempty
        isempty(target, model) && move_agent!(agent, target, model)
    else
        move_agent!(agent, target, model)
    end
end

"""
    walk!(agent, rand, model)

Invoke a random walk by providing the `rand` function in place of
`distance`. For `GridSpace`, the walk will cover ±1 positions in all directions,
`ContinuousSpace` will reside within [-1, 1].
"""
walk!(agent, ::typeof(rand), model::ABM{<:GridSpace{D}}; kwargs...) where {D} =
    walk!(agent, Tuple(rand(model.rng, -1:1, D)), model; kwargs...)

walk!(agent, ::typeof(rand), model::ABM{<:ContinuousSpace{D}}; kwargs...) where {D} =
    walk!(agent, Tuple(2.0 * rand(model.rng) - 1.0 for _ in 1:D), model; kwargs...)
