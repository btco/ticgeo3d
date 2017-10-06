function MinimapStart()
 SetMode(MODE.MINIMAP)
 -- calculate offsets such that player starts at
 -- screen pos 120,68.
 G.mmox,G.mmoy=120-8*G.ex/TSIZE,68-8*G.ez/TSIZE
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

