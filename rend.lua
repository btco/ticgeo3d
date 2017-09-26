-- Initializes palette.
function PalInit()
 for c=0,15 do
  ORIG_PAL[c]={
   r=peek(0x3fc0+3*c),
   g=peek(0x3fc0+3*c+1),
   b=peek(0x3fc0+3*c+2)
  }
 end
end

-- tint: optional, {r,g,b,a} in 0-255 range.
function PalSet(tint)
 tint=tint or {r=0,g=0,b=0,a=0}
 for c=0,15 do
  local r=_S3Interp(0,ORIG_PAL[c].r,255,tint.r,tint.a)
  local g=_S3Interp(0,ORIG_PAL[c].g,255,tint.g,tint.a)
  local b=_S3Interp(0,ORIG_PAL[c].b,255,tint.b,tint.a)
  poke(0x3fc0+3*c,clamp(S3Round(r),0,255))
  poke(0x3fc0+3*c+1,clamp(S3Round(g),0,255))
  poke(0x3fc0+3*c+2,clamp(S3Round(b),0,255))
 end
end

function Rend()
 S3SetCam(G.ex,G.ey,G.ez,G.yaw)
 S3Rend()
 RendHud(false)
end

-- Renders HUD. full: if true do a full render,
-- if not just update (cheaper).
function RendHud(full)
 local HUDY=120
 local BOXW,BOXH,BOXCLR=14,8,9
 local HPX,HPY=25,HUDY+6
 local AMMOX,AMMOY=89,HUDY+6
 if full then
  local c0,r0=MapPageStart(63)
  map(c0,r0,30,2,0,HUDY)
 else
  rect(HPX,HPY,BOXW,BOXH,BOXCLR)
  rect(AMMOX,AMMOY,BOXW,BOXH,BOXCLR)
 end
 print(To2Dig(G.hp),HPX+2,HPY+1,15,true)
 print(To2Dig(G.ammo),AMMOX+2,AMMOY+1,15,true)

 if G.justHurt then
  print("-"..G.justHurt.hp,100,10,15,true,2)
 end
end
