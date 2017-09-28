---------------------------------------------------
-- S3 "Simple 3D" library
---------------------------------------------------
-- Constants and aliases:
local sin,cos,PI=math.sin,math.cos,math.pi
local floor,ceil,sqrt=math.floor,math.ceil,math.sqrt
local min,max,abs,HUGE=math.min,math.max,math.abs,math.huge
local random=math.random
function clamp(x,lo,hi) return max(min(x,hi),lo) end

local SCRW=240
local SCRH=136

-- Texture IDs (replace by your texture IDs).
-- Also set the appropriate texture params in S3.TEX
-- below.
local TID={
  STONE=256,     -- stone wall
  DOOR=260,      -- door
  LDOOR=264,     -- locked door
  CYC_W1=320,    -- cyclops walk 1
  CYC_ATK=324,   -- cyclops attack
  CYC_W2=384,    -- cyclops walk 2
  CYC_PRE=448,   -- cyclops prepare
  CBOW_N=460,    -- crossbow neutral
  CBOW_D=492,    -- crossbow drawn
  CBOW_E=428,    -- crossbow empty
  ARROW=412,     -- arrow flying
  POTION_1=458,  -- healing potion
  POTION_2=490,
  AMMO_1=456,    -- ammo (arrows)
  AMMO_2=488,
  DEMON_1=388,   -- flying demon, flying 1
  DEMON_2=390,   -- flying demon, flying 2
  DEMON_PRE=420, -- flying demon, prepare
  DEMON_ATK=422, -- flying demon, attack
  KEY_1=440,     -- key (on floor, to pick up)
  KEY_2=442,
}

local S3={
 ---------------------------------------------------
 -- ENGINE CONFIGURATION SECTION

 -- If true, interleave frames for performance
 -- (each frame alternates drawing odd/even cols).
 ILEAVE=true,
 -- Viewport (left, top, right, bottom)
 VP_L=0,VP_T=0,VP_R=239,VP_B=119,
 -- min/max world Y coord of all walls
 FLOOR_Y=0,
 CEIL_Y=50,
 -- fog start and end dists (squared)
 FOG_S=20000,
 FOG_E=80000,
 -- light flicker amount (as dist squared)
 FLIC_AMP=1500,
 FLIC_FM=0.003,  -- frequency multiplier
 -- Texture definitions. Each texture is identified
 -- by a texture ID, which is the top-left sprite
 -- where the texture starts. This map is keyed
 -- by texture ID.
 TEX={
  [TID.STONE]={w=32,h=32},
  [TID.DOOR]={w=32,h=32},
  [TID.LDOOR]={w=32,h=32},
  [TID.CYC_W1]={w=32,h=32},
  [TID.CYC_ATK]={w=32,h=32},
  [TID.CYC_W2]={w=32,h=32},
  [TID.CYC_PRE]={w=32,h=32},
  [TID.CBOW_N]={w=32,h=16},
  [TID.CBOW_D]={w=32,h=16},
  [TID.CBOW_E]={w=32,h=16},
  [TID.ARROW]={w=8,h=8},
  [TID.POTION_1]={w=16,h=16},
  [TID.POTION_2]={w=16,h=16},
  [TID.AMMO_1]={w=16,h=16},
  [TID.AMMO_2]={w=16,h=16},
  [TID.DEMON_1]={w=16,h=16},
  [TID.DEMON_2]={w=16,h=16},
  [TID.DEMON_PRE]={w=16,h=16},
  [TID.DEMON_ATK]={w=16,h=16},
  [TID.KEY_1]={w=16,h=8},
  [TID.KEY_2]={w=16,h=8},
 },
 
 ---------------------------------------------------
 -- ENGINE INTERNALS:

 -- eye coordinates (world coords)
 ex=0, ey=0, ez=0, yaw=0,
 -- Precomputed from ex,ey,ez,yaw:
 cosMy=0, sinMy=0, termA=0, termB=0,
 -- Clock (in frames).
 t=0,
 -- These are hard-coded into the projection function,
 -- so if you change them, also update the math.
 NCLIP=0.1,
 FCLIP=1000,
 -- list of all walls, each with
 --
 --  lx,lz,rx,rz: x,z coords of left and right endpts
 --  in world coords (y coord is auto, goes from
 --  FLOOR_Y to CEIL_Y)
 --  tid: texture ID
 --
 --  Computed at render time:
 --   slx,slz,slty,slby: screen space coords of
 --     left side of wall (x, z, top y, bottom y)
 --   srx,srz,srty,srby: screen space coords of
 --     right side of wall (x, z, top y, bottom y)
 --   clifs,clife: clip fraction start/end (0 to 1).
 --     Indicates how much of this wall is being
 --     drawn. If cfs=0 and cfe=1, whole wall. If
 --     for example cfs=0.25 and cfe=1 then only
 --     the right 3/4 of the wall are drawn (rest
 --     is z-clipped).
 walls={},
 -- H-Buffer, used at render time. For each screen
 -- X coordinate x, hbuf[x+1] (1-based) stores
 -- info about which wall will be rendered on that
 -- coord, and also depth. This allows clipping and
 -- rudimentary depth testing.
 hbuf={},
 -- Floor and ceiling colors.
 floorC=9,
 ceilC=0,
 -- Color model, indicating which colors are shades
 -- of the same hue.
 clrM={
  -- Gray ramp
  {1,2,3,15},
  -- Green ramp
  {7,6,5,4},
  -- Brown ramp
  {8,9,10,11}
 },
 -- Reverse color lookup (ramp for given color)
 -- Fields:
 --   ramp (reference to a ramp in clrM)
 --   i (index of the color within the ramp).
 clrMR={}, -- computed on init
 -- PVS (Potentially Visible Set) grid square size.
 PVS_CELL=50,
 -- Potentially visible set of walls for each
 -- tile that the player can be on. This is indexed
 -- by r*10000+c and gives an array of walls
 -- potentially visible from that position.
 pvstab={},
 -- stencil buf, addressed as y*240+x+1. To avoid
 -- having to clear this buf, the value is the # of
 -- the frame when the value was written; any values
 -- below that are ignored.
 stencil={},
 -- All billboards. Each:
 --  x,y,z: world position of center
 --  w,h: width and height, world coords
 --  tid: texture ID
 --  clrO: if not nil, override all non transparent
 --   pixels with this color.
 --  Computer at render time:
 --   sx,sy,sz: screen coords
 --   sw,sh: width/height in screen coords
 --   slx,srx: left/right x screen coord
 --   sty,sby: top/bottom y screen coord
 --   vis: (bool) true iff any part of this bill
 --    was visible (rendered to screen) last
 --    frame.
 bills={},
 -- All overlays (screen space). Each:
 --   sx,sy: screen position on which to render
 --   scale: scale factor (integer -- 2, 3, etc)
 --   tid: texture ID
 overs={},
 -- Potentially visible billboards, z-ordered
 -- from near to far. Computed every frame.
 zobills={},
}

function S3Init()
 _S3InitClr()
 S3Reset()
 _S3StencilInit()
end

function S3Reset()
 S3SetCam(0,0,0,0)
 S3.walls={}
 S3.pvstab={}
end

function _S3InitClr()
 -- Build reverse color model
 for c=15,1,-1 do S3.clrMR[c]=nil end
 for _,ramp in pairs(S3.clrM) do
  for i=1,#ramp do
   local thisC=ramp[i]
   S3.clrMR[thisC]={ramp=ramp,i=i}
  end
 end
end

-- Modules a color by a given factor, using the
-- color ramps in the color model.
-- If sx,sy are provided, we will dither using
-- that screen position as reference.
function _S3ClrMod(c,f,x,y)
 if f==1 then return c end
 local mr=S3.clrMR[c]
 if not mr then return c end
 local di=mr.i*f -- desired intensity
 local int
 if x then
  -- Dither.
  local loi=floor(di)
  local hii=ceil(di)
  local fac=di-loi
  local ent=(x+y)%3
  int=fac>0.9 and hii or
   ((fac>0.5 and ent~=1) and hii or
   ((fac>0.1 and ent==1) and hii or loi))
 else
  -- No dither, just round.
  int=S3Round(di)
 end
 return int<=0 and 0 or
   mr.ramp[S3Clamp(int,1,#mr.ramp)]
end

-- Adds a wall. Walls must have:
--    lx,lz,rx,rz: endpoint coordinates
--    tid: texture ID
function S3WallAdd(w)
 assert(w.lx) assert(w.lz) assert(w.rx) assert(w.rz)
 assert(w.tid)
 table.insert(S3.walls,w)
 _S3WallReg(w.lx,w.lz,w)
 _S3WallReg(w.rx,w.rz,w)
end

-- We don't actually delete walls (that would
-- be slow). We just mark them as dead.
function S3WallDel(w) w.dead=true end

-- Register an endpoint of a wall in the PVS table.
function _S3WallReg(x,z,w)
 -- Add the wall to all PVSs in a certain radius.
 local RADIUS=6
 local RADIUS2=RADIUS*RADIUS
 x,z=S3Round(x),S3Round(z)
 local centerC,centerR=x//S3.PVS_CELL,z//S3.PVS_CELL
 for r=centerR-RADIUS,centerR+RADIUS do
  for c=centerC-RADIUS,centerC+RADIUS do
   local dist2=(c-centerC)*(c-centerC)+
     (r-centerR)*(r-centerR)
   if dist2<=RADIUS2 then
    _S3PvsAdd(c,r,w)
   end
  end
 end
 
end

function _S3PvsAdd(c,r,w)
 local t=S3.pvstab[r*32768+c]
 if not t then
  t={}
  S3.pvstab[r*32768+c]=t
 end
 for i=1,#t do
  if t[i]==w then return end -- already in table
 end
 table.insert(t,w)
end

-- Returns the PVS for the given coordinates,
-- or an empty set if there is none.
local _S3PvsGet_empty={}
function _S3PvsGet(x,z)
 x,z=S3Round(x),S3Round(z)
 local c,r=x//S3.PVS_CELL,z//S3.PVS_CELL
 return S3.pvstab[r*32768+c] or _S3PvsGet_empty;
end

function S3SetCam(ex,ey,ez,yaw)
 S3.ex,S3.ey,S3.ez,S3.yaw=ex,ey,ez,yaw
 -- Precompute some factors we will need often:
 S3.cosMy,S3.sinMy=cos(-yaw),sin(-yaw)
 S3.termA=-ex*S3.cosMy-ez*S3.sinMy
 S3.termB=ex*S3.sinMy-ez*S3.cosMy
end

function S3Proj(x,y,z)
 local c,s,a,b=S3.cosMy,S3.sinMy,S3.termA,S3.termB
 -- Hard-coded from manual matrix calculations:
 local px=0.9815*c*x+0.9815*s*z+0.9815*a
 local py=1.7321*y-1.7321*S3.ey
 local pz=s*x-z*c-b-0.2
 local pw=x*s-z*c-b
 local ndcx=px/abs(pw)
 local ndcy=py/abs(pw)
 return 120+ndcx*120,68-ndcy*68,pz
end

function S3Rend()
 local pvs=_S3PvsGet(S3.ex,S3.ez)
 local hbuf=S3.hbuf
 -- First, prepare the HBUF. We will use it for
 -- clipping.
 _S3PrepHbuf(hbuf,pvs)
 -- Render overlays before anything else. Write
 -- stencil.
 _S3RendOvers()
 -- Now render the billboards BEFORE the walls.
 -- Billboards will write stencil, and will be clipped
 -- by the HBUF.
 _S3RendBills()
 -- Now render the walls. Clipped by stencil so we
 -- don't render over billboards.
 _S3RendHbuf(hbuf)
 -- And lastly, render ceiling and floor. Clipped
 -- by stencil so we don't render over anything
 -- else.
 _S3RendFlats(hbuf)
 S3.t=S3.t+1
end

function _S3ResetHbuf(hbuf)
 for x=S3.VP_L,S3.VP_R do
  -- hbuf is 1-indexed (because Lua)
  hbuf[x+1]=hbuf[x+1] or {}
  local b=hbuf[x+1]
  b.wall=nil
  b.z=HUGE
 end
end

-- Compute screen-space coords for wall.
function _S3ProjWall(w,boty,topy)
 topy=topy or S3.CEIL_Y
 boty=boty or S3.FLOOR_Y
 local nclip=S3.NCLIP
 local fclip=S3.FCLIP

 local lx,lz,rx,rz=w.lx,w.lz,w.rx,w.rz

 for try=1,2 do  -- second try is with z clipping
  -- notation: lt=left top, rt=right top, etc.
  local ltx,lty,ltz=S3Proj(lx,topy,lz)
  local rtx,rty,rtz=S3Proj(rx,topy,rz)
  if rtx<=ltx then return false end  -- cull back side
  if rtx<S3.VP_L or ltx>S3.VP_R then return false end
  local lbx,lby,lbz=S3Proj(lx,boty,lz)
  local rbx,rby,rbz=S3Proj(rx,boty,rz)

  w.slx,w.slz,w.slty,w.slby=ltx,ltz,lty,lby
  w.srx,w.srz,w.srty,w.srby=rtx,rtz,rty,rby

  if w.slz<nclip and w.srz<nclip
    then return false
  elseif w.slz>fclip and w.srz>fclip
    then return false
  elseif try==2 then return true
  elseif w.slz<nclip then -- left is nearer than nclip
   local cutsx=_S3Interp(w.slz,w.slx,w.srz,w.srx,nclip)
   local f=(cutsx-w.slx)/(w.srx-w.slx)
   lx,lz=lx+f*(rx-lx),lz+f*(rz-lz)
   w.clifs,w.clife=f,1
  elseif w.srz<nclip then -- right is nearer than nclip
   local cutsx=_S3Interp(w.slz,w.slx,w.srz,w.srx,nclip)
   local f=(cutsx-w.slx)/(w.srx-w.slx)
   rx,rz=lx+f*(rx-lx),lz+f*(rz-lz)
   w.clifs,w.clife=0,f
  else
   w.clifs,w.clife=0,1
   return true
  end
 end
end

-- Calculates how to iterate over the HBUF in the
-- given frame to account for possible interleaving.
-- Returns startx,endx,step to be used for iteration.
function _S3AdjHbufIter(startx,endx)
 if not S3.ILEAVE then
  return startx,endx,1
 end
 if startx%2~=S3.t%2 then
  return startx+1,endx,2
 else
  return startx,endx,2
 end
end

function _S3PrepHbuf(hbuf,walls)
 _S3ResetHbuf(hbuf)
 for i=1,#walls do
  local w=walls[i]
  if not w.dead then
   if _S3ProjWall(w) then _AddWallToHbuf(hbuf,w) end
  end
 end
 -- Now hbuf has info about all the walls that we have
 -- to draw, per screen X coordinate.
 -- Fill in the top and bottom y coord per column as
 -- well.
 for x=S3.VP_L,S3.VP_R do
  local hb=hbuf[x+1] -- hbuf is 1-indexed
  if hb.wall then
   local w=hb.wall
   hb.ty=S3Round(_S3Interp(w.slx,w.slty,w.srx,w.srty,x))
   hb.by=S3Round(_S3Interp(w.slx,w.slby,w.srx,w.srby,x))
  end
 end
end

function _AddWallToHbuf(hbuf,w)
 local startx=max(S3.VP_L,S3Round(w.slx))
 local endx=min(S3.VP_R,S3Round(w.srx))
 local step
 local nclip,fclip=S3.NCLIP,S3.FCLIP
 startx,endx,step=_S3AdjHbufIter(startx,endx)

 for x=startx,endx,step do
  -- hbuf is 1-indexed (because Lua)
  local hbx=hbuf[x+1]
  local z=_S3Interp(w.slx,w.slz,w.srx,w.srz,x)
  if z>nclip and z<fclip then
   if hbx.z>z then  -- depth test.
    hbx.z,hbx.wall=z,w  -- write new depth.
   else
   end
  end
 end
end

function _S3RendHbuf(hbuf)
 local startx,endx,step=_S3AdjHbufIter(S3.VP_L,S3.VP_R)
 for x=startx,endx,step do
  local hb=hbuf[x+1]  -- hbuf is 1-indexed
  local w=hb.wall
  if w then
   local z=_S3Interp(w.slx,w.slz,w.srx,w.srz,x)
   local u=_S3PerspTexU(w,x)
   _S3RendTexCol(w.tid,x,hb.ty,hb.by,u,z)
  end
 end
end

function _S3StencilInit()
 for i=1,240*136+1 do S3.stencil[i]=-1 end
end

function _S3StencilRead(x,y)
 return S3.stencil[240*y+x+1]==S3.t
end

function _S3StencilWrite(x,y)
 if x>=0 and y>=0 and x<240 and y<136 then
  S3.stencil[240*y+x+1]=S3.t
 end
end

-- Adds a billboard.
function S3BillAdd(bill)
 assert(bill.x and bill.y and bill.z and bill.w and
  bill.h and bill.tid)
 table.insert(S3.bills,bill)
 return bill
end

function S3BillDel(bill)
 local bills=S3.bills
 for i=1,#bills do
  if bills[i]==bill then
   bills[i]=bills[#bills]
   table.remove(bills)
   return true
  end
 end
 return false
end

-- Adds a screen-space overlay.
function S3OverAdd(over)
 assert(over.sx) assert(over.sy) assert(over.tid)
 over.scale=over.scale or 1
 table.insert(S3.overs,over)
 return over
end

-- Renders eye-aligned billboard. Will test against
-- and write stencil. Clips against hbuf for depth.
-- Billboards must be rendered from near to far,
-- before walls.
function _S3RendBill(b)
 if b.slx<S3.VP_L and b.srx<S3.VP_L or 
   b.slx>S3.VP_R and b.srx>S3.VP_R
   then return end

 local lx,rx,z=b.slx,b.srx,b.sz
 local startx,endx,step=_S3AdjHbufIter(lx,rx)
 local tid=b.tid
 local ty,by=b.sty,b.sby
 local hbuf=S3.hbuf

 for x=startx,endx,step do
  -- clip against hbuf
  local hb=hbuf[x+1] -- 1-indexed
  if not hb or not hb.wall or hb.z>z then
   local u=_S3Interp(lx,0,rx,1,x)
   if _S3RendTexCol(tid,x,ty,by,u,z,nil,nil,
     0,true,b.clrO) then b.vis=true end
  end
 end
end

function _S3RendOvers()
 local overs=S3.overs
 for i=1,#overs do _S3RendOver(overs[i]) end
end

function _S3RendOver(o)
 local td=S3.TEX[o.tid]
 assert(td)
 local scale=o.scale
 local w=td.w*scale
 local h=td.h*scale
 local lx,rx=o.sx,o.sx+w-1
 local startx,endx,step=_S3AdjHbufIter(lx,rx)
 for x=startx,endx,step do
  for y=o.sy,o.sy+h-1 do
   local t=_S3GetTexel(o.tid,(x-lx)//scale,
     (y-o.sy)//scale)
   if t>0 then
    pix(x,y,t)
    _S3StencilWrite(x,y)
   end
  end
 end
end

-- Fills in the screen coordinates for the given
-- billboard (sx,sy,sz,sh,sw,slx,srx,sty,sby).
function _S3ProjBill(b)
 b.sx,b.sy,b.sz=S3Proj(b.x,b.y,b.z)
 -- From projection formula, this is how widths/
 -- heights project from world to screen:
 b.sw=117.78*b.w/b.sz
 b.sh=117.78*b.h/b.sz
 b.slx,b.srx=S3Round(b.sx-0.5*b.sw),
   S3Round(b.sx+0.5*b.sw)
 b.sty,b.sby=S3Round(b.sy-0.5*b.sh),
   S3Round(b.sy+0.5*b.sh)
end

-- Renders all billboards. Writes stencil.
function _S3RendBills()
 local nclip,fclip=S3.NCLIP,S3.FCLIP
 local bills=S3.bills
 -- billboards to render, sorted by sz increasing
 local r={}
 for i=1,#bills do
  local b=bills[i]
  b.vis=false
  _S3ProjBill(b)
  if b.slx<=S3.VP_R and b.srx>=S3.VP_L and
    b.sz>nclip and b.sz<fclip then
   _S3BillIns(r,b)  -- potentially visible
  end
 end

 -- r is sorted by depth (near to far). Render
 -- in this order. This uses stencil and clips by
 -- the hbuf, so we will get the right occlusion.
 for i=1,#r do
  _S3RendBill(r[i])
 end
 S3.zobills=r
end

-- Inserts billboard b in list l, keeping l sorted
-- by sz (screen z) increasing.
function _S3BillIns(l,b)
 for i=1,#l do
  if l[i].sz>b.sz then table.insert(l,i,b) return end
 end
 table.insert(l,b)
end

-- Returns the fog factor (0=completely fogged/dark,
-- 1=completely lit) for a point at screen pos
-- sx and screen-space depth sz.
function _S3FogFact(sx,sz)
 local FOG_S,FOG_E=S3.FOG_S,S3.FOG_E
 sx=120-sx
 local d2=sx*sx+sz*sz
 if S3.FLIC_AMP>0 then
  local f=sin(time()*S3.FLIC_FM)*S3.FLIC_AMP
  d2=d2+f
 end
 return d2<FOG_S and 1 or
   _S3Interp(FOG_S,1,FOG_E,0,d2)
end

-- Renders a vertical column of a texture to
-- the screen given:
--   tid: texture ID
--   x: x coordinate
--   ty,by: top and bottom y coordinate.
--   u: horizontal texture coordinate (0 to 1)
--   z: depth.
--   v0: bottom V coordinate (default 0)
--   v1: top V coordinate (default 1)
--   ck: color key (default -1)
--   wsten: if true, write to stencil buf (default
--    is false)
--   clrO: if not nil, override color (all pixels
--    will have this color unless transparent).
-- Returns true if any pixels were actually drawn.
function _S3RendTexCol(tid,x,ty,by,u,z,v0,v1,ck,
    wsten,clrO)
 ty=S3Round(ty)
 by=S3Round(by)
 local td=S3.TEX[tid]
 assert(td)
 local fogf=_S3FogFact(x,z)
 local aty,aby=max(ty,S3.VP_T),min(by,S3.VP_B)
 if fogf<=0 then
  -- Shortcut: just a black line
  for y=aty,aby do
   if not _S3StencilRead(x,y) then pix(x,y,0) end
  end
  return false
 end
 v0,v1,ck=v0 or 0,v1 or 1,ck or -1
 local drew=false
 for y=aty,aby do
  if not _S3StencilRead(x,y) then
   -- affine texture mapping for the v coord is ok,
   -- since walls are never slanted.
   local v=_S3Interp(ty,v0,by,v1,y)
   local clr=_S3TexSamp(tid,td,u,v)
   if clr~=ck then
    if not clrO then
     clr=_S3ClrMod(clr,fogf,x,y)
    end
    pix(x,y,clrO or clr)
    drew=true
    if wsten then _S3StencilWrite(x,y) end
   end
  end
 end
 return drew
end

-- Calculates the texture U coordinate for the given screen
-- X coordinate of the given wall.
function _S3PerspTexU(w,x)
 local us,ue=w.clifs,w.clife
 local a=_S3Interp(w.slx,us,w.srx,ue,x)
 local oma=1-a
 local u0,u1=us,ue
 local iz0,iz1=1/w.slz,1/w.srz
 local u=(oma*u0*iz0+a*u1*iz1)/(oma*iz0+a*iz1)
 return u
end

-- Returns the factor by which to module the color
-- of the floor or ceiling when drawing at those
-- screen coordinates.
function _S3FlatFact(x,y)
 --local z=2944.57/(68-y)  -- manually calculated
 local z=5000/(68-y)  -- manually calculated
 return _S3FogFact(x,z)
end

function _S3RendFlats(hbuf)
 local scrw,scrh=SCRW,SCRH
 local ceilC,floorC=S3.ceilC,S3.floorC
 local startx,endx,step=_S3AdjHbufIter(S3.VP_L,S3.VP_R)
 for x=startx,endx,step do
  local cby=scrh//2 -- ceiling bottom y
  local fty=scrh//2+1 -- floor top y
  local hb=hbuf[x+1] -- hbuf is 1-indexed
  if hb.wall then
   cby=min(cby,hb.ty)
   fty=max(fty,hb.by)
  end
  for y=S3.VP_T,cby do
   if not _S3StencilRead(x,y) then pix(x,y,ceilC) end
  end
  for y=fty,S3.VP_B do
   if not _S3StencilRead(x,y) then
    pix(x,y,_S3ClrMod(floorC,_S3FlatFact(x,y),x,y))
   end
  end
 end
end

function S3Round(x) return floor(x+0.5) end
function S3Clamp(x,lo,hi)
 return x<lo and lo or (x>hi and hi or x)
end

function _S3Interp(x1,y1,x2,y2,x)
 if x2<x1 then
  x1,x2=x2,x1
  y1,y2=y2,y1
 end
 return x<=x1 and y1 or (x>=x2 and y2 or
   (y1+(y2-y1)*(x-x1)/(x2-x1)))
end

-- Sample texture ID tid at texture coords u,v.
-- tid: the texture ID
-- td: the texture defitinion (S3.TEX[tid]).
-- u,v: texture coordinates.
function _S3TexSamp(tid,td,u,v)
 -- texture size in pixels
 local SX,SY=td.w,td.h
 local tx=floor(u*SX)%SX
 local ty=floor(v*SY)%SY
 return _S3GetTexel(tid,tx,ty)
end

-- Sample texture ID tid at integer texel coordinates
-- texx,texy.
function _S3GetTexel(tid,texx,texy)
 local spid=tid+(texy//8)*16+(texx//8)
 texx=texx%8
 texy=texy%8
 return peek4(0x8000+spid*64+texy*8+texx)
end

function S3Dot(ax,az,bx,bz)
 return ax*bx+az*bz
end

function S3Norm(x,z)
 return sqrt(x*x+z*z)
end

function S3Normalize(x,z)
 local l=S3Norm(x,z)
 return x/l,z/l
end

