return function(input: buffer, inOffset: number, output: buffer, outOffset: number)
	local x = buffer.readf32(input, inOffset)
	local y = buffer.readf32(input, inOffset + 4)
	
	local sum = x + y
	local acc = sum
	for _ = 1, 1000 do
		acc = math.sin(acc) * math.cos(acc) + math.sqrt(math.abs(acc) + 1)
	end
	
	buffer.writef32(output, outOffset, acc)
end
