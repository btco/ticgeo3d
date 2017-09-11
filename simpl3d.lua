local G={
 ex=0, ey=0, ez=100, yaw=0,
}

function Boot()
 S3Init()
end

function TIC()
 cls(2)
 G.ex=G.ex+(btn(2) and -1 or (btn(3) and 1 or 0))
 G.ez=G.ez+(btn(0) and -1 or (btn(1) and 1 or 0))
 S3SetCam(G.ex,G.ey,G.ez,G.yaw)

 local p1x,p1y,p1z=S3Proj(-50,-50,50)
 local p2x,p2y,p2z=S3Proj(-50,-50,-50)
 local p3x,p3y,p3z=S3Proj(50,-50,-50)
 local p4x,p4y,p4z=S3Proj(50,-50,50)

 tri(p1x,p1y,p2x,p2y,p3x,p3y,14)
 tri(p1x,p1y,p3x,p3y,p4x,p4y,13)
end

---------------------------------------------------

local S={
 ex=0, ey=0, ez=0, yaw=0,
 -- Precomputed from ex,ey,ez,yaw:
 cosYaw=0, sinYaw=0, termA=0, termB=0,
}

local sin,cos=math.sin,math.cos
local floor,ceil=math.floor,math.ceil

function S3Init()
 S3SetCam(0,0,0,0)
end

function S3SetCam(ex,ey,ez,yaw)
 S.ex,S.ey,S.ez,S.yaw=ex,ey,ez,yaw
 -- Precompute some factors we will need often:
 S.cosYaw,S.sinYaw=cos(yaw),sin(yaw)
 S.termA=-ex*S.cosYaw-ez*S.sinYaw
 S.termB=ex*S.sinYaw-ez*S.cosYaw
end

function S3Proj(x,y,z)
 local c,s,a,b=S.cosYaw,S.sinYaw,S.termA,S.termB
 -- Hard-coded from manual matrix calculations:
 local px=0.9815*c*x+0.9815*s*z+0.9815*a
 local py=1.7321*y-1.7321*S.ey
 local pz=-s*x+z*c+b+0.2
 local pw=x*s-z*c-b
 local ndcx=px/pw
 local ndcy=py/pw
 return 120+ndcx*120,68-ndcy*68,pz
end

function S3Round(x) return floor(x+0.5) end

--------------------------------------------------
Boot()
