module ACEpotentials

using Reexport 
@reexport using JuLIP
@reexport using ACE1
@reexport using ACE1x
@reexport using ACEfit

include("atoms_data.jl")
include("model.jl")
include("export.jl")
include("example_data.jl")
include("descriptor.jl")

include("analysis/potential_analysis.jl")
include("analysis/dataset_analysis.jl")

include("outdated/fit.jl")
include("outdated/data.jl")
include("outdated/basis.jl")
include("outdated/solver.jl")
include("outdated/regularizer.jl")
include("outdated/read_params.jl")

end
