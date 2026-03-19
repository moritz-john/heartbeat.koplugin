--- heartbeat.koplugin
-- This plugin allows KOReader to send its current state to a Home Assistant binary sensor.

local _ = require("gettext")
local UIManager = require("ui/uimanager")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Device = require("device")
local powerd = Device:getPowerDevice()
local NetworkMgr = require("ui/network/manager")
local rapidjson = require("rapidjson")
local logger = require("logger")
local API = require("heartbeat_api")

-- Use heartbeat_debug_config.lua if it exists (for development); otherwise heartbeat_config.lua (for end-user)
local ok, ha_config = pcall(require, "heartbeat_debug_config")
if not ok then
    ha_config = require("heartbeat_config")
end

local Heartbeat = WidgetContainer:extend {
    name        = "heartbeat",
    is_doc_only = false,
}

Heartbeat.default_settings = {
    heartbeat_name = "koreader_status",
    heartbeat_enabled = false,
    heartbeat_loop_enabled = false,
    heartbeat_interval = 300, -- Default: 5 minutes
    resume_delay = 8,         -- Default: 8 seconds
}

--- Load settings and merge with defaults
function Heartbeat:loadSettings()
    -- Load saved settings, or start with empty table if none exist
    self.settings = G_reader_settings:readSetting("heartbeat") or {}

    -- Merge in any missing default values (important for plugin updates that add new settings)
    for key, value in pairs(self.default_settings) do
        if self.settings[key] == nil then
            self.settings[key] = value
        end
    end

    -- Save the merged settings back to disk
    G_reader_settings:saveSetting("heartbeat", self.settings)
    G_reader_settings:flush()
end

--- Initialize the plugin
function Heartbeat:init()
    self.ui.menu:registerToMainMenu(self)

    self:loadSettings()

    -- Guard to ensure initialization only happens once at startup
    if not Heartbeat._initialized then
        Heartbeat._initialized = true

        -- Start heartbeat loop if enabled
        if self.settings.heartbeat_loop_enabled then
            self:heartbeatLoop(true)
        end

        -- Send initial heartbeat if enabled
        if self.settings.heartbeat_enabled then
            self:sendHeartbeat("on")
        end
    end
end

function Heartbeat:buildUrl()
    local protocol = ha_config.https == true and "https" or "http"
    return string.format("%s://%s:%d/api/states/binary_sensor.%s",
        protocol, ha_config.host, ha_config.port, self.settings.heartbeat_name)
end

--- Send the current KOReader state to Home Assistant
function Heartbeat:sendHeartbeat(state, skip_book_info)
    if not NetworkMgr:isConnected() then
        if not self._offline_logged then
            logger.info("[Heartbeat]: no network connection, skipping heartbeats")
            self._offline_logged = true
        end
        return
    end
    self._offline_logged = false

    local url = self:buildUrl()

    -- Get book title and author
    local book_title, book_author = nil, nil
    if self.ui and self.ui.doc_props and state == "on" and not skip_book_info then
        book_title = self.ui.doc_props.display_title or "Unknown Book"
        book_author = (self.ui.doc_props.authors and self.ui.doc_props.authors:gsub("\n", ", ")) or "Unknown Author"
    end

    local service_data = {
        state = state,
        attributes = {
            friendly_name = "KOReader Status",
            icon = state == "on" and "mdi:book-variant" or "mdi:book-off",
            device_model = Device.model,
            book_title = book_title or rapidjson.null,
            book_author = book_author or rapidjson.null,
            battery_level = Device:hasBattery() and powerd:getCapacity() or rapidjson.null,
            is_charging = Device:hasBattery() and powerd:isCharging() or false,
            last_seen = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }
    }
    local has_error, response = API:performRequest(url, ha_config.token, service_data)

    if has_error then
        logger.info("[Heartbeat]: sending heartbeat failed - Error:", response)
    end
end

--- Heartbeat loop that reschedules itself
function Heartbeat:heartbeatLoop(skip_first)
    if not self.settings.heartbeat_loop_enabled then return end -- safety guard: stop if loop was disabled
    if not skip_first then
        self:sendHeartbeat("on")
    end
    UIManager:scheduleIn(self.settings.heartbeat_interval, self.heartbeatLoop, self)
end

--- Called when document is fully loaded
function Heartbeat:onReaderReady()
    if self.settings.heartbeat_enabled then
        self:sendHeartbeat("on")
    end
end

function Heartbeat:onCloseDocument()
    if self.settings.heartbeat_enabled then
        -- Send "on" without book info: doc_props may still be available during close
        self:sendHeartbeat("on", true)
    end
end

function Heartbeat:onSuspend()
    -- Stop the loop if it's running
    if self.settings.heartbeat_loop_enabled then
        UIManager:unschedule(self.heartbeatLoop)
    end

    if self.settings.heartbeat_enabled then
        -- Prevent delayed "on" heartbeat from overriding "off" state
        UIManager:unschedule(self.sendHeartbeat)
        self:sendHeartbeat("off")
    end
end

function Heartbeat:onResume()
    -- Restart the loop if it's enabled (waits full heartbeat_interval before first send)
    if self.settings.heartbeat_loop_enabled then
        self:heartbeatLoop(true)
    end

    if self.settings.heartbeat_enabled then
        -- Wait <delay> for WiFi, then send "on"
        -- scheduleIn(delay, function, arg1, arg2...)
        UIManager:scheduleIn(self.settings.resume_delay, self.sendHeartbeat, self, "on")
    end
end

function Heartbeat:saveSettings()
    -- Save the settings table to settings.reader.lua under the "heartbeat" key
    G_reader_settings:saveSetting("heartbeat", self.settings)
    -- Force immediate settings write to disk
    G_reader_settings:flush()
end

--- Add Heatbeat Configuration submenu to the Tools menu
function Heartbeat:addToMainMenu(menu_items)
    local sub_items = {}

    -- Settings submenu
    table.insert(sub_items, {
        text = "Update On Sleep/Wake",
        -- checked_func determines if the checkbox is shown as checked
        checked_func = function()
            return self.settings.heartbeat_enabled -- Read from in-memory settings
        end,
        hold_callback = function()
            UIManager:show(InfoMessage:new {
                text = "When enabled, KOReader tries to send a status update to Home Assistant on sleep/wake and document open/close.",
            })
        end,
        callback = function()
            -- Toggle the value in settings
            self.settings.heartbeat_enabled = not self.settings.heartbeat_enabled

            -- If turning OFF, also turn off the loop
            if not self.settings.heartbeat_enabled and self.settings.heartbeat_loop_enabled then
                self.settings.heartbeat_loop_enabled = false
                UIManager:unschedule(self.heartbeatLoop)
            end

            self:saveSettings()

            -- Immediate action: update HA status based on the new toggle state
            if self.settings.heartbeat_enabled then
                self:sendHeartbeat("on")
            else
                self:sendHeartbeat("off", true)
            end
        end,
    })

    table.insert(sub_items, {
        text = "Periodic Updates",
        separator = true,
        enabled_func = function()
            return self.settings.heartbeat_enabled -- Only enabled if heartbeat_sensor is true
        end,
        checked_func = function()
            return self.settings.heartbeat_loop_enabled
        end,
        hold_callback = function()
            UIManager:show(InfoMessage:new {
                text = "When enabled, KOReader will repeatedly send status updates to Home Assistant while the device is awake.",
            })
        end,
        callback = function()
            self.settings.heartbeat_loop_enabled = not self.settings.heartbeat_loop_enabled

            self:saveSettings()

            if self.settings.heartbeat_loop_enabled then
                self:heartbeatLoop(true)
            else
                UIManager:unschedule(self.heartbeatLoop)
            end
        end,
    })
    table.insert(sub_items, {
        text_func = function()
            return string.format(("Sensor Name: '%s'"), self.settings.heartbeat_name)
        end,
        hold_callback = function()
            UIManager:show(InfoMessage:new {
                text = _("The name used for the binary sensor entity in Home Assistant.\n\nFor example, a name of 'koreader_status' will create the entity 'binary_sensor.koreader_status'."),
            })
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            local input_dialog
            input_dialog = InputDialog:new {
                title = "Set sensor name",
                input = self.settings.heartbeat_name,
                input_type = "string",
                buttons = {
                    {
                        {
                            text = _("Cancel"),
                            id = "close",
                            callback = function()
                                UIManager:close(input_dialog)
                            end,
                        },
                        {
                            text = _("Set"),
                            is_enter_default = true,
                            callback = function()
                                local value = input_dialog:getInputText()
                                if value and value ~= "" then
                                    self.settings.heartbeat_name = value:gsub("%s+", "_")

                                    self:saveSettings()

                                    -- Send updated heartbeat
                                    if self.settings.heartbeat_enabled then
                                        self:sendHeartbeat("on")
                                    end

                                    touchmenu_instance:updateItems()
                                end
                                UIManager:close(input_dialog)
                            end,
                        },
                    },
                },
            }
            UIManager:show(input_dialog)
            input_dialog:onShowKeyboard()
        end,
    })
    table.insert(sub_items, {
        text_func = function()
            return string.format(("Update Interval (seconds): %d"), self.settings.heartbeat_interval)
        end,
        hold_callback = function()
            UIManager:show(InfoMessage:new {
                text = _("How often (in seconds) KOReader sends a status update to Home Assistant while the device is awake.\n\nOnly applies when Periodic Updates is enabled. Default is 300 seconds (5 minutes)."),
            })
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            local input_dialog
            input_dialog = InputDialog:new {
                title = "Set heartbeat interval (seconds)",
                input = tostring(self.settings.heartbeat_interval),
                input_type = "number",
                buttons = {
                    {
                        {
                            text = _("Cancel"),
                            id = "close",
                            callback = function()
                                UIManager:close(input_dialog)
                            end,
                        },
                        {
                            text = _("Set"),
                            is_enter_default = true,
                            callback = function()
                                local value = tonumber(input_dialog:getInputText())
                                if value and value > 0 then
                                    self.settings.heartbeat_interval = value

                                    self:saveSettings()

                                    -- If loop is running, restart it with new interval
                                    if self.settings.heartbeat_loop_enabled then
                                        UIManager:unschedule(self.heartbeatLoop)
                                        self:heartbeatLoop(true)
                                    end

                                    touchmenu_instance:updateItems()
                                end
                                UIManager:close(input_dialog)
                            end,
                        },
                    },
                },
            }
            UIManager:show(input_dialog)
            input_dialog:onShowKeyboard()
        end,
    })
    table.insert(sub_items, {
        text_func = function()
            return string.format(("Resume Delay (seconds): %d"), self.settings.resume_delay)
        end,
        hold_callback = function()
            UIManager:show(InfoMessage:new {
                text = _("How long (in seconds) to wait after waking before sending an 'on' status update.\n\nThis delay gives WiFi time to reconnect before the update is attempted. Default is 8 seconds."),
            })
        end,
        separator = true,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            local input_dialog
            input_dialog = InputDialog:new {
                title = "Set resume delay (seconds)",
                input = tostring(self.settings.resume_delay),
                input_type = "number",
                buttons = {
                    {
                        {
                            text = _("Cancel"),
                            id = "close",
                            callback = function()
                                UIManager:close(input_dialog)
                            end,
                        },
                        {
                            text = _("Set"),
                            is_enter_default = true,
                            callback = function()
                                local value = tonumber(input_dialog:getInputText())
                                if value and value >= 0 then
                                    self.settings.resume_delay = value

                                    self:saveSettings()

                                    touchmenu_instance:updateItems()
                                end
                                UIManager:close(input_dialog)
                            end,
                        },
                    },
                },
            }
            UIManager:show(input_dialog)
            input_dialog:onShowKeyboard()
        end,
    })
    table.insert(sub_items, {
        text = "Test Connection",
        hold_callback = function()
            UIManager:show(InfoMessage:new {
                text = _("Creates or updates the binary sensor in Home Assistant with minimal attributes.\n\nDisplays a success or failure message so you can verify your host, port, token, and sensor name are correct."),
            })
        end,
        keep_menu_open = true,
        callback = function()
            local url = self:buildUrl()

            local has_error, response = API:performRequest(url, ha_config.token, {
                state = "on",
                attributes = {
                    friendly_name = "KOReader Status",
                    last_seen = os.date("!%Y-%m-%dT%H:%M:%SZ")
                }
            })
            if has_error then
                UIManager:show(InfoMessage:new {
                    text = string.format("Failure:\n%s", response),
                })
            else
                UIManager:show(InfoMessage:new {
                    text = "Success!",
                })
            end
        end,
    })

    menu_items.heartbeat = {
        text = "\u{ECF5} Heartbeat Configuration", -- heart-pulse icon font glyph
        sorting_hint = "tools",
        sub_item_table = sub_items,
    }
end

return Heartbeat
