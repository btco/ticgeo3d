
-- Add the walls belonging to the given level tile.
function AddWalls(c,r,td)
 local s=TSIZE
 local xw,xe=c*s,(c+1)*s -- x of east and west
 local zn,zs=r*s,(r+1)*s -- z of north and south
 local interest=(0~=td.f&TF.DOOR) or
   (0~=td.f&TF.LEVER) or (0~=td.f&TF.GATE)
 if 0~=(td.f&TF.N) then
  -- north wall
  AddWall({lx=xe,rx=xw,lz=zn,rz=zn,tid=td.tid},
   c,r,interest)
 end
 if 0~=(td.f&TF.S) then
  -- south wall
  AddWall({lx=xw,rx=xe,lz=zs,rz=zs,tid=td.tid},
   c,r,interest)
 end
 if 0~=(td.f&TF.E) then
  -- east wall
  AddWall({lx=xe,rx=xe,lz=zs,rz=zn,tid=td.tid},
   c,r,interest)
 end
 if 0~=(td.f&TF.W) then
  -- west wall
  AddWall({lx=xw,rx=xw,lz=zn,rz=zs,tid=td.tid},
   c,r,interest)
 end
end

-- Adds a wall at the given tile.
-- interest: (bool) whether it's a wall of interest
--  (door, button, etc).
function AddWall(w,c,r,interest)
 S3WallAdd(w)
 if interest then IwallAdd(c,r,w) end
 -- Apply the CMT (color mapping table) if the level
 -- requires it.
 if G.lvl.wallCmt then w.cmt=G.lvl.wallCmt[w.tid] end
end

-- Add a wall of interest at col/row.
function IwallAdd(c,r,w) G.iwalls[r*240+c]=w end

-- Looks for a wall of interest at the given col,row,
-- nil if not found.
function IwallAt(c,r) return G.iwalls[r*240+c] end

-- Deletes a wall of interest at the given col,row.
function IwallDel(c,r) G.iwalls[r*240+c]=nil end

-- Opens the door at the given coordinates.
function DoorOpen(c,r)
 local w=IwallAt(c,r)
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
 LvlTile(c,r,T.FLOOR)  -- becomes floor tile
 IwallDel(c,r)
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
 if 0~=td.f&TF.INTEREST then return c,r
 else return nil,nil end
end

function UpdateFocusTile()
 G.focC,G.focR=GetFocusTile()
end

function Interact()
 if not G.focC then return end
 local td=TD[LvlTile(G.focC,G.focR)]
 if td.f&TF.DOOR~=0 then
  DoorOpen(G.focC,G.focR)
 elseif td.f&TF.LEVER~=0 then
  PullLever(G.focC,G.focR)
 end
end

-- Loads the given level. This won't set the mode
-- to play mode, it will only load the level.
function LoadLevel(lvlNo)
 -- Reset G (game state), resetting it to the initial
 -- state.
 PalSet()
 G=DeepCopy(G_INIT)
 G.lvlNo=lvlNo
 G.lvl=LVL[lvlNo]
 local lvl=G.lvl
 S3Reset()
 S3.FLOOR_CLR,S3.CEIL_CLR=lvl.floorC,lvl.ceilC
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

 -- Create weapon overlay.
 G.weapOver=S3OverAdd({sx=84,sy=94,tid=460,scale=2})
end

-- Returns the level tile at c,r.
-- If newval is given, it will be set as the new
-- value.
function LvlTile(c,r,newval)
 local cols,rows=LvlSize()
 if c>=cols or r>=rows or c<0 or r<0 then
  return 0
 end
 local val=G.otiles[r*240+c]
 if not val then
  local c0,r0=MapPageStart(G.lvl.pg)
  val=mget(c0+c,r0+r)
 end
 if newval then G.otiles[r*240+c]=newval end
 return val
end

function LvlSize()
 return G.lvl.pgw*30,G.lvl.pgh*17
end

-- Returns the level tile at the given x,z pos.
function LvlTileAtXz(x,z)
 local c,r=floor(x/TSIZE),floor(z/TSIZE)
 return LvlTile(c,r)
end

function PullLever(c,r)
 LvlTile(c,r,T.SOLID)
 local w=IwallAt(c,r)
 if w then w.tid=TID.LEVER_P end
 -- TODO: sfx
 -- Open the gate.
 -- (For now we assume there's a single gate,
 -- and open it).
 local cols,rows=LvlSize()
 local gatec,gater=nil,nil
 for r=0,rows-1 do
  for c=0,cols-1 do
   local t=LvlTile(c,r)
   if TD[t] and TD[t].f&TF.GATE~=0 then
    gatec,gater=c,r
    break
   end
  end
 end
 -- Remove gate.
 assert(gatec)
 local w=IwallAt(gatec,gater)
 assert(w)
 IwallDel(gatec,gater)
 S3WallDel(w)
 LvlTile(gatec,gater,T.FLOOR)
 Say("THE GATE OPENED!")
end

-- Returns the interaction hint for the currently
-- focused tile.
function GetInteractHint()
 local c,r=G.focC,G.focR
 if not c then return end
 local hint=nil
 local td=TD[LvlTile(c,r)]
 if td.f&TF.DOOR~=0 then
  if td.f&TF.LOCKED~=0 then
   if G.hasKey then
    return "Press S to unlock"
   else
    return "You need a key"
   end
  else
   return "Press S to open door"
  end
 elseif td.f&TF.LEVER~=0 then
  return "Press S to activate"
 elseif td.f&TF.GATE~=0 then
  return "Gate opens elsewhere!"
 elseif td.f&TF.PORTAL~=0 then
  return "Step into the portal!"
 end
 return nil
end

function CheckLevelEnd()
 local t=LvlTileAtXz(G.ex,G.ez)
 if TD[t] and TD[t].f&TF.PORTAL then
  -- Player stepped through portal
  SetMode(MODE.EOL)
  Snd(SND.EOL)
  MarkLvlDone(G.lvlNo)
 end
end


