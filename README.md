# Zapret Auto

An add-on for [zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube) that picks the best zapret strategy by itself and switches it automatically when your ISP starts blocking it.

Set it up once and forget about it. It runs in the background, and an icon near the clock shows whether everything is fine.

[Русская версия](README.ru.md)

---

## Quick start

1. **Put the zapret folder in the root of any drive**, for example `C:\zapret`. Not on the Desktop, not in Downloads or Documents.
2. **Put the `zapret-auto` folder inside the zapret folder**, next to `service.bat`.
3. **Double-click `START zapret-auto.bat`** and allow administrator rights.

The first run picks the best strategy. It takes about 10 minutes, and your internet will blink during that time. Then the window hides into the icon near the clock. After that, everything starts automatically when you log in to Windows.

Before the first run, **remove the zapret service** in zapret's `service.bat` (Remove Services): Zapret Auto starts the strategies itself.

## Requirements

- Windows 10 (version 1803 or newer) or Windows 11.
- zapret-discord-youtube (tested with version 1.10.4).
- Administrator rights.
- VPN or WARP turned off while it runs: they interfere with the checks. The script warns you if it finds one.

## How it works

- **First test.** The script starts every `general*.bat` strategy one by one and checks YouTube, Discord and other sites. Each strategy gets a score.
- **Watching.** YouTube and Discord are checked every minute, the YouTube video server every three minutes, and every five minutes the script makes sure YouTube loads completely.
- **Switching.** If a check fails twice in a row, the script starts the next best strategy. This usually takes 5 to 15 seconds.
- **Self-learning.** The longer a strategy survives, the higher its score. Over time the script learns which strategies hold up best with your ISP.
- **No internet:** the script simply waits and does not touch the ratings.
- **Changed zapret settings** (lists, ipset, strategies): the script notices it and runs a new test.

## The tray icon

| Icon | Meaning |
| --- | --- |
| Green, knob right | Everything works. Hover to see the strategy and how many minutes it has been running |
| Yellow, knob right | Testing or switching |
| Red, knob left | No strategy works right now, the script keeps trying |
| Grey, knob left | No internet, or the script is stopped |

Right-click the icon to show the window, open the log or stop the script. If Windows hid the icon, click the "^" arrow next to the clock.

By default there is only one notification: when no strategy works.

## Security

- **Download only from this repository.** Copies in Telegram, on forums or in other people's bundles are not ours.
- **Check the hash before the first run.** In PowerShell: `Get-FileHash .\zapret-auto.ps1` and compare it with the hash on the release page. The script shows its own hash too, but a fake could show anything, so check it yourself.
- **The zapret folder gets locked:** only administrators can change files in it. This protects against malware replacing the script, since it runs with administrator rights. To edit your own files, open Notepad as administrator.
- **Autostart only works from the root of a drive.** From a user folder the script still works, but without autostart.
- The script **never downloads or updates anything by itself** and sends your data nowhere. It only checks whether sites open.
- To remove the folder lock: `icacls "C:\path\to\zapret" /reset /T /C /Q`

## Files

| File | Purpose |
| --- | --- |
| `START zapret-auto.bat` | Start |
| `zapret-auto.ps1` | Main script: settings and setup |
| `zapret-auto-engine.ps1` | Checks and switching |
| `zapret-auto-tray.ps1` | Tray icon |
| `zapret-auto-lang-ru.txt` | Russian texts |
| `zapret-auto-targets.txt` | Your sites to check |
| `zapret-auto-domains.txt` | Your domains to unblock |
| `packs\` | Service packs |
| `zapret-auto.log` | Log |
| `zapret-auto-stats.json` | Strategy ratings. Delete it to start learning from scratch |

## For advanced users

### Settings

Settings are at the top of `zapret-auto.ps1` and `zapret-auto-tray.ps1`. The most useful ones:

- `$Prefer`: your favourite strategy, for example `"general (EXP).bat"`. It is started first.
- `$Fails`: how many failures in a row trigger a switch (default 2).
- `$Language`: `"auto"`, `"ru"` or `"en"`.
- `$ShowConsole` (tray): `$true` to always see the window.
- `$NotifySwitch` (tray): `$true` for a notification on every switch.

### Service packs

The `packs` folder lets you add your own service without touching the code. A pack is a txt file with domains, addresses to check and, optionally, IPs. The folder it is in decides what happens:

| Folder | What happens |
| --- | --- |
| `critical` | Checked all the time, like YouTube and Discord. If it fails, the strategy is switched. Three packs at most |
| `normal` | Checked during the test and affects the choice of strategy |
| `off` | Only adds domains, no checks |
| `disabled` | Not used |

To make your own pack, copy `packs\_template.txt` into the folder you need, rename it and add your domains. Ready examples for GitHub, Steam and Instagram are in `disabled`.

Only public IP addresses, no wider than /16, are accepted. Local networks (`192.168.x.x`, `10.x.x.x` and others) are always refused, so your home network, VPN and development tools keep working. For now, IPs are only saved to `packs-ipset.txt` and are not connected to zapret.

## Known limitations

- **Discord images** do not load on any strategy with some ISPs. With others they work.
- **Instagram** does not pass on any strategy yet, so its pack is disabled.
- **The YouTube video server** is not always detected automatically. Then `redirector.googlevideo.com` is checked instead.
- The script does not bypass IP-based blocking and does not help with services that refuse to work in Russia themselves (for example, Spotify sign-in).

## Reporting a problem

Open an Issue and attach **the beginning of** `zapret-auto.log`: it contains the versions of the script, zapret and Windows, the ipset mode and VPN status. Also add the part of the log where the problem happened. Remove anything you consider private.

## Disclaimer

Zapret Auto is provided "as is", without any warranty. The author is not liable for any damage resulting from its use. You are responsible for making sure your use complies with the laws of your country and the terms of the services you use.

Zapret Auto is an independent project. It is not affiliated with or endorsed by the authors of zapret or zapret-discord-youtube. It only runs their strategies and does not change their files, except for adding your domains to `list-general-user.txt`.

## License

[MIT](LICENSE). An unofficial Russian translation is in [LICENSE.ru.md](LICENSE.ru.md). Only the English text is legally binding.
