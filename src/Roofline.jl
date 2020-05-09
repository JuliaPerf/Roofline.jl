module Roofline

# Reading: 
# - https://crd.lbl.gov/assets/Uploads/CS267-2019-Roofline-SWWilliams.pdf
# - https://www.mjr19.org.uk/sw/mflops/
# - https://software.intel.com/sites/default/files/managed/8b/6e/335279_performance_monitoring_events_guide.pdf
using LinuxPerf

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
    EventType(:raw, :mem_inst_retired_all_stores) => (;mul=1, vlen=1, ops=1, kind=:mem)
)


const intel_roofline_events_double = [
    [
        EventType(:raw, :fp_arith_inst_retired_scalar_double),
        EventType(:raw, :fp_arith_inst_retired_128B_packed_double),
        EventType(:raw, :fp_arith_inst_retired_256B_packed_double),
        # EventType(:raw, :mem_inst_retired_all_loads),
        # EventType(:raw, :mem_inst_retired_all_stores)
    ]
]

const intel_roofline_events_single = [
    [
        EventType(:raw, :fp_arith_inst_retired_scalar_single),
        EventType(:raw, :fp_arith_inst_retired_128B_packed_single),
        EventType(:raw, :fp_arith_inst_retired_256B_packed_single),
        # EventType(:raw, :mem_inst_retired_all_loads),
        # EventType(:raw, :mem_inst_retired_all_stores)
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
