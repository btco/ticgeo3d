
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
  tid=e.tid,ent=e}
 S3BillAdd(e.bill)
 table.insert(G.ents,e)
 return e
end

function CheckEntHits()
 local ents=G.ents
 for i=1,#ents do
  local e=ents[i]
  if e.etype==E.ARROW then CheckArrowHit(e)
  elseif e.etype==E.POTION or e.etype==E.AMMO then
   CheckPickUp(e)
  end
 end
end

function CheckArrowHit(arrow)
 local ents=G.ents
 -- only check against visible entities,
 -- ordered from near to far.
 local zob=S3.zobills
 for i=1,#zob do
  if arrow.dead then break end
  local e=zob[i].ent
  if not e.dead and e.vuln and e.bill.vis and
     ArrowHitEnt(arrow,e) then
   arrow.dead=true
   e.hp=e.hp-1
   e.hurtT=G.clk
   if e.hp<0 then
    -- TODO: visual fx
    e.dead=true
    Snd(SND.KILL)
   else
    Snd(SND.HIT)
   end
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
  end
 end
end

function ArrowHitEnt(arrow,e)
 local d2=DistSqXZ(arrow.x,arrow.z,e.x,e.z)
 local r=0.5*e.w
 return d2<(r*r)
end


function UpdateEnts()
 local ents=G.ents
 for i=1,#ents do
  UpdateEnt(ents[i])
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

function UpdateEnt(e)
 UpdateEntAnim(e)
 if e.pursues then EntPursuePlr(e) end
 if e.attacks then EntAttPlr(e) end
 if e.ttl then EntApplyTtl(e) end
 if e.vx and e.vz then EntApplyVel(e) end
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

function EntPursuePlr(e)
 if not e.speed then return end
 local dist2=DistSqXZ(e.x,e.z,G.ex,G.ez)
 if dist2<2500 or dist2>250000 then return end
 local dt=G.dt

 -- Find the move direction that brings us closest
 -- to the player.
 local bestx,bestz,bestd2=nil,nil,nil
 for mz=-1,1 do
  for mx=-1,1 do
   local px,pz=e.x+mx*e.speed*dt,
     e.z+mz*e.speed*dt
   if IsPosValid(px,pz) then
    local d2=DistSqToPlr(px,pz)
    if not bestd2 or d2<bestd2 then
     bestx,bestz,bestd2=px,pz,d2
    end
   end
  end
 end
 if not bestx then return end
 e.x,e.z=bestx,bestz
end

function EntApplyVel(e)
 e.x=e.x+e.vx*G.dt
 e.z=e.z+e.vz*G.dt
end

function EntApplyTtl(e)
 e.ttl=e.ttl-G.dt
 if e.ttl<0 then e.dead=true end
end

function EntAttPlr(e)
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
   Snd(SND.HURT)
  end
 end

 -- Update TID.
 if e.att then e.tid=e.attseq[e.att].tid end
end
