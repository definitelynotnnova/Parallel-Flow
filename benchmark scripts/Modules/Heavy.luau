return function(x: number): number
	local acc = x
	for _ = 1, 2000 do
		acc = math.sin(acc) * math.cos(acc) + math.sqrt(math.abs(acc) + 1)
	end
	return acc
end
