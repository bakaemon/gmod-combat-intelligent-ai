local BR = CAI.Brain

-- SEARCH: delegate to CAI.Search. Sweep the last-known area / likely hiding
-- spots, return to PATROL once the search is exhausted.
BR.Exec[6] = function(data)
    if not data.search then
        local enemy, rec = CAI.Memory.FreshestEnemy(data)
        if not rec or not CAI.Search.Begin(data, enemy, rec.pos) then
            BR.SetState(data, CAI.STATE.PATROL, "nothing_to_search")
            return
        end
    end
    if not CAI.Search.Update(data) then
        BR.SetState(data, CAI.STATE.PATROL, "search_over")
    end
end

