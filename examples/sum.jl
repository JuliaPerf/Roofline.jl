using Roofline 

const bench = Roofline.intel_roofline_double()

@noinline function g(A)
    Roofline.enable!(bench)
    acc = zero(eltype(A))
    for x in A
        acc += x
    end
    Roofline.disable!(bench)
    acc
end
g(rand(1000000))
