
using LinearAlgebra: I, Diagonal

import ACE1x 
import ACE1x: ACE1Model, acemodel, _set_params!, smoothness_prior

export acefit!

import JuLIP: energy, forces, virial, cutoff
import ACE1.Utils: get_maxn

_mean(x) = sum(x) / length(x)


default_weights() = Dict("default"=>Dict("E"=>30.0, "F"=>1.0, "V"=>1.0))

function _make_prior(model, smoothness, P)
   if P isa AbstractMatrix || P isa UniformScaling 
      return P 
   elseif smoothness isa Number 
      if smoothness >= 0 
         return smoothness_prior(model; p = smoothness)
      end
   end
end

"""
`function acefit!(model, data; kwargs...)` : 
provides a simplified interface to fitting the 
parameters of a model specified via `ACE1Model`. The data should be 
provided as a collection (`AbstractVector`) of `JuLIP.Atoms` structures. 

Keyword arguments:
* `energy_key`, `force_key`, `virial_key` specify 
the label of the data to which the parameters will be fitted. 
* `weights` specifies the regression weights, default is 30 for energy, 1 for forces and virials
* `solver` specifies the lsq solver, default is `BayesianLinearRegressionSVD`
* `smoothness` specifies the smoothness prior, i.e. how strongly damped 
   parameters corresponding to high polynomial degrees are; is 2.
* `prior` specifies a covariance of the prior, if `nothing` then a smoothness prior 
   is used, using the `smoothness` parameter 
* `repulsion_restraint` specifies whether to add artificial data to the training 
   set that effectively introduces a restraints encouraging repulsion 
   in the limit rij -> 0.
* `restraint_weight` specifies the weight of the repulsion restraint.
"""
function acefit!(model::ACE1Model, raw_data;
                solver = ACEfit.BayesianLinearRegressionSVD(), 
                weights = default_weights(),
                energy_key = "energy", 
                force_key = "force", 
                virial_key = "virial", 
                smoothness = 2, 
                prior = nothing, 
                repulsion_restraint = false, 
                restraint_weight = 0.01) 

   data = [ AtomsData(at; energy_key = energy_key, force_key=force_key, 
                          virial_key = virial_key, weights = weights, 
                          v_ref = model.Vref) 
            for at in raw_data ] 

   if repulsion_restraint 
      append!(data, _rep_dimer_data(model, weight = restraint_weight))
   end
                  
   P = _make_prior(model, smoothness, prior)
   A, Y, W = ACEfit.assemble(data, model.basis)
   Ap = Diagonal(W) * (A / P) 
   Y = W .* Y
   result = ACEfit.solve(solver, Ap, Y)
   coeffs = P \ result["C"]
   ACE1x._set_params!(model, coeffs)

   return model 
end



function linear_errors(raw_data::AbstractVector{<: Atoms}, model::ACE1Model; 
                       energy_key = "energy", 
                       force_key = "force", 
                       virial_key = "virial", 
                       weights = default_weights())
   Vref = model.Vref                       
   data = [ AtomsData(at; energy_key = energy_key, force_key=force_key, 
                          virial_key = virial_key, weights = weights, 
                          v_ref = model.Vref) 
            for at in raw_data ] 
   return linear_errors(data, model.potential)
end


# ---------------- Implementaiton of the repuslion restraint 

at_dimer(r, z1, z0) = Atoms(X = [ SVector(0.0,0.0,0.0), SVector(r, 0.0, 0.0)], 
                            Z = [z0, z1], pbc = false, 
                            cell = [r+1 0 0; 0 1 0; 0 0 1])

function _rep_dimer_data(model; 
                         weight = 0.01, 
                         )
   zz = model.basis.BB[1].zlist.list
   restraints = [] 
   restraint_weights = Dict("restraint" => Dict("E" => weight, "F" => 0.0, "V" => 0.0))
   B_pair = model.basis.BB[1] 
   if !isa(B_pair, ACE1.PolyPairBasis)
      error("repulsion restraints only implemented for PolyPairBasis")
   end

   for i = 1:length(zz), j = i:length(zz)
      z1, z2 = zz[i], zz[j]
      s1, s2 = chemical_symbol.((z1, z2))
      r0_est = 1.0   # could try to get this from the model meta-data 
      _rin = r0_est / 100  # can't take 0 since we'd end up with ∞ / ∞
      Pr_ij = B_pair.J[i, j]
      if !isa(Pr_ij, ACE1.OrthPolys.TransformedPolys)
         error("repulsion restraints only implemented for TransformedPolys")
      end
      envfun = Pr_ij.envelope 
      if !isa(envfun, ACE1.OrthPolys.PolyEnvelope)
         error("repulsion restraints only implemented for PolyEnvelope")
      end
      if !(envfun.p >= 0)
         error("repulsion restraints only implemented for PolyEnvelope with p >= 0")
      end
      env_rin = ACE1.evaluate(envfun, _rin)
      at = at_dimer(_rin, z1, z2)
      set_data!(at, "REF_energy", env_rin)
      set_data!(at, "config_type", "restraint")
      dat = ACE1pack.AtomsData(at, "REF_energy", "REF_forces", "REF_virial", 
                                 restraint_weights, model.Vref)
      push!(restraints, dat) 
   end
   
   return restraints
end