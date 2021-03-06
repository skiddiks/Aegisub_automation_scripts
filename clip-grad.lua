--[[
==README==

Gradient along clip edge

Expands a vector clip shape in order to create a freeform color gradient. You can use this to
create diagonal gradients, zigzag gradients, or gradients in the shape of a curve.

Use the vector clip tool to draw the shape of the gradient you want. If you only want one of
the edges to have the gradient, make sure the other edges are placed with a wide margin around
and enclosing your typeset.

THIS SCRIPT ONLY WORKS ON SOLID ALPHA TYPESETS. That is, it will NOT work for any typesets that
have any form of transparency. This is a consequence of the way anti-aliasing is rendered.

Furthermore, although the interface provides options for all four colors, it's advised that
you only gradient one color per layer of the typeset. If you want to gradient a bordered
typeset, put the border on another, lower layer, and set the top layer border to zero. There's
some odd quirk with the way vector clips are rendered that causes tiny stripes of the border to
interfere with the gradient. The same goes for shadow.

]]--

script_name="Gradient along clip edge"
script_description="Color gradient along clip edge. Solid alpha only."
script_version="0.1.4"

include("karaskel.lua")
include("utils.lua")

--Global config, to allow storing of data across multiple runs
gconfig=nil

--Creates a shallow copy of the given table
local function shallow_copy(source_table)
	new_table={}
	for key,value in pairs(source_table) do
		new_table[key]=value
	end
	return new_table
end

--Creates a deep copy of the given table, to the given depth
local function deep_copy(source_table,depth)
	depth=math.floor(depth) or -1
	if depth==0 then return source_table end
	
	new_table={}
	for key,value in pairs(source_table) do
		if type(value)=="table" then value=deep_copy(value,depth-1) end
		new_table[key]=value
	end
	return new_table
end

--Distance between two points
local function distance(x1,y1,x2,y2)
	return math.sqrt((x2-x1)^2+(y2-y1)^2)
end

--Sign of a value
local function sign(n)
	return n/math.abs(n)
end

--Converts rad to degrees
local function todegree(n)
	return n * 180/math.pi
end

--Converts degrees to rad
local function torad(n)
	return n * math.pi/180
end

--Parses vector shape and makes it into a table
function make_vector_table(vstring)
	local vtable={}
	local vexp=vstring:match("^([1-4]),")
	vexp=tonumber(vexp) or 1
	for vtype,vcoords in vstring:gmatch("([mlb])([%d%s%-]+)") do
		for vx,vy in vcoords:gmatch("([%d%-]+)%s+([%d%-]+)") do
			table.insert(vtable,{["class"]=vtype,["x"]=tonumber(vx),["y"]=tonumber(vy)})
		end
	end
	return vtable,vexp
end

--Reverses a vector table object
function reverse_vector_table(vtable)
	local nvtable={}
	if #vtable<1 then return nvtable end
	--Make sure vtable does not end in an m. I don't know why this would happen but still
	maxi=#vtable
	while vtable[maxi].class=="m" do
		maxi=maxi-1
	end
	
	--All vector shapes start with m
	nstart=shallow_copy(vtable[maxi])
	tclass=nstart.class
	nstart.class="m"
	table.insert(nvtable,nstart)
	
	--Reinsert coords in backwards order, but shift the class over by 1
	--because that's how vector shapes behave in aegi
	for i=maxi-1,1,-1 do
		tcoord=shallow_copy(vtable[i])
		_temp=tcoord.class
		tcoord.class=tclass
		tclass=_temp
		table.insert(nvtable,tcoord)
	end
	
	return nvtable
end

--Turns vector table into string
function vtable_to_string(vt)
	cclass=nil
	result=""
	
	for i=1,#vt,1 do
		if vt[i].class~=cclass then
			result=result..string.format("%s %d %d ",vt[i].class,vt[i].x,vt[i].y)
			cclass=vt[i].class
		else
			result=result..string.format("%d %d ",vt[i].x,vt[i].y)
		end
	end
	
	return result
end

--Rounds to the given number of decimal places
function round(n,dec)
	dec=dec or 0
	return math.floor(n*10^dec+0.5)/(10^dec)
end

--Grows vt outward by the radius r scaled by sc
function grow(vt,r,sc)
	ch=get_chirality(vt)
	local wvt=wrap(vt)
	local nvt={}
	sc=sc or 1
	
	--Grow
	for i=2,#wvt-1,1 do
		cpt=wvt[i]
		ppt=wvt[i].prev
		npt=wvt[i].next
		while distance(cpt.x,cpt.y,ppt.x,ppt.y)==0 do
			ppt=ppt.prev
		end
		while distance(cpt.x,cpt.y,npt.x,npt.y)==0 do
			npt=npt.prev
		end
		rot1=todegree(math.atan2(cpt.y-ppt.y,cpt.x-ppt.x))
		rot2=todegree(math.atan2(npt.y-cpt.y,npt.x-cpt.x))
		drot=(rot2-rot1)%360
		
		--Angle to expand at
		nrot=(0.5*drot+90)%180
		if ch<0 then nrot=nrot+180 end
		
		--Adjusted radius
		__ar=math.cos(torad(ch*90-nrot)) --<3
		ar=(__ar<0.00001 and r) or r/math.abs(__ar)
		
		newx=cpt.x*sc
		newy=cpt.y*sc
		
		if r~=0 then
			newx=newx+sc*round(ar*math.cos(torad(nrot+rot1)))
			newy=newy+sc*round(ar*math.sin(torad(nrot+rot1)))
		end
		
		table.insert(nvt,{["class"]=cpt.class,
			["x"]=newx,
			["y"]=newy})
	end
	
	--Check for "crossovers"
	--New data type to store points with same coordinates
	local mvt={}
	local wnvt=wrap(nvt)
	for i,p in ipairs(wnvt) do
		table.insert(mvt,{["class"]={p.class},["x"]=p.x,["y"]=p.y})
	end
	
	--Number of merges so far
	merges=0
	
	for i=2,#wnvt,1 do
		mi=i-merges
		dx=wvt[i].x-wvt[i-1].x
		dy=wvt[i].y-wvt[i-1].y
		ndx=wnvt[i].x-wnvt[i-1].x
		ndy=wnvt[i].y-wnvt[i-1].y
		
		if (dy*ndy<0 or dx*ndx<0) then
			--Multiplicities
			c1=#mvt[mi-1].class
			c2=#mvt[mi].class
			
			--Weighted average
			mvt[mi-1].x=(c1*mvt[mi-1].x+c2*mvt[mi].x)/(c1+c2)
			mvt[mi-1].y=(c1*mvt[mi-1].y+c2*mvt[mi].y)/(c1+c2)
			
			--Merge classes
			mvt[mi-1].class={unpack(mvt[mi-1].class),unpack(mvt[mi].class)}
			
			--Delete point
			table.remove(mvt,mi)
			merges=merges+1
		end
	end
	
	--Rebuild wrapped new vector table
	wnvt={}
	for i,p in ipairs(mvt) do
		for k,pclass in ipairs(p.class) do
			table.insert(wnvt,{["class"]=pclass,["x"]=p.x,["y"]=p.y})
		end
	end
	
	return unwrap(wnvt)
end

function merge_identical(vt)
	local mvt=shallow_copy(vt)
	i=2
	lx=mvt[1].x
	ly=mvt[1].y
	while i<#mvt do
		if mvt[i].x==lx and mvt[i].y==ly then
			table.remove(mvt,i)
		else
			lx=mvt[i].x
			ly=mvt[i].y
			i=i+1
		end
	end
	return mvt
end

--Returns chirality of vector shape. +1 if counterclockwise, -1 if clockwise
function get_chirality(vt)
	local wvt=wrap(vt)
	wvt=merge_identical(wvt)
	trot=0
	for i=2,#wvt-1,1 do
		rot1=math.atan2(wvt[i].y-wvt[i-1].y,wvt[i].x-wvt[i-1].x)
		rot2=math.atan2(wvt[i+1].y-wvt[i].y,wvt[i+1].x-wvt[i].x)
		drot=todegree(rot2-rot1)%360
		if drot>180 then drot=360-drot elseif drot==180 then drot=0 else drot=-1*drot end
		trot=trot+drot
	end
	return sign(trot)
end

--Duplicates first and last coordinates at the end and beginning of shape,
--to allow for wraparound calculations
function wrap(vt)
	local wvt={}
	table.insert(wvt,shallow_copy(vt[#vt]))
	for i=1,#vt,1 do
		table.insert(wvt,shallow_copy(vt[i]))
	end
	table.insert(wvt,shallow_copy(vt[1]))
	
	--Add linked list capability. Because. Hacky fix gogogogo
	for i=2,#wvt-1 do
		wvt[i].prev=wvt[i-1]
		wvt[i].next=wvt[i+1]
	end
	--And link the start and end
	wvt[2].prev=wvt[#wvt-1]
	wvt[#wvt-1].next=wvt[2]
	
	return wvt
end

--Cuts off the first and last coordinates, to undo the effects of "wrap"
function unwrap(wvt)
	local vt={}
	for i=2,#wvt-1,1 do
		table.insert(vt,shallow_copy(wvt[i]))
	end
	return vt
end

--Returns the position of a line
local function get_pos(line)
	local _,_,posx,posy=line.text:find("\\pos%(([%d%.%-]*),([%d%.%-]*)%)")
	if posx==nil then
		_,_,posx,posy=line.text:find("\\move%(([%d%.%-]*),([%d%.%-]*),")
		if posx==nil then
			_,_,align_n=line.text:find("\\an([%d%.%-]*)")
			if align_n==nil then
				_,_,align_dumb=line.text:find("\\a([%d%.%-]*)")
				if align_dumb==nil then
					--If the line has no alignment tags
					posx=line.x
					posy=line.y
				else
					--If the line has the \a alignment tag
					vid_x,vid_y=aegisub.video_size()
					align_dumb=tonumber(align_dumb)
					if align_dumb>8 then
						posy=vid_y/2
					elseif align_dumb>4 then
						posy=line.eff_margin_t
					else
						posy=vid_y-line.eff_margin_b
					end
					_temp=align_dumb%4
					if _temp==1 then
						posx=line.eff_margin_l
					elseif _temp==2 then
						posx=line.eff_margin_l+(vid_x-line.eff_margin_l-line.eff_margin_r)/2
					else
						posx=vid_x-line.eff_margin_r
					end
				end
			else
				--If the line has the \an alignment tag
				vid_x,vid_y=aegisub.video_size()
				align_n=tonumber(align_n)
				_temp=align_n%3
				if align_n>6 then
					posy=line.eff_margin_t
				elseif align_n>3 then
					posy=vid_y/2
				else
					posy=vid_y-line.eff_margin_b
				end
				if _temp==1 then
					posx=line.eff_margin_l
				elseif _temp==2 then
					posx=line.eff_margin_l+(vid_x-line.eff_margin_l-line.eff_margin_r)/2
				else
					posx=vid-x-line.eff_margin_r
				end
			end
		end
	end
	return posx,posy
end

--Main execution function
function grad_clip(sub,sel)

	local meta,styles = karaskel.collect_head(sub, false)
	
	--[[
	TODO:
	GET GLOBAL CONFIG TO WORK
	]]
	if gconfig==nil then
	
		--Reference line to grab default gradient colors from
		refline=sub[sel[1]]
		karaskel.preproc_line(sub,meta,styles,refline)
		refc1=refline.text:match("\\c(&H%x+&)") or refline.text:match("\\1c(&H%x+&)") or refline.styleref.color1
		refc2=refline.text:match("\\2c(&H%x+&)") or refline.styleref.color2
		refc3=refline.text:match("\\3c(&H%x+&)") or refline.styleref.color3
		refc4=refline.text:match("\\4c(&H%x+&)") or refline.styleref.color4
		
		--GUI config
		gconfig=
		{
			{
				class="label",
				label="Gradient size:",
				x=0,y=0,width=2,height=1
			},
			gsize=
			{
				class="floatedit",
				name="gsize",
				min=0,step=0.5,value=20,
				x=2,y=0,width=2,height=1
			},
			{
				class="label",
				label="Gradient position:",
				x=0,y=1,width=2,height=1
			},
			gpos=
			{
				class="dropdown",
				name="gpos",
				items={"outside","middle","inside"},
				value="outside",
				x=2,y=1,width=2,height=1
			},
			{
				class="label",
				label="Step size:",
				x=0,y=2,width=2,height=1
			},
			gstep=
			{
				class="intedit",
				name="gstep",
				min=1,max=20,value=1,
				x=2,y=2,width=2,height=1
			},
			{
				class="label",
				label="Color1",
				x=0,y=3,width=1,height=1
			},
			{
				class="label",
				label="Color2",
				x=1,y=3,width=1,height=1
			},
			{
				class="label",
				label="Color3",
				x=2,y=3,width=1,height=1
			},
			{
				class="label",
				label="Color4",
				x=3,y=3,width=1,height=1
			},
			c1_1=
			{
				class="color",
				name="c1_1",
				x=0,y=4,width=1,height=1,
				value=refc1
			},
			c2_1=
			{
				class="color",
				name="c2_1",
				x=1,y=4,width=1,height=1,
				value=refc2
			},
			c3_1=
			{
				class="color",
				name="c3_1",
				x=2,y=4,width=1,height=1,
				value=refc3
			},
			c4_1=
			{
				class="color",
				name="c4_1",
				x=3,y=4,width=1,height=1,
				value=refc4
			},
			c1_2=
			{
				class="color",
				name="c1_2",
				x=0,y=5,width=1,height=1,
				value=refc1
			},
			c2_2=
			{
				class="color",
				name="c2_2",
				x=1,y=5,width=1,height=1,
				value=refc2
			},
			c3_2=
			{
				class="color",
				name="c3_2",
				x=2,y=5,width=1,height=1,
				value=refc3
			},
			c4_2=
			{
				class="color",
				name="c4_2",
				x=3,y=5,width=1,height=1,
				value=refc4
			}
		}
	
	end
	
	--For some reason the utils.lua extract_color refuses to work, so here's my own
	function get_color(s)
		r,g,b=s:match("#(%x%x)(%x%x)(%x%x)")
		if r then
			return tonumber(r or 0, 16), tonumber(g or 0, 16), tonumber(b or 0, 16)
		end
		return nil
	end
	
	--Show dialog
	pressed,results=aegisub.dialog.display(gconfig,{"Go","Cancel"})
	if pressed~="Go" then aegisub.cancel() end
	
	--Size of the blur
	gsize=results["gsize"]
	
	--Step size
	gstep=results["gstep"]
	
	--Colors table
	tcolors={}
	if results["c1_1"]~=results["c1_2"] then
		table.insert(tcolors,{
				["idx"]=1,
				["start"]=ass_color(get_color(results["c1_1"])),
				["end"]=ass_color(get_color(results["c1_2"]))
			}) end
	if results["c2_1"]~=results["c2_2"] then
		table.insert(tcolors,{
				["idx"]=2,
				["start"]=ass_color(get_color(results["c2_1"])),
				["end"]=ass_color(get_color(results["c2_2"]))
			}) end
	if results["c3_1"]~=results["c3_2"] then
		table.insert(tcolors,{
				["idx"]=3,
				["start"]=ass_color(get_color(results["c3_1"])),
				["end"]=ass_color(get_color(results["c3_2"]))
			}) end
	if results["c4_1"]~=results["c4_2"] then
		table.insert(tcolors,{
				["idx"]=4,
				["start"]=ass_color(get_color(results["c4_1"])),
				["end"]=ass_color(get_color(results["c4_2"]))
			}) end
	
	--How far to offset the blur by
	goffset=0
	if results["gpos"]=="inside" then goffset=gsize
	elseif results["gpos"]=="middle" then goffset=gsize/2 end
	
	--How far to offset the next line read
	lines_added=0
	
	--Update config
	for gk,gv in pairs(results) do
		gconfig[gk].value=gv
	end
	
	for si,li in ipairs(sel) do
		
		--Progress report
		aegisub.progress.task("Processing line "..si.."/"..#sel)
		aegisub.progress.set(100*si/#sel)
		
		--Read in the line
		line=sub[li+lines_added]
		
		--Preprocess
		karaskel.preproc_line(sub,meta,styles,line)
		
		--Comment it out
		line.comment=true
		sub[li+lines_added]=line
		line.comment=false
		
		--Find the clipping shape
		ctype,tvector=line.text:match("\\(i?clip)%(([^%(%)]+)%)")
		
		--Cancel if it doesn't exist
		if tvector==nil then
			aegisub.log("Make sure all lines have a clip statement.")
			aegisub.cancel()
		end
		
		--If it's a rectangular clip, convert to vector clip
		if tvector:match("([%d%-%.]+),([%d%-%.]+),([%d%-%.]+),([%d%-%.]+)")~=nil then
			_x1,_y1,_x2,_y2=tvector:match("([%d%-%.]+),([%d%-%.]+),([%d%-%.]+),([%d%-%.]+)")
			tvector=string.format("m %d %d l %d %d %d %d %d %d",
				_x1,_y1,_x2,_y1,_x2,_y2,_x1,_y2)
		end
		
		--The original table and original scale exponent
		otable,oexp=make_vector_table(tvector)
		oscale=2^(oexp-1)
		
		--Add tag block if none exists
		if line.text:match("^{")==nil then line.text="{}"..line.text end
		
		--Get position and add
		px,py=get_pos(line)
		if line.text:match("\\pos")==nil and line.text:match("\\move")==nil then
			line.text=line.text:gsub("^{",string.format("{\\pos(%d,%d)",px,py))
		end
		
		--The innermost line
		iline=shallow_copy(line)
		itable={}
		if ctype=="iclip" then
			itable=grow(otable,gsize-goffset-1,oscale)
		else
			itable=grow(otable,-1*goffset,oscale)
		end
		iline.text=iline.text:gsub("\\i?clip%([^%(%)]+%)","\\"..ctype.."("..oexp..","..vtable_to_string(itable)..")")
		
		--Add colors
		for _,val in pairs(tcolors) do
			if val.idx==1 then iline.text=iline.text:gsub("\\c&H%x+&","") end
			iline.text=iline.text:gsub("\\"..val.idx.."c&H%x+&","")
			iline.text=iline.text:gsub("^{","{\\"..val.idx.."c"..val.start)
		end
		
		--Add it to the subs
		sub.insert(li+lines_added+1,iline)
		lines_added=lines_added+1
		
		prevclip=itable
		
		for j=1,math.ceil(gsize/gstep),1 do
			
			--Interpolation factor
			factor=j/math.ceil(gsize/gstep+1)
			
			--Flip if it's an iclip
			if ctype=="iclip" then factor=1-factor end
			
			--Copy the line
			tline=shallow_copy(line)
			
			--Add colors
			for _,val in pairs(tcolors) do
				if val.idx==1 then tline.text=tline.text:gsub("\\c&H%x+&","") end
				tline.text=tline.text:gsub("\\"..val.idx.."c&H%x+&","")
				tline.text=tline.text:gsub("^{",
					"{\\"..val.idx.."c"..interpolate_color(factor,val["start"],val["end"]))
			end
			
			--Write the correct clip
			thisclip=grow(otable,(j*gstep<gsize) and (j*gstep-goffset) or (gsize-goffset),oscale)
			clipstring=
				vtable_to_string(thisclip)..vtable_to_string(reverse_vector_table(grow(prevclip,-1,oscale)))
			prevclip=thisclip
			
			tline.text=tline.text:gsub("\\i?clip%([^%(%)]+%)","\\clip("..oexp..","..clipstring..")")
			
			--Insert the line
			sub.insert(li+lines_added+1,tline)
			lines_added=lines_added+1
		end
		
		--The outermost line
		lline=shallow_copy(line)
		ltable={}
		ltype=""
		if ctype=="iclip" then
			ltable=grow(otable,-1*goffset+gstep,oscale)
			ltype="clip"
		else
			ltable=grow(prevclip,-1,oscale)
			ltype="iclip"
		end
		
		lline.text=lline.text:gsub("\\i?clip%([^%(%)]+%)","\\"..ltype.."("..oexp..","..vtable_to_string(ltable)..")")
		
		--Add colors
		for _,val in pairs(tcolors) do
			if val.idx==1 then lline.text=lline.text:gsub("\\c&H%x+&","") end
			lline.text=lline.text:gsub("\\"..val.idx.."c&H%x+&","")
			lline.text=lline.text:gsub("^{","{\\"..val.idx.."c"..val["end"])
		end
		
		--Insert the line
		sub.insert(li+lines_added+1,lline)
		lines_added=lines_added+1
	end
	
	aegisub.set_undo_point(script_name)
end

aegisub.register_macro(script_name,script_description,grad_clip)