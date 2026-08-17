local D = CAI.DebugUI

local beamMat = Material("cable/redlaser")

local UP2 = Vector(0, 0, 2)

local function Ring(pos, radius, col, segments)
    segments = segments or 26
    render.SetColorMaterial()
    local prev
    for i = 0, segments do
        local ang = (i / segments) * math.pi * 2
        local p = Vector(pos.x + math.cos(ang) * radius, pos.y + math.sin(ang) * radius, pos.z)
        if prev then render.DrawLine(prev, p, col, false) end
        prev = p
    end
end

local function Beam(a, b, width, col, scroll)
    render.SetMaterial(beamMat)
    local len = a:Distance(b) / 72
    local t = scroll and (CurTime() * scroll) or 0
    render.DrawBeam(a, b, width, t, t + len, col)
end

local function Cross(pos, size, col)
    render.SetColorMaterial()
    render.DrawLine(pos + Vector(-size, -size, 0), pos + Vector(size, size, 0), col, false)
    render.DrawLine(pos + Vector(-size, size, 0), pos + Vector(size, -size, 0), col, false)
end

local function Destination(from, to, col, pulse)
    local base = to + UP2
    Beam(from, base, 5, col, 1.8)
    Beam(base, base + Vector(0, 0, 52), 5, col, 0)
    Ring(base, 20 + pulse * 8, col)
    Ring(base, 9, ColorAlpha(col, col.a * 0.55), 16)
end

hook.Add("PostDrawTranslucentRenderables", "CAI_DebugWorld", function(_, skybox)
    if skybox then return end
    if not D.Fresh() then return end
    if not D.WorldEnabled() then return end

    local xray = D.Opt.xray
    if xray then cam.IgnoreZ(true) end

    local pulse = 0.5 + math.sin(CurTime() * 3.4) * 0.5
    local list = D.Sorted(0)
    local squads = {}

    for _, r in ipairs(list) do
        local npc = r.ent
        if IsValid(npc) then
            local feet = npc:GetPos() + UP2
            local chest = npc:WorldSpaceCenter()
            local a = D.Alpha(r.dist)

            if a > 0.02 then
                if r.cover then
                    local base = r.cover + UP2
                    local col = ColorAlpha(D.Col.cover, 235 * a)
                    Ring(base, 22, col)
                    Ring(base, 9, ColorAlpha(D.Col.cover, 120 * a), 16)
                    Beam(base, base + Vector(0, 0, 36), 3, col, 0)
                end

                if r.move then
                    Destination(feet, r.move, ColorAlpha(D.Col.move, 255 * a), pulse)
                end

                local tgt = Entity(r.target)
                if IsValid(tgt) then
                    Beam(chest, tgt:WorldSpaceCenter(), 2.5, ColorAlpha(D.Col.target, 200 * a), 3.2)
                end
            end

            if r.squad and r.squad > 0 then
                local s = squads[r.squad]
                if not s then
                    s = { sum = Vector(0, 0, 0), n = 0, members = {} }
                    squads[r.squad] = s
                end
                s.sum = s.sum + feet
                s.n = s.n + 1
                s.members[#s.members + 1] = feet
            end
        end
    end

    if D.Opt.links then
        for id, s in pairs(squads) do
            if s.n > 1 then
                local center = s.sum / s.n
                local col = ColorAlpha(D.SquadColor(id), 110)
                Ring(center, 26, col)
                render.SetColorMaterial()
                for _, m in ipairs(s.members) do
                    render.DrawLine(m, center, col, false)
                end
            end
        end
    end

    if D.Opt.deaths then
        local now = CurTime()
        for _, d in ipairs(D.Deaths) do
            local f = 1 - math.Clamp((now - d.t) / 30, 0, 1)
            if f > 0 then
                local p = d.pos + UP2
                Cross(p, 14, ColorAlpha(D.Col.death, 210 * f))
                Ring(p, 18 + (1 - f) * 14, ColorAlpha(D.Col.death, 95 * f), 18)
            end
        end
    end

    if xray then cam.IgnoreZ(false) end
end)