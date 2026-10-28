package antikristianos.woodcutter;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.iso.IsoObject;

@Patch(className="zombie.iso.IsoObject",methodName="removeFromWorld",strictMatch=true)
public final class PatchTreeRemoved {
    @Patch.OnEnter
    public static void before(@Patch.This IsoObject object) { Main.treeChanged(object); }
}
