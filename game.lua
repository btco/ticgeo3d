function Boot()
 PalInit()
 S3Init()

 -- TEST:
 StartLevel(1)

 -- TEST
 --S3BillAdd({x=350,y=25,z=200,w=50,h=50,tid=320})
 --S3BillAdd({x=400,y=25,z=200,w=50,h=50,tid=324})
 --EntAdd(E.ZOMB,350,200)
 --EntAdd(E.ZOMB,450,170)
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

 local vx,vz=PlrFwdVec(fwd)
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
 UpdateJustHurt()
 UpdatePlrAtk()
 CheckEntHits()
 UpdateEnts()
 Rend()
 print(S3Round(1000/(time()-stime)).."fps")
end

function UpdateJustHurt()
 if not G.justHurt then return end
 G.justHurt.cd=G.justHurt.cd-G.dt
 if G.justHurt.cd<0 then
  PalSet()
  G.justHurt=nil
  return
 end
end

function UpdatePlrAtk()
 if G.atk==0 then
  if btnp(4) and G.ammo>0 then
   -- Start shooting.
   G.ammo=G.ammo-1
   G.atk=1
   G.atke=0
  end
 else
  G.atke=G.atke+G.dt
  if G.atke>PLR_ATK[G.atk].t then
   -- Go to next attack phase.
   G.atk=(G.atk+1)%(#PLR_ATK+1)
   G.atke=0
   if G.atk>0 and PLR_ATK[G.atk].fire then
    local dx,dz=PlrFwdVec(4)
    local arrow=EntAdd(E.ARROW,G.ex+dx,G.ez+dz)
    arrow.y=G.ey-2
    arrow.vx,arrow.vz=dx*200,dz*200
    Snd(SND.ARROW)
   end
  end
 end

 G.weapOver.tid=G.atk==0 and TID.CBOW_N or
   PLR_ATK[G.atk].tid
end

function HurtPlr(hp)
 -- TODO: detect death
 G.hp=max(G.hp-hp,0)
 G.justHurt={hp=hp,cd=0.7}
 PalSet({r=255,g=0,b=0,a=40})
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

function Say(msg)
 G.msg=msg
 G.msgCd=1
end

function Snd(snd)
 assert(snd.sfx)
 sfx(snd.sfx,snd.note,snd.dur,0,snd.vol,snd.spd)
end

Boot()
