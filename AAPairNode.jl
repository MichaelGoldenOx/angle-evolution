using UtilsModule

export AAPairNode
type AAPairNode
  eqfreqs::Array{Float64, 1}
  logeqfreqs::Array{Float64, 1}
  S::Array{Float64,2}
  Q::Array{Float64,2}
  D::Array{Float64,1}
  V::Array{Float64,2}
  Vi::Array{Float64,2}
  t::Float64
  Pt::Array{Float64,2}
  logPt::Array{Float64,2}
  diagsum::Float64
  branchscale::Float64

  function AAPairNode()
    eqfreqs = ones(Float64,20)*0.05
    logeqfreqs = log(eqfreqs)
    S = ones(Float64, 20, 20)
    Q = ones(Float64, 20, 20)
    t = 1.0
    Pt = expm(Q*t)
    logPt = log(Pt)
    return new(eqfreqs, logeqfreqs, S, Q, zeros(Float64,1), zeros(Float64,1,1), zeros(Float64,1,1), t, Pt, logPt, 0.0, 1.0)
  end

  function AAPairNode(node::AAPairNode)
    new(copy(node.eqfreqs), copy(node.logeqfreqs), copy(node.S), copy(node.Q), copy(node.D), copy(node.V), copy(node.Vi), node.t, copy(node.Pt), copy(node.logPt), node.diagsum, node.branchscale)
  end
end

export set_parameters
function set_parameters(node::AAPairNode, eqfreqs::Array{Float64, 1},  S::Array{Float64,2}, t::Float64)
  if 0.999 <= sum(eqfreqs) <= 1.001
    node.eqfreqs = eqfreqs
    node.logeqfreqs = log(eqfreqs)
    node.S = S
    node.Q = zeros(Float64,20,20)
    for i=1:20
      for j=1:20
        node.Q[i,j] = S[i,j]*eqfreqs[j]
      end
    end
    for i=1:20
      node.Q[i,i] = 0.0
      for j=1:20
        if i != j
          node.Q[i,i] -= node.Q[i,j]
        end
      end
    end

    try
      node.D, node.V = eig(node.Q)
      node.Vi = inv(node.V)
      node.Pt = node.V*Diagonal(exp(node.D*t))*node.Vi
      for i=1:20
        for j=1:20
          if node.Pt[i,j] > 0.0
            node.logPt[i,j] = log(node.Pt[i,j])
          else
            node.logPt[i,j] = -1e10
            node.Pt[i,j] = 0.0
          end
        end
      end
    catch e
      println(eqfreqs)
      println(node.Q)
      println(e)
      #exit()
    end
  end
end

export set_aaratematrix
function set_aaratematrix(node::AAPairNode, x::Array{Float64,1})
  S = zeros(Float64,20,20)
  index = 1
  for i=1:20
    for j=1:20
      if j > i
        S[i,j] = x[index]
        S[j,i] = S[i,j]
        index += 1
      end
    end
  end
  #S[2,1] = node.S[2,1]
  #S[1,2] = S[2,1]

  for i=1:20
    for j=1:20
      if i != j
        S[i,i] -= S[i,j]
      end
    end
  end
  tempdiagsum = 0.0
  for i=1:20
    tempdiagsum += -S[i,i]
  end


  set_parameters(node, node.eqfreqs,  S, 1.0)
end

export get_aaratematrixparameters
function get_aaratematrixparameters(node::AAPairNode)
  x = zeros(Float64,190)
  index = 1
  for i=1:20
    for j=1:20
      if j > i
        x[index] = node.S[i,j]
        index += 1
      end
    end
  end
  return x
end

function set_parameters(node::AAPairNode, eqfreqs::Array{Float64, 1}, t::Float64)
  if node.eqfreqs != eqfreqs
    set_parameters(node, eqfreqs, node.S, t)
  elseif node.t != t
    set_parameters(node, t)
  end
end

function set_parameters(node::AAPairNode, t::Float64)
  if(t != node.t)
    node.t = t
    node.Pt = node.V*Diagonal(exp(node.D*t))*node.Vi
    for i=1:20
      for j=1:20
        if node.Pt[i,j] > 0.0
          node.logPt[i,j] = log(node.Pt[i,j])
        else
          node.logPt[i,j] = -1e10
          node.Pt[i,j] = 0.0
        end
      end
    end
  end
end

export load_parameters
function load_parameters(node::AAPairNode, parameter_file)
  f = open(parameter_file)
  lines = readlines(f)
  close(f)

  S = zeros(Float64,20, 20)


  for i=1:20
   spl = split(lines[i])
   for j=1:length(spl)
     S[i+1,j] = parse(Float64, spl[j])
     S[j,i+1] = S[i+1,j]
   end
  end

  priors = Gamma[]
  for i=1:20
    for j=1:20
      if i != j
        S[i,i] -= S[i,j]
      end
      if j > i
        theta = 2.0
        k = (S[i,j]/theta)+1.0
        push!(priors, Gamma(k,theta))
      end
    end
  end

  eqfreqs = zeros(Float64,20)
  spl = split(lines[21])
  for i=1:20
    eqfreqs[i] = parse(Float64, spl[i])
  end

  #=
  node.diagsum = 0.0
  for i=1:20
    node.diagsum += -S[i,i]
  end=#

  set_parameters(node, eqfreqs, S, 1.0)
end

export get_data_lik
function get_data_lik(node::AAPairNode, x0::Int)
  if x0 > 0
    return node.logeqfreqs[x0]
  else
    return 0.0
  end
end

function get_data_lik(node::AAPairNode, x0::Int, xt::Int, t::Float64)
  if x0 > 0 && xt > 0
    set_parameters(node, node.branchscale*t)
    return node.logeqfreqs[x0] + node.logPt[x0,xt]
  elseif x0 > 0
    return node.logeqfreqs[x0]
  elseif xt > 0
    return node.logeqfreqs[xt]
  end

  return 0.0
end

export sample
function sample(node::AAPairNode, rng::AbstractRNG, x0::Int, xt::Int, t::Float64)
  a = x0
  b = xt
  set_parameters(node, node.branchscale*t)
  if a <= 0 && b <= 0
    a = UtilsModule.sample(rng, node.eqfreqs)
    b = UtilsModule.sample(rng, node.Pt[a,:])
  elseif a <= 0
    a = UtilsModule.sample(rng, node.Pt[b,:])
  elseif b <= 0
    b = UtilsModule.sample(rng, node.Pt[a,:])
  end
  return a,b
end
