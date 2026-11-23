# Zapret Auto

An add-on for [zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube) that picks the best zapret strategy by itself and switches it automatically when your ISP starts blocking it.

Set it up once and forget about it. It runs in the background, and an icon in the system tray shows whether everything is fine.

Built on [zapret](https://github.com/bol-van/zapret) by bol-van and strategies by [Flowseal](https://github.com/Flowseal/zapret-discord-youtube). Zapret Auto only picks and switches them.

### [⬇️ Download Zapret Auto](https://github.com/Nikita-C1AY/zapret-auto/releases/latest/download/zapret-auto.zip)

[Русская версия](README.md)

---

## Quick start

1. **Put the zapret folder in the root of any drive**, for example `C:\zapret`. Not on the Desktop, not in Downloads or Documents.
2. **Put the `zapret-auto` folder inside the zapret folder**, next to `service.bat`.
3. **Double-click `!START zapret-auto.bat`** and allow administrator rights.

The first run picks the best strategy. It takes about 10 minutes, and your internet will blink during that time. Then the window shows a countdown and hides into the tray. After that, everything starts automatically when you log in to Windows.

Before the first run, remove the zapret service: open `service.bat` and choose **Remove Services**. Do not delete `service.bat` itself — Zapret Auto starts the strategies itself, and the service gets in its way.

## Requirements

- Windows 10 (version 1803 or newer) or Windows 11.
- zapret-discord-youtube (tested with version 1.10.4).
- Administrator rights.
- VPN or WARP turned off while it runs: they interfere with the checks. The script warns you if it finds one.

## How it works

- **First test.** The script starts every `general*.bat` strategy one by one and checks YouTube, Discord and other sites. Each strategy gets a score.
- **Watching.** YouTube and Discord are checked every minute, the YouTube video server every three minutes, and every five minutes the script makes sure YouTube loads completely.
- **Switching.** If a check fails twice in a row, the script starts the next best strategy. This usually takes 5 to 15 seconds.
- **Penalty and quarantine.** A failed strategy loses half its score and is skipped for 30 minutes while something else works.
- **Self-learning.** The longer a strategy survives, the higher its score. Over time the script learns what holds up best with your ISP.
- **No internet:** the script simply waits, does not touch the ratings and does not count offline time.
- **Changed zapret settings** (lists, ipset, strategies): the script notices it and runs a new test.
- **New versions.** Once a day the script looks up the latest version number of Zapret Auto and of Flowseal's zapret and tells you when an update is out.

## What makes it different

- **Works quietly.** No windows and no extra notifications — just an icon in the tray. Starts with Windows by itself.
- **Just a script, not a program.** Installs and downloads nothing — runs on top of the Flowseal zapret you already have.
- **Almost no resources.** One short check per minute, the rest of the time it sleeps.
- **Fast switching.** On failure it takes the next strategy from the rating right away, no full re-test.
- **Learns your ISP.** Strategies that survive longer on your connection move up.
- **Tells you about updates.** No need to watch GitHub — you get a notification when a new Zapret Auto or zapret version is out.
- **Flexible.** Your own sites and services via packs, a favourite strategy, check frequency, quarantine and more — all in one file, `data\settings.txt`. No code editing, and everything is kept on updates.
- **Open, checkable code.** A few PowerShell files you can read in full, plus SHA-256 hashes in every release.

## The tray icon

Zapret Auto lives in the **system tray** — the area on the right of the taskbar, next to the clock and language.

The icon looks like a **toggle switch with a lightning bolt**: an oval with a white knob and a bolt inside. Knob right = on, knob left = off, the colour shows the status.

| Icon | Meaning |
| --- | --- |
| Green, knob right | Everything works. Hover to see the strategy and how many minutes it has been running |
| Yellow, knob right | Testing or switching. If it says "not responding", the script is stuck: open its window and press Esc |
| Red, knob left | No strategy works right now, the script keeps trying |
| Grey, knob left | No internet, or the script is stopped |

- **Double-click the icon** to show or hide the script window.
- **Right-click** to show / hide the window, open the log or stop the script. When a new version is out, an item that opens its page appears there too.

By default there are two kinds of notifications: when no strategy works, and when a new version of Zapret Auto or zapret is out — only once per version. Hovering over the icon also shows "· 9.x.x available".

**The icon is hidden under the "^" arrow.** Windows puts new tray icons there by itself, a program cannot prevent it. To keep it always visible in the tray:

- **Easiest:** click "^" and drag the toggle icon into the tray, next to the clock.
- **Windows 11:** Settings → Personalization → Taskbar → "Other system tray icons" → turn on **Windows PowerShell** (Zapret Auto's icon is listed under this name).
- **Windows 10:** right-click the taskbar → "Taskbar settings" → "Select which icons appear on the taskbar" → turn on **Windows PowerShell**.

## Security

- **Download only from this repository.** Copies in Telegram, on forums or in other people's bundles are not ours.
- **Check the hash before the first run.** In PowerShell: `Get-FileHash .\zapret-auto.zip` and compare it with the hash on the release page. The script shows its own hash too, but a fake could show anything, so check it yourself.
- **The zapret folder gets locked:** only administrators can change files in it. This protects against the script being replaced, since it runs with administrator rights. To edit your files, save them to the Desktop and drag them back into the folder — Windows will ask for confirmation.
- **Autostart only works from the root of a drive.** From a user folder the script still works, but without autostart.
- The script **never downloads or updates anything by itself** and sends your data nowhere. It checks whether sites open, and once a day asks GitHub only for the latest **version number** of Zapret Auto and of Flowseal's zapret. You install updates yourself. To turn the check off: `CheckUpdates = false` in `data\settings.txt`.
- The tray button opens only two pages: the Zapret Auto releases and the zapret-discord-youtube releases.
- Settings are read only by known names, and every value is checked.
- To remove the folder lock: `icacls "C:\path\to\zapret" /reset /T /C /Q`

## Files

| File | Purpose |
| --- | --- |
| `!START zapret-auto.bat` | Start |
| `zapret-auto.ps1` | Main script: setup and settings check |
| `zapret-auto-engine.ps1` | Checks and switching |
| `zapret-auto-tray.ps1` | Tray icon and update check |
| `zapret-auto-lang-ru.txt` | Russian texts |
| `packs\` | Service packs |
| `docs\` | README and licenses |
| `data\settings.txt` | **Your settings** — kept on updates |
| `data\zapret-auto-targets.txt` | Your sites to check |
| `data\zapret-auto-domains.txt` | Your domains to unblock |
| `data\zapret-auto.log` | Log |
| `data\zapret-auto-stats.json` | Strategy ratings. Delete it to start learning from scratch |
| `data\versions.txt`, `data\update-seen.txt` | Service files for the update check |

## Updating

1. Right-click the tray icon → "Stop".
2. Unpack the new archive **over** the `zapret-auto` folder, replacing the files. Windows will ask for administrator confirmation — that is the folder lock, it is expected.
3. Run `!START zapret-auto.bat`.

The `data` folder with your settings and ratings stays as it is; new settings are added to `settings.txt` automatically.

**If you edit the script files by hand**, save them as **UTF-8 with BOM**. Without it PowerShell misreads the Russian text, and the script or the tray icon will not start.

Starting with 9.5.3, the script tells you about the next updates itself.

## For advanced users

### Settings

All settings are in `data\settings.txt`, each with a comment. Delete a line to get the default; an invalid line is skipped and written to the log. The most useful ones:

- `Prefer`: your favourite strategy, for example `general (EXP).bat`. It is started first.
- `Fails`: how many failures in a row trigger a switch (default 2).
- `QuarantineMin`: how many minutes a failed strategy is skipped (30).
- `FailPenalty`: score multiplier on failure (0.5 = half).
- `ShowConsole`: `true` to always see the window.
- `NotifySwitch`: `true` for a notification on every switch.
- `MemLimitMB`: memory limit before an automatic restart (200).
- `CheckUpdates`: `false` to stop checking for new versions (default `true`).
- `Language`: `auto`, `ru` or `en`.

### Service packs

The `packs` folder lets you add your own service without touching the code. A pack is a txt file with domains, addresses to check and, optionally, IPs. The folder it is in decides what happens:

| Folder | What happens |
| --- | --- |
| `critical` | Checked all the time, like YouTube and Discord. If it fails, the strategy is switched. Three packs at most |
| `normal` | Checked during the test and affects the choice of strategy |
| `off` | Only adds domains, no checks |
| `disabled` | Not used |

To make your own pack, copy `packs\_template.txt` into the folder you need, rename it and add your domains. Ready examples for GitHub, Steam and Instagram are in `disabled`.

Only public IP addresses, no wider than /16, are accepted. Local networks (`192.168.x.x`, `10.x.x.x` and others) are always refused. For now, IPs are only saved to `data\packs-ipset.txt` and are not connected to zapret.

## Known limitations

- **Discord images** do not load on any strategy with some ISPs.
- **Instagram** does not pass on any strategy yet, so its pack is disabled.
- **The YouTube video server** is not always detected automatically. Then `redirector.googlevideo.com` is checked instead. Because of this, the YouTube page may open while videos or Shorts keep loading — this will be fixed in the next version.
- **Steam Community, profiles and inventory** may not work even though games launch. Moving the Steam pack from `packs\disabled` to `normal` may help.
- The script does not bypass IP-based blocking and does not help with services that refuse to work in Russia themselves.

## Reporting a problem

Open an Issue and attach **the beginning of** `data\zapret-auto.log`: it contains the versions of the script, zapret and Windows, the ipset mode and VPN status. Also add the part of the log where the problem happened. Remove anything you consider private.

## Credits

- [bol-van/zapret](https://github.com/bol-van/zapret) — for the DPI bypass tool itself.
- [Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube) — for the ready strategies Zapret Auto runs on.
- Friends who tested the first versions, and everyone who reports issues.

## Disclaimer

Zapret Auto is provided "as is", without any warranty. The author is not liable for any damage resulting from its use. You are responsible for making sure your use complies with the laws of your country and the terms of the services you use. The project was made to study network technologies.

Zapret Auto is an independent project. It is not affiliated with or endorsed by the authors of zapret or zapret-discord-youtube. It only runs their strategies and does not change their files, except for adding your domains to `list-general-user.txt`.

## License

[MIT](LICENSE). An unofficial Russian translation is in [LICENSE.ru.md](LICENSE.ru.md). Only the English text is legally binding.
