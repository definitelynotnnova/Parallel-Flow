-- Read directly from buffer for efficiency
return function(view: buffer, offset: number)
	local x = buffer.readf32(view, offset)
	local y = buffer.readf32(view, offset + 4)
	
	-- Heavy compute
	local acc = x + y
	for _ = 1, 2000 do
		acc = math.sin(acc) * math.cos(acc) + math.sqrt(math.abs(acc) + 1)
	end
	return acc
end
