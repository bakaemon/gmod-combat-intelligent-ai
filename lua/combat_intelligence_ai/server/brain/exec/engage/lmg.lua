local BR = CAI.Brain

BR.RegisterHook("brain/exec/engage", "lmg", function(data)
    BR.Exec.Engage.Ranged.Run(data)
end)