return {
    -- Home Assistant connection settings
    host = "192.168.1.10", -- Change to your Home Assistant IP Address or Hostname
    port = 8123,           -- Home Assistant Port (usually 443 for HTTPS)
    https = false,         -- Set true only if your Home Assistant is served over HTTPS
    token =                -- Change to your own Long-Lived Access Token
    "PasteYourHomeAssistantLong-LivedAccessTokenHere",
}
