using Roofline 

@noinline function experiment(A)
    acc = zero(eltype(A))
    @simd for i in eachindex(A)
        @inbounds acc += A[i]
    end
    acc
end

function setup(N)
    data = rand(N)
    return (data,)
end

bench = Roofline.RooflineBench(experiment, setup)
bench(2^27)