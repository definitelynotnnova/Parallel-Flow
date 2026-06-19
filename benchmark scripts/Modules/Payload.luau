return function(t: any): number
	local sum = t.x + t.y
	local data = t.data
	for _, v in data do
		sum += v
	end
	
	local acc = sum
	for _ = 1, 500 do
		acc = math.sin(acc) * math.cos(acc) + math.sqrt(math.abs(acc) + 1)
	end
	return acc
end
