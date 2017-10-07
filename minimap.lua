function MinimapStart()
 SetMode(MODE.MINIMAP)
 -- calculate offsets such that player starts at
 -- screen pos 90,68.
 G.mmox,G.mmoy=90-8*G.ex/TSIZE,68-8*G.ez/TSIZE
end

-- Converts a world position to a mini map screen
-- position.
function MinimapFromWorld(x,z)
 return G.mmox+8*x/TSIZE,G.mmoy+8*z/TSIZE
end

-- Updates the minimap when minimap is NOT being
-- shown (for offline tasks like marking tiles as
-- seen).
function MinimapUpdateOff()
 local seen=G.mmseen
 local c0,r0=floor(G.ex/TSIZE),floor(G.ez/TSIZE)
 for r=r0-3,r0+3 do
  for c=c0-3,c0+3 do
   seen[r*240+c]=true
  end
 end
end

function MinimapTick()
 local mx,my=GetDpad()
 G.mmox=G.mmox-mx
 G.mmoy=G.mmoy+my

 local c0,r0=MapPageStart(G.lvl.pg)
 local cols,rows=LvlSize()
 clip(S3.VP_L,S3.VP_T,S3.VP_R-S3.VP_L+1,
   S3.VP_B-S3.VP_T+1)
 cls(0)
 local startx,starty=MinimapFromWorld(0,0)
 map(c0,r0,cols,rows,S3Round(startx),
   S3Round(starty),0,1,MinimapRemap)

 if Blink(0.2,0.1) then
  local px,py=MinimapFromWorld(G.ex,G.ez)
  rect(px-1,py-1,3,3,4)
  local fx,fy=PlrFwdVec(8)
  line(px,py,px+fx,py+fy,6)
 end

 if btnp(BTN.OPEN) then
  SetMode(MODE.PLAY)
 end

 local IX,IY=170,0
 local IW,IH=240-IX,110
 local X0,Y0=IX+2,IY+2
 local R=7  -- row height
 rect(IX,IY,IW,IH,1)
 rectb(IX,IY,IW,IH,15)
 local y=Y0
 print("Buttons",X0,y,3)
 y=y+R
 print("Z",X0,y,4)
 print("fire",X0+10,y,6)
 y=y+R
 print("X",X0,y,14)
 print("throw orb",X0+10,y,11)
 y=y+R
 print("A",X0,y,3)
 print("strafe",X0+10,y,2)
 y=y+R
 print("S",X0,y,3)
 print("open",X0+10,y,2)
 y=y+2*R
 print("Flame orbs",X0,y,2)
 y=y+R
 print("are rare,",X0,y,2)
 y=y+R
 print("don't waste",X0,y,2)
 y=y+R
 print("them!",X0,y,2)
 y=y+2*R
 if G.hasKey then
  print("Use the key",X0,y,2)
  y=y+R
  print("to open the",X0,y,2)
  y=y+R
  print("locked door.",X0,y,2)
 else
  print("Find key to",X0,y,2)
  y=y+R
  print("open locked",X0,y,2)
  y=y+R
  print("door.",X0,y,2)
 end

 print("Press S to close map",2,110,2)
 print("Level "..G.lvlNo..": "..G.lvl.name,2,2,15)

 clip()
end

function MinimapRemap(t,c,r)
 -- c,r are relative to full map, not level.
 -- So we have to convert:
 local c0,r0=MapPageStart(G.lvl.pg)
 c,r=c-c0,r-r0
 if not G.mmseen[r*240+c] then return T.VOID end
 if TD[t] then return t end
 if MMTILES[t] then return t end
 return t==T.VOID and T.VOID or T.FLOOR
end

