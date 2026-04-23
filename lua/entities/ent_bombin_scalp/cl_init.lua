include("shared.lua")

-- ================================================================
-- SCALP/Storm Shadow -- CLIENT
-- ================================================================

local FLAME_MODEL = "models/roycombat/shared/trail_f22.mdl"
local BACK_OFFSET = 55
local FLAME_SCALE = 0.55

function ENT:Initialize()
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
end

function ENT:Draw()
	self:DrawModel()

	if not IsValid(self._flameProp) then return end

	local exhaustPos = self:GetPos() + (-self:GetForward()) * BACK_OFFSET
	local ang = self:GetAngles()
	ang.y = ang.y + 180

	self._flameProp:SetPos(exhaustPos)
	self._flameProp:SetAngles(ang)
	self._flameProp:DrawModel()

	local dlight = DynamicLight(self:EntIndex())
	if dlight then
		dlight.pos        = exhaustPos
		dlight.r          = 255
		dlight.g          = 120
		dlight.b          = 20
		dlight.brightness = 4
		dlight.Decay      = 1200
		dlight.Size       = math.Rand(280, 380)
		dlight.DieTime    = CurTime() + 0.05
	end
end

function ENT:OnRemove()
	if IsValid(self._flameProp) then
		self._flameProp:Remove()
	end
end
