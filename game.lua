function Boot()
 PalInit()
 S3Init()
end

function SetMode(m)
 A.mode,A.mclk=m,0
end

function TIC()
 local stime=time()
 local dtmillis=A.lftime and (stime-A.lftime) or 16
 A.lftime=stime
 A.dt=dtmillis*.001 -- convert to seconds
 local dt=A.dt
 A.mclk=A.mclk+dt

 if A.mode==MODE.TITLE then
  TICTitle()
 elseif A.mode==MODE.PLAY then
  TICPlay()
 elseif A.mode==MODE.DEAD then
  TICDead()
 elseif A.mode==MODE.INSTRUX then
  TICInstrux()
 end

 print(S3Round(1000/(time()-stime)).."fps")
end

function TICTitle()
 local c,r=MapPageStart(62)
 map(c,r,30,17)
 if btnp(BTN.FIRE) then SetMode(MODE.INSTRUX) end
end

function TICDead()
 Rend()
 rect(0,50,240,30,0)
 print("You died.",80,60,15,false,2)
 if A.mclk>5 then
  PalSet()
  SetMode(MODE.TITLE)
  return
 end
end

function TICInstrux()
 local c,r=MapPageStart(61)
 cls(0)
 map(c,r,30,17)
 print("CONTROLS",100,10,8)

 local X=88
 local Y=32
 print("Strafe",X,Y,3)
 print("Open/Use",X,Y+16,3)
 print("Grenade",X,Y+48,14)
 print("FIRE",X,Y+64,4)

 print("Move",168,96,15)

 if Blink(0.5) then
  print("- Press FIRE to continue -",50,124,4)
 end
 if btnp(BTN.FIRE) then StartLevel(1) end
end

function TICPlay()
 G.dt=A.dt
 G.clk=G.clk+A.dt
 local PSPD=G.PSPD
 local dt=G.dt
 
 local fwd=btn(BTN.FWD) and 1 or btn(BTN.BACK) and
   -1 or 0
 local right=btn(BTN.LEFT) and -1 or btn(BTN.RIGHT)
   and 1 or 0

 local vx,vz=PlrFwdVec(fwd)
 MovePlr(PSPD*dt,vx,vz)

 if btn(BTN.STRAFE) then
  -- strafe
  vx=-math.sin(G.yaw-1.5708)*right
  vz=-math.cos(G.yaw-1.5708)*right
  MovePlr(PSPD*dt,vx,vz)
 else
  -- Turn.
  G.yaw=G.yaw-right*G.PASPD*dt
 end

 -- Try to open a door.
 if btnp(BTN.OPEN) then TryOpenDoor() end

 DoorAnimUpdate(dt)
 UpdateJustHurt()
 UpdatePlrAtk()
 CheckEntHits()
 UpdateEnts()
 Rend()
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
  if btnp(BTN.FIRE) and G.ammo>0 then
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

 if btnp(BTN.LOB) and G.clk-G.lastGrenT>2 then
  local dx,dz=PlrFwdVec(4)
  local gren=EntAdd(E.GREN,G.ex+dx,G.ez+dz)
  gren.y=G.ey-2
  gren.vx,gren.vz=dx*50,dz*50
 end

 G.weapOver.tid=G.atk==0 and TID.CBOW_N or
   PLR_ATK[G.atk].tid
end

function HurtPlr(hp)
 if D_INVULN then return end
 G.hp=max(G.hp-hp,0)
 if G.hp==0 then
  -- Died.
  SetMode(MODE.DEAD)
  music(-1)
  Snd(SND.DIE)
  PalSet({r=0,g=0,b=0,a=80})
  return
 end
 G.justHurt={hp=hp,cd=0.7}
 PalSet({r=255,g=0,b=0,a=40})
 Snd(SND.HURT)
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
