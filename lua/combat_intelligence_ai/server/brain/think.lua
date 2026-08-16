local BR = CAI.Brain
local ROOT = "combat_intelligence_ai/server/brain/think/"

include(ROOT .. "perceive.lua")
include(ROOT .. "sense.lua")
include(ROOT .. "phase.lua")

function BR.Think(data, dt)
    local npc = data.ent
    if not CAI.Util.Alive(npc) then return end

    local classInfo = CAI.Config.NPCClasses[npc:GetClass()]
    if classInfo and classInfo.lightTouch then
        BR.Perceive(data)
        CAI.Memory.Fade(data)
        CAI.Suppression.Decay(data, dt)
        CAI.Morale.Regen(data, dt)
        return
    end

    BR.Perceive(data)
    CAI.Memory.Fade(data)
    CAI.Suppression.Decay(data, dt)
    CAI.Morale.Regen(data, dt)
    CAI.Personality.ApplyProficiency(data)
    CAI.Nav.CheckStuck(data)

    BR.Call("brain/react", BR.HOOK_LOADER, data, dt)

    local urgency = data.reflex and data.reflex.urgency
    local expired = data.plan and CurTime() >= data.plan.expiresAt
    if expired or urgency or data.planPending then
        BR.Call("brain/ooda", BR.HOOK_LOADER, data)
    end

    CAI.FireAim.Tick(data)
    BR.Call("brain/exec", BR.HOOK_LOADER, data)
    BR.Retaliate(data)

    if CAI.CVBool("cai_npc_regen") and npc:Health() < npc:GetMaxHealth()
       and CurTime() - (data.lastHurtAt or 0) > 6 then
        npc:SetHealth(math.min(npc:GetMaxHealth(), npc:Health() + 9 * dt))
    end
end