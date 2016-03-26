----------------------------------------------------------------------------------
-- Copyright 2016 Marcelo Costa Toyama
--
-- This file is part of PixelnDice.
--
--    PixelnDice is free software: you can redistribute it and/or modify
--    it under the terms of the GNU Affero General Public License as published by
--    the Free Software Foundation, either version 3 of the License, or
--    any later version.
--
--    PixelnDice is distributed in the hope that it will be useful,
--    but WITHOUT ANY WARRANTY; without even the implied warranty of
--    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--    GNU Affero General Public License for more details.
--
--    You should have received a copy of the GNU Affero General Public License
--    along with PixelnDice.  If not, see <http://www.gnu.org/licenses/>.
--
----------------------------------------------------------------------------------

package.path = package.path..";"..'/usr/share/lua/5.1/?.lua;/var/www/dicewsocket/?.lua;/var/www/dicelib/?.lua;;'
package.cpath = package.cpath..";"..'/usr/lib/i386-linux-gnu/lua/5.1/?.so;;'

local os = require("os")
local math = require("math")

-- init random engine
math.randomseed(os.time())

----------------------------------------------------------------------------------

local DiceMod = {}

----------------------------------------------------------------------------------
function DiceMod.single(a)

   local ret = ""

   local m,d = a:match("(%d*)[dD](%d+)")

   if( m == "" ) then
      ret = math.random(d)
   else
      ret = "("..math.random(d)

      for idx=2, tonumber(m) do
         local v = math.random(d)
         ret = ret.." + "..v
      end
      ret = ret..")"

   end

   return ret

end
----------------------------------------------------------------------------------
-- eval CMD:DICE
function DiceMod.roll(roll)

   -- rolls dices
   roll = roll:gsub("[^%d+dD-%*/()]","")
   local ret = roll:gsub("%d*[dD]%d+", DiceMod.single)

   -- save string roll
   local stringRoll = ret

   local ret = "out("..ret..")"
   local state = ""

   -- make environment
   local env = {out=function(msg) state = msg end} -- add functions you know are safe here

   -- run code under environment [Lua 5.1]
   local function run(untrusted_code)
      if untrusted_code:byte(1) == 27 then return nil, "binary bytecode prohibited" end
      local untrusted_function, message = loadstring(untrusted_code)
      if not untrusted_function then return nil, message end
      setfenv(untrusted_function, env)
      return pcall(untrusted_function)
   end

   -- run code under environment [Lua 5.2]
   --[[
   local function run(untrusted_code)
      local untrusted_function, message = load(untrusted_code, nil, 't', env)
      if not untrusted_function then return nil, message end
      return pcall(untrusted_function)
      end
   ]]--

   run(ret)

   return roll,stringRoll,state

end
----------------------------------------------------------------------------------

return DiceMod

----------------------------------------------------------------------------------
