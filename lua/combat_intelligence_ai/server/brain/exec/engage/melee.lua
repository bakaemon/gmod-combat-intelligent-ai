local BR = CAI.Brain

BR.RegisterHook("brain/exec/engage", "melee", function(data)
    BR.Exec.Engage.Melee.Run(data)
end)