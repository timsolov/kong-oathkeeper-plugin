local access = require "kong.plugins.oathkeeper.access"

local OathkeeperHandler = {
  VERSION  = "1.0.0",
  PRIORITY = 900,
}

OathkeeperHandler.access = access

return OathkeeperHandler