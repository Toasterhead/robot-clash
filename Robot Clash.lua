-- title:   Robot Clash
-- author:  Lenny Young
-- desc:    A simple platformer.
-- site:    website link
-- license: MIT License
-- version: 0.1
-- script:  lua

t=0
pallette={
	v0={initial=nil,ground=nil},
	v1={initial=nil}}
message={t=0,text=""}
endStage={condition=-1,t=-1}

RESOLUTION={width=240,height=136}
KEYBOARD_LOOKUP={-1,-1,10,12,4,6,-1,-1}

GROUND=RESOLUTION.height-16

X=0
Y=1

R=0
G=1
B=2
NUM_COLOR_COMPONENTS=3
PALLETTE_SIZE=16

TILE_SIZE=0x8
LEVEL_TILE_MAP_W=0x1E
LEVEL_TILE_MAP_H=0x11

TILE_ID_BLANK=0x30

FLAG_PLATFORM=0
FLAG_PICKUP=1
FLAG_HAZARD=2
FLAG_SWITCH=3

ADDR_PALLETTE=0x3FC0
ADDR_TILES=0x04000

PLAY_MODE_SINGLE_PLAYER=0
PLAY_MODE_COOPERATIVE=1
PLAY_MODE_COMPETITIVE=2

END_STAGE_GAME_OVER=0
END_STAGE_COMPLETE=1

COLLIDE_HIT=1
COLLIDE_FLOOR=2
COLLIDE_HEAD=3
COLLIDE_BUMP=4
COLLIDE_PICKUP=5

JUMP_TAPER=0x1/0x2
DELTA_GRAVITY=0x1/0x6

level=0
playMode=PLAY_MODE_SINGLE_PLAYER
p1KeysOnly=true

--General Functions

function deep_copy(a)
	b={}
	for i=1,#a do b[i]=a[i] end
	return b
end

function in_set(value,a)
	for i=1,#a do
		if value==a[i] then return true end
	end
	return false
end

function distance(x,y,a,b) return math.sqrt((a-x)^2+(b-y)^2) end

function coterminal(theta)
 	if theta<0 then while theta+ROTATION<ROTATION do theta=theta+ROTATION end
 	else while theta-ROTATION>=0 do theta=theta-ROTATION end end
 	return theta
end

function extract_sign(x)
	if x>0 then return 1
	elseif x<0 then return -1 end
	return 0
end

function id_at(relativeX,relativeY,newId)
	local absoluteX=level*LEVEL_TILE_MAP_W+relativeX
	local absoluteY=playMode*LEVEL_TILE_MAP_H+relativeY
	if newId then mset(absoluteX,absoluteY,newId) end
	return mget(absoluteX,absoluteY)
end

function flag_configured(id,index)
	local indexedFlag=fget(id,index)
	if indexedFlag==false then return false end
	if index>0 then
		for i=0,indexedFlag-1 do
			if fget(id,i)==false then return false end
		end
	end
	return true
end

--Vector Class

Vector={}
Vector.__index=Vector
function Vector:new(x,y) return setmetatable({x=x or 0,y=y or 0},self) end

function Vector:type_list() return {Vector.__index} end

function Vector:magnitude() return math.sqrt(self.x^2+self.y^2) end

function Vector:normalize() return self:scale(1/self:magnitude()) end

function Vector:add(other) return Vector:new(self.x+other.x,self.y+other.y) end

function Vector:scale(scalar) return Vector:new(scalar*self.x,scalar*self.y) end

function Vector:angle()
	local theta=math.atan(self.y/self.x)
	if self.x<0 then theta=math.pi+theta end
	return coterminal(theta)
end

--Collision Region Class

CollisionRegion={}
CollisionRegion.__index=CollisionRegion
function CollisionRegion:new(x,y,w,h)
	return setmetatable({X=x,Y=y,W=w,H=h},self)
end

function CollisionRegion:type_list() return {CollisionRegion.__index} end

function CollisionRegion:intersects(other)
	if self.W and self.H and other.W and other.H then
		return self.X<(other.X+other.W) and (self.X+self.W)>other.X and self.Y<(other.Y+other.H) and (self.Y+self.H)>other.Y
	elseif self.W and self.H and not other.W and not other.H then
		return other.X>=self.X and other.X<self.X+self.W and other.Y>=self.Y and other.Y<self.Y+self.H
	elseif self.W and not self.H then
		local operand=self.W
		if other.W then operand=operand+other.W end
		operand=operand+other.W
		return math.sqrt((other.X-self.X)^0x2+(other.Y-self.Y)^0x2)<operand
	end
	return false
end

--Actor Class

Actor={}
Actor.__index=Actor
function Actor:new(x,y,cells,collisionRegions,delay)
	return setmetatable({
		X=x or 0,
		Y=y or 0,
		Cells=cells or {},
		CollisionRegions=collisionRegions or {},
		Delay=delay or 10,
		DelayT=0,
		CellIndex=0,
		active=true},self)
end

function Actor:type_list() return {Actor.__index} end

function Actor:absolute_col_reg(i)
	local cR=self.CollisionRegions[i]
	local x,y,w,h
	x=self.X+cR.X
	if cR.Y then y=self.Y+cR.Y end
	if cR.W then w=cR.W end
	if cR.H then h=cR.H end
	return CollisionRegion:new(x,y,w,h)
end

function Actor:animate()
	self.DelayT=self.DelayT+1
	if self.DelayT>=self.Delay then
		self.DelayT=0
		self.CellIndex=self.CellIndex+1
		if self.CellIndex>=#self.Cells then self.CellIndex=0 end
	end
end

function Actor:update() self:animate() end

--Mover Class

Mover={}
Mover.__index=Mover
setmetatable(Mover,Actor)

Mover.Velocity=Vector:new() Mover.Travel=Vector:new() Mover.Push=Vector:new()
Mover.Inertia=0x1/0x10 Mover.TopSpeed=0xC/0x10 Mover.DeltaSpeed=0x1/0x10
Mover.Previous={X=Mover.X,Y=Mover.Y} Mover.FacingDirection=0

function Mover:init_mover(inert,tS,dS) self.Travel=Vector:new() self.Inertia=inert self.TopSpeed=tS self.DeltaSpeed=dS end

function Mover:type_list() return {Actor.__index,Mover.__index} end

function Mover:move()
	self.Previous={X=self.X,Y=self.Y}
	self.Velocity=self.Velocity:add(self.Travel)
	self.Velocity=self.Velocity:add(self.Push)	
	self.X=self.X+self.Velocity.x
	self.Y=self.Y+self.Velocity.y
 self.Velocity=Vector:new()
	self:apply_friction()
	self:enforce_bounds()
end

function Mover:enforce_bounds()
	local cR=self.CollisionRegions[COLLIDE_HIT]
	if cR then
		if self.X<-cR.X then
			self.X=-cR.X
			self:neutralize(X)
		elseif self.X>=RESOLUTION.width-(cR.X+cR.W) then
			self.X=RESOLUTION.width-(cR.X+cR.W)-0x1
			self:neutralize(X)
		end
	end
end

function Mover:begin_push(direction)
	local INITIAL_SPEED=0x1
	self.Travel.x=0
	self.Push=Vector:new(direction*INITIAL_SPEED,0)
end

function Mover:apply_friction()
	local pX=self.Push.x
	if pX~=0 then
		self.Push.x=extract_sign(pX)*(math.abs(pX)-self.Inertia)
		if math.abs(self.Push.x)<=self.Inertia then self.Push.x=0 end
	end
end

function Mover:can_slide() return self.Sliding~=nil and self.SlideReduction~=nil end

function Mover:set_horizontal_motion(direction,topSpeed,deltaSpeed)
	if self.Push.x~=0 then return end
	local SLIDE_STOP_THRESHOLD=0x1/0x2
	local SLIDE_THRESHOLD=0x4/0x5
	local dS=deltaSpeed or self.DeltaSpeed
	local tS=topSpeed or self.TopSpeed
	local trX=self.Travel.x
	local sl=self:can_slide() and self.Sliding==true
	local speed=math.abs(trX)
	if sl==false and direction and in_set(direction,{-1,0,1}) then
		self.Travel.x=self.Travel.x+(dS*direction)
		if self:can_slide() and sl==false and speed>=SLIDE_THRESHOLD*tS and ((direction>0 and trX<0) or (direction<0 and trX>0)) then self.Sliding=true end
	elseif math.abs(trX)<dS then
		self.Travel.x=0
		if self:can_slide() then self.Sliding=false end
	elseif trX~=0 then
		if sl==true then
			if speed<SLIDE_STOP_THRESHOLD*tS then
				self.Sliding=false
				self:neutralize(X)
			else dS=dS*self.SlideReduction end
		end
		self.Travel.x=trX+((-trX/speed)*dS)
	end
	if math.abs(self.Travel.x)>tS then self.Travel.x=extract_sign(self.Travel.x)*tS end
	if direction then self.FacingDirection=direction end
end

function Mover:neutralize(axis)
	if not axis then
		self.Travel=Vector:new()
		self.Velocity=Vector:new()
	elseif axis==X then 
		self.Travel.x=0
		self.Velocity.x=0
	elseif axis==Y then
		self.Travel.y=0
		self.Velocity.y=0
	end
end

function Mover:update()
	self:move()
	self:animate()
end

--Jumper Class

Jumper={}
Jumper.__index=Jumper
setmetatable(Jumper,Mover)

Jumper.AirborneT=-1 Jumper.InitialVelocity=-0x7/0x2
Jumper.AirTopSpeed=0 Jumper.AirDeltaSpeed=0x1/0x80
Jumper.jumpActionReleased=true

function Jumper:init_jumper(v0) self.InitialVelocity=v0 end

function Jumper:type_list() return {Actor.__index,Mover.__index,Jumper.__index} end

function Jumper:pull()
	if self.AirborneT>=0 then
		self.AirborneT=self.AirborneT+1
		self.Travel.y=self.Travel.y+DELTA_GRAVITY
		self:check_landing()
		if self:can_slide() then self.Sliding=false end
	else self:check_falling() end
end

function Jumper:launch(scaleV0)
	local scaleV0=scaleV0 or 0x1
	if self.AirborneT<0 then
		self.AirborneT=0
		if math.abs(self.Travel.x)<self.TopSpeed*(0x1/0x4) then
			self.AirTopSpeed=self.TopSpeed*(0x1/0x4)
		else self.AirTopSpeed=math.abs(self.Travel.x) end
		self.Travel.y=self.Travel.y+(scaleV0*self.InitialVelocity)
	end
end

function Jumper:fall()
	if self.AirborneT<0 then
		self.AirborneT=0
		self.AirTopSpeed=math.abs(self.Travel.x)
		self.Travel.y=self.Travel.y+DELTA_GRAVITY
	end
end

function Jumper:taper_jump()
	if self.AirborneT>=0 and self.Travel.y<JUMP_TAPER*self.InitialVelocity then
		self.Travel.y=JUMP_TAPER*self.InitialVelocity
	end
end

function Jumper:land(yPosition,cR)
	self:neutralize(Y)
	self.Y=yPosition-cR.Y
	self.AirborneT=-1
end

function Jumper:check_falling()
	local cR=self.CollisionRegions[COLLIDE_FLOOR]
	if cR then
		local aCR=self:absolute_col_reg(COLLIDE_FLOOR)
		if aCR.Y<GROUND and not self:on_platform(self:absolute_col_reg(COLLIDE_FLOOR)) then self:fall() end
	end
end

function Jumper:check_landing()
	local cR=self.CollisionRegions[COLLIDE_FLOOR]
	if cR then
		aCR=self:absolute_col_reg(COLLIDE_FLOOR)
		if aCR.Y>=0 then
			if aCR.Y>GROUND then self:land(GROUND,cR)
			elseif self.Travel.y>0 then
				local platformCR=self:on_platform(aCR)
				if platformCR then self:land(platformCR.Y,cR) end
			end
		end
	end
end

function Jumper:on_platform(aCR)
	local PLATFORM_DETECTION_H=0x4
	local gridX=aCR.X//TILE_SIZE
	local gridY=aCR.Y//TILE_SIZE
	local candidates=
	{
		{x=gridX,y=gridY},
		{x=gridX+1,y=gridY},
		{x=gridX,y=gridY+1},
		{x=gridX+1,y=gridY+1}
	}
	for i=1,#candidates do
		local cI=candidates[i]
		if flag_configured(id_at(cI.x,cI.y),FLAG_PLATFORM)==true then
			local platformCR=CollisionRegion:new(cI.x*TILE_SIZE,cI.y*TILE_SIZE,TILE_SIZE,PLATFORM_DETECTION_H)
			if aCR:intersects(platformCR) and platformCR.X>=0 and platformCR.X<RESOLUTION.width then
				return platformCR
			end
		end
	end
	return nil
end

function Jumper:update()
	self:move()
	self:pull()
	self:animate()
end

--Player Class

Player={}
Player.__index=Player
setmetatable(Player,Jumper)

Player.Lives=3 Player.Score=0 Player.InvincibleT=0 Player.RespawnT=0
Player.BatteryLife=1.0 Player.Wattage=0.00025
Player.CarriedItem=nil Player.Carrier=nil Player.CarryReduction=0x3/0x4
Player.Sliding=false Player.SlideReduction=0x1/0x2
Player.IOutline=1

function Player:type_list() return {Actor.__index,Mover.__index,Jumper.__index,Player.__index} end

function Player:init_player(lives,score,wattage,carryReduction,slideReduction)
	self.Lives=lives
	self.Score=score
	self.Wattage=wattage
	self.carryReduction=carryReduction
	self.slideReduction=slideReduction
end

function Player:carry(item)
	self.CarriedItem=item
	item.Carrier=self
	item.CarriedItem=nil
	if in_set(Player.__index,item:type_list()) then
		item:land(self:absolute_col_reg(COLLIDE_HEAD).Y,item.CollisionRegions[COLLIDE_FLOOR])
		item:neutralize(X)
	end
end

function Player:increase_score(points) self.Score=self.Score+points end

function Player:decrease_lives()
	self.Lives=self.Lives-1
	self.RespawnT=TIME_RESPAWN
end

function Player:animate()
		
	local DELAY_RANGE=8
	local DELAY_MAX=16
	local speedRatio=math.abs(self.Travel.x/self.TopSpeed)
	local delayDifference=speedRatio*DELAY_RANGE
	local cellStart=0
	local cellEnd=#self.Cells
	
	if self.Carrier then
		cellStart=cellEnd-1
	elseif self.AirborneT<0 then
		if self.Push.x~=0 then
			if self.Push.x<0 then
				cellStart=20
				cellEnd=21
			else
				cellStart=21
				cellEnd=22
			end
		elseif self.Sliding and self.Sliding==true then
			if self.FacingDirection==-1 then
				if self.CarriedItem then
					cellStart=14
					cellEnd=15
				else
					cellStart=10
					cellEnd=11
				end
			else
				if self.CarriedItem then
					cellStart=12
					cellEnd=13
				else
					cellStart=11
					cellEnd=12
				end
			end
		elseif math.abs(self.Travel.x)>self.DeltaSpeed then
			self.Delay=DELAY_MAX-delayDifference
			if self.Travel.x<0 then
				if self.CarriedItem then
					cellStart=12
					cellEnd=14
				else
					cellStart=0
					cellEnd=4
				end
			else
				if self.CarriedItem then
					cellStart=14
					cellEnd=16
				else
					cellStart=4
					cellEnd=8
				end
			end
		else
			if self.FacingDirection==-1 then
				if self.CarriedItem then
					cellStart=12
					cellEnd=13
				else
					cellStart=8
					cellEnd=9
				end
			elseif  self.FacingDirection==1 then
				if self.CarriedItem then
					cellStart=14
					cellEnd=15
				else	
					cellStart=9
					cellEnd=10
				end
			else
				cellStart=cellEnd-1
			end
		end
	else
		if self.Travel.y<0 then
			if self.FacingDirection==-1 then
				if self.CarriedItem then
					cellStart=13
					cellEnd=14
				else
					cellStart=16
					cellEnd=17
				end
			else
				if self.CarriedItem then
					cellStart=15
					cellEnd=16
				else
					cellStart=18
					cellEnd=19
				end
			end
		else
			if self.FacingDirection==-1 then
				if self.CarriedItem then
					cellStart=13
					cellEnd=14
				else
					cellStart=17
					cellEnd=18
				end
			else
				if self.CarriedItem then
					cellStart=15
					cellEnd=16
				else
					cellStart=19
					cellEnd=20
				end
			end
		end
	end
	
	if self.CellIndex<cellStart then self.CellIndex=cellStart end
	
	self.DelayT=self.DelayT+1
	if self.DelayT>=self.Delay then
		self.DelayT=0
		self.CellIndex=self.CellIndex+1
		if self.CellIndex>=cellEnd then self.CellIndex=cellStart end
	end
	
end

function Player:update()
	if self.RespawnT>0 then self.RespawnT=self.RespawnT-1 end
	if self.InvincibleT>0 then self.InvincibleT=self.InvincibleT-1 end
	self.BatteryLife=self.BatteryLife-self.Wattage
	if self.BatteryLife<0 then self.BatteryLife=0 end
	if self.Carrier then
		--In progress.
		local carrier=self.Carrier
		local cR=self.CollisionRegions[COLLIDE_HIT]
		wCarrier=carrier.CollisionRegions[COLLIDE_HIT].W/0x2
		wSelf=cR.W/0x2
		self.X=carrier.X+wCarrier-wSelf
		self.Y=carrier:absolute_col_reg(COLLIDE_HEAD).Y-(self:absolute_col_reg(COLLIDE_FLOOR).Y-self.Y)-1
	end
	self:pull()
	self:move()
	self:animate()
end

--Loading Functions

function get_pallette()
 local pallette={}
	for i=0,PALLETTE_SIZE-1 do
		pallette[i+1]={
			r=peek(ADDR_PALLETTE+(NUM_COLOR_COMPONENTS*i+R)),
			g=peek(ADDR_PALLETTE+(NUM_COLOR_COMPONENTS*i+G)),
			b=peek(ADDR_PALLETTE+(NUM_COLOR_COMPONENTS*i+B))}
	end
	return pallette
end

function set_pallette(i,r,g,b)
	poke(ADDR_PALLETTE+(NUM_COLOR_COMPONENTS*i+R),r)
	poke(ADDR_PALLETTE+(NUM_COLOR_COMPONENTS*i+G),g)
	poke(ADDR_PALLETTE+(NUM_COLOR_COMPONENTS*i+B),b)
	return {r=r,g=g,b=b}
end

function load_respawn_locations()
	local ID_SET_RESPAWN={178,179,194,195}
	local respawnLocations={}
	for i=0,LEVEL_TILE_MAP_W-1 do
		for j=0,LEVEL_TILE_MAP_H do
			id=id_at(i,j)
			if in_set(id,ID_SET_RESPAWN) then
				id_at(i,j,TILE_ID_BLANK)
				if id==ID_SET_RESPAWN[1] then respawnLocations[#respawnLocations+1]={x=i,y=j} end
			end
		end
	end
	return respawnLocations
end

--Input Functions

function check_input(playerIndex)
	local player=players[playerIndex]
	local topSpeed=player.TopSpeed
	local deltaSpeed=player.DeltaSpeed
	if player.AirborneT>=0 then
		topSpeed=player.AirTopSpeed
		deltaSpeed=player.AirDeltaSpeed
	end
	
	if pressed(playerIndex,2) then player:set_horizontal_motion(-1,topSpeed,deltaSpeed)
	elseif pressed(playerIndex,3) then player:set_horizontal_motion(1,topSpeed,deltaSpeed)
	else player:set_horizontal_motion() end
	
	if pressed(playerIndex,4) then
		if player.jumpActionReleased==true then player:launch() end
		player.jumpActionReleased=false
	else
		player:taper_jump()
		player.jumpActionReleased=true
	end
	
	--For testing pushes.
	if key(1) then player:begin_push(-player.FacingDirection) end
	
	if pressed(playerIndex,5) and player.CarriedItem then end--
end

function pressed(playerIndex,buttonIndex)
	local BITS=8
	local controllerIndex=(playerIndex-1)*BITS
	if p1KeysOnly==true then controllerIndex=controllerIndex-BITS end
	if playerIndex==1 and p1KeysOnly==true then
		if key(KEYBOARD_LOOKUP[buttonIndex+1]) then return true end
	elseif playerIndex==1 then
		if key(KEYBOARD_LOOKUP[buttonIndex+1]) or btn(controllerIndex+buttonIndex) then return true end
	elseif btn(controllerIndex+buttonIndex) then return true end
	return false
end

--Drawing Functions

function animate_tiles()
	local ID_CONVEYOR_LEFT=0
	local ID_CONVEYOR_MIDDLE=4
	local ID_CONVEYOR_RIGHT=8
	local ID_WATER=104
	local ID_FLAME_TOP=144
	local ID_FLAME_MIDDLE=146
	local ID_FLAME_BOTTOM=148
	local FRAMES=4
	local BOTTOM_ROW=RESOLUTION.height//TILE_SIZE-1
	local frame=(t//10)%FRAMES
	for i=0,RESOLUTION.height//TILE_SIZE-1 do
		for j=0,RESOLUTION.width//TILE_SIZE-1 do
			id=mget(j,i)
			if id>=ID_CONVEYOR_LEFT and id<ID_CONVEYOR_LEFT+FRAMES then mset(j,i,ID_CONVEYOR_LEFT+frame)
			elseif id>=ID_CONVEYOR_MIDDLE and id<ID_CONVEYOR_MIDDLE+FRAMES then mset(j,i,ID_CONVEYOR_MIDDLE+frame)
			elseif id>=ID_CONVEYOR_RIGHT and id<ID_CONVEYOR_RIGHT+FRAMES then mset(j,i,ID_CONVEYOR_RIGHT+frame)
			elseif id>=ID_WATER and id<ID_WATER+FRAMES then mset(j,i,ID_WATER+frame)
			elseif id==ID_FLAME_TOP or id==ID_FLAME_TOP+1 then mset(j,i,ID_FLAME_TOP+(frame%2))
			elseif id==ID_FLAME_MIDDLE or id==ID_FLAME_MIDDLE+1 then mset(j,i,ID_FLAME_MIDDLE+(frame%2))
			elseif id==ID_FLAME_BOTTOM or id==ID_FLAME_BOTTOM+1 then mset(j,i,ID_FLAME_BOTTOM+(frame%2)) end
		end
	end
end

function draw_tiles()
	animate_tiles()
	map(level*LEVEL_TILE_MAP_W,playMode*LEVEL_TILE_MAP_H)
end

function draw_hud(number,life)
	WHITE=1
	TOP_MARGIN=4
	FULL_WIDTH=40
	lifeWidth=life>0 and life*FULL_WIDTH or 0
	hPos=number*(RESOLUTION.width/4)
	color=6
	if life<0.125 then color=3
	elseif life<0.25 then color=4
	elseif life<0.5 then color=5 end
	if life>0 then
		line(hPos+5,TOP_MARGIN,hPos+5+lifeWidth,TOP_MARGIN,color)
		line(hPos+1,TOP_MARGIN,hPos+3,TOP_MARGIN,WHITE)
		line(hPos+2,TOP_MARGIN-1,hPos+2,TOP_MARGIN+1,WHITE)
		line(hPos+5+FULL_WIDTH+2,TOP_MARGIN,hPos+5+FULL_WIDTH+4,TOP_MARGIN,WHITE)
	end
	if message.t>0 then print(message.text,TILE_SIZE,RESOLUTION.height-6,WHITE) end
end

function draw_sprite(id,x,y,w,h,bits,colorMap)
	local TILES_PER_TILE_ROW=16
	local DEFAULT_PIXELS_PER_ROW=8
	local DEFAULT_BITS=8
	local DEFAULT_TILE_BITS=4
	local w=w or 1
	local h=h or 1
	local bits=bits or 4
	local colorMap=colorMap or {0,1,2,3}
	local bitScale=DEFAULT_BITS//bits
	local tileScale=DEFAULT_TILE_BITS//bits
	local addrTilesAdjusted=bitScale*ADDR_TILES
	local addressesPerPixelRow=tileScale*DEFAULT_PIXELS_PER_ROW
	local addressesPerTile=addressesPerPixelRow*DEFAULT_BITS
	local addressesPerTileRow=addressesPerTile*TILES_PER_TILE_ROW
	for i=0,h-1 do
		for j=0,w-1 do
			for k=0,DEFAULT_PIXELS_PER_ROW-1 do
				for l=0,DEFAULT_PIXELS_PER_ROW-1 do
					local id=id+(i*(tileScale*TILES_PER_TILE_ROW))+j
					local id4=id//tileScale
					local horizontalOffset=id%tileScale
					local addrSubTile=addrTilesAdjusted+(id4*addressesPerTile)
					addrCountV=k*addressesPerPixelRow
					addrCountH=(horizontalOffset*DEFAULT_BITS)+l
					color=peek(addrSubTile+addrCountV+addrCountH,bits)
					color=remap_color(color,colorMap)
					if color>=0 then pix(x+(j*DEFAULT_PIXELS_PER_ROW)+l,y+(i*DEFAULT_PIXELS_PER_ROW)+k,color) end
				end
			end
		end
	end
end

function remap_color(color, pallette)
	if color<#pallette then return pallette[color+1] end
	return color
end

function create_sprite_matrix(id,w,h,bits,colorMap)
	local TILES_PER_TILE_ROW=16
	local DEFAULT_PIXELS_PER_ROW=8
	local DEFAULT_BITS=8
	local DEFAULT_TILE_BITS=4
	local w=w or 1
	local h=h or 1
	local bits=bits or 4
	local colorMap=colorMap or {0,1,2,3}
	local bitScale=DEFAULT_BITS//bits
	local tileScale=DEFAULT_TILE_BITS//bits
	local addrTilesAdjusted=bitScale*ADDR_TILES
	local addressesPerPixelRow=tileScale*DEFAULT_PIXELS_PER_ROW
	local addressesPerTile=addressesPerPixelRow*DEFAULT_BITS
	local addressesPerTileRow=addressesPerTile*TILES_PER_TILE_ROW
	local matrix={}
	for i=0,(DEFAULT_PIXELS_PER_ROW*h)-1 do matrix[i]={} end
	for i=0,h-1 do
		for j=0,w-1 do
			for k=0,DEFAULT_BITS-1 do
				for l=0,DEFAULT_BITS-1 do
					local id=id+(i*(tileScale*TILES_PER_TILE_ROW))+j
					local id4=id//tileScale
					local horizontalOffset=id%tileScale
					local addrSubTile=addrTilesAdjusted+(id4*addressesPerTile)
					addrCountV=k*addressesPerPixelRow
					addrCountH=(horizontalOffset*DEFAULT_BITS)+l
					color=peek(addrSubTile+addrCountV+addrCountH,bits)
					color=remap_color(color,colorMap)
					matrix[(j*DEFAULT_PIXELS_PER_ROW)+l][(i*DEFAULT_PIXELS_PER_ROW)+k]=color
				end
			end
		end
	end
	return matrix
end

function reflect_sprite_matrix(matrix,reflectH,reflectV,w,h)
	reflected={}
	for i=0,w-1 do reflected[i]={} end
	for i=0,w-1 do
		for j=0,h-1 do
			if matrix[i][j] then 
				local indexH=i
				local indexV=j
				if reflectH==true then indexH=w-1-i end
				if reflectV==true then indexV=h-1-j end
				if matrix[indexH][indexV] then reflected[i][j]=matrix[indexH][indexV] end
			end
		end
	end
	return reflected
end

function outline_sprite_matrix(matrix,color,w,h,cutFloor)
	local OUTLINE_VALUE=-2
	outlined={}
	for i=0,w+1 do outlined[i]={} end
	for i=0,w+1 do
		for j=0,h+1 do outlined[i][j]=-1 end
	end
	for i=0,w-1 do
		for j=0,h-1 do
			if matrix[i][j] then outlined[i+1][j+1]=matrix[i][j] end
		end
	end
	for i=0,w+1 do
		for j=0,h+1 do
			if filled(outlined,i,j)==false and (
				filled(outlined,i-1,j-1) or filled(outlined,i,j-1) or filled(outlined,i+1,j-1) or
				filled(outlined,i-1,j)   or filled(outlined,i+1,j) or
				filled(outlined,i-1,j+1) or filled(outlined,i,j+1) or filled(outlined,i+1,j+1)) then outlined[i][j]=OUTLINE_VALUE end
		end
	end
	for i=0,w+1 do
		for j=0,h+1 do
			if outlined[i][j]==OUTLINE_VALUE then outlined[i][j]=color end
		end
	end
	if cutFloor==true then
		for i=0,w+1 do outlined[i][h+1]=-1 end
	end
	return outlined
end

function filled(matrix,i,j)
	if i<0 or j<0 or not matrix[i] or not matrix[i][j] then return false end
	color=matrix[i][j]
	return color>=0 and color<PALLETTE_SIZE
end

function draw_sprite_matrix(matrix,x,y,w,h)
	for i=0,w-1 do
		for j=0,h-1 do
			if matrix[i] and matrix[i][j] and matrix[i][j]>=0 then pix(x+i,y+j,matrix[i][j]) end
		end
	end
end

function quick_sprite_matrices(idSet,w,h,colorMap,outlineColor,cutFloor)
	local DEFAULT_BITS=2
	matrices={}
	for i=1,#idSet do
		if outlineColor then 
			local cutFloor=cutFloor or false
			matrices[i]=outline_sprite_matrix(create_sprite_matrix(idSet[i],w,h,DEFAULT_BITS,colorMap),outlineColor,w*TILE_SIZE,h*TILE_SIZE,cutFloor)
		else matrices[i]=create_sprite_matrix(idSet[i],w,h,DEFAULT_BITS,colorMap) end
	end
	return matrices
end

function draw_actor(actor)
	local outlineColor=nil
	local outlineOffset=0
	local w=#actor.Cells[actor.CellIndex+1]+1
	local h=#actor.Cells[actor.CellIndex+1][0]+1 or 0
	if actor.IOutline then
		outlineColor=0
		outlineOffset=-1
	end
	draw_sprite_matrix(actor.Cells[actor.CellIndex+1],actor.X+outlineOffset,actor.Y+outlineOffset,w,h)
end

--Program Flow

function BOOT()
	vbank(1)
	pallette.v1.initial=get_pallette()
	vbank(0)
	pallette.v0.initial=get_pallette()
	pallette.v0.ground=get_pallette()
	local grdPal=pallette.v0.ground
	grdPal[2]={r=0x0,g=0x60,b=0x80}
	grdPal[3]={r=0x0,g=0xC0,b=0xFF}
	grdPal[4]={r=0x80,g=0xE0,b=0xFF}
	grdPal[8]={r=0x80,g=0x60,b=0x0}
	grdPal[9]={r=0xFF,g=0xC0,b=0x0}
	grdPal[10]={r=0xFF,g=0xE0,b=0x80}
	respawnLocations=load_respawn_locations()
	message.t=120
	message.text="This is a test."
	players={}
	actors={}
	matricesA=quick_sprite_matrices({530,532,534,532,538,540,542,540,528,536,788,790,792,794,796,798,768,770,772,774,788,790,784},2,2,{-1,7,8,9},0)
	matricesB=quick_sprite_matrices({592,594,596,598,600,602,604,606,592,600,592,600,856,856,860,860,832,834,836,838,600,592,848},2,2,{-1,7,8,9},0)
	playerA=Player:new(
		136,
		104,
		matricesA,
		{
			CollisionRegion:new(0x5,0x4,0x6,0xB),
			CollisionRegion:new(0x2,0x10,0xE,0x2),
			CollisionRegion:new(0x2,0x2,0xC,0x4),
			CollisionRegion:new(0x3,0x3,0xA,0xD)
		})
	playerB=Player:new(
		112,
		104,
		matricesB,
		{
			CollisionRegion:new(0x5,0x4,0x6,0xB),
			CollisionRegion:new(0x2,0x10,0xE,0x2),
			CollisionRegion:new(0x2,0x2,0xC,0x4),
			CollisionRegion:new(0x2,0x2,0xC,0xE)
		})
	playerB:init_mover(0x1/0x6,0xA/0x10,0x9/0x10)
	playerB:init_jumper(-0x19/0x8)
	playerB:init_player(3,0,0.00015,0x4/0x5,0x1)
	actors[#actors+1]=playerA
	actors[#actors+1]=playerB
	players[#players+1]=playerA
	players[#players+1]=playerB
	--This fixes a glitch where both players share the same travel vector.
	players[1].Travel=Vector:new()
	players[2].Travel=Vector:new()
end

function TIC()
	for i=1,#players do check_input(i) end
	update_state()
	draw_tiles()
	for i=1,#actors do draw_actor(actors[i]) end
	t=t+1
end

function update_state()
	for i=1,#players do
		local pI=players[i]
		for j=i+1,#players do
			local pJ=players[j]
			if pI:absolute_col_reg(COLLIDE_FLOOR):intersects(pJ:absolute_col_reg(COLLIDE_HEAD)) then
				pJ:carry(pI)
			elseif pJ:absolute_col_reg(COLLIDE_FLOOR):intersects(pI:absolute_col_reg(COLLIDE_HEAD)) then
				pI:carry(pJ)
			elseif pI:absolute_col_reg(COLLIDE_BUMP):intersects(pJ:absolute_col_reg(COLLIDE_BUMP)) then
				if pI.Previous.X<pJ.Previous.X then
					pI:begin_push(-1)
					pJ:begin_push(1)
				else
					pI:begin_push(1)
					pJ:begin_push(-1)
				end
			end
		end
	end
	for i=1,#actors do actors[i]:update() end
	message.t=message.t-1
end

function OVR()
	vbank(1)
	cls(0)
	for i=1,#players do draw_hud(i-1,players[i].BatteryLife) end
end

function BDR(scanline)
	vbank(0)
	local V_BLANK=4
	local SCN_HUD=V_BLANK+TILE_SIZE
	local SCN_DEEP_WATER=V_BLANK+RESOLUTION.height-4
	local SCN_GROUND=V_BLANK+RESOLUTION.height-(2*TILE_SIZE)
	local SCN_MESSAGE=V_BLANK+RESOLUTION.height-TILE_SIZE
	if scanline>=SCN_MESSAGE then
		local grdPal=pallette.v0.ground
		local ratio=message.t>0 and (1-((scanline-SCN_MESSAGE)/8))/2 or 1
		if message.t>0 then
			for i=0,PALLETTE_SIZE-1 do
				set_pallette(
					i,
					grdPal[i+1].r*ratio,
					grdPal[i+1].g*ratio,
					grdPal[i+1].b*ratio)
			end
		end
		if scanline>=SCN_DEEP_WATER then
			local WATER_INDEX_BRIGHT=3
			local WATER_INDEX_DARK=1
			local ratioWater=1-((scanline-SCN_DEEP_WATER)/4)
			set_pallette(
				WATER_INDEX_BRIGHT,
				(grdPal[WATER_INDEX_DARK+1].r+((grdPal[WATER_INDEX_BRIGHT+1].r-grdPal[WATER_INDEX_DARK+1].r)*ratioWater))*ratio,
				(grdPal[WATER_INDEX_DARK+1].g+((grdPal[WATER_INDEX_BRIGHT+1].g-grdPal[WATER_INDEX_DARK+1].g)*ratioWater))*ratio,
				(grdPal[WATER_INDEX_DARK+1].b+((grdPal[WATER_INDEX_BRIGHT+1].b-grdPal[WATER_INDEX_DARK+1].b)*ratioWater))*ratio)
		end
	elseif scanline>=SCN_GROUND then
		for i=0,PALLETTE_SIZE-1 do
			set_pallette(
				i,
				pallette.v0.ground[i+1].r,
				pallette.v0.ground[i+1].g,
				pallette.v0.ground[i+1].b)
		end
	elseif scanline>=SCN_HUD then
		for i=0,PALLETTE_SIZE-1 do
			set_pallette(
				i,
				pallette.v0.initial[i+1].r,
				pallette.v0.initial[i+1].g,
				pallette.v0.initial[i+1].b)
		end
	else
		local ratio=scanline/SCN_HUD
		for i=0,PALLETTE_SIZE-1 do
			set_pallette(
				i,
				pallette.v0.initial[i+1].r*ratio,
				pallette.v0.initial[i+1].g*ratio,
				pallette.v0.initial[i+1].b*ratio)
		end
	end
end