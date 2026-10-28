package antikristianos.woodcutter;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.iso.IsoChunk;
import zombie.iso.IsoGridSquare;

@Patch(className="zombie.iso.IsoChunk",methodName="setSquare",strictMatch=true)
public final class PatchChunkSquare {
    @Patch.OnExit
    public static void after(@Patch.This IsoChunk chunk,@Patch.Argument(0) int x,
            @Patch.Argument(1) int y,@Patch.Argument(2) int z,@Patch.Argument(3) IsoGridSquare square) {
        Main.chunkSquareChanged(chunk,x,y,z);
    }
}
