CAI.Perf = CAI.Perf or {}
local P = CAI.Perf

P.Stats = {
    managed = 0,
    thinksThisSecond = 0,
    thinksPerSecond = 0,
    avgThinkMs = 0,
    _accumMs = 0,
    _accumN = 0,
}

function P.GetThinkInterval(npc)
    local _, distSqr = CAI.Util.NearestPlayer(npc:GetPos())
    local perfMode = CAI.CVBool("cai_performance_mode")
    for _, tier in ipairs(CAI.Config.LOD) do
        if distSqr <= tier.dist * tier.dist then
            local interval = tier.interval
            if perfMode then interval = interval * 1.75 end
            return interval, tier.dist
        end
    end
    return 3.0, math.huge
end

function P.RecordThink(ms)
    P.Stats.thinksThisSecond = P.Stats.thinksThisSecond + 1
    P.Stats._accumMs = P.Stats._accumMs + ms
    P.Stats._accumN = P.Stats._accumN + 1
end

timer.Create("CAI_PerfStats", 1, 0, function()
    local S = P.Stats
    S.thinksPerSecond = S.thinksThisSecond
    S.thinksThisSecond = 0
    S.avgThinkMs = S._accumN > 0 and (S._accumMs / S._accumN) or 0
    S._accumMs, S._accumN = 0, 0
end)

CAI.Prof = CAI.Prof or {}
local Pr = CAI.Prof
Pr.active = false
Pr.t0 = 0
Pr.t1 = 0
Pr.buckets = {}

function Pr.Reset()
    Pr.buckets = {}
    Pr.t0 = SysTime()
    Pr.t1 = 0
end

function Pr.Start()
    Pr.Reset()
    Pr.active = true
    print(CAI.PrintPrefix .. "Profiler started.")
end

function Pr.Stop()
    Pr.active = false
    Pr.t1 = SysTime()
    print(CAI.PrintPrefix .. "Profiler stopped.")
end

function Pr.Record(label, secs)
    if not Pr.active then return end
    local ms = secs * 1000
    local b = Pr.buckets[label]
    if not b then b = { ms = 0, n = 0, max = 0 } Pr.buckets[label] = b end
    b.ms = b.ms + ms
    b.n = b.n + 1
    if ms > b.max then b.max = ms end
end

function Pr.Wrap(label, fn)
    return function(...)
        if not Pr.active then return fn(...) end
        local t = SysTime()
        local r = { fn(...) }
        Pr.Record(label, SysTime() - t)
        return unpack(r)
    end
end

function Pr.WrapFn(tbl, name, label)
    local orig = tbl[name]
    if not orig then return end
    tbl[name] = function(...)
        if not Pr.active then return orig(...) end
        local t = SysTime()
        local r = { orig(...) }
        Pr.Record(label, SysTime() - t)
        return unpack(r)
    end
end

function Pr.Dump()
    if Pr.t0 == 0 then
        print(CAI.PrintPrefix .. "Profiler never started. Run cai_profiler_start first.")
        return
    end
    local win = (Pr.t1 > Pr.t0 and Pr.t1 or SysTime()) - Pr.t0
    if win <= 0 then win = 1 end

    local rows = {}
    local total = 0
    for label, b in pairs(Pr.buckets) do
        total = total + b.ms
        rows[#rows + 1] = { label = label, ms = b.ms, n = b.n, max = b.max }
    end
    table.sort(rows, function(a, b) return a.ms > b.ms end)

    print(CAI.PrintPrefix .. "===== Profiler (window " .. string.format("%.1f", win) .. "s) =====")
    print(("  %-22s %9s %8s %8s %9s %7s"):format("LABEL", "ms", "n", "avg", "ms/s", "%"))
    for _, r in ipairs(rows) do
        local mss = r.ms / win
        local pct = total > 0 and (r.ms / total * 100) or 0
        print(("  %-22s %9.0f %8d %8.3f %9.1f %6.1f%%"):format(r.label, r.ms, r.n, r.n > 0 and r.ms / r.n or 0, mss, pct))
    end
    print(("  %-22s %9.0f %8s %8s %9.1f"):format("TOTAL measured", total, "", "", total / win))
    print(CAI.PrintPrefix .. "Headline: thinks/s=" .. CAI.Perf.Stats.thinksPerSecond
        .. " avgThinkMs=" .. string.format("%.3f", CAI.Perf.Stats.avgThinkMs)
        .. " managed=" .. CAI.Perf.Stats.managed)
    print(CAI.PrintPrefix .. "(session " .. (Pr.active and "RUNNING" or "stopped") .. ")")
end
