
local function elem(k)
	local t = type(k)
	if t=='nil' or t=='boolean' or t=='number' then
		return '['..tostring(k)..']'
	elseif t=='string' and k:match('^[A-Za-z_][A-Za-z_0-9]*$') then
		return '.'..k
	elseif t=='string' then
		return '['..string.format("%q", k):gsub('\n', '\\n'):gsub('\t', '\\t')..']'
	else
		error("unsupported key type '"..t.."'")
	end
end

local function pathstr(path)
	for i=1,#path do
		path[i] = elem(path[i])
	end
	return table.concat(path)
end

local function match(a, b, path)
	local t = type(a)
	if t~=type(b) then
		return false,path
	else
		if t=='nil' or t=='boolean' or t=='number' or t=='string' or t=='function' or t=='thread' then
			return a==b,path
		elseif t=='table' then
			if a==b then return true end
			-- try to differentiate from content
			local keys = {}
			for k in pairs(a) do keys[k] = true end
			for k in pairs(b) do keys[k] = true end
			for k in pairs(keys) do
				local t = type(k)
				if t=='boolean' or t=='number' or t=='string' then
					local subpath = {}
					if path then for i,k in ipairs(path) do subpath[i] = k end end
					table.insert(subpath, k)
					local success,path = match(a[k], b[k], subpath)
					if not success then
						return false,path
					end
				else
					error("unsupported key type '"..t.."'")
				end
			end
			return true
		elseif t=='userdata' then
			if a==b then return true,path end
			-- if the udata share a metatable with a __tostring, compare their string form
			local mt = debug.getmetatable(a)
			if mt~=debug.getmetatable(b) then
				return false,path
			elseif mt then
				if mt.__tostring then
					return tostring(a)==tostring(b),path
				else
					return false,path
				end
			else
				return false,path
			end
		else
			error("unsupported value type '"..t.."'")
		end
	end
end

function expect(expectation, value, ...)
	local success,path = match(expectation, value)
	if not success then
		if path then
			local a,b = expectations,value
			for _,k in ipairs(path) do
				expectation,value = expectation[k],value[k]
			end
			error("expectation failed!"..
				" "..tostring(expectation).." ("..type(expectation)..") expected"..
				" for field "..pathstr(path)..
				", got "..tostring(value).." ("..type(value)..")",
				2)
		else
			error("expectation failed!"..
				" "..tostring(expectation).." ("..type(expectation)..") expected"..
				", got "..tostring(value).." ("..type(value)..")",
				2)
		end
	end
end

if ...==nil then
	assert(elem(nil)=='[nil]')
	assert(elem(0)=='[0]')
	assert(elem(" ")=='[" "]')
	assert(elem("foo")=='.foo')
	
	assert(pathstr({})=='')
	assert(pathstr({1})=='[1]')
	assert(pathstr({'foo', 'bar'})=='.foo.bar')
	
	local success,path
	-- matching nils
	success,path = match(nil, nil)
	assert(success and path==nil)
	-- matching numbers
	success,path = match(0, 0)
	assert(success and path==nil)
	-- non-matching numbers
	success,path = match(0, 1)
	assert(not success and path==nil)
	-- matching strings
	success,path = match("", "")
	assert(success and path==nil)
	-- non-matching strings
	success,path = match("", " ")
	assert(not success and path==nil)
	-- identical tables
	local t = {}
	success,path = match(t, t)
	assert(success and path==nil)
	-- matching tables
	success,path = match({}, {})
	assert(success and path==nil)
	-- matching table field
	success,path = match({0}, {0})
	assert(success and path==nil)
	-- non-matching table fields
	success,path = match({0}, {1})
	assert(not success and pathstr(path)=='[1]')
	-- matching table sub-fields
	success,path = match({{0}}, {{0}})
	assert(success and path==nil)
	-- non-matching table sub-fields
	success,path = match({{0}}, {{1}})
	assert(not success and pathstr(path)=='[1][1]')
	success,path = match({{type='library', filename='foo'}}, {{type='library', filename='fooa'}})
	assert(not success and pathstr(path)=='[1].filename')
	-- identical functions
	success,path = match({print}, {print})
	assert(success and path==nil)
	-- distinct functions
	success,path = match({print}, {assert})
	assert(not success and pathstr(path)=='[1]')
	-- identical coroutines
	local c = coroutine.create(function() end)
	success,path = match({c}, {c})
	assert(success and path==nil)
	-- distinct coroutines
	local c1 = coroutine.create(function() end)
	local c2 = coroutine.create(function() end)
	success,path = match({c1}, {c2})
	assert(not success and pathstr(path)=='[1]')
	-- identical udata
	local ud = newproxy()
	success,path = match({ud}, {ud})
	assert(success and path==nil)
	-- distinct udata without metatable (mt)
	local ud1,ud2 = newproxy(),newproxy()
	success,path = match({ud1}, {ud2})
	assert(not success and pathstr(path)=='[1]')
	-- distinct udata with distinct mt
	local ud1,ud2 = newproxy(true),newproxy(true)
	success,path = match({ud1}, {ud2})
	assert(not success and pathstr(path)=='[1]')
	-- distinct udata with identical mt, no __tostring
	local ud1 = newproxy(true)
	local ud2 = newproxy(ud1)
	success,path = match({ud1}, {ud2})
	assert(not success and pathstr(path)=='[1]')
	-- distinct udata with identical mt, matching __tostring
	local ud1 = newproxy(true)
	local ud2 = newproxy(ud1)
	getmetatable(ud1).__tostring = function() return "" end
	success,path = match({ud1}, {ud2})
	assert(success and path==nil)
	-- distinct udata with identical mt, non-matching __tostring
	local ud1 = newproxy(true)
	local ud2 = newproxy(ud1)
	getmetatable(ud1).__tostring = function(self) if self==ud1 then return "" else return " " end end
	success,path = match({ud1}, {ud2})
	assert(not success and pathstr(path)=='[1]')
end

