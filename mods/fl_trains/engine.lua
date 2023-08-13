local max_speed = 5

local function speed_check(vec, limit)
    local v = vector.apply(vec, math.abs)
    local l = limit
    if v.x >= l then return false
    elseif v.y >= l then return false
    elseif v.z >= l then return false end
    return true
end

function deg_to_rad(x)
    return x * math.pi/180
end

function rad_to_deg(x)
    return x * 180/math.pi
end

local function is_centered(vec) --is centered ish
    local fx, fz = math.floor(vec.x), math.floor(vec.z)
    if vec.x >= fx-0.1 and vec.x <= fx+0.1 and vec.z >= fz-0.1 and vec.z <= fz+0.1 then
        return true
    else
        return false
    end
end

minetest.register_entity("fl_trains:train_engine", {
    --mte object properties
    initial_properties = {
        physical = true,
        --stepheight = 0.4,
        collide_with_objects = true,
        collisionbox = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
        visual = "mesh",
        mesh = "farlands_train_engine.obj",
        textures = {
            "farlands_train_engine.png",
        },
        backface_culling = false,
        visual_size = {x=10, y=10, z=10},
        static_save = true,
        damage_texture_modifier = "^[colorize:#FF000040"
    },

    --on_step = mobkit.stepfunc, --this is required
    on_activate = function(self, staticdata, dtime_s)
        --load memory
        local sdata = minetest.deserialize(staticdata)
        if sdata then
            for k,v in pairs(sdata) do
                self[k] = v
            end
        end
        if not self.memory then self.memory = {} end
        --other stuff
    end,
    get_staticdata = function(self)
        local tmp = {memory = self.memory}
        return minetest.serialize(tmp)
    end,
    on_step = function(self, dtime, moveresult)
        local yaw = tonumber(string.format("%.2f", self.object:get_yaw()))
        local dir = vector.round(minetest.yaw_to_dir(yaw))
        local pos = self.object:get_pos()
        local ndir = dir

        local vel = self.object:get_velocity()
        local player
        if self.memory.driver then player = minetest.get_player_by_name(self.memory.driver) end
        if not player then return end
        local pcontrols = player:get_player_control()
        if pcontrols.up and speed_check(vel, max_speed) then
            self.object:add_velocity(vector.multiply(dir, 0.2))
        elseif pcontrols.down and speed_check(vel, max_speed) then
            self.object:add_velocity(vector.multiply(dir, -0.2))
            ndir = vector.multiply(ndir, -1)
        end

        --brakes
        if pcontrols.jump then
            self.object:set_velocity(vector.new(0,0,0))
        end

        local node = minetest.get_node_or_nil(vector.add(ndir, pos))
        local currnode = minetest.get_node_or_nil(pos)
        if not node or not currnode then self.object:set_velocity(vector.new(0,0,0)) return end

        local continue_rail_nodes = {
            ["fl_trains:straight_track"] = true,
            ["fl_trains:crossing_track"] = true,
            ["fl_trains:straight_45_track"] = true,
            ["fl_trains:curve_left_track"] = true,
        }

        if continue_rail_nodes[node.name] then
            --self.object:set_velocity(vector.new(0,0,0))
            --just keep moving
            return
        else
            --works if straight headed in to curve left track param2 of 1
            --TODO: take into account param2 for rotation
            if currnode.name == "fl_trains:curve_left_track" then
                --minetest.chat_send_all(dump(pos))
                if is_centered(pos) then
                    local currrotation = self.object:get_rotation()

                    if math.floor(rad_to_deg(currrotation.y))%90==0 then
                        --is center can only determine if we are roughly center, so force center
                        self.object:set_pos(vector.apply(pos, math.floor))
                        self.object:set_rotation(
                            vector.new(currrotation.x, currrotation.y + deg_to_rad(45), currrotation.z)
                        )
                        --self.object:set_velocity(vector.new(0,0,0))
                        self.object:set_velocity(
                            vector.multiply(
                                minetest.yaw_to_dir(
                                    self.object:get_yaw()
                                ),
                                vector.length( --speed
                                    self.object:get_velocity()
                                )
                            )
                        )
                    end
                end

                return
            end
            --minetest.chat_send_all(node.name)

            --dont know what the next rail is, stop
            self.object:set_velocity(vector.new(0,0,0))
            return
        end
    end,

    on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
        self.object:remove()
    end,

    on_rightclick=function(self, clicker)
        if #self.object:get_children() > 0 then
            for _, obj in pairs(self.object:get_children()) do
                if obj:is_player() and obj:get_player_name() == self.memory.driver then
                    obj:set_detach()
                    obj:set_properties({visual_size = vector.new(1,1,1)})
                    fl_player.ignore[obj:get_player_name()] = nil
                    obj:set_eye_offset(vector.new(0,0,0), vector.new(0,0,0))
                    self.memory.driver = nil
                end
            end
        else
            clicker:set_attach(self.object, "", vector.new(0,-0.49,0.45), vector.new(0,0,0), true)
            clicker:set_properties({visual_size = vector.new(.075,.075,.075)})
            fl_player.ignore[clicker:get_player_name()] = true
            clicker:set_animation(fl_player.animations["sit"], 15)
            clicker:set_eye_offset(vector.new(0,-13,5.5), vector.new(0,-13,5.5))
            self.memory.driver = clicker:get_player_name()
        end
    end,
})

minetest.register_craftitem("fl_trains:train_engine", {
    description = "train_engine",
    inventory_image = "farlands_cart_item.png",
    wield_image = "farlands_cart_item.png",
    on_place = function(itemstack, placer, pointed_thing)
        if pointed_thing.type ~= "node" then return end
        local node = minetest.get_node_or_nil(pointed_thing.under)
        if string.find(node.name, "fl_trains") then
            local ent = minetest.add_entity(pointed_thing.under, "fl_trains:train_engine")
            if node.name == "fl_trains:straight_track" and node.param2%2 ~= 0 then
                ent:set_rotation(vector.new(0,90*(math.pi/180),0))
                --minetest.chat_send_all(ent:get_yaw())
            end
        end
    end,
    groups = {not_in_creative_inventory = 1}
})