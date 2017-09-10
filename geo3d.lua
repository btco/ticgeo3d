-- Common formats:
-- Mat4: 16 floats in row major format
-- Vec4: x,y,z,w
-- Vec3: x,y,z
-- Material ID: an int. If positive, it's a color,
--   if negative, it's a texture ID.
-- Geom:
--   opos: array of Vec3 with object space
--         vertex coords
--   spos: array of transformed coords in
--         screen space.
--   tris: array of tris, each being an
--     mtl: material ID (positive = color,
--       negative for texture id)
--     v: array of 3 indices into opos[]
--     texc: array of 3 tex coord pairs
--        each being {u,v}

local SCRH=136
local SCRW=240

local G={
 CULL=false,
 eye={0,0,150},
 yaw=0,
 modelMat=nil,
 tmp=nil,
 tmp2=nil,
}

function Boot()
 G.modelMat=QMNew()
 G.tmp=QMNew()
 G.tmp2=QMNew()
 G.modelMat=QMNew()
 QInit(60,SCRW/SCRH,0.1,1000)
 QSetViewPos(G.eye,G.yaw)
end

function TIC()
 cls(2)
 local ge={
  opos={
   {-50,-50,0},{-50,50,0},
   {50,50,0},{50,-50,0},
  },
  spos={},
  tris={
   {v={1,2,3},texc={{0,0},{0,1},{1,1}},mtl=-1},
   {v={1,3,4},texc={{0,0},{1,1},{1,0}},mtl=-1}
  }
 }

 QGeoRend(ge,G.modelMat)

 local fwd=btn(0) and 1 or btn(1) and -1 or 0
 local right=btn(2) and -1 or btn(3) and 1 or 0

 G.yaw=G.yaw-right*0.01
 G.eye[1]=G.eye[1]-math.sin(G.yaw)*fwd*2.0
 G.eye[3]=G.eye[3]-math.cos(G.yaw)*fwd*2.0
 QSetViewPos(G.eye,G.yaw)
 print("yaw="..G.yaw.."  pos="..G.eye[1]..", "..G.eye[2]..", "..G.eye[3])
end

-------------------------------------------------
-- "Q", OUR 3D LIBRARY
-- Q* functions are the public API.
-- _Q* functions are private.
-------------------------------------------------
local Q={
 projMat=nil,
 nearClip=0,
 farClip=0,
 viewMat=nil,
 pvMat=nil,
}

-- Aliases to math functions:
local floor,ceil,abs=math.floor,math.ceil,math.abs
local sin,cos,tan=math.sin,math.cos,math.tan
local PI,HUGE=math.pi,math.huge

-- Init 3d library.
-- fovy: field of view angle, degrees
-- asp: aspect ratio, w/h
-- n: near clip
-- f: far clip
function QInit(fovy,asp,n,f)
 Q.projMat=QMNew()
 Q.viewMat=QMNew()
 Q.pvMat=QMNew()
 Q.nearClip=n
 Q.farClip=f
 QMPersp(Q.projMat,fovy,asp,n,f)
 QSetViewMat(QMNew())
end

-- Update view matrix.
function QSetViewMat(m)
 QMCopy(Q.viewMat,m)
 _QUpdatePvm()
end

function _QUpdatePvm()
 QMMul(Q.pvMat,Q.projMat,Q.viewMat)
end

-- (Convenience) Set view matrix from eye pos
-- and yaw angle.
-- eye: position of eye.
-- yaw: yaw angle (radians), that is, rotation about Y
-- axis where 0 is looking along negative Z.
local QSetViewPos_tmp={}
local QSetViewPos_tmp2={}
local QSetViewPos_tmp3={}
function QSetViewPos(eye,yaw)
 local xlatem=QSetViewPos_tmp
 local rotm=QSetViewPos_tmp2
 local v=QSetViewPos_tmp3
 Q3Scale(v,eye,-1) -- v=-eye
 QMTransl(xlatem,v)
 Q3Set(v,0,1,0)
 QMRot(rotm,v,-yaw)
 QMMul(Q.viewMat,rotm,xlatem)
 _QUpdatePvm()
end

-- Transforms a point (vec3 or vec4).
-- Returns screen coords in dest.
function QTransf(dest,p)
 QMMulVec4(dest,Q.pvMat,p)
 -- Perspective division.
 local ndcx=dest[1]/dest[4]
 local ndcy=dest[2]/dest[4]
 -- Convert to screen coords.
 dest[1]=SCRW*0.5+ndcx*SCRW*0.5
 dest[2]=SCRH*0.5-ndcy*SCRH*0.5
 dest[3]=-dest[4]  -- clip.w=-eye.z
 dest[4]=1
end

----------------------------------------
-- Q: RENDERING
----------------------------------------

-- Renders given geometry with given model matrix.
local QGeoRend_tmp={0,0,0,0}
function QGeoRend(geom,mat)
 local t=QGeoRend_tmp
 -- transform all coords to screen space
 for i=1,#geom.opos do
  QMMulVec4(t,mat,geom.opos[i])
  geom.spos[i]=geom.spos[i] or {0,0,0}
  QTransf(t,t)
  Q3RoundXy(geom.spos[i],t)
 end
 -- Rasterize all the tris
 for i=1,#geom.tris do
  _QTriRast(geom,geom.tris[i])
 end
end

-- Calculates descending order of the given values.
-- Example: if v1=10, v2=3, v3=72, returns
-- {3,1,2} because v3 is biggest, followed by v1,
-- then v2.
function _QCalcOrd(v1,v2,v3,result)
 if v1>=v2 and v1>=v3 then
  -- v1 is top.
  result[1]=1
  if v2>=v3 then result[2]=2 result[3]=3
  else result[2]=3 result[3]=2 end
 elseif v2>=v1 and v2>=v3 then
  -- v2 is top.
  result[1]=2
  if v1>=v3 then result[2]=1 result[3]=3
  else result[2]=3 result[3]=1 end
 else
  -- v3 is top
  result[1]=3
  if v1>=v2 then result[2]=1 result[3]=2
  else result[2]=2 result[3]=1 end
 end
end

-- Rast (render) a given triangle.
-- geom: the geomtry to render. Assumes geom.spos[]
--   has already been calculated (screen positions).
-- tri: the triangle to rasterize.
local _QTriRast_tmp={0,0,0}
function _QTriRast(geom,tri)
 local p1=geom.spos[tri.v[1]]
 local p2=geom.spos[tri.v[2]]
 local p3=geom.spos[tri.v[3]]
 -- Cull back faces.
 if Q.CULL and _QTriWind(p1,p2,p3)<0
   then return end
 -- Find order of vertices to split rasterization
 -- into two flat-base triangles.
 local yord=_QTriRast_tmp
 _QCalcOrd(p1[2],p2[2],p3[2],yord)
 local top=geom.spos[tri.v[yord[1]]]
 local mid=geom.spos[tri.v[yord[2]]]
 local bot=geom.spos[tri.v[yord[3]]]
 -- Tex coords of each vertex:
 local ttop=tri.texc[yord[1]]
 local tmid=tri.texc[yord[2]]
 local tbot=tri.texc[yord[3]]

 if top[2]==bot[2] then return end
 if top[2]~=mid[2] then
  -- Render top part (top to middle).
  _QTriRastFlat(top,ttop,mid,tmid,bot,tbot,tri.mtl)
 end
 if bot[2]~=mid[2] then
  -- Render bottom part (bottom to middle).
  _QTriRastFlat(bot,tbot,mid,tmid,top,ttop,tri.mtl)
 end
end

-- Calculate winding of given points (in screen
-- coords). Returns positive for counter-clockwise,
-- negative for clockwise.
local _QTriWind_tmp={0,0,0}
local _QTriWind_tmp2={0,0,0}
function _QTriWind(p1,p2,p3)
 local a=_QTriWind_tmp
 local b=_QTriWind_tmp2
 Q3AddS(a,p2,-1,p1)
 Q3AddS(b,p3,-1,p1)
 Q3Cross(a,a,b)
 return a[3]
end

-- Rasterize flat-base triangle.
-- a: apex (start) vertex pos
-- ta: tex coords of apex vertex
-- b: target (end) vertex pos
-- tb: tex coords of target vertex.
-- c: other vertex pos
-- tc: tex coords of other vertex.
-- mtl: material ID
function _QTriRastFlat(a,ta,b,tb,c,tc,mtl)
 -- abort if y is out of bounds
 if a[2]<0 and b[2]<0 then return end
 if a[2]>SCRH and b[2]>SCRH then return end

 local aby=a[2]-b[2]
 local acy=a[2]-c[2]
 -- derivatives of each variable (x,z,u,v) with
 -- respect to changes in y, for each segment.
 -- (we say the "a-b" segment is "side 1", and the
 -- "a-c" segment is "side 2").
 local dx1=(a[1]-b[1])/aby
 local dz1=(a[3]-b[3])/aby
 local du1=(ta[1]-tb[1])/aby
 local dv1=(ta[2]-tb[2])/aby
 local dx2=(a[1]-c[1])/acy
 local dz2=(a[3]-c[3])/acy
 local du2=(ta[1]-tc[1])/acy
 local dv2=(ta[2]-tc[2])/acy

 local ys=QClamp(a[2],0,SCRH-1) -- start y
 local yf=QClamp(b[2],0,SCRH-1) -- end y
 if not QIsFinite(ys) or not QIsFinite(yf)
   then return end
 
 local totdy=yf-a[2]
 -- xf1 is the final x coord of side 1
 -- xf2 is the final x coord of side 2
 -- (etc)
 local xf1=a[1]+dx1*totdy
 local xf2=a[1]+dx2*totdy
 local zf1=a[3]+dz1*totdy
 local zf2=a[3]+dz2*totdy

 -- abort if x is out of bounds
 if (a[1]<0 and xf1<0 and xf2<0) or 
   (a[1]>SCRW and xf1>SCRW and xf2>SCRW)
   then return end
 local ncl=Q.nearClip
 local fcl=Q.farClip
 -- abort if z is out of bounds (z should be
 -- negative).
 if (-a[3]<ncl and -zf1<ncl and -zf2<ncl) or 
    (-a[3]>fcl and -zf1>fcl and -zf2>fcl)
    then return end
 
 local dy=yf>=ys and 1 or -1
 -- Rasterize each scanline.
 for y=ys,yf,dy do
  local dy=y-a[2]
  -- Compute variables for this scanline.
  -- (remember side 1 is a-b, side 2 is a-c)
  local x1=a[1]+dy*dx1
  local x2=a[1]+dy*dx2
  local z1=a[3]+dy*dz1
  local z2=a[3]+dy*dz2
  -- Texture coordinates:
  --local u1=ta[1]+dy*du1
  --local u2=ta[1]+dy*du2
  --local v1=ta[2]+dy*dv1
  --local v2=ta[2]+dy*dv2
  local u1,v1=_QPerspTexC(a[2],a[3],ta[1],ta[2],
    b[2],b[3],tb[1],tb[2],y)
  local u2,v2=_QPerspTexC(a[2],a[3],ta[1],ta[2],
    c[2],c[3],tc[1],tc[2],y)

  if (x1>=0 and x1<SCRW) or
     (x2>=0 and x2<SCRW) then
   x1c=QClamp(QRound(x1),0,SCRW-1)
   x2c=QClamp(QRound(x2),0,SCRW-1)
   local xinc=x2c>=x1c and 1 or -1
   for x=x1c,x2c,xinc do
    local z=QInterp(x1,z1,x2,z2,x)
    if -z>=ncl and -z<=fcl then
      if mtl>=0 then
       -- Plain color.
       pix(x,y,mtl)
      else
       -- Sample texture (with perspective correction).
       local u,v=_QPerspTexC(x1,z1,u1,v1,x2,z2,u2,v2,x)
       pix(x,y,_QTexSamp(-mtl,u,v))
      end
    end
   end
  end
 end
end

-- Calculates interpolated perspective-correct texture
-- coords.
-- c1: x (or y) coordinate of first point.
-- z1: z coordinate of first point.
-- u1,v1: tex coords of first point.
-- (same for second point).
-- c: the coordinate to find the texture coords for
-- (must be between c1 and c2).
function _QPerspTexC(c1,z1,u1,v1,c2,z2,u2,v2,c)
 local a=QInterp(c1,0,c2,1,c) 
 local f=1/((1-a)/z1+a/z2)
 local u=((1-a)*(u1/z1)+a*(u2/z2))*f
 local v=((1-a)*(v1/z1)+a*(v2/z2))*f
 return u,v
end

-- Sample texture ID tid at texture coords u,v.
-- The texture ID is just the sprite ID where
-- the texture begins in sprite memory.
function _QTexSamp(tid,u,v)
 -- texture size in pixels
 -- TODO make this variable
 local SX=16
 local SY=16
 local tx=QRound(u*SX)%SX
 local ty=QRound(v*SY)%SY
 local spid=tid+(ty//8)*16+(tx//8)
 tx=tx%8
 ty=ty%8
 return peek4(0x8000+spid*64+ty*8+tx)
end

----------------------------------------
-- Q: MATH UTILITY
----------------------------------------

function QRound(x) return floor(x+0.5) end
function QIsFinite(v) return v<HUGE and v>-HUGE end
function QClamp(v,l,h)
 return (v<l and l) or (v>h and h or v)
end

function QInterp(x1,y1,x2,y2,x)
 if x2<x1 then x1,x2=x2,x1 y1,y2=y2,y1 end
 return x<x1 and y1 or (x>x2 and y2 or
   (y1+(y2-y1)*(x-x1)/(x2-x1)))
end

----------------------------------------
-- Q: MATRICES
----------------------------------------
function QMNew()
 return {1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}
end

function QMCopy(dest,src)
 for i=1,16 do dest[i]=src[i] end
end

function QMGet(m,r,c) return m[(r-1)*4+c] end

function QMZero(m)
 for i=1,16 do m[i]=0 end
end

function QMIdent(m)
 QMZero(m)
 m[1]=1 m[6]=1 m[11]=1 m[16]=1
end

function QMScale(m,s)
 QMIdent(m)
 m[1]=s[1] m[6]=s[2] m[11]=s[3]
end

function QMTransl(m,t)
 QMIdent(m)
 m[4]=t[1] m[8]=t[2] m[12]=t[3]
end

-- Rotation from axis angle
-- axis: axis of rotation
-- phi: angle in RADIANS.
function QMRot(m,axis,phi)
 local c=cos(phi)
 local s=sin(phi)
 local c1=1-c
 local x=axis[1]
 local y=axis[2]
 local z=axis[3]
 QMZero(m)
 m[1]=c+x*x*c1
 m[2]=-z*s+x*y*c1
 m[3]=y*s+x*z*c1
 m[5]=z*s+y*x*c1
 m[6]=c+y*y*c1
 m[7]=-x*s+y*z*c1
 m[9]=-y*s+z*x*c1
 m[10]=x*s+z*y*c1
 m[11]=c+z*z*c1
 m[16]=1
end

-- Inner product of row r of a with
-- col c of b
function _QMSubMul(a,b,r,c)
 local v=0
 for i=1,4 do
  v=v+QMGet(a,r,i)*QMGet(b,i,c)
 end
 return v
end

function QMMul(dest,lhs,rhs)
 if dest==lhs or dest==rhs then
  error("QMMul: no overlap allowed.")
 end
 dest[1]=_QMSubMul(lhs,rhs,1,1)
 dest[2]=_QMSubMul(lhs,rhs,1,2)
 dest[3]=_QMSubMul(lhs,rhs,1,3)
 dest[4]=_QMSubMul(lhs,rhs,1,4)
 dest[5]=_QMSubMul(lhs,rhs,2,1)
 dest[6]=_QMSubMul(lhs,rhs,2,2)
 dest[7]=_QMSubMul(lhs,rhs,2,3)
 dest[8]=_QMSubMul(lhs,rhs,2,4)
 dest[9]=_QMSubMul(lhs,rhs,3,1)
 dest[10]=_QMSubMul(lhs,rhs,3,2)
 dest[11]=_QMSubMul(lhs,rhs,3,3)
 dest[12]=_QMSubMul(lhs,rhs,3,4)
 dest[13]=_QMSubMul(lhs,rhs,4,1)
 dest[14]=_QMSubMul(lhs,rhs,4,2)
 dest[15]=_QMSubMul(lhs,rhs,4,3)
 dest[16]=_QMSubMul(lhs,rhs,4,4)
end

-- inner prod of row r of a with v (vec4)
function _QMSubMulVec4(a,r,v)
 return v[1]*QMGet(a,r,1)+
  v[2]*QMGet(a,r,2)+
  v[3]*QMGet(a,r,3)+
  (v[4] or 1)*QMGet(a,r,4)
end

-- multiply matrix a by vec4 v,
-- save result in dest
-- (dest can be same as v)
local QMMulVec4_tmp={0,0,0,0}
function QMMulVec4(dest,a,v)
 if dest==v then
  Q4Copy(QMMulVec4_tmp,v)
  v=QMMulVec4_tmp
 end
 dest[1]=_QMSubMulVec4(a,1,v)
 dest[2]=_QMSubMulVec4(a,2,v)
 dest[3]=_QMSubMulVec4(a,3,v)
 dest[4]=_QMSubMulVec4(a,4,v)
 return dest
end

function QMFrust(dest,l,r,b,t,n,f)
 QMZero(dest)
 dest[1]=2*n/(r-l)
 dest[3]=(r+l)/(r-l)
 dest[6]=2*n/(t-b)
 dest[7]=(t+b)/(t-b)
 dest[11]=(f+n)/(f-n)
 dest[12]=2*f*n/(f-n)
 dest[15]=-1
end

function QMPersp(dest,fovy,asp,n,f)
 local sh=n*tan(fovy/360*PI);
 local sw=asp*sh;
 QMFrust(dest,-sw,sw,-sh,sh,n,f);
end

----------------------------------------
-- Q: VECTORS
----------------------------------------

function Q3Set(dest,x,y,z)
 dest[1]=x
 dest[2]=y
 dest[3]=z
end

function Q3Copy(dest,src)
 dest[1]=src[1] or 0
 dest[2]=src[2] or 0
 dest[3]=src[3] or 0
end

function Q4Copy(dest,src)
 dest[1]=src[1] or 0
 dest[2]=src[2] or 0
 dest[3]=src[3] or 0
 dest[4]=src[4] or 1
end

function Q3Add(dest,v,u)
 dest[1]=v[1]+u[1]
 dest[2]=v[2]+u[2]
 dest[3]=v[3]+u[3]
end

function Q3Scale(dest,v,s)
 dest[1]=v[1]*s
 dest[2]=v[2]*s
 dest[3]=v[3]*s
end

function Q3AddS(dest,v,s,u)
 dest[1]=v[1]+s*u[1]
 dest[2]=v[2]+s*u[2]
 dest[3]=v[3]+s*u[3]
end

function Q3RoundXy(dest,v)
 dest[1]=QRound(v[1])
 dest[2]=QRound(v[2])
 dest[3]=v[3]
end

function Q3Cross(dest,u,v)
 local x=u[2]*v[3]-u[3]*v[2]
 local y=u[3]*v[1]-u[1]*v[3]
 local z=u[1]*v[2]-u[2]*v[1]
 dest[1]=x dest[2]=y dest[3]=z
end

----------------------------------------
-- Q: DEBUG
----------------------------------------
function QTrace(label,v)
 trace(label..":")
 if v==nil then trace("  nil") return end
 for i=1,#v do
  trace(" ["..i.."]="..v[i])
 end
end

-- Must be last line in file:
Boot()

