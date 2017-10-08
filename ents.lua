
-- Adds an ent of the given type at the given pos.
function EntAdd(etype,x,z)
 local e=Overlay({},
   Overlay(ECFG_DFLT,ECFG[etype] or {}))
 e.x,e.z=x,z
 e.y=e.yanch==YANCH.FLOOR and FLOOR_Y+e.h*0.5
   or (e.yanch==YANCH.CEIL and CEIL_Y-e.h*0.5
   or (FLOOR_Y+CEIL_Y)*0.5)
 e.tid=e.anim and e.anim.tids[1] or e.tid
 e.etype=etype
 e.ctime=G.clk
 e.bill={x=e.x,y=e.y,z=e.z,w=e.w,h=e.h,
  tid=e.tid,ent=e,cmt=e.cmt}
 S3BillAdd(e.bill)
 table.insert(G.ents,e)
 return e
end

function CheckEntHits()
 local ents=G.ents
 for i=1,#ents do
  local e=ents[i]
  if e.etype==E.ARROW then CheckArrowHit(e)
  elseif e.etype==E.GREN then CheckGrenBlast(e)
  elseif e.etype==E.POTION or e.etype==E.AMMO or
    e.etype==E.KEY or e.etype==E.GREN_BOX then
   CheckPickUp(e)
  end
 end
end

-- Figures out what entity was hit by the
-- given projectile. nil if none.
function CalcHitTarget(proj)
 local ents=G.ents
 -- only check against visible entities,
 -- ordered from near to far.
 local zob=S3.zobills
 for i=1,#zob do
  local e=zob[i].ent
  if not e.dead and e.vuln and e.bill.vis and
     ProjHitEnt(proj,e) then
   return e
  end
 end
 return nil
end

function CheckArrowHit(arrow)
 local e=CalcHitTarget(arrow)
 if not e then return end
 arrow.dead=true
 -- Arrow damage decreases with distance (how long
 -- the arrow has been flying)
 local age=G.clk-arrow.ctime
 local dmg=max(1,S3Round(10-age*20))
 HurtEnt(e,dmg)
end

function HurtEnt(e,dmg)
 e.hp=e.hp-dmg
 e.hurtT=G.clk
 if e.hp<0 then
  e.dead=true
  Snd(SND.KILL)
  S3PartsSpawn(e.x,e.y,e.z,PFX.KILL)
 else
  Snd(SND.HIT)
  if e.wanderOnHurt then
   EntStartWander(e,0.3)
  end
 end
end

function CheckPickUp(item)
 if DistSqToPlr(item.x,item.z)<400 then
  -- Picked up.
  if item.etype==E.POTION then
   G.hp=min(99,G.hp+15)
   Say("Healing potion +15")
   item.dead=true
   Snd(SND.BONUS)
  elseif item.etype==E.AMMO then
   G.ammo=min(50,G.ammo+5)
   Say("Arrows +5")
   item.dead=true
   Snd(SND.BONUS)
  elseif item.etype==E.KEY then
   G.hasKey=true
   Say("PICKED UP A KEY.")
   item.dead=true
   Snd(SND.BONUS)
  elseif item.etype==E.GREN_BOX then
   G.grens=min(G.grens+3,20)
   Say("Flame orbs +3")
   item.dead=true
   Snd(SND.BONUS)
  end
 end
end

-- Returns true iff given projectile has
-- hit the given entity.
function ProjHitEnt(p,e)
 -- Projectiles are fast, so we need to check
 -- smaller increments of their motion.
 local dt=G.dt
 local r2=0.25*e.w*e.w
 for u=0,100,25 do
  local px,pz=p.x-G.dt*p.vx*u*0.01,
   p.z-G.dt*p.vz*u*0.01
  if r2>DistSqXZ(px,pz,e.x,e.z) then return true end
 end
 return false
end

function UpdateEnts()
 local ents=G.ents
 UpdateFlash()
 for i=1,#ents do
  local e=ents[i]
  UpdateEnt(e)
  if not D_NOAWAKE then
   -- If entity was seen, it's now awake.
   e.asleep=e.asleep and not e.bill.vis
  end
 end
 -- Delete dead entities.
 for i=#ents,1,-1 do
  if ents[i].dead then
   ents[i].bill.ent=nil  -- break cycle, help GC
   S3BillDel(ents[i].bill)
   ents[i]=ents[#ents]
   table.remove(ents)
  end
 end
end

function CheckGrenBlast(gren)
 local BLASTR2=30000  -- blast radius, squared
 local VBLASTR2=45000 -- visual blast radius, squared
 -- Did it go into a solid tile?
 local solid=IsInSolidTile(gren.x,gren.z)
 -- Has it hit an entity?
 local et=CalcHitTarget(gren)
 -- If it hasn't hit a solid tile, hasn't hit an ent
 -- and didn't hit the floor, nothing happens.
 if not solid and not et and
   gren.y>FLOOR_Y then return end
 -- Has hit enemy, a solid tile, or fell on floor.
 gren.dead=true
 if G.flash then S3FlashDel(G.flash) end
 G.flash=S3FlashAdd({x=gren.x,z=gren.z,
  int=10,fod2=VBLASTR2})
 -- Hurt all enemies in blast radius.
 for i=1,#G.ents do
  local e=G.ents[i]
  if e.vuln and e.bill.vis and e.hp then
   local d2=DistSqXZ(e.x,e.z,gren.x,gren.z)
   -- Main target takes 40 damage, others take 10.
   local dmg=(e==et and 40 or 10)
   if d2<BLASTR2 then HurtEnt(e,dmg) end
  end
 end
 Snd(SND.BOOM)
 S3PartsSpawn(gren.x,gren.y,gren.z,PFX.BLAST)
end

function UpdateFlash()
 local f=G.flash
 if not f then return end
 f.int=f.int-30*G.dt
 if f.int<0 then
  G.flash=nil
  S3FlashDel(f)
 end
end

function UpdateEnt(e)
 UpdateEntAnim(e)
 -- Update behaviors
 if not e.asleep then
  if e.pursues then EntBehPursues(e) end
  if e.attacks then EntBehAttacks(e) end
  if e.vx and e.vz then EntBehVel(e) end
  if e.shoots then EntBehShoots(e) end
  if e.hurtsPlr then EntBehHurtsPlr(e) end
  if e.falls then EntBehFalls(e) end
  if e.fragile then EntBehFragile(e) end
  if e.ttl then EntBehTtl(e) end
 end
 -- Copy necessary fields to the billboard object.
 e.bill.x,e.bill.y,e.bill.z=e.x,e.y,e.z
 e.bill.w,e.bill.h=e.w,e.h
 e.bill.tid=e.tid
 -- Shift color if just hurt.
 e.bill.clrO=(e.hurtT and G.clk-e.hurtT<0.1) and
   14 or nil
end

function UpdateEntAnim(e)
 if e.anim then
  local frs=floor((G.clk-e.ctime)/e.anim.inter)
  e.tid=e.anim.tids[1+frs%#e.anim.tids]
 end
end

function EntBehFragile(e)
 if IsInSolidTile(e.x,e.z) then e.dead=true end
end

function EntBehPursues(e)
 if not e.speed then return end
 local ideald2=e.idealDist2 or 2500
 local dist2=DistSqXZ(e.x,e.z,G.ex,G.ez)
 if dist2>250000 then return end
 local dt=G.dt

 -- If in wander mode, just wander in the given
 -- direction until we hit something.
 if e.pursueWcd then
  e.pursueWcd=e.pursueWcd-dt
  if e.pursueWcd<0 then e.pursueWcd=nil end
  local px,pz=e.x+e.pursueWvx*dt,
    e.z+e.pursueWvz*dt
  if IsPosValid(px,pz,e) then
   -- Continue wandering.
   e.x,e.z=px,pz
   return
  end
  -- If we got here, we bumped into something.
  -- End wandering.
  e.pursueWcd=nil
 end

 -- Find the move direction that brings us closest
 -- to the ideal distance from the player.
 local bestx,bestz,bestd2,bestmx,bestmz=
   nil,nil,nil,nil,nil
 for mz=-1,1 do
  for mx=-1,1 do
   local px,pz=e.x+mx*e.speed*dt,
     e.z+mz*e.speed*dt
   if IsPosValid(px,pz,e) then
    local d2=DistSqToPlr(px,pz)
    if not bestd2 or
      abs(d2-ideald2)<abs(bestd2-ideald2) then
     bestx,bestz,bestd2,bestmx,bestmz=px,pz,d2,mx,mz
    end
   end
  end
 end
 if not bestx or (bestmx==0 and bestmz==0) then
  -- We're stuck (no good direction found).
  -- Wander in a random direction for a bit.
  EntStartWander(e)
  return
 end
 e.x,e.z=bestx,bestz
end

function EntStartWander(e,time)
 e.pursueWcd=time or (e.wanderTime or 2)
 local phi=random()*6.28
 e.pursueWvx=e.speed*cos(phi)
 e.pursueWvz=e.speed*sin(phi)
end

function EntBehVel(e)
 e.x=e.x+e.vx*G.dt
 e.z=e.z+e.vz*G.dt
end

function EntBehTtl(e)
 e.ttl=e.ttl-G.dt
 if e.ttl<0 then e.dead=true end
end

function EntBehAttacks(e)
 if not e.att then
  -- Not attacking. Check if we should attack.
  local dist2=DistSqXZ(e.x,e.z,G.ex,G.ez)
  if dist2>3000 then return end -- too far.
  -- We should attack.
  e.origAnim=e.anim
  e.att=1
  e.atte=0 -- elapsed
  e.anim=nil
 end

 -- Check if we should move to the next attack phase.
 e.atte=e.atte+G.dt
 if e.atte>e.attseq[e.att].t then
  -- Move to next attack phase
  e.att=e.att+1
  if e.att>#e.attseq then
   -- End of attack sequence.
   e.att=nil
   e.anim=e.origAnim
  elseif e.attseq[e.att].dmg then
   -- Cause damage to player.
   HurtPlr(random(e.dmgMin,e.dmgMax))
  end
 end

 -- Update TID.
 if e.att then e.tid=e.attseq[e.att].tid end
end

function EntBehShoots(e)
 assert(e.shot)
 assert(e.shotInt)
 assert(e.shotSpd)
 -- Countdown to next shot
 e.shootC=(e.shootC or e.shotInt)-G.dt
 if e.shootC>0 then return end
 e.shootC=e.shotInt
 local vx,vz=V2Normalize(G.ex-e.x,G.ez-e.z)
 local shot=EntAdd(e.shot,e.x,e.z)
 shot.vx,shot.vz=vx*e.shotSpd,vz*e.shotSpd
 if e.shotSnd and DistSqToPlr(e.x,e.z)<80000 then
  Snd(e.shotSnd)
 end
end

function EntBehHurtsPlr(e)
 local d2=DistSqToPlr(e.x,e.z)
 local r=(e.collRF or 1)*e.w*0.5
 if d2<r*r then
  HurtPlr(random(e.dmgMin,e.dmgMax))
  e.dead=true
 end
end

function EntBehFalls(e)
 local gacc=e.fallAcc or -150
 local spd=(e.fallVy0 or 0)+gacc*(G.clk-e.ctime)
 e.y=e.y+spd*G.dt
end

