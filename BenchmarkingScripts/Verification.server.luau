--!nonstrict

local RS           = game:GetService("ReplicatedStorage")
local PF           = RS:WaitForChild("ParallelFlow")
local ParallelFlow = require(PF)
local Serializer   = require(PF.Serializer)

local Modules       = script.Parent:WaitForChild("Modules")
local heavyModule   = Modules:WaitForChild("Heavy")
local vec3Worker    = Modules:WaitForChild("Vector3Worker")
local tableWorker   = Modules:WaitForChild("NestedTableWorker")
local bufferIO      = Modules:WaitForChild("BufferIO")
local bufferPayload = Modules:WaitForChild("BufferPayload")


local passed, failed = 0, 0
local failures = {}

local function check(name, cond, detail)
	if cond then
		passed += 1
	else
		failed += 1
		local line = name .. (detail and ("  ->  " .. tostring(detail)) or "")
		table.insert(failures, line)
		warn("[FAIL] " .. line)
	end
end


local function approxEqual(a, b, tol)
	tol = tol or 1e-5
	local ta, tb = typeof(a), typeof(b)
	if ta ~= tb then return false end

	if ta == "number" then
		return math.abs(a - b) <= tol * (1 + math.abs(b))
	elseif ta == "boolean" or ta == "string" then
		return a == b
	elseif ta == "nil" then
		return true
	elseif ta == "Vector3" then
		return approxEqual(a.X, b.X, tol) and approxEqual(a.Y, b.Y, tol) and approxEqual(a.Z, b.Z, tol)
	elseif ta == "Vector2" then
		return approxEqual(a.X, b.X, tol) and approxEqual(a.Y, b.Y, tol)
	elseif ta == "Color3" then
		return approxEqual(a.R, b.R, tol) and approxEqual(a.G, b.G, tol) and approxEqual(a.B, b.B, tol)
	elseif ta == "CFrame" then
		local ca = { a:GetComponents() }
		local cb = { b:GetComponents() }
		for i = 1, 12 do
			if not approxEqual(ca[i], cb[i], tol) then return false end
		end
		return true
	elseif ta == "buffer" then
		if buffer.len(a) ~= buffer.len(b) then return false end
		for i = 0, buffer.len(a) - 1 do
			if buffer.readu8(a, i) ~= buffer.readu8(b, i) then return false end
		end
		return true
	elseif ta == "table" then
		for k, v in a do
			if not approxEqual(v, b[k], tol) then return false end
		end
		for k, v in b do
			if a[k] == nil and v ~= nil then return false end
		end
		return true
	else
		return a == b
	end
end

local function arraysApproxEqual(a, b, tol)
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	if #a ~= #b then return false end
	for i = 1, #a do
		if not approxEqual(a[i], b[i], tol) then return false end
	end
	return true
end


local function buffersF32Equal(a, b, tol)
	if typeof(a) ~= "buffer" or typeof(b) ~= "buffer" then return false end
	if buffer.len(a) ~= buffer.len(b) then return false end
	local n = buffer.len(a) // 4
	for i = 0, n - 1 do
		if not approxEqual(buffer.readf32(a, i * 4), buffer.readf32(b, i * 4), tol or 1e-4) then
			return false
		end
	end
	return true
end


local function makeNumbers(n)
	local d = table.create(n)
	for i = 1, n do d[i] = (i * 0.013) % 7 end
	return d
end

local function makeVectors(n)
	local d = table.create(n)
	for i = 1, n do d[i] = Vector3.new((i * 0.13) % 9, (i * 0.07) % 5, (i * 0.21) % 3) end
	return d
end

local function makeNestedTables(n)
	local d = table.create(n)
	for i = 1, n do
		d[i] = {
			x = (i * 0.011) % 4,
			y = (i * 0.017) % 6,
			z = (i * 0.019) % 8,
			values = { (i * 0.1) % 2, (i * 0.2) % 3, (i * 0.3) % 5 },
		}
	end
	return d
end

local function makeNumberBuffer(n)
	local buf = buffer.create(n * 8)
	for i = 0, n - 1 do
		buffer.writef32(buf, i * 8,     ((i + 1) * 0.013) % 7)
		buffer.writef32(buf, i * 8 + 4, ((i + 1) * 0.017) % 5)
	end
	return buf
end

print("A. Serializer round-trip")

local function roundtrip(name, value, tol)
	local ok, decoded = pcall(function()
		return Serializer.decode(Serializer.encode(value))
	end)
	check("encode/decode: " .. name, ok and approxEqual(value, decoded, tol or 1e-4), ok and "value mismatch" or decoded)
end

roundtrip("nil", nil)
roundtrip("boolean true", true)
roundtrip("boolean false", false)
roundtrip("integer", 123456)
roundtrip("negative int", -98765)
roundtrip("float", 3.14159265358979)
roundtrip("string", "hello parallel flow")
roundtrip("empty string", "")
roundtrip("small array (<8)", { 1, 2, 3 })
roundtrip("number array (T_ANUM)", makeNumbers(64), 1e-9)
roundtrip("vector3 array (T_AV3)", makeVectors(64), 1e-3)
roundtrip("cframe array (T_ACF)", { CFrame.new(1, 2, 3), CFrame.new(4, 5, 6), CFrame.Angles(0.1, 0.2, 0.3),
	CFrame.new(7, 8, 9), CFrame.new(0, 0, 0), CFrame.new(1, 1, 1), CFrame.new(2, 2, 2),
	CFrame.new(3, 3, 3), CFrame.new(4, 4, 4) }, 1e-3)
roundtrip("nested array", { { 1, 2 }, { 3, 4 }, { 5, { 6, 7 } } })
roundtrip("map", { alpha = 1, beta = "two", gamma = true })
roundtrip("deep nested (recursion/state)", { a = { b = { c = { 1, 2, 3 } } }, list = { 10, 20, 30 }, name = "x" })
roundtrip("mixed array", { 1, "two", true, Vector3.new(1, 2, 3) }, 1e-3)
roundtrip("Vector2", Vector2.new(3.5, -7.25), 1e-3)
roundtrip("Color3", Color3.new(0.2, 0.4, 0.8), 1e-3)
roundtrip("UDim2", UDim2.new(0.5, 10, 0.25, -4), 1e-3)
roundtrip("Rect", Rect.new(1, 2, 30, 40), 1e-3)
roundtrip("NumberRange", NumberRange.new(2, 9), 1e-3)


do
	local b = buffer.create(16)
	for i = 0, 15 do buffer.writeu8(b, i, (i * 7) % 256) end
	roundtrip("raw buffer (T_BUF)", b)
end


do
	local data = makeNumbers(100)
	local enc = Serializer.encode(data, 10, 19)
	local dec = Serializer.decode(enc)
	local expected = table.create(10)
	for i = 10, 19 do expected[i - 9] = data[i] end
	check("encode(data, start, finish) sub-array", arraysApproxEqual(dec, expected, 1e-9), #dec .. " elems")
end


do
	local data = table.create(20)
	for i = 1, 20 do data[i] = { a = i, b = i * 2, c = "k" .. i } end
	local dec = Serializer.decode(Serializer.encode(data, 1, 20))
	check("schema map array (T_SMAP)", arraysApproxEqual(dec, data), "struct mismatch")
end

print("B. Pool method correctness")

local pool = ParallelFlow.createPool({ size = 4 })
pool:prewarm(heavyModule)
pool:prewarm(vec3Worker)
pool:prewarm(tableWorker)
pool:prewarm(bufferPayload)
pool:prewarm(bufferIO)

local hfn = require(heavyModule)
local vfn = require(vec3Worker)
local tfn = require(tableWorker)
local bpfn = require(bufferPayload)
local biofn = require(bufferIO)


local function refHeavy(data)
	local out = table.create(#data)
	for i, v in data do out[i] = hfn(v) end
	return out
end

local function refVec3(data)
	local out = table.create(#data)
	local b = buffer.create(12)
	for i, v in data do
		buffer.writef32(b, 0, v.X); buffer.writef32(b, 4, v.Y); buffer.writef32(b, 8, v.Z)
		out[i] = vfn(b, 0)
	end
	return out
end

local function refTables(data)
	local out = table.create(#data)
	for i, v in data do out[i] = tfn(v) end
	return out
end


do
	local x = 0.737
	local expected = hfn(x)
	local r1 = pool:dispatch(heavyModule, x)
	local r2 = pool:dispatch(heavyModule, x)
	local r3 = pool:dispatch(heavyModule, x)
	check("dispatch float run1", approxEqual(r1, expected, 1e-6), "got " .. tostring(r1))
	check("dispatch float run2", approxEqual(r2, expected, 1e-6), "got " .. tostring(r2))
	check("dispatch float run3", approxEqual(r3, expected, 1e-6), "got " .. tostring(r3))

	local ri = pool:dispatch(heavyModule, 42)
	check("dispatch int", approxEqual(ri, hfn(42), 1e-6), "got " .. tostring(ri))

	
	local rt = pool:dispatch(tableWorker, { x = 1, y = 2, z = 3, values = { 0.1, 0.2 } })
	check("dispatch table payload", type(rt) == "table" and rt.result ~= nil, "got " .. typeof(rt))
end


do
	local data = makeNumbers(10)
	check("map small (<50, sequential branch)", arraysApproxEqual(pool:map(data, heavyModule), refHeavy(data), 1e-6))
end

-- map: large (parallel branch)
do
	local data = makeNumbers(500)
	check("map large (parallel branch)", arraysApproxEqual(pool:map(data, heavyModule), refHeavy(data), 1e-6))
end

do
	local data = makeNestedTables(300)
	check("mapTables", arraysApproxEqual(pool:mapTables(data, tableWorker), refTables(data), 1e-6))
end


do
	local data = makeVectors(300)
	check("mapVector3", arraysApproxEqual(pool:mapVector3(data, vec3Worker), refVec3(data), 1e-4))
end

do
	local n = 300
	local buf = makeNumberBuffer(n)
	local expected = table.create(n)
	for i = 1, n do expected[i] = bpfn(buf, (i - 1) * 8) end
	check("mapBuffer", arraysApproxEqual(pool:mapBuffer(buf, 8, bufferPayload), expected, 1e-6))
end


do
	local n = 300
	local buf = makeNumberBuffer(n)
	local expected = buffer.create(n * 4)
	for i = 0, n - 1 do biofn(buf, i * 8, expected, i * 4) end
	local got = pool:mapBufferOut(buf, 8, 4, bufferIO)
	check("mapBufferOut", buffersF32Equal(got, expected, 1e-4),
		typeof(got) == "buffer" and ("len " .. buffer.len(got) .. " vs " .. buffer.len(expected)) or ("type " .. typeof(got)))
end


do
	local nums = makeNumbers(200)
	check("Map -> numbers (map)", arraysApproxEqual(pool:Map(nums, heavyModule), refHeavy(nums), 1e-6))

	local vecs = makeVectors(200)
	check("Map -> Vector3 (mapVector3)", arraysApproxEqual(pool:Map(vecs, vec3Worker), refVec3(vecs), 1e-4))

	local n = 200
	local buf = makeNumberBuffer(n)
	local expected = table.create(n)
	for i = 1, n do expected[i] = bpfn(buf, (i - 1) * 8) end
	check("Map -> buffer (mapBuffer)", arraysApproxEqual(pool:Map(buf, bufferPayload), expected, 1e-6))
end


do
	local data = makeNumbers(120)
	local out = pool:filter(data, heavyModule)
	check("filter keeps truthy + order", #out == #data and arraysApproxEqual(out, data, 1e-9), #out .. "/" .. #data)
end

do
	local data = makeNumbers(200)
	local expected = table.create(#data)
	for i, v in data do expected[i] = hfn(hfn(v)) end
	check("Pipeline two stages", arraysApproxEqual(pool:Pipeline(data, { heavyModule, heavyModule }), expected, 1e-6))
end


do
	local data = makeNumbers(200)
	local t = pool:mapAsync(data, heavyModule)
	t:Wait()
	check("mapAsync completes", not t:IsCancelled())
end

print("C. Phase 1 features")

do
	if pool.getStats then
		local s = pool:getStats()
		local perWorkerSum = 0
		if s.perWorker then for _, c in s.perWorker do perWorkerSum += c end end
		check("getStats: size", s.size == 4, tostring(s.size))
		check("getStats: dispatched > 0", (s.dispatched or 0) > 0, tostring(s.dispatched))
		check("getStats: completed <= dispatched", (s.completed or 0) <= (s.dispatched or 0))
		check("getStats: perWorker sums to dispatched", perWorkerSum == (s.dispatched or -1), perWorkerSum .. " vs " .. tostring(s.dispatched))
		check("getStats: avgRoundTripMs is number >= 0", type(s.avgRoundTripMs) == "number" and s.avgRoundTripMs >= 0, tostring(s.avgRoundTripMs))
	else
		check("getStats exists", false, "Pool:getStats not implemented yet")
	end
end

do
	local data = makeNumbers(800)
	local balancedPool = ParallelFlow.createPool({ size = 4, loadBalanceFactor = 4 })
	balancedPool:prewarm(heavyModule)
	local base = pool:map(data, heavyModule)
	local bal  = balancedPool:map(data, heavyModule)
	check("loadBalanceFactor preserves map results", arraysApproxEqual(base, bal, 1e-6))
	balancedPool:destroy()
end

do
	local ok = pcall(function()
		pool:mapInto({ 1, 2, 3 }, {}, heavyModule)
	end)
	check("mapInto rejects plain table target", not ok)
end

do
	local okShared, ST = pcall(function() return SharedTable end)
	if okShared and ST then
		local n = 100
		local data = makeNumbers(n)
		local target = ST.new()
		local ok = pcall(function() pool:mapInto(data, target, heavyModule) end)
		local allGood = ok
		if ok then
			for i = 1, n do
				if not approxEqual(target[i], hfn(data[i]), 1e-6) then allGood = false; break end
			end
		end
		check("mapInto writes into SharedTable", allGood, ok and "value mismatch" or "call failed")
	else
		print("  (SharedTable unavailable, skipping mapInto-shared test)")
	end
end

print("D. Phase 2 adaptive cost model")
do
	local apool = ParallelFlow.createPool({ size = 4, adaptive = true })
	apool:prewarm(heavyModule)

	local small = makeNumbers(20)
	local large = makeNumbers(800)
	check("adaptive map small correct", arraysApproxEqual(apool:map(small, heavyModule), refHeavy(small), 1e-6))
	check("adaptive map large correct", arraysApproxEqual(apool:map(large, heavyModule), refHeavy(large), 1e-6))

	local s = apool:getStats()
	local w = s.costModel and s.costModel[heavyModule.Name]
	check("adaptive learned per-elem cost", type(w) == "number" and w > 0, "w=" .. tostring(w))

	local spool = ParallelFlow.createPool({ size = 4, adaptive = false })
	spool:prewarm(heavyModule)
	check("static pool still correct", arraysApproxEqual(spool:map(large, heavyModule), refHeavy(large), 1e-6))

	apool:destroy()
	spool:destroy()
end

print("E. Phase 3 submit & coalescing")
do
	local f = pool:submit(heavyModule, 0.5)
	local r = f:Await()
	check("submit single Await returns value", approxEqual(r, hfn(0.5), 1e-6), "got " .. tostring(r))
	check("submit future IsCompleted", f:IsCompleted() == true)

	local N = 60
	local futures = table.create(N)
	local expected = table.create(N)
	for i = 1, N do
		local x = (i * 0.013) % 7
		expected[i] = hfn(x)
		futures[i] = pool:submit(heavyModule, x)
	end
	local results = pool:awaitAll(futures)
	check("awaitAll length", #results == N, #results .. "/" .. N)
	check("awaitAll correct & ordered", arraysApproxEqual(results, expected, 1e-6))

	local p1 = ParallelFlow.createPool({ size = 1 })
	local g1 = p1:submit(heavyModule, 0.3)
	local g2 = p1:submit(tableWorker, { x = 1, y = 2, z = 3, values = { 0.1, 0.2 } })
	local gr1 = g1:Await()
	local gr2 = g2:Await()
	check("batch mixed modules: heavy", approxEqual(gr1, hfn(0.3), 1e-6), "got " .. tostring(gr1))
	check("batch mixed modules: table", type(gr2) == "table" and gr2.result ~= nil, "got " .. typeof(gr2))
	p1:destroy()

	local fired = false
	local fc = pool:submit(heavyModule, 0.7)
	fc:OnComplete(function(_, ok) fired = (ok == true) end)
	fc:Await()
	task.wait()
	check("submit OnComplete fired", fired)
end

print("F. Phase 4 error handling")
do
	local faulty = Modules:WaitForChild("FaultyWorker")
	pool:prewarm(faulty)

	
	local N = 400
	local data = table.create(N)
	for i = 1, N do data[i] = i end
	data[50] = -1; data[200] = -2; data[395] = -3
	local badIdx = { [50] = true, [200] = true, [395] = true }

	local results, errors = pool:map(data, faulty)

	local validOk = true
	for i = 1, N do
		if badIdx[i] then
			if results[i] ~= nil then validOk = false end
		elseif results[i] ~= data[i] * 2 then
			validOk = false
		end
	end
	check("continue: valid results correct, bad slots nil", validOk)
	check("continue: errors is a table", type(errors) == "table")
	if type(errors) == "table" then
		check("continue: error count == 3", #errors == 3, "#=" .. #errors)
		local gotIdx, haveMsg = {}, true
		for _, e in errors do
			gotIdx[e.index] = true
			if type(e.message) ~= "string" or e.message == "" then haveMsg = false end
		end
		check("continue: error indices match (50,200,395)", gotIdx[50] and gotIdx[200] and gotIdx[395])
		check("continue: errors carry messages", haveMsg)
	end

	local goodData = table.create(N)
	for i = 1, N do goodData[i] = i end
	local r2, e2 = pool:map(goodData, faulty)
	check("continue: clean map has nil errors", e2 == nil)
	check("continue: clean map correct", r2[1] == 2 and r2[N] == N * 2)

	local small = { 1, 2, 3, -4, 5 }
	local sres, serr = pool:map(small, faulty)
	check("continue: sequential path isolates", sres[1] == 2 and sres[5] == 10 and sres[4] == nil)
	check("continue: sequential path reports error", type(serr) == "table" and serr[1].index == 4)

	local strictPool = ParallelFlow.createPool({ size = 4, errorMode = "strict" })
	strictPool:prewarm(faulty)
	check("strict: map throws on element error", not pcall(function() strictPool:map(data, faulty) end))
	local sok, sclean = pcall(function() return strictPool:map(goodData, faulty) end)
	check("strict: clean data ok", sok and sclean[1] == 2)
	strictPool:destroy()

	local fGood  = pool:submit(faulty, 7)
	local fBad   = pool:submit(faulty, -9)
	local fGood2 = pool:submit(faulty, 11)
	local rg, rb, rg2 = fGood:Await(), fBad:Await(), fGood2:Await()
	check("submit: good job correct", rg == 14, "got " .. tostring(rg))
	check("submit: bad job isolated (nil, completed)", rb == nil and fBad:IsCompleted() == true)
	check("submit: sibling good job unaffected", rg2 == 22, "got " .. tostring(rg2))
end


pool:destroy()

print("Verification Summary")
print(string.format("PASS: %d  FAIL: %d", passed, failed))
if failed > 0 then
	for _, f in failures do print("  Fail: " .. f) end
	print("NO MERGE: Fix issues first.")
else
	print("All tests passed.")
end
