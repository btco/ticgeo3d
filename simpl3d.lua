---------------------------------------------------
-- S3 "Simple 3D" library
---------------------------------------------------
-- Constants and aliases:
local sin,cos,PI=math.sin,math.cos,math.pi
local floor,ceil,sqrt=math.floor,math.ceil,math.sqrt
local min,max,abs,HUGE=math.min,math.max,math.abs,math.huge
local SCRW=240
local SCRH=136

local S3={
 -- eye coordinates (world coords)
 ex=0, ey=0, ez=0, yaw=0,
 -- Precomputed from ex,ey,ez,yaw:
 cosMy=0, sinMy=0, termA=0, termB=0,
 -- Clock (in frames).
 t=0,
 -- If true, interleave frames for performance
 -- (each frame alternates drawing odd/even cols).
 ILEAVE=true,
 -- These are hard-coded into the projection function,
 -- so if you change them, also update the math.
 NCLIP=0.1,
 FCLIP=1000,
 -- Viewport (left, top, right, bottom)
 VP_L=0,VP_T=0,VP_R=239,VP_B=106,
 -- min/max world Y coord of all walls
 FLOOR_Y=0,
 CEIL_Y=50,
 -- fog start and end dists (squared)
 FOG_S=20000,
 FOG_E=80000,
 -- light flicker amount (as dist squared)
 FLIC_AMP=1500,
 FLIC_FM=0.003,  -- frequency multiplier
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
 --  Computer at render time:
 --   sx,sy,sz: screen coords
 --   sw,sh: width/height in screen coords
 --   slx,srx: left/right x screen coord
 --   sty,sby: top/bottom y screen coord
 bills={},
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
 -- For an explanation of the rendering, see: https://docs.google.com/document/d/1do-iPbUHS2RF-lJAkPX98MsT9ZK5d5sBaJmekU1bZQU/edit#bookmark=id.7tkdwb6fk7e2

 -- First, prepare the HBUF. We will use it for
 -- clipping.
 _S3PrepHbuf(hbuf,pvs)
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
   _S3RendTexCol(tid,x,ty,by,u,z,nil,nil,0,true)
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
function _S3RendTexCol(tid,x,ty,by,u,z,v0,v1,ck,wsten)
 ty=S3Round(ty)
 by=S3Round(by)
 local fogf=_S3FogFact(x,z)
 local aty,aby=max(ty,S3.VP_T),min(by,S3.VP_B)
 if fogf<=0 then
  -- Shortcut: just a black line
  for y=aty,aby do
   if not _S3StencilRead(x,y) then pix(x,y,0) end
  end
  return
 end
 v0,v1,ck=v0 or 0,v1 or 1,ck or -1
 for y=aty,aby do
  if not _S3StencilRead(x,y) then
   -- affine texture mapping for the v coord is ok,
   -- since walls are never slanted.
   local v=_S3Interp(ty,v0,by,v1,y)
   local clr=_S3TexSamp(tid,u,v)
   if clr~=ck then
    clr=_S3ClrMod(clr,fogf,x,y)
    pix(x,y,clr)
    if wsten then _S3StencilWrite(x,y) end
   end
  end
 end
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
-- The texture ID is just the sprite ID where
-- the texture begins in sprite memory.
function _S3TexSamp(tid,u,v)
 -- texture size in pixels
 -- TODO make this variable
 local SX=32
 local SY=32
 local tx=floor(u*SX)%SX
 local ty=floor(v*SY)%SY
 local spid=tid+(ty//8)*16+(tx//8)
 tx=tx%8
 ty=ty%8
 return peek4(0x8000+spid*64+ty*8+tx)
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








--------------------------------------------------
-- GAME LOGIC
--------------------------------------------------

-- Tile size in world coords
local TSIZE=50

-- Player's collision rect size
local PLR_CS=20

local FLOOR_Y=S3.FLOOR_Y
local CEIL_Y=S3.CEIL_Y

local G={
 -- eye position and yaw
 ex=350, ey=25, ez=350, yaw=30,
 lvlNo=0,  -- level # we're currently playing
 lvl=nil,  -- reference to LVL[lvlNo]
 lftime=-1,  -- last frame time
 clk=0, -- game clock, seconds

 -- All the doors in the level. This is a dict indexed
 -- by r*240+c where c,r are the col/row on the map.
 -- The value is a reference to the wall that
 -- represents the (closed) door.
 doors={},

 -- If set, a door open animation is in progress
 -- Fields:
 --   w: the wall being animated.
 --   irx,irz: initial pos of door's right side
 --   phi: how much door has rotated so far
 --     (this increases until it's PI/2,
 --     then the animation ends).
 doorAnim=nil,

 -- Player speed (linear and angular)
 PSPD=120,PASPD=1.2,
 
 -- Entities. Each has:
 --   etype: entity type (E.* constants)
 --   bill: the billboard that represents it
 --   ctime: time when entity was created.
 --   anim: active animation (optional)
 --   x,y,z: position
 --   w,h: width,height
 --   tid: texture id
 --
 --  Behavior-related fields:
 --   pursues: (bool) does it pursue the player?
 --   speed: speed of motion, if it moves
 ents={}
}

-- sprite numbers
local S={
 FLAG=240,
 META_0=241,
}

-- entity types
local E={
 ZOMB=1,
}

-- animations
local ANIM={
 ZOMBW={inter=0.2,tids={320,384}},
}

-- possible Y anchors for entities
local YANCH={
 FLOOR=0,   -- entity anchors to the floor
 CENTER=1,  -- entity is centered vertically
 CEIL=2,    -- entity anchors to the ceiling
}

-- default entity params
--  w,h: entity size in world space
--  yanch: Y anchor (one of the YANCH.* consts)
--  tid: texture ID
--  data: fields to shallow-copy to entity as-is
local ECFG_DFLT={
 yanch=YANCH.FLOOR,
}
-- Entity params overrides (non-default) by type:
local ECFG={
 [E.ZOMB]={
  w=50,h=50,
  anim=ANIM.ZOMBW,
  pursues=true,
  speed=20,
 },
}

-- tile flags
local TF={
 -- walls in the tile
 N=1,E=2,S=4,W=8,
 -- tile is non-solid.
 NSLD=0x10,
 -- tile is a door
 DOOR=0x20,
}

-- tile descriptors
-- w: which walls this tile contains
local TD={
 -- Stone walls
 [1]={f=TF.S|TF.E,tid=256},
 [2]={f=TF.S,tid=256},
 [3]={f=TF.S|TF.W,tid=256},
 [17]={f=TF.E,tid=256},
 [19]={f=TF.W,tid=256},
 [33]={f=TF.N|TF.E,tid=256},
 [34]={f=TF.N,tid=256},
 [35]={f=TF.N|TF.W,tid=256},
 -- Doors
 [5]={f=TF.S|TF.DOOR,tid=260},
 [20]={f=TF.E|TF.DOOR,tid=260},
 [22]={f=TF.W|TF.DOOR,tid=260},
 [37]={f=TF.N|TF.DOOR,tid=260},
}

local LVL={
 -- Each has:
 --   name: display name of level.
 --   pg: map page where level starts.
 --   pgw,pgh: width and height of level, in pages
 {name="Level 1",pg=0,pgw=1,pgh=1},
 {name="Level Test",pg=1,pgw=1,pgh=1},
}

local DEBUGS=""

function Boot()
 S3Init()

 -- TEST:
 StartLevel(1)

 -- TEST
 --S3BillAdd({x=350,y=25,z=200,w=50,h=50,tid=320})
 --S3BillAdd({x=400,y=25,z=200,w=50,h=50,tid=324})
 EntAdd(E.ZOMB,350,200)
end

function TIC()
 local stime=time()
 local dtmillis=G.lftime and (stime-G.lftime) or 16
 local PSPD=G.PSPD
 G.lftime=stime
 G.dt=dtmillis*.001 -- convert to seconds
 local dt=G.dt
 G.clk=G.clk+dt
 
 local fwd=btn(0) and 1 or btn(1) and -1 or 0
 local right=btn(2) and -1 or btn(3) and 1 or 0

 local vx=-sin(G.yaw)*fwd
 local vz=-cos(G.yaw)*fwd
 MovePlr(PSPD*dt,vx,vz)

 if btn(4) then
  -- strafe
  vx=-math.sin(G.yaw-1.5708)*right
  vz=-math.cos(G.yaw-1.5708)*right
  MovePlr(PSPD*dt,vx,vz)
 else
  G.yaw=G.yaw-right*G.PASPD*dt
 end

 -- Try to open a door.
 if btnp(5) then TryOpenDoor() end

 DoorAnimUpdate(dt)

 S3SetCam(G.ex,G.ey,G.ez,G.yaw)
 UpdateEnts()

 S3Rend()
 RendHud(false)

 print(S3Round(1000/(time()-stime)).."fps")
 print(DEBUGS,4,12)
end

function StartLevel(lvlNo)
 G.lvlNo=lvlNo
 G.lvl=LVL[lvlNo]
 local lvl=G.lvl
 S3Reset()

 for r=0,lvl.pgh*17-1 do
  for c=0,lvl.pgw*30-1 do
   local t=LvlTile(c,r)
   local td=TD[t]
   if td then AddWalls(c,r,td) end
  end
 end

 -- Fully render hud. Thereafter we only render
 -- updates to small parts of it.
 RendHud(true)
end

-- Add a door (wall w) at col/row.
function DoorAdd(c,r,w) G.doors[r*240+c]=w end

-- Looks for a door at the given col,row,
-- nil if not found.
function DoorAt(c,r) return G.doors[r*240+c] end

-- Deletes a door at the given col,row.
function DoorDel(c,r) G.doors[r*240+c]=nil end

-- Opens the door at the given coordinates.
function DoorOpen(c,r)
 local w=DoorAt(c,r)
 if not w then return false end
 -- Start door open animation.
 G.doorAnim={w=w,phi=0,irx=w.rx,irz=w.rz}
 LvlTile(c,r,0)  -- becomes empty tile
 DoorDel(c,r)
 return true
end

function DoorAnimUpdate(dt)
 local anim=G.doorAnim
 if not anim then return end
 anim.phi=anim.phi+dt*1.5
 local phi=min(anim.phi,1.5)
 anim.w.rx,anim.w.rz=RotPoint(
  anim.w.lx,anim.w.lz,anim.irx,anim.irz,-phi)
 if anim.phi>1.5 then
  G.doorAnim=nil
  return
 end
end

function TryOpenDoor()
 local c0,r0=floor(G.ex/TSIZE),floor(G.ez/TSIZE)
 local pfwdx,pfwdz=-sin(G.yaw),-cos(G.yaw)
 for c=c0-2,c0+2 do
  for r=r0-2,r0+2 do
   local dx,dz=S3Normalize(c*TSIZE-G.ex,r*TSIZE-G.ez)
   if S3Dot(dx,dz,pfwdx,pfwdz)>0.8 then
    if DoorOpen(c,r) then return end
   end
  end
 end
end

-- Add the walls belonging to the given level tile.
function AddWalls(c,r,td)
 local s=TSIZE
 local xw,xe=c*s,(c+1)*s -- x of east and west
 local zn,zs=r*s,(r+1)*s -- z of north and south
 local isdoor=(0~=td.f&TF.DOOR)
 if 0~=(td.f&TF.N) then
  -- north wall
  AddWall({lx=xe,rx=xw,lz=zn,rz=zn,tid=td.tid},
   c,r,isdoor)
 end
 if 0~=(td.f&TF.S) then
  -- south wall
  AddWall({lx=xw,rx=xe,lz=zs,rz=zs,tid=td.tid},
   c,r,isdoor)
 end
 if 0~=(td.f&TF.E) then
  -- east wall
  AddWall({lx=xe,rx=xe,lz=zs,rz=zn,tid=td.tid},
   c,r,isdoor)
 end
 if 0~=(td.f&TF.W) then
  -- west wall
  AddWall({lx=xw,rx=xw,lz=zn,rz=zs,tid=td.tid},
   c,r,isdoor)
 end
end

function AddWall(w,c,r,isdoor)
 S3WallAdd(w)
 if isdoor then DoorAdd(c,r,w) end
end

function UpdateEnts()
 local ents=G.ents
 for i=1,#ents do
  UpdateEnt(ents[i])
 end
end

function UpdateEnt(e)
 UpdateEntAnim(e)
 if e.pursues then
  EntPursuePlr(e)
 end
 -- Copy necessary fields to the billboard object.
 e.bill.x,e.bill.y,e.bill.z=e.x,e.y,e.z
 e.bill.w,e.bill.h=e.w,e.h
 e.bill.tid=e.tid
end

function UpdateEntAnim(e)
 if e.anim then
  local frs=floor((G.clk-e.ctime)/e.anim.inter)
  e.tid=e.anim.tids[1+frs%#e.anim.tids]
 end
end

function EntPursuePlr(e)
 if not e.speed then return end
 local dist2=DistSqXZ(e.x,e.z,G.ex,G.ez)
 if dist2<2500 or dist2>250000 then return end
 local dt=G.dt

 -- Find the move direction that brings us closest
 -- to the player.
 local bestx,bestz,bestd2=nil,nil,nil
 for mz=-1,1 do
  for mx=-1,1 do
   local px,pz=e.x+mx*e.speed*dt,
     e.z+mz*e.speed*dt
   if IsPosValid(px,pz) then
    local d2=DistSqToPlr(px,pz)
    if not bestd2 or d2<bestd2 then
     bestx,bestz,bestd2=px,pz,d2
    end
   end
  end
 end
 if not bestx then return end
 e.x,e.z=bestx,bestz
end

-- Returns the level tile at c,r.
-- If newval is given, it will be set as the new
-- value.
function LvlTile(c,r,newval)
 if c>=G.lvl.pgw*30 or
   r>=G.lvl.pgh*17 or c<0 or r<0 then
  return 0
 end
 local c0,r0=MapPageStart(G.lvl.pg)
 local val=mget(c0+c,r0+r)
 if newval then mset(c0+c,r0+r,newval) end
 return val
end

-- Returns col,row where the given map page starts.
function MapPageStart(pg)
 return (pg%8)*30,(pg//8)*16
end

-- Gets the meta "value" of the given tile, or nil
-- if it has none.
function MetaValue(t)
 if t>=S.META_0 and t<=S.META_0+9 then
  return t-S.META_0
 end
end

-- Gets the meta value of a meta tile that's adjacent
-- to the given tile, nil if not found. This is called
-- the tile "label".
function TileLabel(tc,tr)
 for c=tc-1,tc+1 do
  for r=tr-1,tr+1 do
   local mv=MetaValue(LvlTile(c,r))
   if mv then return mv end
  end
 end
 return nil
end

-- Moves player, taking care not to collide with
-- solid tiles.
-- d: the total distance to move the player
-- vx,vz: the direction (normalized) in which to move
-- the player.
function MovePlr(d,vx,vz)
 local STEP=1
 local ex,ez=G.ex,G.ez
 while d>0 do
  local l=min(d,STEP)  -- how much to move this step
  d=d-STEP
  -- Candidate positions (a, b and c):
  -- (this allows player to slide along walls).
  local ax,az=ex+l*vx,ez+l*vz -- full motion
  local bx,bz=ex,ez+l*vz  -- move only in Z direction
  local cx,cz=ex+l*vx,ez  -- move only in X direction
  if IsPosValid(ax,az) then ex,ez=ax,az
  elseif IsPosValid(bx,bz) then ex,ez=bx,bz
  elseif IsPosValid(cx,cz) then ex,ez=cx,cz
  else break end  -- motion completely blocked
 end
 G.ex,G.ez=ex,ez
end

-- Adds an ent of the given type at the given pos.
function EntAdd(etype,x,z)
 local e=Overlay({},
   Overlay(ECFG_DFLT,ECFG[etype] or {}))
 e.x,e.z=x,z
 e.y=e.yanch==YANCH.FLOOR and FLOOR_Y+e.h*0.5
   or (e.yanch==YANCH.CEIL and CEIL_Y-e.h*0.5
   or (FLOOR_Y+CEIL_Y)*0.5)
 e.tid=e.anim and e.anim.tids[1] or e.tid
 e.etype=etype
 e.ctime=G.clk
 e.bill={x=e.x,y=e.y,z=e.z,w=e.w,h=e.h,tid=e.tid}
 S3BillAdd(e.bill)
 table.insert(G.ents,e)
end

-- Renders HUD. full: if true do a full render,
-- if not just update (cheaper).
function RendHud(full)
 local HUDY=106
 if full then
  rect(0,HUDY,240,136-HUDY,0)
  -- TODO: render more bg
 else
  rect(5,HUDY+8,16,8,1)
 end
 print("100",6,HUDY+8)
end

-- Returns if the given position is valid as a 
-- player position (that is, doesn't collide with
-- any solid tiles).
function IsPosValid(x,z)
 local cs=PLR_CS
 -- Test four corners of player's collision rect.
 return not IsInSolidTile(x-cs,z-cs) and
   not IsInSolidTile(x-cs,z+cs) and
   not IsInSolidTile(x+cs,z-cs) and
   not IsInSolidTile(x+cs,z+cs)
end

-- Returns whether the given position lies within
-- a solid tile.
function IsInSolidTile(x,z)
 local c,r=floor(x/TSIZE),floor(z/TSIZE)
 local t=LvlTile(c,r)
 local td=TD[t]
 if not td then return false end
 return 0==td.f&TF.NSLD
end

-- Rotate point P=px,pz about point O=ox,oz
-- by an angle of alpha radians.
function RotPoint(ox,oz,px,pz,alpha)
 local ux,uz=px-ox,pz-oz
 local c,s=cos(alpha),sin(alpha)
 return ox+ux*c-uz*s,oz+uz*c+ux*s
end

-- Overlays (shallowly) the fields of table b over the
-- fields of table a. So if a={x=1,y=2,z=3} and
-- b={y=42,foo="bar"}, then this will return:
-- {x=1,y=42,z=3,foo="bar"}.
function Overlay(a,b)
 local result={}
 for k,v in pairs(a) do
  result[k]=v
 end
 for k,v in pairs(b) do
  result[k]=v
 end
 return result
end

function DistSqXZ(x1,z1,x2,z2)
 return (x1-x2)*(x1-x2)+(z1-z2)*(z1-z2)
end

function DistXZ(x1,z1,x2,z2)
 return sqrt(DistSqXZ(x1,z1,x2,z2))
end

function DistSqToPlr(x,z)
 return DistSqXZ(x,z,G.ex,G.ez)
end

function DistToPlr(x,z)
 return DistXZ(x,z,G.ex,G.ez)
end

Boot()
