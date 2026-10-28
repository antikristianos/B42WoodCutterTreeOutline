package antikristianos.woodcutter;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.iso.IsoObject;

@Patch(className="zombie.iso.IsoObject",methodName="removeFromSquare",strictMatch=true)
public final class PatchTreeSquareRemoved {
    @Patch.OnEnter
    public static void before(@Patch.This IsoObject object) { Main.treeChanged(object); }
}
