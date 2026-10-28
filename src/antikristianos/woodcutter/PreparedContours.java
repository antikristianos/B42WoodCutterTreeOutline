package antikristianos.woodcutter;

import java.io.*;
import java.util.*;
import zombie.iso.objects.IsoTree;
import zombie.iso.sprite.IsoSprite;

/** Immutable shared catalog. No runtime pixel tracing, triangulation or source scans. */
public final class PreparedContours {
    public record Shape(int width,int height,float[] points,int[] triangles) {}
    public record Binding(String key,Shape shape,int x,int y) {}
    public record Pose(Shape shape,float x,float y,float[] points) {}
    private static final Map<String,Binding> variants=load();
    public static long resolutions,positionBuilds;
    private static Map<String,Binding> load(){
        try(var input=PreparedContours.class.getResourceAsStream("/antikristianos/woodcutter/exterior.bin")){
            if(input==null)throw new IOException("prepared exterior catalog missing");
            var in=new DataInputStream(input);
            if(in.readInt()!=0x57434e41||in.readInt()!=1)throw new IOException("prepared exterior format");
            int count=in.readInt();if(count!=88)throw new IOException("prepared summer shape count");
            Shape[] shapes=new Shape[count];
            for(int s=0;s<count;s++){
                int w=in.readInt(),h=in.readInt(),n=in.readInt();if(w<=0||h<=0||n<3||n>65535)throw new IOException("shape limits");
                float[] points=new float[n*2];for(int i=0;i<points.length;i++)points[i]=in.readUnsignedShort();
                int length=in.readInt();if(length<3||length>(n-2)*3||length%3!=0)throw new IOException("triangle limits");
                int[] indices=new int[length];for(int i=0;i<length;i++){indices[i]=in.readUnsignedShort();if(indices[i]>=n)throw new IOException("triangle index");}
                shapes[s]=new Shape(w,h,points,indices);
            }
            int mappings=in.readInt();if(mappings!=688)throw new IOException("composition count");
            Map<String,Binding> result=new LinkedHashMap<>();
            for(int i=0;i<mappings;i++){String key=in.readUTF();int id=in.readInt(),x=in.readInt(),y=in.readInt();if(id<0||id>=count||result.put(key,new Binding(key,shapes[id],x,y))!=null)throw new IOException("composition binding");}
            if(in.read()!=-1)throw new IOException("trailing catalog");return Collections.unmodifiableMap(result);
        }catch(IOException error){throw new IllegalStateException("Wood Cutter prepared contours unavailable",error);}
    }
    public static Collection<Binding> bindings(){return variants.values();}
    public static Binding binding(String key){return variants.get(key);}
    public static boolean sameGeometry(Binding a,Binding b){return a==b || a!=null&&b!=null&&a.shape==b.shape&&a.x==b.x&&a.y==b.y;}
    public static IsoSprite effective(IsoTree tree,IsoSprite sprite){
        if(sprite!=null&&tree.isUseSnowSprite()&&sprite.getSnowSprite()!=null)return sprite.getSnowSprite();
        return sprite;
    }
    public static Binding resolve(String name,String child,boolean unsupported){resolutions++;return unsupported?null:variants.get(name+"|"+child);}
    public static Pose pose(Binding binding,float renderX,float renderY,Pose previous){
        if(binding==null)return null;
        float x=renderX+binding.x,y=renderY+binding.y;
        if(previous!=null&&previous.shape==binding.shape&&previous.x==x&&previous.y==y)return previous;
        float[] source=binding.shape.points,points=new float[source.length];
        for(int i=0;i<points.length;i+=2){points[i]=source[i]+x;points[i+1]=source[i+1]+y;}
        positionBuilds++;return new Pose(binding.shape,x,y,points);
    }
}
