using Roofline 

@noinline function experiment(A)
    acc = zero(eltype(A))
    @simd for i in eachindex(A)
        @inbounds acc += A[i]
    end
    acc
end

function setup(N)
    data = rand(Float32, N)
    return (data,)
end

bench = Roofline.benchmark(experiment, setup, 2^27)