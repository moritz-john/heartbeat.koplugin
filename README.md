# heartbeat.koplugin

<p align="center">
<img src="assets/heartbeat_sensor.png" />
  <i></i>
</p>

<p align="center">
<img src="assets/heartbeat_attributes.png"  alt="homeassistant.koplugin screenshots" />
  <i>KOReader status sensor in Home Assistant & its attributes</i>
</p>

## Features

The plugin can send KOReader's current state ("a heartbeat") to a Home Assistant binary sensor. This sensor can be used to trigger automations based on your reading activity.

The sensor includes the following attributes: `device_model`, `book_title`, `book_author`, `battery_level`, `is_charging` and `last_seen`.

## Installation

### Step 1: Download the Plugin
[Download the latest release](https://github.com/moritz-john/heartbeat.koplugin/releases) and unpack `heartbeat.koplugin.zip`:  

### Step 2: Edit `heartbeat_config.lua`

Add your Home Assistant connection details.  
Change `host`, `port`, `https` and `token` according to your personal setup:

```lua
return {
    host = "192.168.1.10",
    port = 8123,
    https = false,
    token =
    "PasteYourHomeAssistantLong-LivedAccessTokenHere",
}
```

> [!tip]
> **How to create a Long-Lived Access Token:**  
> [**Home Assistant**](https://my.home-assistant.io/redirect/profile): *Profile → Security (scroll down) → Long-lived access tokens → Create token*  
> *Copy the token now – you won’t be able to view it again.*

### Step 3: Copy Files to Your Device

After editing `heartbeat_config.lua`, copy the files to your KOReader device:

**Copy the entire `heartbeat.koplugin` folder into `koreader/plugins/`**  

### Step 4: Restart KOReader

The plugin appears under **Tools → Page 2 → Heartbeat Configuration**

## Settings & Caveats

Long press a menu entry in **Heartbeat Configuration** to get an explanation of what each setting does.

<br>

> [!NOTE] 
> `heartbeat.koplugin` assumes that KOReader has Wi-Fi connectivity. State updates are sent on start/resume/suspend & document open/close and will fail silently if Home Assistant or Wi-Fi is unavailable. The resume state is sent with an 8-second delay (default) but is adjustable. Not every state update action works on every device.

## Screenshots

<p align="center">
<img src="assets/tools_menu.png" style="width:70%; height:auto;" />
</p>

<p align="center">
<img src="assets/heartbeat_settings.png" style="width:70%; height:auto;" />
</p>

## Requirements
- KOReader (tested with: 2025.10 "Ghost" on a Kindle Basic 2024)  
- Home Assistant & a Long-Lived Access Token