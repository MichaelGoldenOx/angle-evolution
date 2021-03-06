include("VonMisesDensity.jl")

export aminoacids
aminoacids = "ACDEFGHIKLMNPQRSTVWY"
sschars = "HBEGITSC"
sscharsshort = "HSC"
ssmap = Int[1,2,2,1,1,3,3,3] # 1=helix, 2=sheet, 3=coil

MISSING_ANGLE = -1000.0
ANGLE_ERROR_KAPPA = 600.0

encoding = "123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!@#^&*()-+=?<>"
export getstatestring
function getstatestring(states::Array{Int,1})
  s1 = ""
  for i=1:length(states)
      s1 = string(s1, encoding[states[i]])
  end

  return s1
end

export Sequence
type Sequence
  name::AbstractString
  length::Int
  seq::Array{Int, 1}
  phi::Array{Float64, 1}
  psi::Array{Float64, 1}
  phi_obs::Array{Float64, 1}
  psi_obs::Array{Float64, 1}
  angle_error_kappa::Float64
  error_distribution::VonMisesDensity
  inputss::Array{Int,1}
  ss::Array{Int,1}
  errorll::Float64

  function Sequence(length::Int)
    new("", length, zeros(Int,length), ones(Float64,length)*MISSING_ANGLE, ones(Float64,length)*MISSING_ANGLE, ones(Float64,length)*MISSING_ANGLE, ones(Float64,length)*MISSING_ANGLE, ANGLE_ERROR_KAPPA, VonMisesDensity(0.0, ANGLE_ERROR_KAPPA),zeros(Int,length),zeros(Int,length),-Inf)
  end

  function Sequence(seq::AbstractString)
    len = length(seq)
    s = zeros(Int,len)
    for i=1:len
      s[i] = search(aminoacids, seq[i])
    end

    return new("", len, s, ones(Float64,len)*MISSING_ANGLE, ones(Float64,len)*MISSING_ANGLE, ones(Float64,len)*MISSING_ANGLE, ones(Float64,len)*MISSING_ANGLE, ANGLE_ERROR_KAPPA, VonMisesDensity(0.0, ANGLE_ERROR_KAPPA),zeros(Int,len),zeros(Int,len),-Inf)
  end

  function Sequence(seq::AbstractString, phi::Array{Float64,1}, psi::Array{Float64,1})
    len = length(seq)
    s = zeros(Int,len)
    for i=1:len
      s[i] = search(aminoacids, seq[i])
    end

    return new("", len, s, phi, psi, deepcopy(phi), deepcopy(psi), ANGLE_ERROR_KAPPA, VonMisesDensity(0.0, ANGLE_ERROR_KAPPA), zeros(Int,len),zeros(Int,len),-Inf)
  end

  function Sequence(seq::AbstractString, phi::Array{Float64,1}, psi::Array{Float64,1}, ss::AbstractString)
    len = length(seq)
    s = zeros(Int,len)
    for i=1:len
      s[i] = search(aminoacids, seq[i])
    end

    len2 = length(ss)
    inputss =  zeros(Int,len2)
    ssint = zeros(Int,len2)
    for i=1:len2
      res = search(sschars, ss[i])
      inputss[i] = res
      if res > 0
        ssint[i] = ssmap[res]
      end
    end

    return new("", len, s, phi, psi, deepcopy(phi), deepcopy(psi), ANGLE_ERROR_KAPPA, VonMisesDensity(0.0, ANGLE_ERROR_KAPPA), inputss, ssint,-Inf)
  end

  function Sequence(sequence::Sequence)
    return new(sequence.name, sequence.length, deepcopy(sequence.seq), deepcopy(sequence.phi), deepcopy(sequence.psi), deepcopy(sequence.phi_obs), deepcopy(sequence.psi_obs), sequence.angle_error_kappa, VonMisesDensity(0.0, sequence.angle_error_kappa), deepcopy(sequence.inputss), deepcopy(sequence.ss), sequence.errorll)
  end
end

export SequencePair
type SequencePair
  id::Int
  seq1::Sequence
  seq2::Sequence
  t::Float64
  single::Bool
  cornercut::Int

  function SequencePair()
    new(0,Sequence(),Sequence(),1.0,false, 1000000)
  end

  function SequencePair(id::Int, seq1::Sequence, seq2::Sequence)
    return new(id, seq1, seq2, 1.0,false, 1000000)
  end

  function SequencePair(pair::SequencePair)
    return new(pair.id,pair.seq1, pair.seq2, pair.t,false, pair.cornercut)
  end
end

export PairParameters
type PairParameters
  lambda::Float64
  mu::Float64
  ratio::Float64
  r::Float64
  t::Float64

  function PairParameters()
    return new(0.1,0.2,0.5,0.5,0.1)
  end

  function PairParameters(x::PairParameters)
    return new(x.lambda, x.mu, x.ratio, x.r, x.t)
  end

  function PairParameters(x::Array{Float64,1})
    lambda = x[1]
    ratio = x[2]
    mu = lambda/ratio
    r = x[3]
    t = x[4]
    return new(lambda,mu, ratio, r, t)
  end
end

export SequencePairSample
type SequencePairSample
  seqpair::SequencePair
  params::PairParameters
  align1::Array{Int,1}
  align2::Array{Int,1}
  states::Array{Int,1}
  aligned::Bool
  single::Bool
  regimes::Array{Int,1}

  function SequencePairSample()
    align1 = Int[]
    align2 = Int[]
    states = Int[]
    regimes = Int[]
    return new(SequencePair(), PairParameters(params), align1, align2, states, false, regimes)
  end

  function SequencePairSample(seqpair::SequencePair, params::PairParameters)
    align1 = Int[]
    align2 = Int[]
    states = Int[]
    regimes = Int[]
    return new(seqpair, PairParameters(params), align1, align2, states, false, false, regimes)
  end

   function SequencePairSample(seqpair::SequencePair, align1::Array{Int,1}, align2::Array{Int,1})
    states = Int[]
    regimes = Int[]
    return new(seqpair, PairParameters(), align1, align2, states, false, false, regimes)
  end

  function SequencePairSample(sample::SequencePairSample)
    return new(SequencePair(sample.seqpair), PairParameters(sample.params), copy(sample.align1), copy(sample.align2), copy(sample.states), sample.aligned, sample.single, copy(sample.regimes))
  end
end

export getconfigurations
function getconfigurations(align1::Array{Int,1},align2::Array{Int,1})
  conf1 = Int[]
  conf2 = Int[]
  for i=1:length(align1)
    if align1[i] > 0
      push!(conf1, align2[i])
    end
    if align2[i] > 0
      push!(conf2, align1[i])
    end
  end
  return conf1, conf2
end

export getstates
function getstates(states::Array{Int,1}, align1::Array{Int,1},align2::Array{Int,1})
  states1 = Int[]
  states2 = Int[]
  for i=1:length(align1)
    if align1[i] > 0
      push!(states1, states[align1[i]])
    end
    if align2[i] > 0
      push!(states2, states[align2[i]])
    end
  end
  return states1, states2
end

export getalignmentpath
function getalignmentpath(n::Int, m::Int, align1::Array{Int,1},align2::Array{Int,1}, states::Array{Int,1})
  matrix::SparseMatrixCSC{Int64,Int64} = spzeros(Int, n+1, m+1)
  hindex = length(states)
  matrix[n+1,m+1] = states[hindex]
  if states[hindex] == 0
    matrix[n+1,m+1] = 1000000
  end
  i = n+1
  j = m+1
  for (a,b) in zip(reverse(align1), reverse(align2))
    if a > 0 && b > 0
      i -= 1
      j -= 1
    elseif a > 0
      i -= 1
    elseif b > 0
      j -= 1
    end

    hindex -= 1
    if i > 0 && j > 0
      if hindex > 0
        matrix[i,j] = states[hindex]
      else
        matrix[i,j] = 1000000
      end
    end
  end
  return matrix
end

export getsequencestates
function getsequencestates(align1::Array{Int,1}, align2::Array{Int,1}, states::Array{Int,1})
  states1 = Int[]
  states2 = Int[]
  for i=1:length(align1)
    if align1[i] > 0
      push!(states1, states[i])
    end
    if align2[i] > 0
      push!(states2, states[i])
    end
  end
  return states1, states2
end

export getaasequence
function getaasequence(seq1::Sequence)
  s1 = ""
  for i=1:seq1.length
    if seq1.seq[i] > 0
      s1 = string(s1, aminoacids[seq1.seq[i]])
    else
      s1 = string(s1,"-")
    end
  end
  return s1
end

export getaminoacidalignment
function getaminoacidalignment(seq1::Sequence, align1::Array{Int,1})
  s1 = ""
  index = 1
  for i=1:length(align1)
    if align1[i] > 0 && seq1.seq[index] > 0
      s1 = string(s1, aminoacids[seq1.seq[index]])
      index += 1
    else
       s1 = string(s1, "-")
    end
  end

  return s1
end

export getssalignment
function getssalignment(seq1::Sequence, align1::Array{Int,1})
  s1 = ""
  for i=1:length(align1)
    if align1[i] > 0
      if seq1.inputss[align1[i]] == 0
        s1 = string(s1, "-")
      else
        #s1 = string(s1, sschars[seq1.inputss[align1[i]]])
        #println("SS",seq1.inputss[align1[i]])
        s1 = string(s1, sscharsshort[ssmap[seq1.inputss[align1[i]]]])
      end
    else
       s1 = string(s1, "-")
    end
  end

  return s1
end

export PriorDistribution
type PriorDistribution
    lambdaprior::Gamma
    muprior::Gamma
    rprior::Beta
    tprior::Gamma
    params::Array{Float64,1}

    function PriorDistribution()
      new(Gamma(), Gamma(), Beta(), Gamma(), zeros(Float64,8))
    end

    function PriorDistribution(params::Array{Float64, 1})
      new(Gamma(params[1], params[2]), Gamma(params[3], params[4]), Beta(params[5], params[6]), Gamma(params[7], params[8]), params)
    end
end

export logprior
function logprior(prior::PriorDistribution, pairparams::PairParameters)
      ll = 0.0
      ll += logpdf(prior.lambdaprior, pairparams.lambda)
      ll += logpdf(prior.muprior, pairparams.mu)
      ll += logpdf(prior.rprior, pairparams.r)
      ll += logpdf(prior.tprior, pairparams.t)
      return ll
end

function logprior(prior::PriorDistribution, samples::Array{SequencePairSample,1})
  ll = 0.0
  for sample in samples
    if !sample.seqpair.single
      ll += logprior(prior, sample.params)
    end
  end
  return ll
end

export get_alignment
function get_alignment(sequence_with_gaps::AbstractString)
  align = Int[]
  c = 1
  for i=1:length(sequence_with_gaps)
    if sequence_with_gaps[i] == '-'
      push!(align, 0)
    else
      push!(align, c)
      c += 1
    end
  end
  return align
end

export load_sequences_and_alignments
function load_sequences_and_alignments(datafile)
  f = open(datafile);
  line = 0
  seq1 = ""
  phi1 = Float64[]
  psi1 = Float64[]
  ss1 = ""
  seq2 = ""
  phi2 = Float64[]
  psi2 = Float64[]
  ss2 = ""
  align1 = Int[]
  align2 = Int[]
  id = 1
  pairs = SequencePairSample[]
  aligned=false
  title = ""
  for fileline in eachline(f)
    ln = strip(fileline)
    if length(ln) > 0 && ln[1] == '>'
      title = ln
      line = 0
    end

    if line == 1
      seq1 = ln
    elseif line == 2
      seq2 = ln
    elseif line == 3
      phi1 = zeros(Float64,length(seq1))
      if length(ln) > 0
        phi1 = Float64[parse(Float64, s) for s in split(ln, ",")]
      end
    elseif line == 4
      psi1 = zeros(Float64,length(seq1))
      if length(ln) > 0
        psi1 = Float64[parse(Float64, s) for s in split(ln, ",")]
      end
    elseif line == 5
      phi2 = zeros(Float64,length(seq2))
      if length(ln) > 0
        phi2 = Float64[parse(Float64, s) for s in split(ln, ",")]
      end
    elseif line == 6
      psi2 = zeros(Float64,length(seq2))
      if length(ln) > 0
        psi2 = Float64[parse(Float64, s) for s in split(ln, ",")]
      end
    elseif line == 7
      ss1 = ""
      for i=1:length(seq1)
        ss1 = string(ss1, "-")
      end
      if length(ln) > 0
        ss1 = ln
      end
    elseif line == 8
      ss2 = ""
      for i=1:length(seq2)
        ss2 = string(ss2, "-")
      end
      if length(ln) > 0
        ss2 = ln
      end
    elseif line == 9
      align1 = get_alignment(strip(ln))
      aligned = true
    elseif line == 10
      align2 = get_alignment(strip(ln))
      aligned = true
    end


    if line == 11
      if length(seq2) > 0
        seq1 = Sequence(seq1,phi1,psi1,ss1)
        seq1.name = split(title, r">| |\t")[2]
        seq2 = Sequence(seq2,phi2,psi2,ss2)
        seq2.name = split(title, r">| |\t")[3]
        seqpair = SequencePair(id, seq1, seq2)
        id += 1
        sample = SequencePairSample(seqpair,align1,align2)
        sample.aligned = aligned
        push!(pairs, sample)
      else
        seq = Sequence(seq1,phi1,psi1,ss1)
        seq.name = split(title, r">| |\t")[2]
        id += 1
        align1 = Int[i for i=1:seq.length]
        align2 = zeros(Int,seq.length)
        seqpair = SequencePair(id, seq, Sequence(0))
        seqpair.single = true
        sample = SequencePairSample(seqpair,align1,align2)
        sample.aligned = true
        sample.single = true
        push!(pairs, sample)
      end
    end
    line += 1
  end
  close(f)

  return pairs
end

export OBSERVED_DATA
OBSERVED_DATA = 1
export MISSING_DATA
MISSING_DATA = 0
export masksequences
function masksequences(seq1::Sequence, seq2::Sequence, mask::Array{Int,1})
  newseq1 = Sequence(seq1)
  newseq2 = Sequence(seq2)
  for i=1:newseq1.length
    if mask[1] == MISSING_DATA
      newseq1.seq[i] = 0
    end
    if mask[2] == MISSING_DATA
      newseq1.phi[i] = -1000.0
      newseq1.psi[i] = -1000.0
      newseq1.phi_obs[i] = -1000.0
      newseq1.psi_obs[i] = -1000.0
    end
    if mask[3] == MISSING_DATA
      newseq1.ss[i] = 0
    end
  end
  for i=1:newseq2.length
    if mask[4] == MISSING_DATA
      newseq2.seq[i] = 0
    end
    if mask[5] == MISSING_DATA
      newseq2.phi[i] = -1000.0
      newseq2.psi[i] = -1000.0
      newseq2.phi_obs[i] = -1000.0
      newseq2.psi_obs[i] = -1000.0
    end
    if mask[6] == MISSING_DATA
      newseq2.ss[i] = 0
    end
  end

  return newseq1, newseq2
end

include("AlignmentUtils.jl")
