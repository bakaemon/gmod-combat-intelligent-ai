local BR = CAI.Brain

BR.RegisterHook("brain/exec/engage", "sniper", function(data)
    BR.Exec.Engage.Ranged.Run(data)
end)