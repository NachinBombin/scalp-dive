include("shared.lua")

-- ================================================================
-- SCALP/Storm Shadow -- CLIENT
-- Death state: engine flame swaps to smoke trail,
-- dynamic light turns red to signal kill.
-- ================================================================

local FLAME_MODEL = "models/roycombat/shared/trail_f22.mdl"
local SMOKE_MODEL = "models/roycombat/shared/trail_f22.mdl"  -- reuse; tinted via render
local BACK_OFFSET = 55
local FLAME_SCALE = 0.55
local SMOKE_SCALE = 0.75

function ENT:Initialize()
	self:SetModelScale(1.6, 0)
	-- Group 1 = wings
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

	-- Swap flame to smoke model on first destruction frame
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
		-- Render smoke trail with a dark tint when destroyed
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
			-- Red-orange glow: burning wreckage
			dlight.r = 255
			dlight.g = 40
			dlight.b = 0
			dlight.brightness = 6
			dlight.Size       = math.Rand(400, 600)
		else
			-- Normal engine glow
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
end
