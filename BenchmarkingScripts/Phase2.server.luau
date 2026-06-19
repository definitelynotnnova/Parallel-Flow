--!nonstrict

local RS           = game:GetService("ReplicatedStorage")
local ParallelFlow = require(RS:WaitForChild("ParallelFlow"))
local Modules      = script.Parent:WaitForChild("Modules")
local heavyModule  = Modules:WaitForChild("Heavy")

local RUNS, WARMUP = 8, 2

local function avg(t)
	local s = 0
	for _, v in t do s += v end
	return s / #t
end
local function median(t)
	local c = table.clone(t); table.sort(c)
	local n = #c
	return n % 2 == 0 and (c[n // 2] + c[n // 2 + 1]) / 2 or c[math.ceil(n / 2)]
end
local function stddev(t, m)
	local s = 0
	for _, v in t do s += (v - m) ^ 2 end
	return math.sqrt(s / #t)
end
local function measure(fn)
	for _ = 1, WARMUP do fn() task.wait() end
	local times = table.create(RUNS)
	for i = 1, RUNS do
		local t0 = os.clock()
		fn()
		times[i] = (os.clock() - t0) * 1000
		task.wait()
	end
	return times
end
local function row(label, times, baseMean)
	local m = avg(times)
	print(string.format("  %-28s | %8.2f | %8.2f | %8.2f | %s",
		label, m, median(times), stddev(times, m),
		baseMean and string.format("%.2fx", baseMean / m) or "1.00x"))
end

local heavyFn = require(heavyModule)
local function makeNumbers(n)
	local d = table.create(n)
	for i = 1, n do d[i] = (i * 0.013) % 7 end
	return d
end
local function refSeq(data)
	local out = table.create(#data)
	for i, v in data do out[i] = heavyFn(v) end
	return out
end

print("Phase 2: Adaptive Cost Model")

local staticPool   = ParallelFlow.createPool({ size = 4, adaptive = false })
local adaptivePool = ParallelFlow.createPool({ size = 4, adaptive = true })
staticPool:prewarm(heavyModule)
adaptivePool:prewarm(heavyModule)

local SIZES = { 50, 100, 200, 300, 500, 1000, 3000 }

for _, size in ipairs(SIZES) do
	local data = makeNumbers(size)
	print(string.format("Dataset size: %d", size))
	print(string.rep("-", 70))
	print(string.format("  %-28s | %8s | %8s | %8s | %s",
		"Implementation", "Avg(ms)", "Med(ms)", "SD(ms)", "Ratio"))
	print(string.rep("-", 70))

	local seqTimes = measure(function() refSeq(data) end)
	local seqMean = avg(seqTimes)
	row("sequential", seqTimes, nil)
	row("static pool", measure(function() staticPool:map(data, heavyModule) end), seqMean)
	row("adaptive pool", measure(function() adaptivePool:map(data, heavyModule) end), seqMean)
end

-- Results
local s = adaptivePool:getStats()
local w = s.costModel and s.costModel[heavyModule.Name] or 0
local L = s.latencyFloorMs
local P = s.size
print("Cost Model Stats:")
print(string.format("  per-element cost w = %.5f ms", w))
print(string.format("  round-trip floor L = %.3f ms", L))
print(string.format("  avg round-trip     = %.3f ms", s.avgRoundTripMs))
if w > 0 then
	local crossover = L / w
	print(string.format("  computed crossover n* = %.0f elements", crossover))
end

staticPool:destroy()
adaptivePool:destroy()
print("Phase 2 complete")

