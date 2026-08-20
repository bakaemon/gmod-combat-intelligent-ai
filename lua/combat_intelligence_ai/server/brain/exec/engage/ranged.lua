local BR = CAI.Brain

BR.RegisterHook("brain/exec/engage", "ranged", function(data)
    BR.Exec.Engage.Ranged.Run(data)
end)