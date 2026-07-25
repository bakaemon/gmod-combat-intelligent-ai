local BR = CAI.Brain

CAI.FireAim = {}
local VOID_POS = Vector(0, 0, -16000)

function CAI.FireAim.Alloc(data)
    local bull = ents.Create("npc_bullseye")
    if not IsValid(bull) then return end
    bull:SetPos(VOID_POS)
    bull:SetKeyValue("spawnflags", "196608")
    bull:Spawn()
    bull:SetNoDraw(true)
    bull:SetSolid(SOLID_NONE)
    bull:SetHealth(999999)
    data.suppBullseye = bull
    local npc = data.ent
    if IsValid(npc) then npc:AddEntityRelationship(bull, D_HT, 99) end
end

function CAI.FireAim.Aim(data, pos, ttl)
    local npc = data.ent
    local bull = data.suppBullseye
    if not IsValid(bull) then return end

    bull:SetPos(pos)
    if npc.SetEnemy then
        npc:SetEnemy(bull)
        if npc.UpdateEnemyMemory and npc:GetEnemy() == bull then
            npc:UpdateEnemyMemory(bull, pos)
        end
    end
    if ttl then
        data._fireAimUntil = CurTime() + ttl
    else
        data._fireAimUntil = nil
    end
end

function CAI.FireAim.Stop(data)
    local bull = data.suppBullseye
    if not IsValid(bull) then return end

    local npc = data.ent
    if IsValid(npc) and npc.GetEnemy and npc:GetEnemy() == bull then
        npc:SetEnemy(NULL)
    end
    bull:SetPos(VOID_POS)
    data._fireAimUntil = nil
end

function CAI.FireAim.ClearEnemy(data)
    local npc = data.ent
    local bull = data.suppBullseye
    if IsValid(npc) and IsValid(bull) and npc:GetEnemy() == bull then
        npc:SetEnemy(NULL)
    end
end

function CAI.FireAim.Tick(data)
    local bull = data.suppBullseye
    if not IsValid(bull) then return end

    if data._fireAimUntil then
        if CurTime() > data._fireAimUntil then
            local npc = data.ent
            if IsValid(npc) then
                local e = npc:GetEnemy()
                if e == bull then
                    CAI.FireAim.Stop(data)
                else
                    bull:SetPos(VOID_POS)
                    data._fireAimUntil = nil
                end
            else
                CAI.FireAim.Stop(data)
            end
        end
        return
    end

    local isSuppressing = CAI.PhaseIs(data, CAI.PHASE.ENGAGE, "suppress")
    if isSuppressing then return end
    CAI.FireAim.Stop(data)
end

BR.StopSuppressing = CAI.FireAim.Stop

