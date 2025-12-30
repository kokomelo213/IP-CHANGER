================================================================================
IP MANAGER ELITE — made by ketazz
================================================================================

A Windows CMD + PowerShell tool to manage Proton VPN WireGuard profiles faster
from a single terminal menu:
- Connect (Random / Pick)
- Disconnect (Safety OFF)
- Status (Public IP + active tunnel)
- Emergency repair
- Config expiry check (best-effort)
- “Best VPN” options (bench ping and pick the lowest-latency config)

--------------------------------------------------------------------------------
DISCLAIMER / ACCEPTABLE USE (READ THIS)
--------------------------------------------------------------------------------

This project is provided “AS IS”, without warranty of any kind. By using this
software, you acknowledge and agree to the following:

1) USE AT YOUR OWN RISK
   You are solely responsible for how you use this tool and for any outcomes,
   including (but not limited to) service bans, account restrictions, network
   issues, data loss, or any other damages.

2) LEGAL AND TERMS OF SERVICE COMPLIANCE
   You must use this tool only in ways that are legal in your jurisdiction and
   compliant with the Terms of Service of any service you use (including VPN
   providers, games, websites, etc.).

3) NO MISUSE / NO ABUSE
   Do NOT use this tool to:
   - bypass bans or restrictions on online services
   - violate Terms of Service
   - harass, defraud, scam, or harm others
   - perform illegal activities of any kind

4) NO LIABILITY
   The author(s) and contributors of this project are not responsible for any
   misuse by third parties, nor for any damages, losses, claims, or legal issues
   arising from the use or misuse of this tool.

If you do not agree with these terms, do not use this project.

--------------------------------------------------------------------------------
IMPORTANT SECURITY WARNING (DO NOT UPLOAD .CONF FILES)
--------------------------------------------------------------------------------

WireGuard .conf files contain private credentials/keys (similar to access tokens).
Anyone who obtains your .conf files may be able to connect using yourOUR VPN
profiles while they remain valid.

✅ Safe to share:
- CHANGE_IP.cmd
- IP_MANAGER.ps1
- readme.txt
- the EMPTY folder wg-configs\

❌ DO NOT share / DO NOT upload to GitHub:
- any file inside wg-configs\ that ends with .conf

RECOMMENDED: use a .gitignore to prevent accidental leaks:
  wg-configs/*.conf
  .ipmanager_state.json
  ipmanager_*.log
  ipmanager_*.txt

--------------------------------------------------------------------------------
REQUIREMENTS
--------------------------------------------------------------------------------

You need:

1) Proton VPN account
   - You must be able to access the Proton VPN Dashboard and generate WireGuard
     configuration files.

2) Proton VPN application (recommended)
   - Install Proton VPN from the official Proton website.

3) WireGuard for Windows (mandatory)
   - This tool uses WireGuard’s Windows tunnel service to connect/disconnect.
   - Install the official “WireGuard for Windows”.

4) Windows Administrator permissions (mandatory for connect/disconnect)
   - Connecting/disconnecting WireGuard tunnel services requires Admin rights.
   - The menu includes an option to open an elevated (Admin) window.

--------------------------------------------------------------------------------
FOLDER STRUCTURE
--------------------------------------------------------------------------------

Your folder must look like this:

ipchanger\
  CHANGE_IP.cmd
  IP_MANAGER.ps1
  readme.txt
  wg-configs\
    (put your Proton WireGuard .conf files here)

Example:

ipchanger\
  CHANGE_IP.cmd
  IP_MANAGER.ps1
  readme.txt
  wg-configs\
    nl_free_01.conf
    it_free_02.conf
    us_free_03.conf

--------------------------------------------------------------------------------
SETUP (STEP BY STEP)
--------------------------------------------------------------------------------

Step 1) Install Proton VPN
- Download and install the official Proton VPN app.
- Sign in with your Proton account.

Step 2) Install WireGuard for Windows
- Download and install “WireGuard for Windows” (official app).

Step 3) Download WireGuard configs from Proton Dashboard
- Open Proton’s Dashboard in your browser.
- Go to the “Downloads” section.
- Scroll down until you find the WireGuard configuration area.
- Generate/download as many WireGuard configs as you want (.conf files).
  (More configs = more servers to rotate between.)

Step 4) Put configs into wg-configs\
- Move all downloaded .conf files into:

  ipchanger\wg-configs\

Step 5) Run the tool
- Double-click CHANGE_IP.cmd
- Press “A” in the menu to open an Administrator window (recommended)
  Then use the Admin window for connect/disconnect actions.

--------------------------------------------------------------------------------
USAGE GUIDE (MENU OPTIONS)
--------------------------------------------------------------------------------

[1] VPN ON (RANDOM / ROTATE)
- Disconnects any active tunnel (if possible), then selects a random .conf and
  connects using WireGuard tunnel service.
- NOTE: Sometimes Proton can give the same public exit IP even after switching
  servers. That is normal for VPN exit pools.

[2] VPN OFF (DISCONNECT ALL)
- Removes all WireGuard tunnel services created by this tool (and any leftover
  tunnels if present), then returns to your normal connection.

[3] PICK CONFIG (.conf)
- Shows a list of all .conf files in wg-configs\ and lets you choose one.

[4] STATUS
- Prints current public IP and active WireGuard tunnel (if any).

[5] ISP / CITY INFO
- Displays ISP + approximate city/country (uses a public IP geolocation API).

[6] LOCAL NETWORK RENEW
- Flushes DNS and renews local IP (Admin required).

[7] EMERGENCY REPAIR
- Force-removes WireGuard tunnel services + restarts WireGuardManager if needed.
- Use this if Windows or WireGuard gets “stuck” thinking you are connected.

[8] CONFIG EXPIRY (days left)
- Best-effort: If the .conf contains an expiry comment, it will be parsed.
- If no expiry info exists, the tool shows an estimated expiry based on file
  timestamps (creation/last write). This is only a heuristic.

[9] BEST VPN AUTO (LIVE TEST -> best)
- Runs a live benchmark of your configs and automatically picks the lowest
  measured latency profile.
- Testing method:
  - ICMP ping to 1.1.1.1 if allowed, otherwise TCP connect timing to 1.1.1.1:443

[10] BEST VPN LIST (LIVE TEST -> pick)
- Benchmarks configs and prints a sorted list (lowest ping first). You pick one.

[11] BENCH PING (LIVE TEST TABLE)
- Runs the benchmark and prints the table only (does not connect permanently).

--------------------------------------------------------------------------------
NOTES ABOUT PING / GAMING / DISCORD
--------------------------------------------------------------------------------

VPN routing can increase latency. Even the “best” config may still be worse than
your normal ISP route. To reduce ping:
- Prefer servers geographically closer to you
- Use BEST VPN options to pick the lowest latency profile
- Keep in mind: some networks block ICMP ping, so the tool may use TCP fallback

If you need the lowest possible latency for competitive gaming, a VPN may not be
the right choice for that session. Use VPN only when you actually need it.

--------------------------------------------------------------------------------
TROUBLESHOOTING
--------------------------------------------------------------------------------

1) “Run as Administrator”
- You must run connect/disconnect actions as Admin.
- Press “A” in the menu to open an elevated window.

2) Tool says disconnected but you are connected
- Use [7] EMERGENCY REPAIR
- Then try [2] VPN OFF

3) Config stopped working / expired
- Proton WireGuard configs may rotate/expire depending on account/settings.
- Regenerate new configs from the Proton dashboard and replace the old files.

4) I see extra temporary files
- The tool uses temporary safe copies to avoid issues with special characters.
- It cleans them up automatically on EXIT. If leftovers exist, run EXIT or
  run [2] VPN OFF then exit again.

--------------------------------------------------------------------------------
CREDITS
--------------------------------------------------------------------------------

IP MANAGER ELITE — Elite CMD Tool
Made by ketazz
================================================================================
