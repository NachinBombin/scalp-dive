AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ================================================================
--  SCALP/Storm Shadow -- SERVER
-- ================================================================

local PASS_SOUNDS = {
	"ambient/wind/wind_generic_loop1.wav",
	"ambient/wind/wind_generic_loop2.wav",
}

local ENGINE_LOOP_SOUND = "^jet/luxor/external.wav"
local SHARD_MODEL       = "models/props_c17/FurnitureDrawer001a_Shard01.mdl"
local GRAVITY_MULT      = 1.5
local SHARD_LIFE        = 8

ENT.WeaponWindow       = 8
ENT.DIVE_Speed         = 2200
ENT.DIVE_TrackInterval = 0.1

util.AddNetworkString("bombin_scalp_damage_tier")

function ENT:Debug(msg)
	print("[Bombin SCALP] " .. tostring(msg))
end

-- ============================================================
-- TIER HELPERS
-- ============================================================

local function CalcTier(hp, maxHP)
	local frac = hp / maxHP
	if frac > 0.66 then return 0 end
	if frac > 0.33 then return 1 end
	if hp   > 0    then return 2 end
	return 3
end

local function BroadcastTier(ent, tier)
	net.Start("bombin_scalp_damage_tier")
		net.WriteUInt(ent:EntIndex(), 16)
		net.WriteUInt(tier, 2)
	net.Broadcast()
end

-- ============================================================
-- INITIALIZE
-- ============================================================

function ENT:Initialize()
	self.CenterPos    = self:GetVar("CenterPos",    self:GetPos())
	self.CallDir      = self:GetVar("CallDir",      Vector(1,0,0))
	self.Lifetime     = self:GetVar("Lifetime",     40)
	self.SkyHeightAdd = self:GetVar("SkyHeightAdd", 2500)

	self.DIVE_ExplosionDamage = self:GetVar("DIVE_ExplosionDamage", 1200)
	self.DIVE_ExplosionRadius = self:GetVar("DIVE_ExplosionRadius", 1200)

	self.MaxHP = 200

	if self.CallDir:LengthSqr() <= 1 then self.CallDir = Vector(1,0,0) end
	self.CallDir.z = 0
	self.CallDir:Normalize()

	local ground = self:FindGround(self.CenterPos)
	if ground == -1 then self:Debug("FindGround failed") self:Remove() return end

	local altVariance = self.SkyHeightAdd * 0.25
	self.sky = ground + self.SkyHeightAdd + math.Rand(-altVariance, altVariance)

	self.DieTime   = CurTime() + self.Lifetime
	self.SpawnTime = CurTime()

	local baseRadius = self:GetVar("OrbitRadius", 2500)
	local baseSpeed  = self:GetVar("Speed",        250)
	self.OrbitRadius = baseRadius * math.Rand(0.82, 1.18)
	self.Speed       = baseSpeed  * math.Rand(0.85, 1.15)

	-- AN-71-style orbit parameters
	self.OrbitDirection = (math.random(2) == 1) and 1 or -1
	self.OrbitBlend     = 0.08
	self.RadialGain     = 0.42
	self.WallAvoidGain  = 1.8
	self.MaxTurnRate    = 38     -- deg/s; missiles turn tighter than big planes

	-- Compute entry tangent aligned to CallDir
	local right   = Vector(-self.CallDir.y, self.CallDir.x, 0)
	local tangent = self.CallDir + right * 0
	tangent.z = 0
	tangent:Normalize()
	self.OrbitTangent = tangent * self.OrbitDirection

	local spawnOffset = self.OrbitTangent * (-self.OrbitRadius * math.Rand(0.55, 0.95))
	local spawnPos    = self.CenterPos + spawnOffset
	spawnPos.z        = self.sky

	if not util.IsInWorld(spawnPos) then
		spawnPos = Vector(self.CenterPos.x, self.CenterPos.y, self.sky)
	end
	if not util.IsInWorld(spawnPos) then
		self:Debug("Spawn position out of world") self:Remove() return
	end

	self:SetModel("models/sw/fr/missiles/agm/scalp.mdl")
	self:SetModelScale(1.6, 0)
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)
	self:SetPos(spawnPos)
	self:SetBodygroup(1, 1)
	self:SetRenderMode(RENDERMODE_NORMAL)

	self:SetNWInt("HP",    self.MaxHP)
	self:SetNWInt("MaxHP", self.MaxHP)
	self:SetNWBool("Destroyed", false)

	-- flightYaw: true direction of travel, same role as in AN-71
	self.flightYaw = self.OrbitTangent:Angle().y
	self.PrevYaw   = self.flightYaw
	self.ang       = Angle(0, self.flightYaw, 0)

	self.SmoothedRoll  = 0
	self.SmoothedPitch = 0

	self.JitterPhase  = math.Rand(0, math.pi * 2)
	self.JitterPhase2 = math.Rand(0, math.pi * 2)
	self.JitterAmp1   = math.Rand(8,  18)
	self.JitterAmp2   = math.Rand(20, 45)
	self.JitterRate1  = math.Rand(0.030, 0.060)
	self.JitterRate2  = math.Rand(0.007, 0.015)

	self.AltDriftCurrent  = self.sky
	self.AltDriftTarget   = self.sky
	self.AltDriftNextPick = CurTime() + math.Rand(8, 20)
	self.AltDriftRange    = 700
	self.AltDriftLerp     = 0.003

	self.BaseCenterPos = Vector(self.CenterPos.x, self.CenterPos.y, self.CenterPos.z)
	self.WanderPhaseX  = math.Rand(0, math.pi * 2)
	self.WanderPhaseY  = math.Rand(0, math.pi * 2)
	self.WanderAmp     = math.Rand(60, 160)
	self.WanderRateX   = math.Rand(0.004, 0.010)
	self.WanderRateY   = math.Rand(0.003, 0.009)

	-- Obstacle evasion (non-sky geometry)
	self.ObsLastEval   = 0
	self.ObsYawBias    = Vector(0, 0, 0)  -- flat avoid vector now, not scalar
	self.ObsAltBias    = 0
	self.ObsConsecHits = 0

	self.PhysObj = self:GetPhysicsObject()
	if IsValid(self.PhysObj) then
		self.PhysObj:Wake()
		self.PhysObj:EnableGravity(false)
	end

	self.EngineLoop = CreateSound(self, ENGINE_LOOP_SOUND)
	if self.EngineLoop then
		self.EngineLoop:SetSoundLevel(130)
		self.EngineLoop:ChangePitch(100, 0)
		self.EngineLoop:ChangeVolume(1.0, 0.5)
		self.EngineLoop:Play()
	end

	self.NextPassSound = CurTime() + math.Rand(5, 10)

	self.CurrentWeapon   = nil
	self.WeaponWindowEnd = 0

	self.Diving           = false
	self.DiveTarget       = nil
	self.DiveTargetPos    = nil
	self.DiveNextTrack    = 0
	self.DiveExploded     = false
	self.DiveAimOffset    = Vector(0,0,0)

	self.DiveWobblePhase  = 0
	self.DiveWobbleAmp    = 180
	self.DiveWobbleSpeed  = 4.5
	self.DiveWobblePhaseV = math.Rand(0, math.pi * 2)
	self.DiveWobbleAmpV   = 130
	self.DiveWobbleSpeedV = 3.1

	self.DiveSpeedMin     = self.DIVE_Speed * 0.55
	self.DiveSpeedCurrent = self.DIVE_Speed * 0.55
	self.DiveSpeedLerp    = 0.018
	self.DivePitchTelegraph = 0

	-- Death tumble state
	self.Destroyed       = false
	self.DestroyedTime   = nil
	self.TumbleAngVel    = Vector(0,0,0)
	self.ExplodeTimer    = nil
	self.ExplodedAlready = false

	self.DamageTier = 0

	self:Debug("Spawned at " .. tostring(spawnPos) .. " OrbitDir=" .. self.OrbitDirection)
end

-- ============================================================
-- DEATH STATE
-- ============================================================

function ENT:IsDestroyed()
	return self.Destroyed == true
end

function ENT:SpawnDebrisShards()
	local count   = math.random(1, 2)
	local origin  = self:GetPos()
	local baseVel = self:GetVelocity()

	for i = 1, count do
		local shard = ents.Create("prop_physics")
		if not IsValid(shard) then continue end

		shard:SetModel(SHARD_MODEL)
		shard:SetPos(origin + Vector(math.Rand(-30,30), math.Rand(-30,30), math.Rand(-20,20)))
		shard:SetAngles(Angle(math.Rand(0,360), math.Rand(0,360), math.Rand(0,360)))
		shard:Spawn()
		shard:Activate()
		shard:SetColor(Color(15, 10, 10, 255))
		shard:SetMaterial("models/debug/debugwhite")

		local phys = shard:GetPhysicsObject()
		if IsValid(phys) then
			phys:Wake()
			local kick = Vector(
				math.Rand(-300, 300),
				math.Rand(-300, 300),
				math.Rand(50,  250)
			)
			phys:SetVelocity(baseVel * 0.3 + kick)
			phys:AddAngleVelocity(Vector(
				math.Rand(-200, 200),
				math.Rand(-200, 200),
				math.Rand(-200, 200)
			))
		end

		shard:Ignite(SHARD_LIFE, 0)
		timer.Simple(SHARD_LIFE, function()
			if IsValid(shard) then shard:Remove() end
		end)
	end
end

function ENT:SetDestroyed()
	if self.Destroyed then return end
	self.Destroyed = true
	self:SetNWBool("Destroyed", true)
	self.DestroyedTime = CurTime()

	BroadcastTier(self, 3)

	if IsValid(self.PhysObj) then
		local existing = self.PhysObj:GetAngleVelocity()
		self.TumbleAngVel = existing + Vector(
			math.Rand(-120, 120),
			math.Rand(-120, 120),
			math.Rand(-120, 120)
		)
		self.PhysObj:EnableGravity(true)
		self.PhysObj:AddAngleVelocity(self.TumbleAngVel)
	end

	self:Ignite(20, 0)
	self:SpawnDebrisShards()

	if self.EngineLoop then
		self.EngineLoop:ChangeVolume(0, 1.5)
		self.EngineLoop:ChangePitch(55, 2.5)
	end

	local altAboveGround = self:GetPos().z - (self.sky - self.SkyHeightAdd)
	local delay = math.Clamp(altAboveGround / 600, 3, 12)
	self.ExplodeTimer = CurTime() + delay

	if not self.Diving then
		self.CurrentWeapon = nil
	end

	self:Debug("DESTROYED -- boom in " .. math.Round(delay,1) .. "s")
end

-- ============================================================
-- DAMAGE
-- ============================================================

function ENT:OnTakeDamage(dmginfo)
	if self.ExplodedAlready then return end
	if dmginfo:IsDamageType(DMG_CRUSH) then return end

	local hp = self:GetNWInt("HP", self.MaxHP or 200)
	hp = hp - dmginfo:GetDamage()
	self:SetNWInt("HP", hp)

	local newTier = CalcTier(math.max(hp, 0), self.MaxHP)
	if newTier ~= self.DamageTier then
		self.DamageTier = newTier
		BroadcastTier(self, newTier)
	end

	if hp <= 0 and not self:IsDestroyed() then
		self:Debug("Shot down!")
		self:SetDestroyed()
	end
end

-- ============================================================
-- THINK
-- ============================================================

function ENT:Think()
	if not self.DieTime or not self.SpawnTime then
		self:NextThink(CurTime() + 0.1)
		return true
	end

	local ct = CurTime()
	if ct >= self.DieTime then self:Remove() return end

	if not IsValid(self.PhysObj) then
		self.PhysObj = self:GetPhysicsObject()
	end
	if IsValid(self.PhysObj) and self.PhysObj:IsAsleep() then
		self.PhysObj:Wake()
	end

	if self:IsDestroyed() then
		if self.ExplodeTimer and ct >= self.ExplodeTimer then
			self:CrashExplode(self:GetPos())
			return true
		end
		self:NextThink(ct + 0.05)
		return true
	end

	if ct >= self.NextPassSound then
		sound.Play(
			table.Random(PASS_SOUNDS),
			self:GetPos(), 90, math.random(96, 104), 0.7
		)
		self.NextPassSound = ct + math.Rand(8, 16)
	end

	if self.Diving then
		self:UpdateDive(ct)
	else
		self:HandleWeaponWindow(ct)
	end

	self:NextThink(ct)
	return true
end

-- ============================================================
-- WALL / SKY AVOIDANCE
-- Returns a flat avoidance vector (may be zero).
-- Fires 5 fan probes forward; any hit (sky OR world brush) contributes
-- a push away from that direction.  This replaces the old SkyYawBias
-- scalar and the RecoverFromBoundary teleport entirely.
-- ============================================================

function ENT:EvaluateWallProbes(pos)
	local probeDist  = math.max(1200, self.Speed * 6)
	local fwdDir     = Angle(0, self.flightYaw, 0):Forward()
	local fwdRight   = Angle(0, self.flightYaw + 90, 0):Forward()

	-- Fan offsets in degrees relative to flight direction
	local fanOffsets = { -60, -30, 0, 30, 60 }
	local avoidVec   = Vector(0, 0, 0)

	for _, yawOff in ipairs(fanOffsets) do
		local probeDir = Angle(0, self.flightYaw + yawOff, 0):Forward()
		probeDir.z = 0.12  -- slight upward lean to catch sky ceiling
		probeDir:Normalize()

		local tr = util.TraceLine({
			start  = pos,
			endpos = pos + probeDir * probeDist,
			filter = self,
			mask   = MASK_SOLID_BRUSHONLY,
		})

		if tr.Hit then
			-- Weight by proximity: closer = stronger push
			local urgency = 1 + (1 - tr.Fraction) * 3
			-- Push away from the hit direction (negate that probe's contribution)
			local awayDir = -probeDir
			awayDir.z = 0
			avoidVec = avoidVec + awayDir * urgency
		end
	end

	if avoidVec:LengthSqr() > 0.001 then
		avoidVec.z = 0
		avoidVec:Normalize()
	end

	return avoidVec
end

-- ============================================================
-- OBSTACLE PROBE EVASION  (non-sky world geometry)
-- Returns a flat avoidance vector.
-- ============================================================

function ENT:EvaluateObstacleProbes(pos)
	local ct = CurTime()
	if ct - self.ObsLastEval < 0.08 then return self.ObsYawBias end
	self.ObsLastEval = ct

	local probeDist = math.max(800, self.Speed * 3)
	local fanAngles = { -80, -40, -15, 0, 15, 40, 80 }
	local avoidVec  = Vector(0, 0, 0)
	local totalHits = 0
	local hitFront  = 0

	for _, yawOff in ipairs(fanAngles) do
		local probeDir = Angle(0, self.flightYaw + yawOff, 0):Forward()
		probeDir.z = 0

		local tr = util.TraceLine({
			start  = pos,
			endpos = pos + probeDir * probeDist,
			filter = self,
			mask   = MASK_SOLID_BRUSHONLY,
		})

		if tr.Hit and not tr.HitSky then
			local urgency = 1 + (1 - tr.Fraction) * 2
			local awayDir = -probeDir
			awayDir.z = 0
			avoidVec = avoidVec + awayDir * urgency
			totalHits = totalHits + 1
			if math.abs(yawOff) <= 15 then
				hitFront = hitFront + urgency
			end
		end
	end

	if totalHits > 0 then
		self.ObsConsecHits = self.ObsConsecHits + 1
	else
		self.ObsConsecHits = 0
	end

	-- Persistent consecutive hits: flip orbit direction as last resort
	if self.ObsConsecHits >= 4 then
		self.OrbitDirection = -self.OrbitDirection
		self.ObsConsecHits  = 0
		self:Debug("Obstacle escalation: orbit direction reversed")
	end

	if hitFront > 1.5 then
		self.ObsAltBias = math.Rand(120, 260)
	else
		self.ObsAltBias = self.ObsAltBias * 0.92
		if math.abs(self.ObsAltBias) < 1 then self.ObsAltBias = 0 end
	end

	if avoidVec:LengthSqr() > 0.001 then
		avoidVec.z = 0
		avoidVec:Normalize()
	end
	self.ObsYawBias = avoidVec

	return avoidVec
end

-- ============================================================
-- PHYSICS UPDATE
-- ============================================================

function ENT:PhysicsUpdate(phys)
	if not self.DieTime or not self.sky then return end
	if CurTime() >= self.DieTime then self:Remove() return end

	-- ---- Destroyed: tumble (phys authority, no manual steering) ----
	if self:IsDestroyed() then
		local dt = FrameTime()
		if dt <= 0 then dt = 0.01 end

		local angVel = phys:GetAngleVelocity()
		phys:AddAngleVelocity(angVel * 0.08 * dt * 60)

		local gravZ  = -600
		local extraG = gravZ * (GRAVITY_MULT - 1) * phys:GetMass()
		phys:ApplyForceCenter(Vector(0, 0, extraG))

		local pos  = self:GetPos()
		local vel  = phys:GetVelocity()
		local next = pos + vel * dt + Vector(0, 0, -24)
		local tr = util.TraceLine({
			start  = pos,
			endpos = next,
			filter = self,
			mask   = MASK_SOLID_BRUSHONLY,
		})
		if tr.Hit then
			self:CrashExplode(tr.HitPos)
		end
		return
	end

	-- ---- Normal orbit (no Havok authority; SetPos only, same as AN-71) ----
	if self.Diving then return end

	local pos = self:GetPos()
	local dt  = engine.TickInterval()
	if dt <= 0 then dt = 0.01 end

	-- Wandering center
	self.WanderPhaseX = self.WanderPhaseX + self.WanderRateX
	self.WanderPhaseY = self.WanderPhaseY + self.WanderRateY
	self.CenterPos = Vector(
		self.BaseCenterPos.x + math.sin(self.WanderPhaseX) * self.WanderAmp,
		self.BaseCenterPos.y + math.sin(self.WanderPhaseY) * self.WanderAmp,
		self.BaseCenterPos.z
	)

	-- Altitude drift
	if CurTime() >= self.AltDriftNextPick then
		self.AltDriftTarget   = self.sky + math.Rand(-self.AltDriftRange, self.AltDriftRange)
		self.AltDriftNextPick = CurTime() + math.Rand(10, 25)
	end
	self.AltDriftCurrent = Lerp(self.AltDriftLerp, self.AltDriftCurrent, self.AltDriftTarget)
	self.JitterPhase  = self.JitterPhase  + self.JitterRate1
	self.JitterPhase2 = self.JitterPhase2 + self.JitterRate2
	local jitter  = math.sin(self.JitterPhase)  * self.JitterAmp1
	             + math.sin(self.JitterPhase2) * self.JitterAmp2
	local liveAlt = self.AltDriftCurrent + jitter + self.ObsAltBias

	-- ---- Steering: AN-71 vector-blend approach ----
	-- 1. Orbit tangent + radial correction
	local flatPos    = Vector(pos.x, pos.y, 0)
	local flatCenter = Vector(self.CenterPos.x, self.CenterPos.y, 0)
	local toCenter   = flatCenter - flatPos
	local dist       = toCenter:Length()

	local radialDir = Vector(0, 0, 0)
	if dist > 1 then radialDir = toCenter / dist end

	local tangentDir = Vector(-radialDir.y, radialDir.x, 0) * self.OrbitDirection
	if tangentDir:LengthSqr() <= 0.001 then
		tangentDir = Angle(0, self.flightYaw, 0):Forward()
		tangentDir.z = 0
	end
	tangentDir:Normalize()

	local radialError = 0
	if self.OrbitRadius > 0 then
		radialError = math.Clamp((dist - self.OrbitRadius) / self.OrbitRadius, -1, 1)
	end

	local desiredDir = tangentDir + radialDir * radialError * self.RadialGain

	-- 2. Wall / sky avoidance -- blended in with strong authority
	local wallAvoid = self:EvaluateWallProbes(pos)
	if wallAvoid:LengthSqr() > 0.001 then
		desiredDir = desiredDir + wallAvoid * self.WallAvoidGain
	end

	-- 3. Non-sky obstacle avoidance
	local obsAvoid = self:EvaluateObstacleProbes(pos)
	if obsAvoid:LengthSqr() > 0.001 then
		desiredDir = desiredDir + obsAvoid * 1.0
	end

	desiredDir.z = 0
	if desiredDir:LengthSqr() <= 0.001 then desiredDir = tangentDir end
	desiredDir:Normalize()

	-- 4. Yaw toward desiredDir, capped by MaxTurnRate
	local desiredYaw = desiredDir:Angle().y
	local yawDiff    = math.NormalizeAngle(desiredYaw - self.flightYaw)
	local maxStep    = self.MaxTurnRate * dt
	self.flightYaw   = self.flightYaw + math.Clamp(yawDiff, -maxStep, maxStep)

	-- Roll / pitch smoothing
	local rawYawDelta  = math.NormalizeAngle(self.flightYaw - (self.PrevYaw or self.flightYaw))
	self.PrevYaw       = self.flightYaw

	local targetRoll  = math.Clamp(rawYawDelta * -2.5, -30, 30)
	local rollLerp    = math.abs(rawYawDelta) > 0.01 and 0.15 or 0.05
	self.SmoothedRoll = Lerp(rollLerp, self.SmoothedRoll, targetRoll)

	local fwdDir      = Angle(0, self.flightYaw, 0):Forward()
	local vel         = IsValid(phys) and phys:GetVelocity() or (fwdDir * self.Speed)
	local fwdSpeed    = vel:Dot(fwdDir)
	local speedRatio  = math.Clamp(fwdSpeed / self.Speed, 0, 1.15)
	local climbDelta  = math.Clamp((liveAlt - pos.z) / 450, -1, 1)
	local targetPitch = math.Clamp(speedRatio * 4 + climbDelta * 7, -12, 12)
	self.SmoothedPitch = Lerp(0.04, self.SmoothedPitch, targetPitch)

	self.ang = Angle(
		self.SmoothedPitch,
		self.flightYaw,
		self.SmoothedRoll
	)

	-- Integrate position; Z Lerped toward liveAlt
	local newPos = pos + fwdDir * self.Speed * dt
	newPos.z = Lerp(0.08, pos.z, liveAlt)

	-- Last-resort world safety: if the computed next position is out of world
	-- steer toward center without any teleport.  This should never fire in
	-- normal play because the probes catch the wall long before we exit.
	if not util.IsInWorld(newPos) then
		local rescueDir = flatCenter - Vector(pos.x, pos.y, 0)
		rescueDir.z = 0
		if rescueDir:LengthSqr() <= 0.001 then rescueDir = -fwdDir; rescueDir.z = 0 end
		rescueDir:Normalize()
		newPos = pos + rescueDir * self.Speed * dt
		newPos.z = math.min(pos.z, liveAlt)
		self.flightYaw = rescueDir:Angle().y
		self.ang = Angle(self.SmoothedPitch, self.flightYaw, self.SmoothedRoll)
		self:Debug("Out-of-world safety steer fired (probes should have caught this)")
	end

	self:SetPos(newPos)
	self:SetAngles(self.ang)
	-- Do NOT call phys:SetVelocity -- Havok would integrate it on top of
	-- SetPos and move the entity twice per tick (double-move / stutter).
end

-- ============================================================
-- TARGET
-- ============================================================

function ENT:GetPrimaryTarget()
	local closest, closestDist = nil, math.huge
	for _, ply in ipairs(player.GetAll()) do
		if not IsValid(ply) or not ply:Alive() then continue end
		local d = ply:GetPos():DistToSqr(self.CenterPos)
		if d < closestDist then closestDist = d; closest = ply end
	end
	return closest
end

-- ============================================================
-- WEAPON WINDOW
-- ============================================================

function ENT:HandleWeaponWindow(ct)
	if not self.CurrentWeapon or ct >= self.WeaponWindowEnd then
		self:PickNewWeapon(ct)
	end
	if self.CurrentWeapon == "dive" then
		self:InitDive(ct)
	end
end

function ENT:PickNewWeapon(ct)
	local roll = math.random(1, 3)
	if roll == 1 then
		self.CurrentWeapon = "peaceful_1"
	elseif roll == 2 then
		self.CurrentWeapon = "peaceful_2"
	else
		self.CurrentWeapon = "dive"
	end
	self.WeaponWindowEnd = ct + self.WeaponWindow
	self:Debug("Behavior slot: " .. self.CurrentWeapon)
end

-- ============================================================
-- DIVE
-- ============================================================

function ENT:InitDive(ct)
	if self.Diving then return end

	if not self.DiveCommitTime then
		self.DiveCommitTime = ct + 1.0
		self:Debug("DIVE: locking target in 1s...")
		return
	end

	local frac = math.Clamp((ct - (self.DiveCommitTime - 1.0)) / 1.0, 0, 1)
	self.DivePitchTelegraph = frac * -60
	self:SetAngles(Angle(self.DivePitchTelegraph, self.ang.y, self.SmoothedRoll))

	if ct < self.DiveCommitTime then return end

	local target = self:GetPrimaryTarget()
	if not IsValid(target) then
		self.CurrentWeapon      = nil
		self.DiveCommitTime     = nil
		self.DivePitchTelegraph = 0
		return
	end

	self.Diving             = true
	self.DiveTarget         = target
	self.DiveTargetPos      = target:GetPos()
	self.DiveNextTrack      = ct
	self.DiveExploded       = false
	self.DiveCommitTime     = nil
	self.DivePitchTelegraph = 0
	self.DiveWobblePhase    = 0
	self.DiveWobblePhaseV   = math.Rand(0, math.pi * 2)
	self.DiveSpeedCurrent   = self.DiveSpeedMin
	self.DiveAimOffset      = Vector(math.Rand(-400,400), math.Rand(-400,400), 0)

	self:SetCollisionGroup(COLLISION_GROUP_NONE)
	self:SetSolid(SOLID_VPHYSICS)
	if IsValid(self.PhysObj) then
		self.PhysObj:EnableGravity(false)
	end

	self:Debug("DIVE: committed -- aim offset " .. tostring(self.DiveAimOffset))
end

function ENT:UpdateDive(ct)
	if self.DiveExploded then return end

	if ct >= self.DiveNextTrack then
		if not self:IsDestroyed() then
			if IsValid(self.DiveTarget) and self.DiveTarget:Alive() then
				self.DiveTargetPos = self.DiveTarget:GetPos() + Vector(
					math.Rand(-120,120), math.Rand(-120,120), 0)
			end
		end
		self.DiveNextTrack = ct + self.DIVE_TrackInterval
	end

	if not self.DiveTargetPos then self:Remove() return end

	local myPos = self:GetPos()
	local dir   = (self.DiveTargetPos + self.DiveAimOffset) - myPos
	local dist  = dir:Length()

	if dist < 120 then
		if self:IsDestroyed() then
			self:CrashExplode(myPos)
		else
			self:DiveExplode(myPos)
		end
		return
	end
	dir:Normalize()

	if self:IsDestroyed() then return end

	self.DiveSpeedCurrent = Lerp(self.DiveSpeedLerp, self.DiveSpeedCurrent, self.DIVE_Speed)

	local dt = FrameTime()
	self.DiveWobblePhase  = self.DiveWobblePhase  + self.DiveWobbleSpeed  * dt
	self.DiveWobblePhaseV = self.DiveWobblePhaseV + self.DiveWobbleSpeedV * dt

	local flatRight = Vector(-dir.y, dir.x, 0)
	if flatRight:LengthSqr() < 0.01 then flatRight = Vector(1,0,0) end
	flatRight:Normalize()
	local worldUp = Vector(0,0,1)
	local upPerp  = worldUp - dir * dir:Dot(worldUp)
	if upPerp:LengthSqr() < 0.01 then upPerp = Vector(0,1,0) end
	upPerp:Normalize()

	local wobbleScale = math.Clamp(dist / 400, 0, 1)
	local wobbleVel   = flatRight * math.sin(self.DiveWobblePhase)  * self.DiveWobbleAmp  * wobbleScale
	                  + upPerp   * math.sin(self.DiveWobblePhaseV) * self.DiveWobbleAmpV * wobbleScale

	local totalVel = dir * self.DiveSpeedCurrent + wobbleVel

	if totalVel:LengthSqr() > 0.01 then
		local faceAng = totalVel:GetNormalized():Angle()
		faceAng.r = 0
		self:SetAngles(faceAng)
		self.ang = faceAng
	end

	local nextPos = myPos + totalVel * dt
	local tr = util.TraceLine({
		start  = myPos,
		endpos = nextPos,
		filter = self,
		mask   = MASK_SOLID,
	})
	if tr.Hit then self:DiveExplode(tr.HitPos) return end

	if IsValid(self.PhysObj) then
		self.PhysObj:SetVelocity(totalVel)
	end
end

-- ============================================================
-- EXPLOSIONS
-- ============================================================

function ENT:DiveExplode(pos)
	if self.DiveExploded then return end
	self.DiveExploded    = true
	self.ExplodedAlready = true
	self:Debug("DIVE: exploding at " .. tostring(pos))

	local function E(effect, origin, sc)
		local ed = EffectData()
		ed:SetOrigin(origin)
		ed:SetScale(sc) ed:SetMagnitude(sc) ed:SetRadius(sc * 100)
		util.Effect(effect, ed, true, true)
	end
	E("HelicopterMegaBomb", pos,                   8)
	E("500lb_air",          pos,                   7)
	E("500lb_air",          pos + Vector(0,0,80),  6)
	E("500lb_air",          pos + Vector(0,0,160), 5)
	E("HelicopterMegaBomb", pos + Vector(0,0,20),  6)

	sound.Play("weapon_AWP.Single",                pos,                155, 52, 1.0)
	sound.Play("ambient/explosions/explode_8.wav", pos,                150, 78, 1.0)
	sound.Play("ambient/explosions/explode_8.wav", pos+Vector(0,0,40), 145, 85, 0.9)

	util.BlastDamage(self, self, pos, self.DIVE_ExplosionRadius, self.DIVE_ExplosionDamage)
	self:Remove()
end

function ENT:CrashExplode(pos)
	if self.ExplodedAlready then return end
	self.ExplodedAlready = true
	self:Debug("CRASH: exploding at " .. tostring(pos))

	local function E(effect, origin, sc)
		local ed = EffectData()
		ed:SetOrigin(origin)
		ed:SetScale(sc) ed:SetMagnitude(sc) ed:SetRadius(sc * 100)
		util.Effect(effect, ed, true, true)
	end
	E("HelicopterMegaBomb", pos,                  5)
	E("500lb_air",          pos,                  4)
	E("500lb_air",          pos + Vector(0,0,60), 3)

	sound.Play("ambient/explosions/explode_8.wav", pos, 145, 72, 1.0)
	sound.Play("ambient/explosions/explode_8.wav", pos, 140, 88, 0.8)

	local crashDmg = self.DIVE_ExplosionDamage * 0.3
	local crashRad = self.DIVE_ExplosionRadius * 0.6
	util.BlastDamage(self, self, pos, crashRad, crashDmg)

	self:Remove()
end

-- ============================================================
-- MISC
-- ============================================================

function ENT:FindGround(centerPos)
	local startPos   = Vector(centerPos.x, centerPos.y, centerPos.z + 64)
	local endPos     = Vector(centerPos.x, centerPos.y, -16384)
	local filterList = { self }
	local maxIter    = 0
	while maxIter < 100 do
		local tr = util.TraceLine({ start = startPos, endpos = endPos, filter = filterList })
		if tr.HitWorld then return tr.HitPos.z end
		if IsValid(tr.Entity) then
			table.insert(filterList, tr.Entity)
		else
			break
		end
		maxIter = maxIter + 1
	end
	return -1
end

function ENT:OnRemove()
	if self.EngineLoop then self.EngineLoop:Stop() end
end
