-- Worker for nested table processing
return function(t: any)
	local sum = t.x + t.y + t.z
	for j = 1, #t.values do
		sum = sum + t.values[j] * 100
	end
	local acc = sum
	for _ = 1, 1000 do
		acc = math.sin(acc) * math.cos(acc) + math.sqrt(math.abs(acc) + 1)
	end
	return {result = acc, original = t}
end
