local Utility = require("Utility")
local Map = require("Map")

local Invoker = {}

local keyGhostWalk = Menu.AddKeyOption({"Hero Specific", "Invoker Extension"}, "Ghost Walk Key", Enum.ButtonCode.KEY_F5)
local optionRightClickCombo = Menu.AddOption({"Hero Specific", "Invoker Extension"}, "Right Click Combo", "cast cold snap, alacrity or forge spirit when right click enemy hero or building")
local optionMeteorBlastCombo = Menu.AddOption({"Hero Specific", "Invoker Extension"}, "Meteor & Blast Combo", "cast defending blast after chaos meteor")
local optionInstanceHelper = Menu.AddOption({"Hero Specific", "Invoker Extension"}, "Instance Helper", "auto switch instances, EEE when attacking, WWW when running")
local optionKillSteal = Menu.AddOption({"Hero Specific", "Invoker Extension"}, "Kill Steal", "auto cast deafening blast, tornado or sun strike to predicted position to KS")
local optionInterrupt = Menu.AddOption({"Hero Specific", "Invoker Extension"}, "Interrupt", "Auto interrupt enemy's tp or channelling spell with tornado or cold snap")
local optionFixedPositionCombo = Menu.AddOption({"Hero Specific", "Invoker Extension"}, "Fixed Position Combo", "Auto cast sun strike, chaos meteor, EMP on stunned/rooted/taunted enemy if possible")
local optionTornadoCombo = Menu.AddOption({"Hero Specific", "Invoker Extension"}, "Eul/Tornado Combo", "Auto cast ice wall, chaos meteor, sun strike, EMP with eul/tornado")
local optionSpellProtection = Menu.AddOption({"Hero Specific", "Invoker Extension"}, "Spell Protection", "Protect uncast spell by moving casted spell to second slot")
local optionMapHack = Menu.AddOption({"Hero Specific", "Invoker Extension"}, "Map Hack", "use information from particle efftects, to tornado tping enemy, or sun strike enemy if it is tping, farming or roshing.")

local isInvokingSpell = false
local lastInvokeTime = 0

function Invoker.OnUpdate()
    local myHero = Heroes.GetLocal()
    if not myHero or NPC.GetUnitName(myHero) ~= "npc_dota_hero_invoker" then return end

    Invoker.UpdateInvokingStatus(myHero)

    if Menu.IsKeyDownOnce(keyGhostWalk) then
        Invoker.CastGhostWalk(myHero)
        return
    end

    if Menu.IsEnabled(optionKillSteal) then
        Invoker.KillSteal(myHero)
    end    

    if Menu.IsEnabled(optionInterrupt) then
        Invoker.Interrupt(myHero)
    end  

    if Menu.IsEnabled(optionFixedPositionCombo) then
        Invoker.FixedPositionCombo(myHero)
    end  

    if Menu.IsEnabled(optionMeteorBlastCombo) then
        Invoker.MeteorBlastCombo(myHero)
    end

    if Menu.IsEnabled(optionTornadoCombo) then
        Invoker.TornadoCombo(myHero)
    end    
end

function Invoker.OnPrepareUnitOrders(orders)
    if not orders then return true end
    if orders.order == Enum.UnitOrder.DOTA_UNIT_ORDER_TRAIN_ABILITY then return true end

    local myHero = Heroes.GetLocal()
    if not myHero or NPC.GetUnitName(myHero) ~= "npc_dota_hero_invoker" then return true end
    if NPC.IsSilenced(myHero) or NPC.IsStunned(myHero) then return true end
    if NPC.HasState(myHero, Enum.ModifierState.MODIFIER_STATE_INVISIBLE) then return true end
    if NPC.HasModifier(myHero, "modifier_teleporting") then return true end
    if NPC.IsChannellingAbility(myHero) then return true end

    if Menu.IsEnabled(optionRightClickCombo) and orders.order == Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET then
        Invoker.RightClickCombo(myHero, orders.target)
    end
    
    if Menu.IsEnabled(optionInstanceHelper) and not isInvokingSpell then
        Invoker.InstanceHelper(myHero, orders.order)
    end

    if Menu.IsEnabled(optionSpellProtection) and orders.ability and Entity.IsAbility(orders.ability) then
        Invoker.ProtectSpell(myHero, orders.ability)
    end

    return true
end

-- update invoking status
-- check whether is invoking spell to avoid miss switch instance.
function Invoker.UpdateInvokingStatus(myHero)
    local elapse_time = 1
    if math.abs(GameRules.GetGameTime() - lastInvokeTime) > elapse_time then
        isInvokingSpell = false
    end

    -- if one of Q, W, E, R, D, F or F5(ghost walk) is pressed
    if Input.IsKeyDown(Enum.ButtonCode.KEY_F5) or Input.IsKeyDown(Enum.ButtonCode.KEY_Q) or Input.IsKeyDown(Enum.ButtonCode.KEY_W) or Input.IsKeyDown(Enum.ButtonCode.KEY_E) or Input.IsKeyDown(Enum.ButtonCode.KEY_R) or Input.IsKeyDown(Enum.ButtonCode.KEY_D) or Input.IsKeyDown(Enum.ButtonCode.KEY_F) then
        isInvokingSpell = true
        lastInvokeTime = GameRules.GetGameTime()
    end
end

function Invoker.InstanceHelper(myHero, order)
	if not myHero or not order then return end
    if not Utility.IsSuitableToCastSpell(myHero) then return end

	-- if about to move
	if order == Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION or order == Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_TARGET then
		if Entity.GetHealth(myHero) < Entity.GetMaxHealth(myHero) then
			Invoker.PressKey(myHero, "QQQ")
		else
			Invoker.PressKey(myHero, "WWW")
		end
	end

	-- if about to attack
	if order == Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_MOVE or order == Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET then
		local E = NPC.GetAbility(myHero, "invoker_exort")
        if E and Ability.IsCastable(E, 0) then
            Invoker.PressKey(myHero, "EEE")
        else
            Invoker.PressKey(myHero, "WWW")
        end
	end
end

-- when attacking enemy hero, enemy building, rosh, or farming hard/ancient camp
-- combo: right click -> cold snap
-- combo: right click -> alacrity
-- combo: right click -> forge spirit
function Invoker.RightClickCombo(myHero, target)
    if not myHero or not target then return end
    if not Utility.IsSuitableToCastSpell(myHero) then return end
    if Entity.IsSameTeam(myHero, target) then return end
    if not NPC.IsEntityInRange(myHero, target, NPC.GetAttackRange(myHero)) then return end

    if NPC.IsHero(target) or NPC.IsRoshan(target) then
        -- combo: right click -> cold snap
        if Invoker.CastColdSnap(myHero, target) then return end
    end

    if NPC.IsHero(target) or NPC.IsRoshan(target) or NPC.IsStructure(target) or Utility.IsAncientCreep(target) or (NPC.IsCreep(target) and not NPC.IsLaneCreep(target)) then
    
        -- combo: right click -> alacrity
        if Invoker.CastAlacrity(myHero, myHero) then return end

        -- combo: right click -> forge spirit
        if Invoker.CastForgeSpirit(myHero) then return end
    end

end

-- tornado/eul combo
-- priority: ice wall -> sun strike -> chaos meteor -> emp 
function Invoker.TornadoCombo(myHero)
    if not myHero then return end
    if not Utility.IsSuitableToCastSpell(myHero) then return end

    local mod
    for i = 1, Heroes.Count() do
        local enemy = Heroes.Get(i)
        if enemy and not Entity.IsSameTeam(myHero, enemy) and not NPC.IsIllusion(enemy) then

            local mod1 = NPC.GetModifier(enemy, "modifier_invoker_tornado")
            local mod2 = NPC.GetModifier(enemy, "modifier_eul_cyclone")
            local mod3 = NPC.GetModifier(enemy, "modifier_brewmaster_storm_cyclone")

            if mod1 then mod = mod1 end
            if mod2 then mod = mod2 end
            if mod3 then mod = mod3 end

            if mod then
                local pos =  Entity.GetAbsOrigin(enemy)
                local time_left = math.max(Modifier.GetDieTime(mod) - GameRules.GetGameTime(), 0)

                -- 1. cast ice wall
                if Invoker.CastIceWall(myHero, enemy) then return end

                -- 2. cast sun strike
                if time_left >= 1 and time_left < 1.7 and Invoker.CastSunStrike(myHero, pos) then return end

                -- 3. cast chaos meteor
                if time_left >= 0.5 and time_left < 1.3 and Invoker.CastChaosMeteor(myHero, pos) then return end
                
                -- 4. cast EMP
                if time_left >= 1 and time_left < 2.9 and Invoker.CastEMP(myHero, pos) then return end
            end
        end
    end    
end

-- combo: chaos meteor -> deafening blast
-- combo: chaos meteor -> cold snap
function Invoker.MeteorBlastCombo(myHero)
    if not myHero then return end
    if not Utility.IsSuitableToCastSpell(myHero) then return end

	-- check nearby enemy who is affected by chaos meteor
    for i = 1, Heroes.Count() do
        local enemy = Heroes.Get(i)
        if enemy and not Entity.IsSameTeam(myHero, enemy) and not NPC.IsIllusion(enemy) and NPC.HasModifier(enemy, "modifier_invoker_chaos_meteor_burn") then
            -- combo: chaos meteor -> deafening blast
            if Invoker.CastDeafeningBlast(myHero, Entity.GetAbsOrigin(enemy)) then return end

            -- combo: chaos meteor -> cold snap
            if Invoker.CastColdSnap(myHero, enemy) then return end
        end
    end
end

-- auto cast deafening blast, tornado or sun strike to predicted position for kill steal
function Invoker.KillSteal(myHero)
    if not myHero then return end
    if not Utility.IsSuitableToCastSpell(myHero) then return end

    local Q = NPC.GetAbility(myHero, "invoker_quas")
    local W = NPC.GetAbility(myHero, "invoker_wex")
    local E = NPC.GetAbility(myHero, "invoker_exort")
    if not Q or not W or not E then return end

    local Q_level = Ability.GetLevel(Q)
    local W_level = Ability.GetLevel(W)
    local E_level = Ability.GetLevel(E)

    if NPC.HasItem(myHero, "item_ultimate_scepter", true) then 
        Q_level = Q_level + 1
        W_level = W_level + 1
        E_level = E_level + 1
    end

    local damage_tornado = 45 * W_level
    local damage_deafening_blast = 40 * E_level
    local damage_sun_strike = 100 + 62.5 * (E_level - 1)

    for i = 1, Heroes.Count() do
        local enemy = Heroes.Get(i)
        if not Entity.IsSameTeam(myHero, enemy) and not NPC.IsIllusion(enemy) and not Entity.IsDormant(enemy) and Entity.IsAlive(enemy) then
            
        	local enemyHp = Entity.GetHealth(enemy)
            local dis = (Entity.GetAbsOrigin(myHero) - Entity.GetAbsOrigin(enemy)):Length()
            local multiplier = NPC.GetMagicalArmorDamageMultiplier(enemy)

            -- cast tornado to KS
            if enemyHp <= damage_tornado * multiplier and not NPC.HasState(enemy, Enum.ModifierState.MODIFIER_STATE_MAGIC_IMMUNE) and not NPC.HasState(enemy, Enum.ModifierState.MODIFIER_STATE_INVULNERABLE) then
                local speed = 1000
                local delay = dis / (speed + 1)
                local pos = Utility.GetPredictedPosition(enemy, delay)
                if Invoker.CastTornado(myHero, pos) then return end
            end

            -- cast deafening blast to KS
            if enemyHp <= damage_deafening_blast * multiplier and not NPC.HasState(enemy, Enum.ModifierState.MODIFIER_STATE_MAGIC_IMMUNE) and not NPC.HasState(enemy, Enum.ModifierState.MODIFIER_STATE_INVULNERABLE) then
                local speed = 1100
                local delay = dis / (speed + 1)
                local pos = Utility.GetPredictedPosition(enemy, delay)
                if Invoker.CastDeafeningBlast(myHero, pos) then return end
            end

            -- cast sun strike to KS
            if enemyHp <= damage_sun_strike and not NPC.HasState(enemy, Enum.ModifierState.MODIFIER_STATE_INVULNERABLE) then
            	local delay = 1.7 -- sun strike has 1.7s delay
            	local pos = Utility.GetPredictedPosition(enemy, delay)
                if Invoker.CastSunStrike(myHero, pos) then return end
            end
        end
    end
end

-- local TpParticleIndex

-- -- interrupt enemy's tp, using information from particle effects
-- function Invoker.OnParticleCreate(particle)
--     if not particle then return end
--     if particle.name == "teleport_start" then TpParticleIndex = particle.index end
-- end

-- -- interrupt enemy's tp, using information from particle effects
-- function Invoker.OnParticleUpdate(particle)
--     if not Menu.IsEnabled(optionInterrupt) then return end

--     if not particle then return end
--     if not TpParticleIndex or TpParticleIndex ~= particle.index then return end

--     local myHero = Heroes.GetLocal()
--     if not myHero or NPC.GetUnitName(myHero) ~= "npc_dota_hero_invoker" then return end
--     if NPC.IsSilenced(myHero) or NPC.IsStunned(myHero) or not Entity.IsAlive(myHero) then return end
--     if NPC.HasState(myHero, Enum.ModifierState.MODIFIER_STATE_INVISIBLE) then return end
--     if NPC.HasModifier(myHero, "modifier_teleporting") then return end
--     if NPC.IsChannellingAbility(myHero) then return end

--     -- have to make sure this tp particle is not from teammate
--     if not particle.position or particle.position:Length() <= 2 then return end
--     local allies = NPCs.InRadius(particle.position, 50, Entity.GetTeamNum(myHero), Enum.TeamType.TEAM_FRIEND)
--     if allies and #allies > 0 then return end
    
--     if Invoker.CastTornado(myHero, particle.position) then return end

--     if Invoker.CastSunStrike(myHero, particle.position) then return end
-- end

-- according to info given by particle effects
-- cast sun strike when enemy is (1) tping; (2) farming neutral creep; (3) roshing
-- interrupt enemy's tp by tornado
function Invoker.MapHack(pos, particleName)
    if not Menu.IsEnabled(optionMapHack) then return end

    local myHero = Heroes.GetLocal()
    if not myHero or NPC.GetUnitName(myHero) ~= "npc_dota_hero_invoker" then return end
    if not Utility.IsSuitableToCastSpell(myHero) then return end
    
    if NPC.IsSilenced(myHero) or NPC.IsStunned(myHero) or not Entity.IsAlive(myHero) then return end
    if NPC.HasState(myHero, Enum.ModifierState.MODIFIER_STATE_INVISIBLE) then return end
    if NPC.HasModifier(myHero, "modifier_teleporting") then return end
    if NPC.IsChannellingAbility(myHero) then return end

    -- have to make sure these particles are not from teammate
    if not pos or not Map.IsValidPos(pos) or Map.IsAlly(myHero, pos) then return end

    -- tp effects
    if particleName == "teleport_start" then
        -- interrupt tp with tornado
        if Invoker.CastTornado(myHero, pos) then return end
        -- sun strike on tping enemy. dont sun strike if enemy is tping in fountain (that would be so obvious)
        if not Map.InFountain(pos) and Invoker.CastSunStrike(myHero, pos) then return end
    end

    -- sun strike when enemy is farming neutral camp or doing roshan
    if Map.InNeutralCamp(pos) or Map.InRoshan(pos) then
        if Invoker.CastSunStrike(myHero, pos) then return end
    end
end

-- Auto interrupt enemy's tp or channelling spell with tornado or cold snap
function Invoker.Interrupt(myHero)
    if not myHero then return end
    if not Utility.IsSuitableToCastSpell(myHero) then return end

    for i = 1, Heroes.Count() do
        local enemy = Heroes.Get(i)
        if enemy and not Entity.IsSameTeam(myHero, enemy) and not NPC.IsIllusion(enemy)
            and not NPC.HasState(enemy, Enum.ModifierState.MODIFIER_STATE_MAGIC_IMMUNE)
            and not NPC.HasState(enemy, Enum.ModifierState.MODIFIER_STATE_INVULNERABLE)
            and (NPC.IsChannellingAbility(enemy) or NPC.HasModifier(enemy, "modifier_teleporting")) then

            -- cast cold snap to interrupt
            if Invoker.CastColdSnap(myHero, enemy) then return end

            -- cast tornado to interrupt
            if Invoker.CastTornado(myHero, Entity.GetAbsOrigin(enemy)) then return end

            -- cast sun strike as follow up
            if Invoker.CastSunStrike(myHero, Entity.GetAbsOrigin(enemy)) then return end

            -- cast chaos meteor as follow up
            if Invoker.CastChaosMeteor(myHero, Entity.GetAbsOrigin(enemy)) then return end

            -- cast EMP as follow up
            if Invoker.CastEMP(myHero, Entity.GetAbsOrigin(enemy)) then return end

        end
    end
end

-- Auto cast sun strike, chaos meteor, EMP on stunned/rooted/taunted enemy if possible
-- Auto cast these spells on enemy who is slower then threshold
-- priority: chaos meteor -> EMP -> sun strike
function Invoker.FixedPositionCombo(myHero)
    if not myHero then return end
    if not Utility.IsSuitableToCastSpell(myHero) then return end

    local speedThreshold = 250

    for i = 1, Heroes.Count() do
        local enemy = Heroes.Get(i)
        -- NPC.GetMoveSpeed() fails to consider (1) hex (2) ice wall
        if enemy and not Entity.IsSameTeam(myHero, enemy) and not NPC.IsIllusion(enemy)
            and not NPC.HasState(enemy, Enum.ModifierState.MODIFIER_STATE_MAGIC_IMMUNE)
            and not NPC.HasState(enemy, Enum.ModifierState.MODIFIER_STATE_INVULNERABLE)
            and (Utility.CantMove(enemy) or Utility.GetMoveSpeed(enemy) < speedThreshold) then

            -- cast chaos meteor on stunned/rooted enemy
            local pos = Utility.GetPredictedPosition(enemy, 1.3)
            if Invoker.CastChaosMeteor(myHero, pos) then return end

            -- cast EMP on stunned/rooted enemy
            local pos = Utility.GetPredictedPosition(enemy, 2.9)
            if Invoker.CastEMP(myHero, pos) then return end

            -- cast sun strike on stunned/rooted enemy
            local pos = Utility.GetPredictedPosition(enemy, 1.7)
            if Invoker.CastSunStrike(myHero, pos) then return end

        end
    end
end

-- define defensive actions
-- priority: tornado -> blast -> cold snap -> ice wall -> EMP
function Invoker.Defend(myHero, source)
    if not myHero or not source then return end
    if not Utility.IsSuitableToCastSpell(myHero) then return end    

    -- 1. use tornado to defend if available
    if Invoker.CastTornado(myHero, Entity.GetAbsOrigin(source)) then return end

    -- 2. use deafening blast to defend if available
    if Invoker.CastDeafeningBlast(myHero, Entity.GetAbsOrigin(source)) then return end

    -- 3. use cold snap to defend if available
    if Invoker.CastColdSnap(myHero, source) then return end

    -- 4. use ice wall to defend if available
    if Invoker.CastIceWall(myHero, source) then return end

    -- 5. use EMP to defend if available
    local mid = (Entity.GetAbsOrigin(myHero) + Entity.GetAbsOrigin(source)):Scaled(0.5)
    if Invoker.CastEMP(myHero, mid) then return end

end

-- return true if successfully cast, false otherwise
function Invoker.CastTornado(myHero, pos)
    if not myHero or not pos then return false end
    if not Utility.IsSuitableToCastSpell(myHero) then return false end

    local invoke = NPC.GetAbility(myHero, "invoker_invoke")
    if not invoke then return false end

    local tornado = NPC.GetAbility(myHero, "invoker_tornado")
    if not tornado or not Ability.IsCastable(tornado, NPC.GetMana(myHero)-Ability.GetManaCost(invoke)) then return false end
    
    local W = NPC.GetAbility(myHero, "invoker_wex")
    if not W or not Ability.IsCastable(W, 0) then return false end

    local level = Ability.GetLevel(W)
    local range = 2000
    local travel_distance = 800 + 400 * (level - 1)

    local dir = pos - Entity.GetAbsOrigin(myHero)
    local dis = dir:Length()
    
    if dis > travel_distance then return false end
    if dis > range then pos = Entity.GetAbsOrigin(myHero) + dir:Scaled(range/dis) end

    if Invoker.HasInvoked(myHero, tornado) or Invoker.PressKey(myHero, "QWWR") then
        Ability.CastPosition(tornado, pos)
        Invoker.ProtectSpell(myHero, tornado)
        return true
    end

    return false
end

-- return true if successfully cast, false otherwise
function Invoker.CastDeafeningBlast(myHero, pos)
    if not myHero or not pos then return false end
    if not Utility.IsSuitableToCastSpell(myHero) then return false end

    local invoke = NPC.GetAbility(myHero, "invoker_invoke")
    if not invoke then return false end

    local blast = NPC.GetAbility(myHero, "invoker_deafening_blast")
    if not blast or not Ability.IsCastable(blast, NPC.GetMana(myHero)-Ability.GetManaCost(invoke)) then return false end

    local range = 1000
    local dis = (Entity.GetAbsOrigin(myHero) - pos):Length()
    if dis > range then return false end

    if Invoker.HasInvoked(myHero, blast) or Invoker.PressKey(myHero, "QWER") then
        Ability.CastPosition(blast, pos)
        Invoker.ProtectSpell(myHero, blast)
        return true
    end

    return false
end

-- return true if successfully cast, false otherwise
function Invoker.CastColdSnap(myHero, target)
    if not myHero or not target then return false end
    if not Utility.IsSuitableToCastSpell(myHero) then return false end

    local invoke = NPC.GetAbility(myHero, "invoker_invoke")
    if not invoke then return false end

    local cold_snap = NPC.GetAbility(myHero, "invoker_cold_snap")
    if not cold_snap or not Ability.IsCastable(cold_snap, NPC.GetMana(myHero)-Ability.GetManaCost(invoke)) then return false end
        
    local range = 1000
    local dis = (Entity.GetAbsOrigin(myHero) - Entity.GetAbsOrigin(target)):Length()
    if dis > range then return false end

    if NPC.IsStructure(target) or not NPC.IsKillable(target) then return false end
    if NPC.HasState(target, Enum.ModifierState.MODIFIER_STATE_MAGIC_IMMUNE) then return false end
    if NPC.HasState(target, Enum.ModifierState.MODIFIER_STATE_INVULNERABLE) then return false end

    if Invoker.HasInvoked(myHero, cold_snap) or Invoker.PressKey(myHero, "QQQR") then
        Ability.CastTarget(cold_snap, target)
        Invoker.ProtectSpell(myHero, cold_snap)
        return true
    end

    return false
end

-- return true if successfully cast, false otherwise
-- input: target, can be nil
function Invoker.CastIceWall(myHero, target)
    if not myHero then return false end
    if not Utility.IsSuitableToCastSpell(myHero) then return false end

    local invoke = NPC.GetAbility(myHero, "invoker_invoke")
    if not invoke then return false end

    local ice_wall = NPC.GetAbility(myHero, "invoker_ice_wall")
    if not ice_wall or not Ability.IsCastable(ice_wall, NPC.GetMana(myHero)-Ability.GetManaCost(invoke)) then return false end
    
    local range = 300
    if target and not NPC.IsEntityInRange(myHero, target, range) then return false end

    local angel = 90
    local dir = (Entity.GetAbsOrigin(target) - Entity.GetAbsOrigin(myHero)):Rotated(Angle(0,angel,0))
    local pos = Entity.GetAbsOrigin(myHero) + dir

    if Invoker.HasInvoked(myHero, ice_wall) or Invoker.PressKey(myHero, "QQER") then
        
        -- turn to direction first
        if target then
            Player.PrepareUnitOrders(Players.GetLocal(), Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_DIRECTION, nil, pos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY , myHero)
        end

        Ability.CastNoTarget(ice_wall)
        Invoker.ProtectSpell(myHero, ice_wall)
        return true
    end


    return false
end

-- return true if successfully cast, false otherwise
function Invoker.CastEMP(myHero, pos)
    if not myHero or not pos then return false end
    if not Utility.IsSuitableToCastSpell(myHero) then return false end

    local invoke = NPC.GetAbility(myHero, "invoker_invoke")
    if not invoke then return false end

    local emp = NPC.GetAbility(myHero, "invoker_emp")
    if not emp or not Ability.IsCastable(emp, NPC.GetMana(myHero)-Ability.GetManaCost(invoke)) then return false end

    local range = 950
    local dis = (Entity.GetAbsOrigin(myHero) - pos):Length()
    if dis > range then return false end
        
    if Invoker.HasInvoked(myHero, emp) or Invoker.PressKey(myHero, "WWWR") then
        Ability.CastPosition(emp, pos)
        Invoker.ProtectSpell(myHero, emp)
        return true
    end

    return false
end

-- return true if successfully cast, false otherwise
function Invoker.CastAlacrity(myHero, target)
    if not myHero or not target then return false end
    if not Utility.IsSuitableToCastSpell(myHero) then return false end
    if not Entity.IsSameTeam(myHero, target) then return false end

    local invoke = NPC.GetAbility(myHero, "invoker_invoke")
    if not invoke then return false end

    local alacrity = NPC.GetAbility(myHero, "invoker_alacrity")
    if not alacrity or not Ability.IsCastable(alacrity, NPC.GetMana(myHero) - Ability.GetManaCost(invoke)) then return false end
        
    if Invoker.HasInvoked(myHero, alacrity) or Invoker.PressKey(myHero, "WWER") then
        Ability.CastTarget(alacrity, myHero)
        Invoker.ProtectSpell(myHero, alacrity)
        return true
    end

    return false
end

-- return true if successfully cast, false otherwise
function Invoker.CastForgeSpirit(myHero)
    if not myHero then return false end
    if not Utility.IsSuitableToCastSpell(myHero) then return false end

    local invoke = NPC.GetAbility(myHero, "invoker_invoke")
    if not invoke then return false end

    local forge_spirit = NPC.GetAbility(myHero, "invoker_forge_spirit")
    if not forge_spirit or not Ability.IsCastable(forge_spirit, NPC.GetMana(myHero) - Ability.GetManaCost(invoke)) then return false end
        
    if Invoker.HasInvoked(myHero, forge_spirit) or Invoker.PressKey(myHero, "QEER") then
        Ability.CastNoTarget(forge_spirit)
        Invoker.ProtectSpell(myHero, forge_spirit)
        return true
    end

    return false
end

-- return true if successfully cast, false otherwise
function Invoker.CastSunStrike(myHero, pos)
    if not myHero or not pos then return false end
    if not Utility.IsSuitableToCastSpell(myHero) then return false end

    local invoke = NPC.GetAbility(myHero, "invoker_invoke")
    if not invoke then return false end
    
    local sun_strike = NPC.GetAbility(myHero, "invoker_sun_strike")
    if not sun_strike or not Ability.IsCastable(sun_strike, NPC.GetMana(myHero) - Ability.GetManaCost(invoke)) then return false end

    if Invoker.HasInvoked(myHero, sun_strike) or Invoker.PressKey(myHero, "EEER") then
        Ability.CastPosition(sun_strike, pos)
        Invoker.ProtectSpell(myHero, sun_strike)
        return true
    end

    return false
end

-- return true if successfully cast, false otherwise
function Invoker.CastChaosMeteor(myHero, pos)
    if not myHero or not pos then return false end
    if not Utility.IsSuitableToCastSpell(myHero) then return false end

    local invoke = NPC.GetAbility(myHero, "invoker_invoke")
    if not invoke then return false end
    
    local meteor = NPC.GetAbility(myHero, "invoker_chaos_meteor")
    if not meteor or not Ability.IsCastable(meteor, NPC.GetMana(myHero) - Ability.GetManaCost(invoke)) then return false end

    local range = 700
    local dis = (Entity.GetAbsOrigin(myHero) - pos):Length()
    if dis > range then return false end

    if Invoker.HasInvoked(myHero, meteor) or Invoker.PressKey(myHero, "WEER") then
        Ability.CastPosition(meteor, pos)
        Invoker.ProtectSpell(myHero, meteor)
        return true
    end

    return false
end

-- return true if successfully cast, false otherwise
function Invoker.CastGhostWalk(myHero)
    if not myHero then return false end
    if not Utility.IsSuitableToCastSpell(myHero) then return false end

    local invoke = NPC.GetAbility(myHero, "invoker_invoke")
    if not invoke then return false end
    
    local ghost_walk = NPC.GetAbility(myHero, "invoker_ghost_walk")
    if not ghost_walk or not Ability.IsCastable(ghost_walk, NPC.GetMana(myHero) - Ability.GetManaCost(invoke)) then return false end

    if Invoker.HasInvoked(myHero, ghost_walk) or Invoker.PressKey(myHero, "QQWR") then
        local ratio = 0.8
        if Entity.GetHealth(myHero) >= ratio * Entity.GetMaxHealth(myHero) then
            Invoker.PressKey(myHero, "WWW")
        else
            Invoker.PressKey(myHero, "QQQ")
        end

        Ability.CastNoTarget(ghost_walk)
        return true
    end

    return false
end

-- return current instances ("QWE", "QQQ", "EEE", etc)
function Invoker.GetInstances(myHero)
    local modTable = NPC.GetModifiers(myHero)
    local Q_num, W_num, E_num = 0, 0, 0
    
    for i, mod in ipairs(modTable) do
        if Modifier.GetName(mod) == "modifier_invoker_quas_instance" then
            Q_num = Q_num + 1
        elseif Modifier.GetName(mod) == "modifier_invoker_wex_instance" then
            W_num = W_num + 1
        elseif Modifier.GetName(mod) == "modifier_invoker_exort_instance" then
            E_num = E_num + 1
        end
    end

    local QWE_text = ""
    while Q_num > 0 do QWE_text = QWE_text .. "Q"; Q_num = Q_num - 1 end
    while W_num > 0 do QWE_text = QWE_text .. "W"; W_num = W_num - 1 end
    while E_num > 0 do QWE_text = QWE_text .. "E"; E_num = E_num - 1 end

    return QWE_text
end

-- return whether a spell has been invoked.
function Invoker.HasInvoked(myHero, spell)
    if not myHero or not spell then return false end 
    
    local name = Ability.GetName(spell)
    local spell_1 = NPC.GetAbilityByIndex(myHero, 3)
    local spell_2 = NPC.GetAbilityByIndex(myHero, 4)    

    if spell_2 and name == Ability.GetName(spell_2) then return true end
    if spell_1 and name == Ability.GetName(spell_1) then return true end

    return false
end

-- After casting a spell , move this spell to second slot 
-- so as to protect another spell
function Invoker.ProtectSpell(myHero, spell)
    if not myHero or not spell then return end
    if not Invoker.HasInvoked(myHero, spell) then return end

    local spell_1 = NPC.GetAbilityByIndex(myHero, 3)
    local spell_2 = NPC.GetAbilityByIndex(myHero, 4)
    if not spell_1 or not spell_2 then return end
    if Ability.GetName(spell) == Ability.GetName(spell_2) then return end

    local name = Ability.GetName(spell_2)

    if name == "invoker_cold_snap" then Invoker.PressKey(myHero, "QQQR") end
    if name == "invoker_ghost_walk" then Invoker.PressKey(myHero, "QQWR") end
    if name == "invoker_tornado" then Invoker.PressKey(myHero, "QWWR") end
    if name == "invoker_emp" then Invoker.PressKey(myHero, "WWWR") end
    if name == "invoker_alacrity" then Invoker.PressKey(myHero, "WWER") end
    if name == "invoker_chaos_meteor" then Invoker.PressKey(myHero, "WEER") end
    if name == "invoker_sun_strike" then Invoker.PressKey(myHero, "EEER") end
    if name == "invoker_forge_spirit" then Invoker.PressKey(myHero, "QEER") end
    if name == "invoker_ice_wall" then Invoker.PressKey(myHero, "QQER") end
    if name == "invoker_deafening_blast" then Invoker.PressKey(myHero, "QWER") end
end

-- return true if all ordered keys have been pressed successfully
-- return false otherwise
function Invoker.PressKey(myHero, keys)
	if not myHero or not keys then return false end
	if Invoker.GetInstances(myHero) == keys then return true end

    local Q = NPC.GetAbility(myHero, "invoker_quas")
    local W = NPC.GetAbility(myHero, "invoker_wex")
    local E = NPC.GetAbility(myHero, "invoker_exort")
    local R = NPC.GetAbility(myHero, "invoker_invoke")

    for i = 1, #keys do
        local key = keys:sub(i,i)   
        if key == "Q" and (not Q or not Ability.IsCastable(Q, 0)) then return false end
        if key == "W" and (not W or not Ability.IsCastable(W, 0)) then return false end
        if key == "E" and (not E or not Ability.IsCastable(E, 0)) then return false end
        if key == "R" and (not R or not Ability.IsCastable(R, NPC.GetMana(myHero))) then return false end
    end

    for i = 1, #keys do
    	local key = keys:sub(i,i)	
    	if key == "Q" then Ability.CastNoTarget(Q) end
    	if key == "W" then Ability.CastNoTarget(W) end
    	if key == "E" then Ability.CastNoTarget(E) end
    	if key == "R" then Ability.CastNoTarget(R) end
    end

    return true
end

return Invoker