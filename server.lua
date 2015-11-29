----------------------------------------------------------------------------------
-- Copyright 2015 Marcelo Costa Toyama
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

package.path = package.path..";"..'/usr/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?.lua;/var/www/dicewsocket/?.lua;/var/www/dicelib/?.lua;;'
package.cpath = package.cpath..";"..'/usr/local/lib/lua/5.1/?.so;/usr/lib/i386-linux-gnu/lua/5.1/?.so;;'




local copas = require('copas')
local json = require("json")

local accountMod = require("account")
local mapMod = require("map")
local diceMod = require("dice")

-- set of all rooms _rooms[roomId] = {accountId=true}
local _rooms = {}

-- set of all accounts _accounts[accountID] = {roomId="", ws=ws}
local _accounts = {}

----------------------------------------------------------------------------------
-- delivers message
function deliver(from,to,cmd,msg,roomId)

   if( to == "ALL" ) then

      if( from ~= "SYSTEM" ) then
         roomId = _accounts[from].roomId
      end

      for k,v in pairs(_rooms[roomId]) do

         local packet = {FROM=from,TO=to,CMD=cmd}

         for k,v in pairs(msg) do packet[k] = v end

         _accounts[k].ws:send(json.encode(packet))
      end
   elseif( to == "ALL-BUT-ME" ) then

      if( from ~= "SYSTEM" ) then
         roomId = _accounts[from].roomId
      end

      for k,v in pairs(_rooms[roomId]) do

         local packet = {FROM=from,TO=to,CMD=cmd}

         for k,v in pairs(msg) do packet[k] = v end

         if( k ~= from ) then
            _accounts[k].ws:send(json.encode(packet))
         end
      end

   else

      if( from == "SYSTEM" or _accounts[from].roomId == _accounts[to].roomId ) then

         if( _accounts[to] ~= nil ) then

            local packet = {FROM=from,TO=to,CMD=cmd}

            for k,v in pairs(msg) do packet[k] = v end

            _accounts[to].ws:send(json.encode(packet))

         else
            _accounts[from]. ws:send(json.encode({FROM="SYSTEM",TO=from,CMD="ERROR",MESSAGE="Send message to: "..to.." failed - user does not exist"}))
         end

      else
         _accounts[from].ws:send(json.encode({FROM="SYSTEM",TO=from,CMD="ERROR",MESSAGE="Send message to: "..to.." failed - TO and FROM are not in the same roomId"}))
      end
   end
end
----------------------------------------------------------------------------------
-- create a copas webserver and start listening
local server = require'websocket'.server.copas.listen
{
   -- listen on port 8080
   port = 9999,
   -- the protocols field holds
   --   key: protocol name
   --   value: callback on new connection
   protocols = {
      -- this callback is called, whenever a new client connects.
      -- ws is a new websocket instance
      diceProtocol = function(ws)

         local msg = ws:receive()
         local packet = json.decode(msg)

         -- processing init
         if( packet.CMD ~= "INIT" ) then

            ws:send(json.encode({FROM="SYSTEM",TO=packet.FROM,CMD="ERROR",MSG="Error: expecting INIT"}))

            ws:close()
            return
         else

            if( packet.TOKEN == accountMod.getToken(packet.FROM) ) then
               ws:send(json.encode({FROM="SYSTEM",TO=packet.FROM,CMD="INITRET",RET=true}))
            else
               ws:send(json.encode({FROM="SYSTEM",TO=packet.FROM,CMD="ERROR",MSG="Invalid token: "..packet.TOKEN}))
               ws:close()
               return
            end

         end

         -- processing join
         msg = ws:receive()
         packet = json.decode(msg)

         if( packet.CMD ~= "JOIN" ) then
            ws:send(json.encode({FROM="SYSTEM",TO=packet.FROM,CMD="ERROR",MSG="Error: expecting JOIN"}))
            ws:close()
            return
         else

            if( _rooms[packet.ROOMID] == nil ) then
               -- creating room

               local players = {}
               players[packet.FROM] = true
               _rooms[packet.ROOMID] = players

            else
               _rooms[packet.ROOMID][packet.FROM] = true
            end

            -- loading player info
            local acc = {roomId=packet.ROOMID, ws=ws, name= accountMod.getName(packet.FROM)}
            _accounts[packet.FROM] = acc

            -- sending players list to me
            local msg = {}

            for k,reg in pairs(_accounts) do
               table.insert(msg, {ACCOUNTID=k,NAME=reg.name})
            end

            deliver("SYSTEM",packet.FROM,"JOINRET",{PLAYERS=msg})

            -- announcing that i have joined the channel
            deliver("SYSTEM","ALL","NEWPLAYER",{ACCOUNTID=packet.FROM,NAME=acc.name},packet.ROOMID)

         end

         while true do

            local msg = ws:receive()

            if msg then

               local packet = json.decode(msg)

               -- text message
               if( packet.CMD == "TEXT" ) then

                  -- scape HTML
                  packet.MESSAGE = packet.MESSAGE:gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;')

                  deliver(packet.FROM,packet.TO,packet.CMD,{MESSAGE = packet.MESSAGE})

               elseif( packet.CMD == "LOADGMMAP" ) then

                  local retJson = mapMod.loadJSON(packet.FROM,packet.CAMPAIGNID,packet.MAPID)
                  ws:send(json.encode({FROM="SYSTEM",TO=packet.FROM,CMD="LOADGMMAPRET",JSON=retJson}))

               elseif( packet.CMD == "QUERYMAP" ) then

                  deliver(packet.FROM,packet.TO,packet.CMD,{})

               elseif( packet.CMD == "DICE") then

                  local iRoll = packet.MESSAGE
                  local msg, statement, value  = diceMod.roll(iRoll)

                  deliver(packet.FROM,packet.TO,"DICERET",{MESSAGE=msg,ROLLDICE=statement,VALUE=value})

               elseif( packet.CMD == "GMDICE" ) then

                  local iRoll = packet.MESSAGE
                  local msg, statement, value  = diceMod.roll(iRoll)

                  deliver(packet.FROM,packet.TO,"GMDICERET",{MESSAGE=msg,ROLLDICE=statement,VALUE=value})
                  deliver(packet.FROM,packet.FROM,"GMDICERET",{MESSAGE=msg,ROLLDICE=statement,VALUE=value})

               elseif( packet.CMD == "LOADMAP" ) then

                  deliver(packet.FROM,packet.TO,packet.CMD,{MAPID=packet.MAPID,NAME=packet.NAME,JSON=packet.JSON})
               elseif( packet.CMD == "ADDTOKEN" ) then
                  deliver(packet.FROM,packet.TO,packet.CMD,{MAPID=packet.MAPID,TOKEN=packet.TOKEN})
               elseif( packet.CMD == "DELETETOKEN" ) then
                  deliver(packet.FROM,packet.TO,packet.CMD,{MAPID=packet.MAPID,UUID=packet.UUID})
               elseif( packet.CMD == "UPDATETOKEN" ) then
                  deliver(packet.FROM,packet.TO,packet.CMD,{MAPID=packet.MAPID,TOKENUUID=packet.TOKENUUID,JSON=packet.JSON})
               else
                  deliver("SYSTEM",packet.FROM,"ERROR",{MESSAGE="Invalid CMD: "..packet.CMD})
               end

            else

               -- closing connection
               for k,v in pairs(_accounts) do

                  if _accounts[k].ws == ws then

                     _rooms[_accounts[k].roomId][k] = nil

                     local count = 0
                     for _, _ in pairs(_rooms[_accounts[k].roomId]) do count = count + 1 end
                     if( count == 0 ) then _rooms[_accounts[k].roomId] = nil end

                     ws:close()
                     _accounts[k] = nil

                     return
                  end
               end

            end

         end
      end
   }
}

-- use the copas loop
copas.loop()
----------------------------------------------------------------------------------
