--!nonstrict

local RS           = game:GetService("ReplicatedStorage")
local ParallelFlow = require(RS:WaitForChild("ParallelFlow"))
local Modules      = script.Parent:WaitForChild("Modules")
local skewed       = Modules:WaitForChild("SkewedWorker")

local RUNS, WARMUP = 8, 2

local function avg(t)
	local s = 0
	for _, v in t do s += v end
	return s / #t
end

local function median(t)
	local c = table.clone(t)
	table.sort(c)
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
	print(string.format("  %-32s | %8.2f | %8.2f | %8.2f | %s",
		label, m, median(times), stddev(times, m),
		baseMean and string.format("%.2fx", baseMean / m) or "1.00x"))
end

-- Ramp up cost with index (skewed workload)
local function makeSkewed(n)
	local d = table.create(n)
	for i = 1, n do d[i] = i / n end
	return d
end

local skewFn = require(skewed)
local function refSeq(data)
	local out = table.create(#data)
	for i, v in data do out[i] = skewFn(v) end
	return out
end

print("Phase 1: Load Balancing")

local n = 2000
local data = makeSkewed(n)

print(string.format("Dataset: %d elements (4 workers)", n))
print(string.rep("-", 76))
print(string.format("  %-32s | %8s | %8s | %8s | %s",
	"Implementation", "Avg(ms)", "Med(ms)", "SD(ms)", "Ratio"))
print(string.rep("-", 76))

local seqTimes = measure(function() refSeq(data) end)
local seqMean = avg(seqTimes)
row("sequential", seqTimes, nil)

local statsByFactor = {}
for _, f in ipairs({ 1, 2, 4, 8 }) do
	local pool = ParallelFlow.createPool({ size = 4, loadBalanceFactor = f })
	pool:prewarm(skewed)
	local times = measure(function() pool:map(data, skewed) end)
	row(string.format("pool factor=%d", f), times, seqMean)
	statsByFactor[f] = pool:getStats()
	pool:destroy()
end

print("Work distribution:")
for _, f in ipairs({ 1, 4, 8 }) do
	local s = statsByFactor[f]
	local pw = {}
	for i = 1, s.size do pw[i] = tostring(s.perWorker[i]) end
	print(string.format("  factor=%d  ->  [%s]   avgMs=%.3f  jobs=%d",
		f, table.concat(pw, ", "), s.avgRoundTripMs, s.dispatched))
end

print("Phase 1 complete")

