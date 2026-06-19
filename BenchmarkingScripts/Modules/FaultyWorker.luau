-- Worker that errors on negative inputs
return function(x: number): number
	if x < 0 then
		error("negative input not allowed: " .. x)
	end
	local acc = x
	for _ = 1, 1500 do
		acc = math.sin(acc) * math.cos(acc) + math.sqrt(math.abs(acc) + 1)
	end
	return x * 2
end
