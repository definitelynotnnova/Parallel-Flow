-- Independent job for submit/coalescing benchmarks
return function(x: number): number
	local acc = x
	for _ = 1, 8000 do
		acc = math.sin(acc) * math.cos(acc) + math.sqrt(math.abs(acc) + 1)
	end
	return acc
end
