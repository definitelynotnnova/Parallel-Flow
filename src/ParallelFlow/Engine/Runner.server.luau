-- boots up the runtime engine for each actor
local actor = script:GetActor()
if not actor then return end

-- setup the engine
-- NOTE: script.Parent is the Actor, script.Parent.Parent is the Engine folder, script.Parent.Parent.Parent is ParallelFlow
local lib = require(script.Parent.Parent.Parent.Serializer)
local engine = require(script.Parent.Parent.Runtime)

engine.start(actor, lib)
