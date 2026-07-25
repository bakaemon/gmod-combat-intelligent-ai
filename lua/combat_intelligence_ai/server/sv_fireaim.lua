local BR = CAI.Brain

CAI.FireAim = {}

function CAI.FireAim.Aim(data, pos, ttl)
    local npc = data.ent
    local bull = data.suppBullseye
    if not IsValid(bull) then
        bull = ents.Create("npc_bullseye")
        if not IsValid(bull) then return end
        bull:SetPos(pos)
        bull:SetKeyValue("spawnflags", "196608")
        bull:Spawn()
        bull:SetNoDraw(true)
        bull:SetSolid(SOLID_NONE)
        bull:SetHealth(999999)
        data.suppBullseye = bull
        npc:AddEntityRelationship(bull, D_HT, 99)
    else
        bull:SetPos(pos)
    end
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
    if IsValid(data.suppBullseye) then
        local npc = data.ent
        if IsValid(npc) and npc.GetEnemy and npc:GetEnemy() == data.suppBullseye then
            npc:SetEnemy(NULL)
        end
        data.suppBullseye:Remove()
    end
    data.suppBullseye = nil
    data._fireAimUntil = nil
end

function CAI.FireAim.ClearEnemy(data)
    local npc = data.ent
    if IsValid(npc) and data.suppBullseye and npc:GetEnemy() == data.suppBullseye then
        npc:SetEnemy(NULL)
    end
end

function CAI.FireAim.Tick(data)
    if not data.suppBullseye then return end

    if data._fireAimUntil then
        if CurTime() > data._fireAimUntil then
            local npc = data.ent
            if IsValid(npc) then
                local e = npc:GetEnemy()
                if e == data.suppBullseye then
                    CAI.FireAim.Stop(data)
                else
                    data.suppBullseye:Remove()
                    data.suppBullseye = nil
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

