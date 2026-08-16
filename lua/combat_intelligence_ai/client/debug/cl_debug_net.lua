local D = CAI.DebugUI

D.Rows = D.Rows or {}
D.RowsAt = D.RowsAt or 0
D.Disp = D.Disp or {}
D.Deaths = D.Deaths or {}
D.Hidden = 0

net.Receive(CAI.Net.Debug, function()
    local rows = {}
    local n = net.ReadUInt(6)
    for i = 1, n do
        local r = {}
        r.idx    = net.ReadUInt(14)
        r.phase  = net.ReadUInt(3)
        r.intent = net.ReadString()
        r.role   = net.ReadUInt(4)
        r.morale = net.ReadUInt(7)
        r.supp   = net.ReadUInt(7)
        r.squad  = net.ReadUInt(8)
        r.plan   = net.ReadString()
        r.why    = net.ReadString()
        if net.ReadBool() then r.cover = net.ReadVector() end
        if net.ReadBool() then r.move = net.ReadVector() end
        r.target = net.ReadUInt(14)
        r.memE   = net.ReadUInt(4)
        r.memD   = net.ReadUInt(4)
        r.lod    = net.ReadFloat()
        r.traits = net.ReadString()
        r.traitList = D.TraitList(r.traits)
        rows[#rows + 1] = r
    end
    D.Rows = rows
    D.RowsAt = CurTime()
end)

function D.Fresh()
    if not D.Active() then return false end
    if CurTime() - D.RowsAt > 1.2 then return false end
    return #D.Rows > 0
end

function D.Sorted(limit)
    local ply = LocalPlayer()
    if not IsValid(ply) then return {}, 0 end

    local eye = ply:EyePos()
    local out = {}
    for _, r in ipairs(D.Rows) do
        local npc = Entity(r.idx)
        if IsValid(npc) then
            r.ent = npc
            r.dist = eye:Distance(npc:WorldSpaceCenter())
            out[#out + 1] = r
        end
    end

    table.sort(out, function(a, b) return a.dist < b.dist end)

    local hidden = 0
    if limit and limit > 0 and #out > limit then
        hidden = #out - limit
        for i = #out, limit + 1, -1 do
            table.remove(out, i)
        end
    end

    local far = {}
    for i = #out, 1, -1 do
        far[#far + 1] = out[i]
    end
    return far, hidden
end

hook.Add("Think", "CAI_DebugInterp", function()
    if not D.Active() then return end

    local seen = {}
    for _, r in ipairs(D.Rows) do
        seen[r.idx] = true
        local d = D.Disp[r.idx]
        if not d then
            d = { morale = r.morale, supp = r.supp }
            D.Disp[r.idx] = d
        end
        d.morale = D.Approach(d.morale, r.morale, 95)
        d.supp = D.Approach(d.supp, r.supp, 150)
    end

    for idx in pairs(D.Disp) do
        if not seen[idx] then D.Disp[idx] = nil end
    end
end)

hook.Add("EntityRemoved", "CAI_DebugDeathMark", function(ent)
    if not D.Active() then return end
    if not D.Opt.deaths then return end
    if not IsValid(ent) or not ent:IsNPC() then return end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local pos = ent:GetPos()
    if ply:GetPos():DistToSqr(pos) > 1400 * 1400 then return end

    D.Deaths[#D.Deaths + 1] = { pos = pos, t = CurTime() }
    if #D.Deaths > 32 then table.remove(D.Deaths, 1) end
end)

timer.Create("CAI_DebugDeathPrune", 2, 0, function()
    local now = CurTime()
    for i = #D.Deaths, 1, -1 do
        if now - D.Deaths[i].t > 30 then
            table.remove(D.Deaths, i)
        end
    end
end)

cvars.AddChangeCallback("cai_debug", function(_, _, new)
    if new == "0" then
        D.Rows = {}
        D.Disp = {}
        D.Deaths = {}
        D.Hidden = 0
    end
end, "CAI_DebugClear")