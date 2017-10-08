-- tint: optional, {r,g,b,a} in 0-255 range.
function PalSet(tint)
 tint=tint or {r=0,g=0,b=0,a=0}
 for c=0,15 do
  local origR=(ORIG_PAL[c]&0xff0000)>>16
  local origG=(ORIG_PAL[c]&0xff00)>>8
  local origB=(ORIG_PAL[c]&0xff)
  local r=_S3Interp(0,origR,255,tint.r,tint.a)
  local g=_S3Interp(0,origG,255,tint.g,tint.a)
  local b=_S3Interp(0,origB,255,tint.b,tint.a)
  poke(0x3fc0+3*c,clamp(S3Round(r),0,255))
  poke(0x3fc0+3*c+1,clamp(S3Round(g),0,255))
  poke(0x3fc0+3*c+2,clamp(S3Round(b),0,255))
 end
end

function Rend()
 S3SetCam(G.ex,G.ey,G.ez,G.yaw)
 S3Rend()
 RendHud(false)
 RendHint()

 if G.msgCd>0 then
  G.msgCd=G.msgCd-G.dt
  print(G.msg,8,100)
 end

 if DEBUGS then print(DEBUGS,4,12) end
end

-- Renders HUD. full: if true do a full render,
-- if not just update (cheaper).
function RendHud(full)
 local HUDY=120
 local BOXW,BOXH,BOXCLR=14,8,9
 local HPX,HPY=25,HUDY+6
 local AMMOX,AMMOY=65,HUDY+6
 local GRENX,GRENY=105,HUDY+6
 if full then
  local c0,r0=MapPageStart(63)
  map(c0,r0,30,2,0,HUDY)
  print("Hold S for",22*8,HUDY+4,9)
  print("map/help",22*8,HUDY+10,9)
 else
  rect(HPX,HPY,BOXW,BOXH,BOXCLR)
  rect(AMMOX,AMMOY,BOXW,BOXH,BOXCLR)
  rect(GRENX,GRENY,BOXW,BOXH,BOXCLR)
 end

 if G.hp>20 or Blink(0.3,0.2) then
  print(To2Dig(G.hp),HPX+2,HPY+1,
    G.hp>20 and 15 or 14,true)
 end

 print(To2Dig(G.ammo),AMMOX+2,AMMOY+1,15,true)
 print(To2Dig(G.grens),GRENX+2,GRENY+1,15,true)

 if G.justHurt then
  print("-"..G.justHurt.hp,100,10,15,true,2)
 end
 if G.hasKey and not G.paintedKey then
  spr(S.HUD_KEY,18*8,HUDY+8)
  G.paintedKey=true
 end

 if G.lvlNo==1 and G.clk<5 then
  rect(0,5,200,9,15)
  print("Z = shoot, X = throw flame orb",2,7,0)
 end
end

-- Render the "interaction hint" text.
function RendHint()
 local hint=GetInteractHint()
 if hint then
  local X,Y,W,H=120,5,120,8
  rect(X,Y,W,H,15)
  print(hint,X+2,Y+2,0)
 end
end

