-- Worker for data where cost grows with input value
return function(x: number): number
	local iters = 50 + math.floor(x * x * 3000)
	local acc = x
	for _ = 1, iters do
		acc = math.sin(acc) * math.cos(acc) + math.sqrt(math.abs(acc) + 1)
	end
	return acc
end
