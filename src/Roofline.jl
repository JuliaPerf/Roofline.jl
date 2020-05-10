module Roofline

using LinuxPerf

@noinline function escape(x)
    Base.inferencebarrier(nothing)::Nothing
end

struct RooflineBench{F, S}
    func::F
    setup::S
    counters::Vector{LinuxPerf.Counter}
    times::Vector{UInt64}

    RooflineBench(f::F, s::S) where {F, S} = new{F, S}(f, s, LinuxPerf.Counters[], UInt64[])
end

function (bench::RooflineBench{F, S})(args...) where {F, S}
    val = bench.func(bench.setup(args...)...)
    escape(val)

    for benchPerf in (intel_roofline_bw_use(),
                      intel_roofline_memory(),
                      intel_roofline_double(),
                      intel_roofline_single(), 
                      )
        data = bench.setup(args...)
        LinuxPerf.enable!(benchPerf)
        start = Base.time_ns()
        val = bench.func(data...)
        stop = Base.time_ns()
        LinuxPerf.disable!(benchPerf)
        escape(val)
        push!(bench.times, stop-start)
        append!(bench.counters, LinuxPerf.counters(benchPerf).counters)
    end
end

function Base.show(io::IO, bench::RooflineBench)
   t = (sum(bench.times)/length(bench.times))*10e-9
   show(io, typeof(bench))
   println(io)
   show(io, "Mean duration $(t)s")
   println(io)
   results = summarize_intel(bench)
   show(io, "Double GFLOP/s $(results.dflops/t * 1e-9) ")
   println(io)
   show(io, "Single GFLOP/s $(results.sflops/t * 1e-9)")
   println(io)
   show(io, "DRAM BW GB/s $(64*results.bw_ops / t * 1e-9)") # cachelines to GB/s
   println(io)
   show(io, "MemOP per FLOP: $(results.mops / (results.sflops + results.dflops))")
   println(io)
end

function summarize_intel(bench::RooflineBench)
    dflops = 0
    dfinst = 0
    sflops = 0
    sfinst = 0
    mops = 0
    bw_ops = 0
    for counter in bench.counters
        prop = intel_properties[counter.event]
        if counter.enabled == 0 || counter.running == 0
            @info "Not counting" counter
            continue
        end
        if prop.kind === :double
            dflops += prop.mul * Int64(counter.value)
            dfinst += prop.ops * Int64(counter.value)
        elseif prop.kind === :single
            sflops += prop.mul * Int64(counter.value)
            sfinst += prop.ops * Int64(counter.value)
        elseif prop.kind === :mem
            mops += Int64(counter.value)
        elseif prop.kind === :bw
            bw_ops += Int64(counter.value)
        else
            @error "Unkown" counter prop
        end
    end
    return (;dflops=dflops, dfinst=dfinst, sflops=sflops, sinst=sfinst, mops=mops, bw_ops=bw_ops)
end

# Reading: 
# - https://crd.lbl.gov/assets/Uploads/CS267-2019-Roofline-SWWilliams.pdf
# - https://www.mjr19.org.uk/sw/mflops/
# - https://software.intel.com/sites/default/files/managed/8b/6e/335279_performance_monitoring_events_guide.pdf

import LinuxPerf: EventType, enable!, disable!, counters

const intel_properties = Dict(
    EventType(:raw, :fp_arith_inst_retired_scalar_double) => (;mul=1, vlen=1, ops=1, kind=:double),
    EventType(:raw, :fp_arith_inst_retired_128B_packed_double) => (;mul=2, vlen=2, ops=1, kind=:double),
    EventType(:raw, :fp_arith_inst_retired_256B_packed_double) => (;mul=4, vlen=4, ops=1, kind=:double),
    # EventType(:raw, :fp_arith_inst_retired_512B_packed_double) => (;mul=8, vlen=8, ops=1, kind=:double),
    EventType(:raw, :fp_arith_inst_retired_scalar_single) => (;mul=1, vlen=1, ops=1, kind=:single),
    EventType(:raw, :fp_arith_inst_retired_128B_packed_single) => (;mul=4, vlen=2, ops=1, kind=:single),
    EventType(:raw, :fp_arith_inst_retired_256B_packed_single) => (;mul=8, vlen=4, ops=1, kind=:single),
    # EventType(:raw, :fp_arith_inst_retired_512B_packed_single) => (;mul=16, vlen=8, ops=1, kind=:single),
    EventType(:raw, :mem_inst_retired_all_loads) => (;mul=1, vlen=1, ops=1, kind=:mem),
    EventType(:raw, :mem_inst_retired_all_stores) => (;mul=1, vlen=1, ops=1, kind=:mem),
    EventType(:raw, :unc_arb_trk_requests_all) => (;mul=1, vlen=1, ops=1, kind=:bw),
    EventType(:raw, :unc_arb_coh_trk_requests_all) =>  (;mul=1, vlen=1, ops=1, kind=:bw),
)

# Can't schedule them all thogether, so seperate double from single from memory.
const intel_roofline_events_double = [
    [
        EventType(:raw, :fp_arith_inst_retired_scalar_double),
        EventType(:raw, :fp_arith_inst_retired_128B_packed_double),
        EventType(:raw, :fp_arith_inst_retired_256B_packed_double),
        # EventType(:raw, :fp_arith_inst_retired_512B_packed_double),
    ],
]

const intel_roofline_events_single = [
    [
        EventType(:raw, :fp_arith_inst_retired_scalar_single),
        EventType(:raw, :fp_arith_inst_retired_128B_packed_single),
        EventType(:raw, :fp_arith_inst_retired_256B_packed_single),
        # EventType(:raw, :fp_arith_inst_retired_512B_packed_single),
    ]
]

const intel_roofline_events_memory = [
    [
        EventType(:raw, :mem_inst_retired_all_loads),
        EventType(:raw, :mem_inst_retired_all_stores)
    ]
]

# https://github.com/andikleen/pmu-tools/blob/bb9e7429903e3a9c9a14c951b1013aa991bf119c/skl_client_ratios.py#L348
# Average external Memory Bandwidth Use for reads and writes [GB / sec]
# def DRAM_BW_Use(self, EV, level):
#    return 64 *(EV("UNC_ARB_TRK_REQUESTS.ALL", level) + EV("UNC_ARB_COH_TRK_REQUESTS.ALL", level)) / OneMillion / EV("interval-s", 0) / 1000

const intel_roofline_events_bw_use = [
    [
        EventType(:raw, :unc_arb_trk_requests_all),
        EventType(:raw, :unc_arb_coh_trk_requests_all)
    ]
]

function intel_roofline_double()
    LinuxPerf.make_bench(intel_roofline_events_double)
end
function intel_roofline_single()
    LinuxPerf.make_bench(intel_roofline_events_single)
end

function summarize_intel(c)
    flops = 0
    finst = 0
    mops = 0
    for counter in c.counters
        prop = intel_properties[c.event]
        if counter.enable == 0 || c.running == 0
            @info "Not counting" c
            continue
        end
        if prop.kind === :double
            flops += prop.mul * Int64(counter.value)
            finst += prop.ops * Int64(counter.value)
        elseif prop.kind === :mem
            mops += Int64(counter.value)
        else
            @error "Unkown" c prop
        end
    end
    return (;flops=flops, finst=finst, mops=mops)
end

end # module
