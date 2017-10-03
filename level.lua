
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
 -- If it's a locked door, require key.
 local t=LvlTile(c,r)
 if TD[t] and 0~=TD[t].f&TF.LOCKED and
   not G.hasKey then
  Say("***You need a key***")
  return false
 end
 -- Start door open animation.
 G.doorAnim={w=w,phi=0,irx=w.rx,irz=w.rz}
 LvlTile(c,r,0)  -- becomes empty tile
 DoorDel(c,r)
 Snd(SND.DOOR)
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

-- Gets the tile that the user is facing toward,
-- the one that can be "interacted" with (e.g.,
-- open a door). Returns c,r of focus tile, or nil,nil
-- to indicate there is no focus tile.
function GetFocusTile()
 local fx,fz=PlrFwdVec(TSIZE)
 local c,r=
   floor((G.ex+fx)/TSIZE),floor((G.ez+fz)/TSIZE)
 local t=LvlTile(c,r)
 local td=TD[t]
 if not td then return nil,nil end
 -- Only doors can be interacted with for now.
 if 0==td.f&TF.DOOR then return nil,nil end
 return c,r
end

function UpdateFocusTile()
 G.focC,G.focR=GetFocusTile()
end

function TryOpenDoor()
 if not G.focC then return end
 local td=TD[LvlTile(G.focC,G.focR)]
 if td.f&TF.DOOR~=0 then
  DoorOpen(G.focC,G.focR)
 end
end

function StartLevel(lvlNo)
 -- Reset G (game state), resetting it to the initial
 -- state.
 PalSet()
 G=DeepCopy(G_INIT)
 G.lvlNo=lvlNo
 G.lvl=LVL[lvlNo]
 local lvl=G.lvl
 S3Reset()
 G.ex=nil
 for r=0,lvl.pgh*17-1 do
  for c=0,lvl.pgw*30-1 do
   local cx,cz=(c+0.5)*TSIZE,(r+0.5)*TSIZE
   local t=LvlTile(c,r)
   local td=TD[t]
   if td then AddWalls(c,r,td) end
   if t==S.FLAG then
    local lbl=TileLabel(c,r)
    assert(lbl)
    if lbl==0 then
     -- Player start pos
     G.ex,G.ez=cx,cz
    end
   end
   if not D_NOENTS and ECFG[t] then
    EntAdd(t,cx,cz)
   end
  end
 end
 assert(G.ex,"Start pos flag not found.")

 -- Fully render hud. Thereafter we only render
 -- updates to small parts of it.
 RendHud(true)

 -- Create weapon overlay.
 G.weapOver=S3OverAdd({sx=84,sy=94,tid=460,scale=2})

 music(0)
 SetMode(MODE.PLAY)
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

