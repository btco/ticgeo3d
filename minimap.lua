function MinimapTick()
 local c0,r0=MapPageStart(G.lvl.pg)
 local cols,rows=LvlSize()
 -- player must be at 120,68.
 local sx,sy=120-8*G.ex/TSIZE,68-8*G.ez/TSIZE
 clip(S3.VP_L,S3.VP_T,S3.VP_R-S3.VP_L+1,
   S3.VP_B-S3.VP_T+1)
 cls(8)
 trace(sx..", "..sy)
 map(c0,r0,cols,rows,sx,sy,0,0,nil)

 if btnp(BTN.OPEN) then
  cls(0)
  SetMode(MODE.PLAY)
 end
 clip()
end

