include("shared.lua")

-- ================================================================
-- SCALP/Storm Shadow -- CLIENT
-- Death state: engine flame swaps to smoke trail,
-- dynamic light turns red to signal kill.
-- Health degradation FX: flames, sparks, smoke via particle system.
-- ================================================================

local FLAME_MODEL = "models/roycombat/shared/trail_f22.mdl"
local SMOKE_MODEL = "models/roycombat/shared/trail_f22.mdl"
local BACK_OFFSET = 55
local FLAME_SCALE = 0.55
local SMOKE_SCALE = 0.75

-- ----------------------------------------------------------------
-- Particle precache
-- ----------------------------------------------------------------
game.AddParticles("particles/fire_01.pcf")
PrecacheParticleSystem("fire_medium_02")

-- ----------------------------------------------------------------
-- Damage tier FX config  (SCALP is a larger missile: ±70/±60 scatter)
-- ----------------------------------------------------------------
local TIER_OFFSETS = {
	[1] = {
		{ x =  40, y =  20, z = 5 },
		{ x = -40, y = -20, z = 5 },
	},
	[2] = {
		{ x =  60, y =  30, z = 8 },
		{ x = -60, y = -30, z = 8 },
		{ x =   0, y =  70, z = 6 },
		{ x =   0, y = -70, z = 6 },
	},
}

local TIER_BURST_DELAY = { [1] = 5.0, [2] = 2.5, [3] = 0.9 }
local TIER_BURST_COUNT = { [1] = 1,   [2] = 2,   [3] = 4   }

local ScalpStates = {}

-- ----------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------
local function BurstAt(pos, tier)
	local ed = EffectData()
	ed:SetOrigin(pos)
	ed:SetScale(1)
	util.Effect("Explosion", ed)

	local sed = EffectData()
	sed:SetOrigin(pos)
	sed:SetScale(1)
	util.Effect("ManhackSparks", sed)

	if tier >= 2 then
		local eed = EffectData()
		eed:SetOrigin(pos)
		eed:SetScale(1)
		util.Effect("ElectricSpark", eed)
	end
end

local function SpawnBurstFX(ent, tier)
	if not IsValid(ent) then return end
	local count = TIER_BURST_COUNT[tier] or 1
	local fwd   = ent:GetForward()
	for i = 1, count do
		local offset = fwd * math.Rand(-60, 60)
		BurstAt(ent:GetPos() + offset, tier)
	end
end

local function ApplyFlameParticles(state, ent, tier)
	-- Stop existing particles
	for _, p in ipairs(state.particles) do
		if IsValid(p) then p:StopEmission() end
	end
	state.particles = {}

	local offsets = TIER_OFFSETS[tier]
	if not offsets then return end

	for _, off in ipairs(offsets) do
		local p = CreateParticleSystem(ent, "fire_medium_02", PATTACH_ABSORIGIN_FOLLOW)
		if IsValid(p) then
			p:SetControlPoint(0, ent:GetPos() + ent:GetRight() * off.x
				                             + ent:GetUp()    * off.z
				                             + ent:GetForward() * off.y)
			table.insert(state.particles, p)
		end
	end
end

-- ----------------------------------------------------------------
-- Net receiver
-- ----------------------------------------------------------------
net.Receive("bombin_scalp_damage_tier", function()
	local idx  = net.ReadUInt(16)
	local tier = net.ReadUInt(2)

	local ent = ents.GetByIndex(idx)

	if not IsValid(ent) then
		-- Entity may not be networked to this client yet; defer one frame
		ScalpStates[idx] = ScalpStates[idx] or { tier = 0, particles = {}, nextBurst = 0, pendingTier = nil }
		ScalpStates[idx].pendingTier = tier
		return
	end

	local state = ScalpStates[idx] or { tier = 0, particles = {}, nextBurst = 0, pendingTier = nil }
	ScalpStates[idx] = state
	state.tier = tier

	ApplyFlameParticles(state, ent, tier)
end)

-- ----------------------------------------------------------------
-- Per-frame think: track particles, periodic bursts, cleanup
-- ----------------------------------------------------------------
hook.Add("Think", "bombin_scalp_damage_fx", function()
	local ct = CurTime()
	for idx, state in pairs(ScalpStates) do
		local ent = ents.GetByIndex(idx)

		if not IsValid(ent) then
			for _, p in ipairs(state.particles) do
				if IsValid(p) then p:StopEmission() end
			end
			ScalpStates[idx] = nil
			continue
		end

		-- Resolve deferred tier
		if state.pendingTier then
			state.tier = state.pendingTier
			state.pendingTier = nil
			ApplyFlameParticles(state, ent, state.tier)
		end

		if state.tier == 0 then continue end

		-- Update control points to follow the missile
		local offsets = TIER_OFFSETS[state.tier]
		if offsets then
			for i, p in ipairs(state.particles) do
				if IsValid(p) and offsets[i] then
					local off = offsets[i]
					p:SetControlPoint(0, ent:GetPos() + ent:GetRight()   * off.x
						                             + ent:GetUp()      * off.z
						                             + ent:GetForward() * off.y)
				end
			end
		end

		-- Periodic burst sparks
		local delay = TIER_BURST_DELAY[state.tier] or 5
		if ct >= state.nextBurst then
			SpawnBurstFX(ent, state.tier)
			state.nextBurst = ct + delay + math.Rand(-delay * 0.2, delay * 0.2)
		end
	end
end)

-- ----------------------------------------------------------------
-- Standard entity functions
-- ----------------------------------------------------------------
function ENT:Initialize()
	self:SetModelScale(1.6, 0)
	self:SetBodygroup(1, 1)

	timer.Simple(0, function()
		if not IsValid(self) then return end
		self._flameProp = ClientsideModel(FLAME_MODEL)
		if IsValid(self._flameProp) then
			self._flameProp:SetModelScale(FLAME_SCALE, 0)
			self._flameProp:SetNoDraw(true)
		end
	end)

	self._wasDestroyed = false
end

function ENT:Draw()
	self:DrawModel()

	local destroyed = self:GetNWBool("Destroyed", false)

	if destroyed and not self._wasDestroyed then
		self._wasDestroyed = true
		if IsValid(self._flameProp) then
			self._flameProp:SetModelScale(SMOKE_SCALE, 0)
		end
	end

	if not IsValid(self._flameProp) then return end

	local exhaustPos = self:GetPos() + (-self:GetForward()) * BACK_OFFSET
	local ang = self:GetAngles()
	ang.y = ang.y + 180

	self._flameProp:SetPos(exhaustPos)
	self._flameProp:SetAngles(ang)

	if destroyed then
		render.SetColorModulation(0.15, 0.15, 0.15)
		self._flameProp:DrawModel()
		render.SetColorModulation(1, 1, 1)
	else
		self._flameProp:DrawModel()
	end

	local dlight = DynamicLight(self:EntIndex())
	if dlight then
		dlight.pos        = exhaustPos
		dlight.brightness = 4
		dlight.Decay      = 1200
		dlight.Size       = math.Rand(280, 380)
		dlight.DieTime    = CurTime() + 0.05

		if destroyed then
			dlight.r = 255
			dlight.g = 40
			dlight.b = 0
			dlight.brightness = 6
			dlight.Size       = math.Rand(400, 600)
		else
			dlight.r = 255
			dlight.g = 120
			dlight.b = 20
		end
	end
end

function ENT:OnRemove()
	if IsValid(self._flameProp) then
		self._flameProp:Remove()
	end
	local state = ScalpStates[self:EntIndex()]
	if state then
		for _, p in ipairs(state.particles) do
			if IsValid(p) then p:StopEmission() end
		end
		ScalpStates[self:EntIndex()] = nil
	end
end
