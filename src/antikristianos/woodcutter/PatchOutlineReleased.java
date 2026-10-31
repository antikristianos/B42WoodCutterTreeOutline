package antikristianos.woodcutter;

import me.zed_0xff.zombie_buddy.Patch;

@Patch(className="zombie.iso.fboRenderChunk.FBORenderObjectOutline$Drawer2",methodName="postRender",strictMatch=true)
public final class PatchOutlineReleased {
    @Patch.OnEnter
    public static void before(@Patch.This Object drawer) { OutlinePasses.release(drawer); }
}