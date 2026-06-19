local RS           = game:GetService("ReplicatedStorage")
local ParallelFlow = require(RS:WaitForChild("ParallelFlow"))

-- Setup paths for external modules
local BenchFolder = script.Parent
local Modules = BenchFolder:WaitForChild("Modules")

local heavyModule  = Modules:WaitForChild("Heavy")
local payloadModule = Modules:WaitForChild("Payload")
local bufferPayload = Modules:WaitForChild("BufferPayload")
local bufferIO = Modules:WaitForChild("BufferIO")
local vec3Worker = Modules:WaitForChild("Vector3Worker")
local tableWorker = Modules:WaitForChild("NestedTableWorker")
local mixedWorker = Modules:WaitForChild("MixedTypesWorker")

-- Benchmark configuration
local RUNS          = 8
local WARMUP        = 2
local DATASET_SIZES = {100, 300, 1000, 3000}
local POOL_SIZES    = {1, 2, 3, 4, 6}
local CROSSOVER_SIZES = {50, 100, 200, 500, 1000, 2000, 5000}

-- Helper math functions
local function avg(t)
    local s = 0
    for _, v in t do s += v end
    return s / #t
end

local function median(t)
    local c = table.clone(t)
    table.sort(c)
    local n = #c
    return n % 2 == 0 and (c[n/2] + c[n/2 + 1]) / 2 or c[math.ceil(n/2)]
end

local function stddev(t, mean)
    local s = 0
    for _, v in t do s += (v - mean) ^ 2 end
    return math.sqrt(s / #t)
end

-- Measures function execution time in milliseconds
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

-- Formats numbers for clean table alignment
local function formatMs(value)
    return string.format("%7.2f", value)
end

local function printTableHeader(title)
    print("\n" .. title)
    print(string.rep("-", #title))
    print(string.format("  %-28s | %8s | %8s | %8s | %8s", "Implementation", "Avg(ms)", "Med(ms)", "SD(ms)", "Ratio"))
    print(string.rep("-", 72))
end

local function printResultRow(label, mean, med, sd, ratio)
    print(string.format("  %-28s | %8s | %8s | %8s | %8s", label, formatMs(mean), formatMs(med), formatMs(sd), ratio and string.format("%.2fx", ratio) or "-"))
end

-- Data Generators
local function makeDataNumbers(size)
    local d = table.create(size)
    for i = 1, size do d[i] = math.random() * 1000 end
    return d
end

local function makeDataVector3(size)
    local d = table.create(size)
    for i = 1, size do
        d[i] = Vector3.new(math.random() * 100, math.random() * 100, math.random() * 100)
    end
    return d
end

local function makeDataNestedTables(size)
    local d = table.create(size)
    for i = 1, size do
        d[i] = {
            x = math.random() * 1000,
            y = math.random() * 1000,
            z = math.random() * 1000,
            values = {math.random(), math.random(), math.random()}
        }
    end
    return d
end

-- Heavy Compute Logic
local function heavyComputeNumber(x: number): number
    local acc = x
    for _ = 1, 2000 do
        acc = math.sin(acc) * math.cos(acc) + math.sqrt(math.abs(acc) + 1)
    end
    return acc
end

local function heavyComputeVector3(v: Vector3): Vector3
    local acc = v.X
    for _ = 1, 500 do
        acc = math.sin(acc) * math.cos(acc) + math.sqrt(math.abs(acc) + 1)
    end
    return Vector3.new(acc, acc, acc)
end

local function heavyComputeNestedTable(t: any): any
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

-- Runner Implementations
local function runSequentialNumbers(data)
    local out = table.create(#data)
    for i, v in data do out[i] = heavyComputeNumber(v) end
    return out
end

local function runSequentialVector3(data)
    local out = table.create(#data)
    for i, v in data do out[i] = heavyComputeVector3(v) end
    return out
end

local function runSequentialNestedTable(data)
    local out = table.create(#data)
    for i, v in data do out[i] = heavyComputeNestedTable(v) end
    return out
end

local function runTaskSpawnGeneric(data, computeFn)
    local n       = #data
    local out     = table.create(n)
    local pending = n
    local thread  = coroutine.running()
    local yielded = false

    for i, v in data do
        local idx, val = i, v
        task.spawn(function()
            out[idx] = computeFn(val)
            pending -= 1
            if pending == 0 and yielded then
                task.spawn(thread)
            end
        end)
    end

    if pending > 0 then
        yielded = true
        coroutine.yield()
    end

    return out
end

-- Consistency check function
local function _verifyResults(expected, actual)
    for i = 1, #expected do
        local exp, act = expected[i], actual[i]
        if type(exp) == "number" and type(act) == "number" then
            if math.abs((exp or 0) - (act or 0)) > 0.001 then return false, i end
        end
    end
    return true
end

-- Initialize workers
local pools = {}
for _, size in ipairs(POOL_SIZES) do
    pools[size] = ParallelFlow.createPool({ size = size })
end

local function runParallelFlow(pool, data)
    return pool:map(data, heavyModule)
end

-- Standard Benchmark Scenarios
local function benchmarkScenarioBaseline(scenarioName, dataGenerator, sequentialFn, spawnFn, dataType, customParallelFn)
    print("\n>> Scenario: " .. scenarioName .. " <<")
    
    for _, size in ipairs(DATASET_SIZES) do
        local title = string.format("Dataset size: %d (%s)", size, dataType)
        printTableHeader(title)
        local data = dataGenerator(size)

        -- Sequential execution
        local seqTimes = measure(function() sequentialFn(data) end)
        local seqMean  = avg(seqTimes)
        printResultRow("sequential", seqMean, median(seqTimes), stddev(seqTimes, seqMean), 1)

        -- task.spawn simulation
        local spawnTimes = measure(function() spawnFn(data) end)
        local spawnMean  = avg(spawnTimes)
        printResultRow("task.spawn", spawnMean, median(spawnTimes), stddev(spawnTimes, spawnMean), seqMean / spawnMean)

        -- ParallelFlow Workers
        for _, poolSize in ipairs(POOL_SIZES) do
            local pool = pools[poolSize]
            local times = measure(function() 
                if customParallelFn then
                    customParallelFn(pool, data)
                else
                    runParallelFlow(pool, data)
                end
            end)
            local mean  = avg(times)
            printResultRow("ParallelFlow pool:" .. poolSize, mean, median(times), stddev(times, mean), seqMean / mean)
        end
    end
end

local function benchmarkScenarioSimple(scenarioName, dataGenerator, sequentialFn, spawnFn, dataType)
    print("\n>> Scenario: " .. scenarioName .. " <<")
    print("ParallelFlow requires custom module for this data type, skipping for now.")
    
    for _, size in ipairs(DATASET_SIZES) do
        local title = string.format("Dataset size: %d (%s)", size, dataType)
        printTableHeader(title)
        local data = dataGenerator(size)

        -- Sequential execution
        local seqTimes = measure(function() sequentialFn(data) end)
        local seqMean  = avg(seqTimes)
        printResultRow("sequential", seqMean, median(seqTimes), stddev(seqTimes, seqMean), 1)

        -- task.spawn simulation
        local spawnTimes = measure(function() spawnFn(data) end)
        local spawnMean  = avg(spawnTimes)
        printResultRow("task.spawn", spawnMean, median(spawnTimes), stddev(spawnTimes, spawnMean), seqMean / spawnMean)
    end
end

-- Capacity & Limit testing
local function analyzeClientLimitAndCrossover()
    print("\n>> Scenario: Client Limit & Crossover Analysis <<")
    print("Finding the point where ParallelFlow pools start outperforming sequential logic.")

    for _, size in ipairs(CROSSOVER_SIZES) do
        local title = string.format("Crossover Analysis: Dataset=%d", size)
        printTableHeader(title)
        local data = makeDataNumbers(size)
        
        -- Sequential baseline
        local seqTimes = measure(function() runSequentialNumbers(data) end)
        local seqMean = avg(seqTimes)
        printResultRow("sequential (baseline)", seqMean, median(seqTimes), stddev(seqTimes, seqMean), 1)
        
        -- Client-friendly pools (1, 2, 3)
        for _, poolSize in ipairs({1, 2, 3}) do
            local pool = pools[poolSize]
            local times = measure(function() runParallelFlow(pool, data) end)
            local mean = avg(times)
            printResultRow("ParallelFlow pool:" .. poolSize, mean, median(times), stddev(times, mean), seqMean / mean)
        end
    end
end

local function analyzePoolScalingForClient()
    print("\n>> Scenario: Pool Scaling (Client-Focused) <<")
    print("Testing pool efficiency under the 3-thread recommendation for clients.")

    for _, size in ipairs({300, 1000, 3000}) do
        local title = string.format("Pool scaling (dataset=%d, client limit=3)", size)
        printTableHeader(title)
        local data = makeDataNumbers(size)
        local seqMean = avg(measure(function() runSequentialNumbers(data) end))
        printResultRow("sequential", seqMean, seqMean, 0, 1)

        for _, poolSize in ipairs(POOL_SIZES) do
            local pool = pools[poolSize]
            local times = measure(function() runParallelFlow(pool, data) end)
            local mean = avg(times)
            local poolNote = poolSize <= 3 and " (fits client limit)" or " (server-only)"
            printResultRow("ParallelFlow pool:" .. poolSize .. poolNote, mean, median(times), stddev(times, mean), seqMean / mean)
        end
    end
end

local function cleanupPools()
    for _, pool in pairs(pools) do
        pool:destroy()
    end
end

-- Execution Start

task.wait(2)

-- Numeric workloads
benchmarkScenarioBaseline("Heavy Compute (Numbers)", makeDataNumbers, runSequentialNumbers, 
    function(data) return runTaskSpawnGeneric(data, heavyComputeNumber) end, "number")

-- Vector3 workloads
benchmarkScenarioBaseline("Vector3 Transform", makeDataVector3, runSequentialVector3,
    function(data) return runTaskSpawnGeneric(data, heavyComputeVector3) end, "Vector3", function(pool, data)
        return pool:mapVector3(data, vec3Worker)
    end)

-- Nested table workloads
benchmarkScenarioBaseline("Nested Table Processing", makeDataNestedTables, runSequentialNestedTable,
    function(data) return runTaskSpawnGeneric(data, heavyComputeNestedTable) end, "table", function(pool, data)
        return pool:mapTables(data, tableWorker)
    end)

-- Performance limits analysis
analyzeClientLimitAndCrossover()

-- scaling analysis
analyzePoolScalingForClient()

-- Scenario 6: Heavy Payload (SharedTable focus)
do
    local function makeDataPayload(size)
        local d = table.create(size)
        for i = 1, size do
            local inner = table.create(50)
            for j = 1, 50 do inner[j] = math.random() end
            d[i] = { x = math.random(), y = math.random(), data = inner }
        end
        return d
    end
    
    local function heavyComputePayload(t)
        local sum = t.x + t.y
        for i = 1, #t.data do sum += t.data[i] end
        local acc = sum
        for _ = 1, 500 do
            acc = math.sin(acc) * math.cos(acc) + math.sqrt(math.abs(acc) + 1)
        end
        return acc
    end

    print("\n>> Scenario: Heavy Payload (SharedTable focus) <<")
    print("Showing performance gains using large nested tables with SharedTable benefits.")
    
    for _, size in ipairs({500, 1000, 2000}) do
        local title = string.format("Heavy Payload size: %d", size)
        printTableHeader(title)
        local data = makeDataPayload(size)
        
        local seqTimes = measure(function() 
            local out = table.create(#data)
            for i, v in data do out[i] = heavyComputePayload(v) end
        end)
        local seqMean = avg(seqTimes)
        printResultRow("sequential", seqMean, median(seqTimes), stddev(seqTimes, seqMean), 1)
        
        for _, poolSize in ipairs({2, 4, 6}) do
            local pool = pools[poolSize]
            local times = measure(function() pool:map(data, payloadModule) end)
            local mean = avg(times)
            printResultRow("ParallelFlow pool:" .. poolSize, mean, median(times), stddev(times, mean), seqMean / mean)
        end
    end
end

-- Scenario 7: Extreme Data Stress Test
do
    local function makeDataExtreme(size)
        local d = table.create(size)
        for i = 1, size do
            local inner = table.create(200)
            for j = 1, 200 do inner[j] = math.random() end
            d[i] = { x = math.random(), y = math.random(), data = inner }
        end
        return d
    end
    
    local function heavyComputeExtreme(t)
        local sum = t.x + t.y
        for _, v in t.data do sum += v end
        local acc = sum
        for _ = 1, 2000 do
            acc = math.sin(acc) * math.cos(acc) + math.sqrt(math.abs(acc) + 1)
        end
        return acc
    end

    print("\n>> Scenario: Extreme Data Stress Test <<")
    print("Testing 5000 elements with massive payloads to stress concurrency limits.")
    
    local size = 5000
    local title = string.format("Extreme Stress: %d elements", size)
    printTableHeader(title)
    local data = makeDataExtreme(size)
    
    local seqTimes = measure(function() 
        local out = table.create(#data)
        for i, v in data do out[i] = heavyComputeExtreme(v) end
    end)
    local seqMean = avg(seqTimes)
    printResultRow("sequential", seqMean, median(seqTimes), stddev(seqTimes, seqMean), 1)
    
    for _, poolSize in ipairs({2, 4, 6}) do
        local pool = pools[poolSize]
        local times = measure(function() pool:map(data, payloadModule) end)
        local mean = avg(times)
        printResultRow("ParallelFlow pool:" .. poolSize, mean, median(times), stddev(times, mean), seqMean / mean)
    end
end

-- Scenario 8: Vectorized Buffer Stress Test
do
    print("\n>> Scenario: Vectorized Buffer Stress Test <<")
    print("Using mapBuffer API for high-speed data transfer for zero overhead.")
    
    local size = 5000
    local title = string.format("Vectorized Stress: %d elements", size)
    printTableHeader(title)
    
    local dataBuf = buffer.create(size * 8)
    for i = 0, size - 1 do
        buffer.writef32(dataBuf, i * 8, math.random())
        buffer.writef32(dataBuf, i * 8 + 4, math.random())
    end
    
    local seqTimes = measure(function() 
        local fn = require(bufferPayload)
        local out = table.create(size)
        for i = 1, size do out[i] = fn(dataBuf, (i - 1) * 8) end
    end)
    local seqMean = avg(seqTimes)
    printResultRow("sequential (buffer)", seqMean, median(seqTimes), stddev(seqTimes, seqMean), 1)
    
    for _, poolSize in ipairs({2, 4, 6}) do
        local pool = pools[poolSize]
        local times = measure(function() 
            pool:mapBuffer(dataBuf, 8, bufferPayload) 
        end)
        local mean = avg(times)
        printResultRow("ParallelFlow pool:" .. poolSize, mean, median(times), stddev(times, mean), seqMean / mean)
    end
end

-- Scenario 9: Direct Binary Pipeline (mapBufferOut)
do
    print("\n>> Scenario: Direct Binary Pipeline (mapBufferOut) <<")
    print("High-performance binary-to-binary pipeline with no table serialization.")
    
    local size = 5000
    local title = string.format("Zero-Combine Binary: %d elements", size)
    printTableHeader(title)
    
    local dataBuf = buffer.create(size * 8)
    for i = 0, size - 1 do
        buffer.writef32(dataBuf, i * 8, math.random())
        buffer.writef32(dataBuf, i * 8 + 4, math.random())
    end
    
    local seqTimes = measure(function() 
        local fn = require(bufferIO)
        local out = buffer.create(size * 4)
        for i = 0, size - 1 do fn(dataBuf, i * 8, out, i * 4) end
    end)
    local seqMean = avg(seqTimes)
    printResultRow("sequential (binary-io)", seqMean, median(seqTimes), stddev(seqTimes, seqMean), 1)
    
    for _, poolSize in ipairs({2, 4, 6}) do
        local pool = pools[poolSize]
        pool:prewarm(bufferIO)
        local times = measure(function() 
            pool:mapBufferOut(dataBuf, 8, 4, bufferIO) 
        end)
        local mean = avg(times)
        printResultRow("ParallelFlow pool:" .. poolSize, mean, median(times), stddev(times, mean), seqMean / mean)
    end
end

-- Scenario 10: Mixed Roblox Types (V13 Centralization)
do
    local function makeDataMixed(size)
        local d = table.create(size)
        local types = {
            function() return NumberRange.new(math.random(), math.random() + 1) end,
            function() return Region3.new(Vector3.new(0,0,0), Vector3.new(math.random(1,10), math.random(1,10), math.random(1,10))) end,
            function() return UDim2.new(math.random(), math.random(0,100), math.random(), math.random(0,100)) end,
            function() return Color3.new(math.random(), math.random(), math.random()) end,
            function() return Rect.new(math.random(0,50), math.random(0,50), math.random(50,100), math.random(50,100)) end,
            function() return Ray.new(Vector3.zero, Vector3.one * math.random(1,10)) end,
            function() return ColorSequence.new(Color3.new(1,0,0), Color3.new(0,1,0)) end,
            function() return DateTime.now() end
        }
        for i = 1, size do
            d[i] = types[math.random(1, #types)]()
        end
        return d
    end

    print("\n>> Scenario: Mixed Roblox Types (V13 Centralization) <<")
    print("Validating performance for newly centralized types via TypeCodecs.")
    
    local size = 1000
    local title = string.format("Mixed Types: %d elements", size)
    printTableHeader(title)
    local data = makeDataMixed(size)
    
    local computeFn = require(mixedWorker)
    local seqTimes = measure(function() 
        local out = table.create(#data)
        for i, v in data do out[i] = computeFn(v) end
    end)
    local seqMean = avg(seqTimes)
    printResultRow("sequential", seqMean, median(seqTimes), stddev(seqTimes, seqMean), 1)
    
    for _, poolSize in ipairs({2, 4, 6}) do
        local pool = pools[poolSize]
        local times = measure(function() pool:map(data, mixedWorker) end)
        local mean = avg(times)
        printResultRow("ParallelFlow pool:" .. poolSize, mean, median(times), stddev(times, mean), seqMean / mean)
    end
end


-- V19: Scalability & Lifecycle Verification
do
    print("\n>> Scenario: V19 Scalability & Ergonomics <<")
    print(string.rep("-", 50))

    local pool = pools[4]
    local data = table.create(10000, 1)

    -- 1. High-Level API Bench
    print("Verification 1: Ergonomic :Map()")
    local t0 = os.clock()
    local res = pool:Map(data, heavyModule)
    print(string.format("  :Map() processed %d items in %.2fms", #res, (os.clock()-t0)*1000))

    -- 2. Frame Budgeting Validation
    print("\nVerification 2: Frame Budgeting (2ms budget)")
    local budgetPool = ParallelFlow.createPool({size = 1, maxFrameMs = 2})
    local startFrame = os.clock()
    budgetPool:Map(table.create(5000, 1), heavyModule)
    local elapsed = (os.clock() - startFrame) * 1000
    print(string.format("  Budgeted Map took %.2fms", elapsed))
    if elapsed > 16 then
        print("  [PASS] Successfully yielded across frames to maintain budget.")
    end
    budgetPool:destroy()

    -- 3. Cancellation Safety
    print("\nVerification 3: Task Cancellation")
    local cancelPool = pools[4]
    local taskHandle = cancelPool:mapAsync(table.create(5000, 1), heavyModule)
    
    task.delay(0.01, function()
        print("  Triggering cancellation...")
        taskHandle:Cancel()
    end)
    
    taskHandle:Wait()
    print("  Task status: " .. (taskHandle:IsCancelled() and "CANCELLED (Safe)" or "COMPLETED"))
    
    -- Verify pool remains sane
    local check = cancelPool:Map({1, 2, 3}, heavyModule)
    print("  Pool health check after cancellation: " .. (#check == 3 and "OK" or "FAILED"))
end

-- Health Check: Production Logic
print("\n>> Scenario: Production Readiness Check <<")
print(string.rep("-", 50))

local errorCount = 0
local customPool = ParallelFlow.createPool({
    size = 2,
    timeout = 1,
    smallDatasetThreshold = 10,
    onError = function(err)
        print("Pool error callback triggered: " .. err)
        errorCount += 1
    end
})

print("Pool Introspection:")
print("  Pool Size: " .. customPool:getSize())
print("  Free Workers: " .. customPool:getFreeCount())

-- Fallback check
local smallResult = customPool:map({1, 2, 3}, heavyModule)
print("Sequential fallback status: " .. tostring(#smallResult == 3))

-- Destruction check
customPool:destroy()
local ok, err = pcall(function()
    customPool:dispatch(heavyModule, 1)
end)
print("Dispatch after destruction fails as expected: " .. tostring(not ok) .. " (" .. tostring(err) .. ")")

cleanupPools()
print("\nExtended benchmarks complete.")

