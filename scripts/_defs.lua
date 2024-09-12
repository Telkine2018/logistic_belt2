---@class Parameters
---@field request_table RequestInfo[]
---@field tick integer      -- mine tick
---@field lane1_items string[]
---@field lane2_items string[]
---@field lane1_item_interval number?
---@field lane2_item_interval number?
---@field speed number  -- belt speed
---@field slow (boolean|number)?

---@class LoaderInfo
---@field loader LuaEntity
---@field output boolean?
---@field loader_type string

---@class DeviceInfo
---@field device LuaEntity
---@field output boolean
---@field direction integer
---@field belt LuaEntity
---@field loader LuaEntity

---@class RequestInfo
---@field item string
---@field count integer

---@class Cluster
---@field routers table<integer, Router>
---@field link_id integer
---@field devices table<integer, Device>
---@field node Node
---@field masterid integer
---@field deleted boolean?

---@alias RequestTable RequestInfo[]
---@alias Router LuaEntity
---@alias Device LuaEntity

------------------------------------

---@class IOPoint
---@field id integer
---@field device LuaEntity
---@field container LuaEntity
---@field inventory LuaInventory
---@field is_output boolean                 @ Container to belt
---@field node Node
---@field error boolean?
---@field connection Connection
---@field inserters LuaEntity[]
---@field overflows table<string, integer>?

---@class Node
---@field id integer
---@field container LuaEntity
---@field inventory LuaInventory
---@field inputs table<integer, IOPoint>                            @ belt to container
---@field outputs table<integer, IOPoint>                           @ container to belt
---@field contents table<string, integer>
---@field routings table<string, table<integer,Routing>>?           @ item => (id routing => routing)
---@field previous Node                                             @ link for searching provider
---@field previous_dist number
---@field graph_tick integer
---@field dist_cache table<integer, number>
---@field next Node                                                 @ link for searching requester
---@field output_map table<integer, IOPoint[]>                      @ map (node) => [output to node]
---@field provided table<string, ProvidedItem>                      @ item => threshold
---@field requested table<string, RequestedItem>                    @ item => requested items
---@field disabled boolean?
---@field last_reset_tick integer
---@field saturated boolean?
---@field remaining table<string, integer>?
---@field priority integer
---@field buffer_size integer
---@field overflows table<integer, IOPoint>
---@field restrictions table<string, boolean>?
---@field disabled_id integer
---@field full_id integer
---@field auto_provide boolean?

---@class Connection
---@field id integer
---@field outputs table<integer, IOPoint>       @ container to belt
---@field inputs table<integer, IOPoint>        @ belt to container

---@class Routing
---@field id integer            @ identifier
---@field item string           @ item name
---@field remaining integer     @ remaining count to route
---@field output IOPoint        @ output point

---@class ProvidedItem
---@field item string
---@field provided integer

---@class RequestedItem
---@field item string
---@field delivery integer?
---@field count integer                 @ count of request items
---@field remaining integer             @ count of items currently on the way
---@field last_provider_node integer?   @ Last providing node
---@field last_provider_tick integer?   @ Last date dof providing node
---@field last_routings integer[]?      @ Last date dof providing node

---@class Context
---@field nodes table<integer, Node>
---@field iopoints table<integer, IOPoint>
---@field clusters table<integer, Cluster>      @ map link_id => cluster
---@field node_count integer
---@field node_index number
---@field node_per_tick number
---@field current_node_id  integer?
---@field structure_tick integer?
---@field graph_tick integer
