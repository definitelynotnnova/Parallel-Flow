--!nonstrict

local RS           = game:GetService("ReplicatedStorage")
local ParallelFlow = require(RS:WaitForChild("ParallelFlow"))
local Modules      = script.Parent:WaitForChild("Modules")
local jobMod       = Modules:WaitForChild("SubmitJob")

local RUNS, WARMUP = 5, 1

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
	print(string.format("  %-30s | %9.2f | %9.2f | %8.2f | %s",
		label, m, median(times), stddev(times, m),
		baseMean and string.format("%.2fx", baseMean / m) or "1.00x"))
end

local jobFn = require(jobMod)
local pool = ParallelFlow.createPool({ size = 4 })
pool:prewarm(jobMod)

local N = 100
local inputs = table.create(N)
for i = 1, N do inputs[i] = (i * 0.017) % 5 end

print("Phase 3: Independent Jobs")
print(string.rep("-", 78))
print(string.format("  %-30s | %9s | %9s | %8s | %s",
	"Implementation", "Avg(ms)", "Med(ms)", "SD(ms)", "Ratio"))
print(string.rep("-", 78))

local seqTimes = measure(function()
	for i = 1, N do jobFn(inputs[i]) end
end)
local seqMean = avg(seqTimes)
row("sequential", seqTimes, nil)

row("dispatch loop (serialized)", measure(function()
	for i = 1, N do pool:dispatch(jobMod, inputs[i]) end
end), seqMean)

row("submit + awaitAll (coalesced)", measure(function()
	local fs = table.create(N)
	for i = 1, N do fs[i] = pool:submit(jobMod, inputs[i]) end
	pool:awaitAll(fs)
end), seqMean)

pool:destroy()
print("Phase 3 complete")

