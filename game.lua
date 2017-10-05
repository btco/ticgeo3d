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

 local f=TICF[A.mode]
 if f then f() end

 if D_SHOWFPS then
  print(S3Round(1000/(time()-stime)).."fps")
 end
end

function TICTitle()
 local c,r=MapPageStart(62)
 map(c,r,30,17)
 if btnp(BTN.FIRE) then
  -- If player already cleared one or more
  -- levels, show level select. Otherwise
  -- show instructions.
  SetMode(IsLvlLocked(2) and
    MODE.INSTRUX or MODE.LVLSEL)
 end
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

function TICWin()
 cls(0)
 PrintC("The end!",120,60)
 PrintC("Thanks for playing!",120,70)
 if A.mclk>2 then SetMode(MODE.TITLE) end
end

function TICPreroll()
 cls(0)
 PrintC("LEVEL "..G.lvlNo,120,60,11)
 PrintC(G.lvl.name,120,70)
 if A.mclk>2 then EndPreroll() end
end

function EndPreroll()
 cls(0)
 music(0)
 SetMode(MODE.PLAY)
 -- Fully render hud. Thereafter we only render
 -- updates to small parts of it.
 RendHud(true)
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
 if btnp(BTN.FIRE) then StartLevel(D_LVL or 1) end
end

function TICLvlSel()
 cls(0)
 PrintC("Select level",120,10,15)
 local X,Y=20,100
 local RH=10
 for i=1,#LVL do
  local y=Y+RH*i
  local locked=IsLvlLocked(i)
  if locked then
   spr(S.LOCK,X+10,y)
  end
  print(i..": "..LVL[i].name,X+20,y,
   locked and 2 or (i==A.sel and 14 or 15))
 end
 spr(S.ARROW,X,A.sel*RH+Y)
 local mx,my=GetDpadP()
 A.sel=A.sel+my
 A.sel=A.sel<1 and #LVL or
  (A.sel>#LVL and 1 or A.sel)
 if btnp(BTN.FIRE) and not IsLvlLocked(A.sel) then
  StartLevel(A.sel)
 end
end

function StartLevel(lvlNo)
 LoadLevel(lvlNo) 
 SetMode(MODE.PREROLL)
end

function TICPlay()
 G.dt=A.dt
 G.clk=G.clk+A.dt
 local PSPD=G.PSPD
 local dt=G.dt
 
 local mx,mz=GetDpad()
 local vx,vz=PlrFwdVec(mz)
 MovePlr(PSPD*dt,vx,vz)

 if btn(BTN.STRAFE) then
  -- strafe
  vx=-math.sin(G.yaw-1.5708)*mx
  vz=-math.cos(G.yaw-1.5708)*mx
  MovePlr(PSPD*dt,vx,vz)
 else
  -- Turn.
  G.yaw=G.yaw-mx*G.PASPD*dt
 end

 -- Try to open a door, push a button, etc.
 if btnp(BTN.OPEN) then Interact() end

 -- Open mini-map, if requested.
 G.minimapC=btn(BTN.OPEN) and G.minimapC+dt or 0
 if G.minimapC>0.5 then
  G.minimapC=0
  MinimapStart()
  return
 end

 DoorAnimUpdate(dt)
 UpdateFocusTile()
 UpdateJustHurt()
 UpdatePlrAtk()
 CheckEntHits()
 UpdateEnts()
 MinimapUpdateOff()
 CheckLevelEnd()
 Rend()
end

function TICMinimap() MinimapTick() end

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
  if btnp(BTN.FIRE) then
   if G.ammo>0 then
    -- Start shooting.
    G.ammo=G.ammo-1
    G.atk=1
    G.atke=0
   else
    Say("No arrows left!")
   end
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

 if btnp(BTN.LOB) then
  if G.grens>0 and G.clk-G.lastGrenT>1 then
   G.lastGrenT=G.clk
   local dx,dz=PlrFwdVec(4)
   local gren=EntAdd(E.GREN,G.ex+dx,G.ez+dz)
   gren.y=G.ey-2
   gren.vx,gren.vz=dx*50,dz*50
   G.grens=G.grens-1
  else
   Say("No flame orbs left!")
   -- TODO: error sfx
  end
 end

 G.weapOver.tid=G.atk==0 and
   (G.ammo>0 and TID.CBOW_N or TID.CBOW_E) or
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

-- TIC update delegation table
TICF={
 [MODE.TITLE]=TICTitle,
 [MODE.LVLSEL]=TICLvlSel,
 [MODE.PLAY]=TICPlay,
 [MODE.DEAD]=TICDead,
 [MODE.INSTRUX]=TICInstrux,
 [MODE.MINIMAP]=TICMinimap,
 [MODE.PREROLL]=TICPreroll,
 [MODE.WIN]=TICWin,
}

Boot()
