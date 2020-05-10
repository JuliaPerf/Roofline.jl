using Roofline 

@noinline function experiment(A)
    acc = zero(eltype(A))
    for i in eachindex(A)
        acc += A[i]
        A[i] = acc
    end
    acc
end

function setup()
    data = rand(1000000)
    return (data,)
end

bench = Roofline.RooflineBench(experiment, setup)
bench()