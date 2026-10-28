package antikristianos.woodcutter;

import java.util.*;
import java.lang.reflect.Field;
import java.util.concurrent.atomic.AtomicLong;
import me.zed_0xff.zombie_buddy.Exposer;
import zombie.characters.IsoPlayer;
import zombie.core.Color;
import zombie.inventory.InventoryItem;
import zombie.inventory.types.HandWeapon;
import zombie.iso.*;
import zombie.iso.objects.IsoTree;
import zombie.iso.fboRenderChunk.FBORenderChunk;
import zombie.iso.sprite.IsoSprite;
import zombie.scripting.objects.WeaponCategory;

@Exposer.LuaClass(name="WoodCutterTreeOutline")
public final class Main {
    private static final long POLL_NS=100_000_000L;
    private static int outlineRange=5;
    private static boolean alwaysShow,showInVehicle;
    private static final int HIDDEN=0,GRAY=1,AIM=2;
    private static final List<IsoTree> candidates=new ArrayList<>();
    private static final IdentityHashMap<IsoTree,Mark> marks=new IdentityHashMap<>();
    private static IsoPlayer trackedPlayer;
    // Build 42.22 uses eight tiles per chunk. The revision gate also guards this layout.
    private static final int CHUNK_TILES=8;
    private static final IsoChunk[] chunks=new IsoChunk[16];
    private static final short[] chunkLoadIds=new short[16];
    private static volatile Region region;
    private static final AtomicLong worldChanges=new AtomicLong();
    private static long cachedWorldChange;
    private static float radiusX=Float.NaN,radiusY=Float.NaN;
    private static IsoTree currentTarget;
    private static int generation;
    private static long lastPoll;
    private static boolean pollStarted;
    public static long scans,polls;
    public static long squareReads,chunkChecks,radiusChecks,colorWrites,flagWrites,anchorBuilds;
    public static boolean supported;
    private static Field drawerX,drawerY;
    private static int diagnosticSamples;
    private static long lastDiagnostic;
    private static boolean diagnosticStarted;

    public static void main(String[] args) {
        supported="e013dbb529".equals(zombie.GitVersion.REVISION);
        if(supported)try{
            Class<?> drawer=Class.forName("zombie.iso.fboRenderChunk.FBORenderObjectOutline$Drawer2");
            drawerX=drawer.getDeclaredField("renderX");drawerY=drawer.getDeclaredField("renderY");
            drawerX.setAccessible(true);drawerY.setAccessible(true);
            OutlinePasses.configure(drawer);PreparedContours.bindings();
        }catch(ReflectiveOperationException error){supported=false;System.out.println("[B42WoodCutterTreeOutline] outline geometry unavailable: "+error);}
        System.out.println("[B42WoodCutterTreeOutline] " + (supported ? "active; native tree-target rules, configurable character radius, 100 ms minimum query interval" : "inactive: game revision needs target-rule review"));
    }
    public static int getOutlineRange() { return outlineRange; }
    public static boolean getAlwaysShow() { return alwaysShow; }
    public static void setAlwaysShow(boolean value) { alwaysShow=value; }
    public static boolean getShowInVehicle() { return showInVehicle; }
    public static void setShowInVehicle(boolean value) { showInVehicle=value; }
    public static void setOutlineRange(double value) {
        outlineRange=Double.isFinite(value) ? (int)Math.max(0,Math.min(10,Math.round(value))) : 5;
        if(outlineRange==0)clearMarks();
    }
    public static HandWeapon equippedAxe(IsoPlayer player) {
        if(player==null)return null;
        InventoryItem primary=player.getPrimaryHandItem();
        if(!(primary instanceof HandWeapon axe) || primary!=player.getSecondaryHandItem() || axe.getScriptItem()==null)return null;
        return axe.getScriptItem().containsWeaponCategory(WeaponCategory.AXE) ? axe : null;
    }
    /** Read-only equivalent of the reviewed native tree selection, not a damage call. */
    public static IsoTree swingTarget(IsoPlayer player,HandWeapon axe) {
        if(player==null || axe==null || axe.isBroken() || player.isAimAtFloor())return null;
        IsoGridSquare origin=player.getCurrentSquare();
        if(!matchesPosition(player,origin) || IsoWorld.instance.currentCell==null)return null;
        IsoDirections direction=IsoDirections.fromAngle(player.getForwardDirection());
        IsoGridSquare next=IsoWorld.instance.currentCell.getGridSquare(origin.x+direction.dx(),origin.y+direction.dy(),origin.z);
        if(next==null || next.x!=origin.x+direction.dx() || next.y!=origin.y+direction.dy() || next.z!=origin.z || next.isBlockedTo(origin))return null;
        // Native combat retains the last tree if a mod places multiple trees on a tile.
        for(int i=next.getObjects().size()-1;i>=0;i--)
            if(next.getObjects().get(i) instanceof IsoTree tree && tree.square==next)return tree;
        return null;
    }
    private static boolean matchesPosition(IsoPlayer player,IsoGridSquare square) {
        float x=player.getX(),y=player.getY(),z=player.getZ();
        return square!=null && Float.isFinite(x) && Float.isFinite(y) && Float.isFinite(z)
            && square.x==Math.floor(x) && square.y==Math.floor(y) && square.z==Math.floor(z);
    }
    public static boolean insideRadius(IsoPlayer player,IsoTree tree) {
        if(outlineRange==0 || player==null || tree==null || tree.square==null)return false;
        float dx=tree.square.x+.5f-player.getX(),dy=tree.square.y+.5f-player.getY();
        return dx*dx+dy*dy<=outlineRange*outlineRange;
    }
    public static void update(IsoPlayer player) {
        updateAt(player,System.nanoTime());
    }
    public static void updateAt(IsoPlayer player,long now) {
        if(!beginPoll(player,now))return;
        int mode=outlineMode(player);
        if(mode==HIDDEN){clearMarks();return;}
        paintAroundPlayer(player,mode==AIM);
        if(mode==AIM && diagnosticSamples>0 && (!diagnosticStarted || now-lastDiagnostic>=1_000_000_000L)){
            diagnosticStarted=true;lastDiagnostic=now;diagnosticSamples--;
            logSnapshot(player);
        }
    }
    /** Bounded WIP evidence: one sample per second of aiming, never a per-frame log. */
    public static void enableDiagnostics(int samples) {
        diagnosticSamples=Math.max(0,Math.min(samples,60));diagnosticStarted=false;
    }
    private static String squareText(IsoGridSquare square) {
        return square==null ? "null" : square.x+","+square.y+","+square.z;
    }
    private static void logSnapshot(IsoPlayer player) {
        HandWeapon axe=equippedAxe(player);
        IsoTree target=currentTarget;
        Mark mark=marks.get(target);
        float zoom=zombie.core.Core.getInstance().getZoom(0);
        float mouseX=zombie.input.Mouse.getXA()*zoom,mouseY=zombie.input.Mouse.getYA()*zoom;
        System.out.println("[B42WoodCutterTreeOutline] sample player="+player.getX()+","+player.getY()+","+player.getZ()
            +" current="+squareText(player.getCurrentSquare())+" square="+squareText(player.square)
            +" direction="+IsoDirections.fromAngle(player.getForwardDirection())
            +" mouseWorld="+IsoUtils.XToIso(0,mouseX,mouseY,player.getZ())+","+IsoUtils.YToIso(0,mouseX,mouseY,player.getZ())
            +" target="+squareText(target==null?null:target.square)+" marked="+(mark!=null)
            +" axe="+axe.getFullType()+" min="+axe.getMinRange()+" max="+axe.getMaxRange(player)+" rangeMod="+axe.getRangeMod(player)
            +" draw="+(mark==null?"none":mark.drawX+","+mark.drawY)
            +" camera="+IsoCamera.frameState.offX+","+IsoCamera.frameState.offY
            +" spriteOffset="+IsoSprite.globalOffsetX+","+IsoSprite.globalOffsetY+" remaining="+diagnosticSamples);
    }
    private static boolean beginPoll(IsoPlayer player,long now) {
        if(player==null || player.getPlayerNum()!=0 || !player.isLocalPlayer())return false;
        if(pollStarted && now-lastPoll<POLL_NS)return false;
        pollStarted=true;lastPoll=now;polls++;
        return true;
    }
    private static int outlineMode(IsoPlayer player) {
        if(outlineRange==0 || !supported || player.getJoypadBind()!=-1 || player.isDead())return HIDDEN;
        IsoGridSquare square=player.getCurrentSquare();
        if(!matchesPosition(player,square) || !square.isOutside() || square.isInARoom())return HIDDEN;
        if(player.getVehicle()!=null)return showInVehicle ? GRAY : HIDDEN;
        if(player.isAiming() && equippedAxe(player)!=null)return AIM;
        return alwaysShow ? GRAY : HIDDEN;
    }
    private static void paintAroundPlayer(IsoPlayer player,boolean detectHit) {
        float playerX=player.getX(),playerY=player.getY();
        if(!Float.isFinite(playerX) || !Float.isFinite(playerY)) {clearMarks();return;}
        if(trackedPlayer!=player){clearMarks();trackedPlayer=player;}
        IsoCell cell=IsoWorld.instance.currentCell;
        if(cell==null || !matchesPosition(player,player.getCurrentSquare())){clearMarks();return;}
        boolean rebuilt=refreshCandidates(cell,player.getCurrentSquare());
        if(rebuilt || playerX!=radiusX || playerY!=radiusY){
            radiusX=playerX;radiusY=playerY;generation++;
            for(IsoTree tree:candidates){
                radiusChecks++;
                if(tree.square==null || tree.getObjectIndex()<0 || !insideRadius(player,tree))continue;
                Mark mark=marks.get(tree);
                if(mark==null){mark=new Mark(tree,player.getPlayerNum());marks.put(tree,mark);}
                mark.generation=generation;
            }
            var iterator=marks.entrySet().iterator();
            while(iterator.hasNext()){
                var entry=iterator.next();
                if(entry.getValue().generation!=generation){entry.getValue().restore(entry.getKey());iterator.remove();}
            }
        }
        // The adjacent-square obstruction can change without player movement.
        currentTarget=detectHit ? swingTarget(player,equippedAxe(player)) : null;
        for(var entry:marks.entrySet())entry.getValue().paint(entry.getKey(),entry.getKey()==currentTarget);
    }
    private static boolean refreshCandidates(IsoCell cell,IsoGridSquare origin) {
        Region area=region;
        boolean rebuild=area==null || area.cell!=cell || area.x!=origin.x || area.y!=origin.y || area.z!=origin.z || area.radius!=outlineRange;
        if(rebuild){area=new Region(cell,origin.x,origin.y,origin.z,outlineRange);region=area;Arrays.fill(chunks,null);}
        long revision=worldChanges.get();
        rebuild|=revision!=cachedWorldChange;
        int index=0;
        for(int x=area.minChunkX;x<=area.maxChunkX;x++)for(int y=area.minChunkY;y<=area.maxChunkY;y++){
            IsoChunk chunk=cell.getChunk(x,y);chunkChecks++;
            if(chunk!=null && (!chunk.loaded || chunk.wx!=x || chunk.wy!=y))chunk=null;
            short loadId=chunk==null ? 0 : chunk.getLoadID();
            if(chunks[index]!=chunk || chunkLoadIds[index]!=loadId)rebuild=true;
            chunks[index]=chunk;chunkLoadIds[index]=loadId;index++;
        }
        if(!rebuild)return false;
        candidates.clear();
        for(int x=area.x-area.radius;x<=area.x+area.radius;x++)for(int y=area.y-area.radius;y<=area.y+area.radius;y++){
            IsoChunk chunk=chunks[(Math.floorDiv(x,CHUNK_TILES)-area.minChunkX)*area.chunkRows+Math.floorDiv(y,CHUNK_TILES)-area.minChunkY];
            if(chunk==null)continue;
            IsoGridSquare square=chunk.getGridSquare(Math.floorMod(x,CHUNK_TILES),Math.floorMod(y,CHUNK_TILES),area.z);squareReads++;
            if(square==null || square.x!=x || square.y!=y || square.z!=area.z)continue;
            for(int i=0;i<square.getObjects().size();i++)if(square.getObjects().get(i) instanceof IsoTree tree && tree.square==square)candidates.add(tree);
        }
        cachedWorldChange=revision;scans++;
        return true;
    }
    /** Lifecycle hooks only invalidate a nearby cache; all scans stay behind the poll gate. */
    public static void treeChanged(IsoObject object) {
        if(!supported || !(object instanceof IsoTree) || object.square==null)return;
        squareChanged(object.square.x,object.square.y,object.square.z);
    }
    public static void chunkSquareChanged(IsoChunk chunk,int x,int y,int z) {
        if(supported && chunk!=null)squareChanged(chunk.wx*CHUNK_TILES+x,chunk.wy*CHUNK_TILES+y,z);
    }
    private static void squareChanged(int x,int y,int z) {
        Region area=region;
        if(area!=null && area.z==z && Math.abs((long)x-area.x)<=area.radius && Math.abs((long)y-area.y)<=area.radius)worldChanges.incrementAndGet();
    }
    private static final class Region {
        final IsoCell cell;
        final int x,y,z,radius,minChunkX,maxChunkX,minChunkY,maxChunkY,chunkRows;
        Region(IsoCell cell,int x,int y,int z,int radius){
            this.cell=cell;this.x=x;this.y=y;this.z=z;this.radius=radius;
            minChunkX=Math.floorDiv(x-radius,CHUNK_TILES);maxChunkX=Math.floorDiv(x+radius,CHUNK_TILES);
            minChunkY=Math.floorDiv(y-radius,CHUNK_TILES);maxChunkY=Math.floorDiv(y+radius,CHUNK_TILES);
            chunkRows=maxChunkY-minChunkY+1;
        }
    }
    public static void reset() {
        clearMarks();pollStarted=false;
    }
    // The native object-outline drawer does not apply IsoTree's jumbo anchors.
    // Only use the geometry prepared by the throttled query; no scans in drawing.
    public static void adjustOutline(Object drawer,IsoObject object) {
        Mark mark=supported && object instanceof IsoTree tree ? marks.get(tree) : null;
        if(mark==null)OutlinePasses.capture(drawer,false,null);
        if(mark==null)return;
        IsoTree tree=(IsoTree)object;
        try{
            mark.drawX=drawerX.getFloat(drawer)+tree.offsetX-mark.anchorX;
            mark.drawY=drawerY.getFloat(drawer)+tree.offsetY-mark.anchorY;
            drawerX.setFloat(drawer,mark.drawX);drawerY.setFloat(drawer,mark.drawY);
            mark.pose=PreparedContours.pose(mark.binding,mark.drawX,mark.drawY,mark.pose);
            OutlinePasses.capture(drawer,true,mark.pose);
        }catch(IllegalAccessException error){throw new IllegalStateException("outline geometry access changed",error);}
    }
    public static float outlineShiftX(IsoTree tree) {
        Mark mark=marks.get(tree);
        return mark==null ? 0f : tree.offsetX-mark.anchorX;
    }
    public static float outlineShiftY(IsoTree tree) {
        Mark mark=marks.get(tree);
        return mark==null ? 0f : tree.offsetY-mark.anchorY;
    }
    private static void clearMarks() {
        if(trackedPlayer==null && marks.isEmpty() && region==null)return;
        for(var entry:marks.entrySet())entry.getValue().restore(entry.getKey());
        marks.clear();candidates.clear();trackedPlayer=null;
        region=null;Arrays.fill(chunks,null);radiusX=Float.NaN;radiusY=Float.NaN;currentTarget=null;
    }
    private static final class Mark {
        final int player,color;
        final boolean highlight,attached,blink;
        int paintedColor,generation;
        IsoSprite sprite;
        String spriteName;
        IsoSprite contourSprite,contourChild;
        String contourName,contourChildName;
        boolean contourUnsupported;
        PreparedContours.Binding binding;
        PreparedContours.Pose pose;
        float anchorX,anchorY;
        float drawX=Float.NaN,drawY=Float.NaN;
        Mark(IsoTree tree,int player){
            this.player=player;color=tree.getOutlineHighlightCol(player);
            highlight=tree.isOutlineHighlight(player);attached=tree.isOutlineHlAttached(player);blink=tree.isOutlineHlBlink(player);
        }
        void paint(IsoTree tree,boolean hit){
            IsoSprite currentSprite=tree.getSprite();
            String currentName=currentSprite==null ? null : currentSprite.name;
            if(sprite!=currentSprite || !Objects.equals(spriteName,currentName) || anchorY==0f){
                anchorBuilds++;
                sprite=currentSprite;spriteName=currentName;
                anchorX=FBORenderChunk.FLOOR_WIDTH/2f;anchorY=FBORenderChunk.PIXELS_PER_LEVEL;
                if(currentName!=null && currentName.contains("JUMBOXXL")){
                    anchorX=FBORenderChunk.JUMBO_XXL_WIDTH/2f;anchorY=FBORenderChunk.JUMBO_XXL_HEIGHT-FBORenderChunk.FLOOR_HEIGHT;
                }else if(currentName!=null && currentName.contains("JUMBOXL")){
                    anchorX=FBORenderChunk.JUMBO_XL_WIDTH/2f;anchorY=FBORenderChunk.JUMBO_XL_HEIGHT-FBORenderChunk.FLOOR_HEIGHT;
                }else if(currentName!=null && currentName.contains("JUMBO")){
                    anchorX=FBORenderChunk.JUMBO_L_WIDTH/2f;anchorY=FBORenderChunk.JUMBO_L_HEIGHT-FBORenderChunk.FLOOR_HEIGHT;
                }
            }
            IsoSprite base=PreparedContours.effective(tree,tree.getSprite());
            int count=tree.getAttachedAnimSpriteCount();
            IsoSprite child=count==1?PreparedContours.effective(tree,tree.getAttachedAnimSprite().get(0).getParentSprite()):null;
            String name=base==null?"":base.name,childName=child==null?"":child.name;
            boolean unsupported=count>1||tree.getOverlaySprite()!=null;
            if(base!=contourSprite||child!=contourChild||!Objects.equals(name,contourName)||!Objects.equals(childName,contourChildName)||unsupported!=contourUnsupported){
                contourSprite=base;contourChild=child;contourName=name;contourChildName=childName;contourUnsupported=unsupported;
                PreparedContours.Binding next=PreparedContours.resolve(name,childName,unsupported);
                if(!PreparedContours.sameGeometry(binding,next))pose=null;
                binding=next;
            }
            paintedColor=hit ? 0xff00ff00 : 0xff808080;
            if(tree.getOutlineHighlightCol(player)!=paintedColor){
                float gray=128f/255f;
                tree.setOutlineHighlightCol(player,hit?0f:gray,hit?1f:gray,hit?0f:gray,1f);colorWrites++;
            }
            if(!tree.isOutlineHlAttached(player)){tree.setOutlineHlAttached(player,true);flagWrites++;}
            if(tree.isOutlineHlBlink(player)){tree.setOutlineHlBlink(player,false);flagWrites++;}
            if(!tree.isOutlineHighlight(player)){tree.setOutlineHighlight(player,true);flagWrites++;}
        }
        void restore(IsoTree tree){
            if(tree.getOutlineHighlightCol(player)!=paintedColor)return;
            tree.setOutlineHighlight(player,highlight);tree.setOutlineHlAttached(player,attached);tree.setOutlineHlBlink(player,blink);
            tree.setOutlineHighlightCol(player,Color.getRedChannelFromABGR(color),Color.getGreenChannelFromABGR(color),Color.getBlueChannelFromABGR(color),Color.getAlphaChannelFromABGR(color));
        }
    }
}
