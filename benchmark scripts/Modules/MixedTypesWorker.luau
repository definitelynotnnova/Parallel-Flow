return function(v)
	local t = typeof(v)
	if t == "NumberRange" then
		local acc = 0
		for i = 1, 500 do
			acc += math.sin(v.Min + (v.Max - v.Min) * (i/500))
		end
		return acc
	elseif t == "Region3" then
		local acc = 0
		local size = v.Size
		for i = 1, 300 do
			acc += math.sqrt(size.X^2 + size.Y^2 + size.Z^2) * math.sin(i)
		end
		return acc
	elseif t == "UDim2" then
		local acc = 0
		for i = 1, 500 do
			acc += math.tan(v.X.Scale * i) + math.atan(v.Y.Offset * i)
		end
		return acc
	elseif t == "Color3" then
		local r, g, b = v.R, v.G, v.B
		for i = 1, 1000 do
			r = math.sin(r * i) 
			g = math.cos(g * i) 
			b = math.tan(b * i)
		end
		return r + g + b
	elseif t == "Rect" then
		local acc = 0
		for i = 1, 500 do
			acc += (v.Width * i) % 7 + (v.Height * i) % 11
		end
		return acc
	elseif t == "Ray" then
		local acc = 0
		for i = 1, 500 do
			acc += v.Direction.Unit:Dot(v.Origin.Unit) * math.sin(i)
		end
		return acc
	elseif t == "ColorSequence" then
		local acc = 0
		for _, kp in v.Keypoints do
			for i = 1, 100 do
				acc += kp.Value.R * i + kp.Time
			end
		end
		return acc
	elseif t == "DateTime" then
		local ts = v.UnixTimestampMillis
		for i = 1, 1000 do
			ts = (ts * 1103515245 + 12345) % 2^31
		end
		return ts
	end
	return 0
end
