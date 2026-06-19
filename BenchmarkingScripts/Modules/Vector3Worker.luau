-- Worker for Vector3 buffer processing
return function(buf: buffer, offset: number)
	local v = Vector3.new(
		buffer.readf32(buf, offset),
		buffer.readf32(buf, offset + 4),
		buffer.readf32(buf, offset + 8)
	)
	
	local acc = v.X
	for _ = 1, 500 do
		acc = math.sin(acc) * math.cos(acc) + math.sqrt(math.abs(acc) + 1)
	end
	return Vector3.new(acc, acc, acc)
end
