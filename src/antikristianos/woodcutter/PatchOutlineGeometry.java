package antikristianos.woodcutter;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.iso.IsoObject;

@Patch(className="zombie.iso.fboRenderChunk.FBORenderObjectOutline$Drawer2",methodName="init",strictMatch=true)
public final class PatchOutlineGeometry {
    @Patch.OnExit
    public static void after(@Patch.This Object drawer,@Patch.Argument(0) IsoObject object) {
        Main.adjustOutline(drawer,object);
    }
}
