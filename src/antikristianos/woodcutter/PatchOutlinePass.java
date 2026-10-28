package antikristianos.woodcutter;

import me.zed_0xff.zombie_buddy.Patch;

@Patch(className="zombie.iso.fboRenderChunk.FBORenderObjectOutline$Drawer2",methodName="render",strictMatch=true)
public final class PatchOutlinePass {
    @Patch.OnEnter(skipOn=true)
    public static boolean before(@Patch.This Object drawer) { return OutlinePasses.before(drawer); }
    @Patch.OnExit
    public static void after(@Patch.This Object drawer) { OutlinePasses.after(drawer); }
}