package antikristianos.woodcutter;

import java.lang.reflect.Field;
import java.util.concurrent.ConcurrentHashMap;
import org.lwjgl.opengl.GL11;
import zombie.core.SpriteRenderer;
import zombie.core.opengl.VBORenderer;
import zombie.core.skinnedmodel.model.ModelOutlines;
import zombie.core.skinnedmodel.shader.Shader;
import zombie.core.textures.ColorInfo;

/** Immutable game-thread geometry snapshots consumed by queued native render drawers. */
public final class OutlinePasses {
    private record Snapshot(PreparedContours.Pose pose) {}
    private static final ConcurrentHashMap<Object,Snapshot> independent=new ConcurrentHashMap<>();
    private static Field color,behind;
    private static Shader shader;
    public static long precedingFlushes,isolatedPasses,preparedDraws;
    public static void configure(Class<?> type)throws ReflectiveOperationException{
        color=type.getDeclaredField("outlineColor");color.setAccessible(true);
        behind=type.getDeclaredField("outlineBehindPlayer");behind.setAccessible(true);
    }
    public static void capture(Object drawer,boolean owned,PreparedContours.Pose pose){
        if(owned)independent.put(drawer,new Snapshot(pose));else independent.remove(drawer);
    }
    public static boolean isIndependent(Object drawer){return independent.containsKey(drawer);}
    /** True skips the native texture-derived mask only for our marked trees. */
    public static boolean before(Object drawer){
        Snapshot snapshot=independent.get(drawer);if(snapshot==null)return false;
        if(flush())precedingFlushes++;
        PreparedContours.Pose pose=snapshot.pose;
        // Unknown/modded compositions intentionally have no rectangle/native fallback.
        if(pose==null)return true;
        try{
            ModelOutlines outlines=ModelOutlines.instance;
            boolean clear=outlines.beginRenderOutline((ColorInfo)color.get(drawer),behind.getBoolean(drawer),false);
            GL11.glDepthMask(true);outlines.fboA.startDrawing(clear,true);
            try{
                if(shader==null)shader=new Shader("vboRenderer_PositionColor",false,false);
                VBORenderer renderer=VBORenderer.getInstance();
                renderer.startRun(renderer.formatPositionColor);renderer.setMode(GL11.GL_TRIANGLES);
                renderer.setShaderProgram(shader.getShaderProgram());
                float[] points=pose.points();
                int[] triangles=pose.shape().triangles();
                for(int i=0;i<triangles.length;i+=3){
                    int a=triangles[i]*2,b=triangles[i+1]*2,c=triangles[i+2]*2;
                    // Native addTriangle reserves all three vertices before any buffer flush.
                    renderer.addTriangle(points[a],points[a+1],0,points[b],points[b+1],0,points[c],points[c+1],0,1,1,1,1);
                }
                renderer.endRun();renderer.flush();preparedDraws++;
            }finally{outlines.fboA.endDrawing();}
        }catch(IllegalAccessException error){throw new IllegalStateException("prepared outline fields changed",error);}
        return true;
    }
    public static void after(Object drawer){if(isIndependent(drawer)&&flush())isolatedPasses++;}
    public static void release(Object drawer){independent.remove(drawer);}
    private static boolean flush(){
        ModelOutlines outlines=ModelOutlines.instance;if(!outlines.dirty)return false;
        // Native blur/blit and player mask are retained around our filled exterior polygon.
        outlines.endFrame(SpriteRenderer.instance.getRenderingPlayerIndex());outlines.dirty=false;return true;
    }
}
