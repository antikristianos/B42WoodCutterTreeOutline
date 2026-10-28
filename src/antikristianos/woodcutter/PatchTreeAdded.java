package antikristianos.woodcutter;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.iso.IsoObject;

@Patch(className="zombie.iso.IsoObject",methodName="addToWorld",strictMatch=true)
public final class PatchTreeAdded {
    @Patch.OnExit
    public static void after(@Patch.This IsoObject object) { Main.treeChanged(object); }
}
