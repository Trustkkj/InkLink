# InkLink

**Your phone. Your tablet. Your freedom.**

> InkLink was born from the simple idea that creativity and fun shouldn't depend on how much money you have.

[Português](README.pt-BR.md)

InkLink turns an Android touchscreen into an absolute-position aiming device over USB for the unofficial browser rhythm game wosu!. It began when a student wanted to play osu! again without buying a graphics tablet. Developed with AI assistance and hands-on testing.

## Experimental v0.3.1

- Automatic touchscreen detection via ADB
- Adjustable active area and orientation; persistent settings
- Local dashboard and on-demand game launcher
- Manual aiming only; use Z/X to hit notes

## Requirements and installation

Tested by the project creator on a Chromebook with Debian Linux (Crostini) and Redmi Note 12 4G. Other devices are untested. Requires Python 3, Git, ADB, Node.js 22+ and npm, and internet access for initial dependency downloads. Review `install.sh` before running it: it uses sudo for ADB and package installation, clones wosu! and installs npm dependencies. Run as your normal user, not root. Install Node.js 22+ from a trusted source first if needed (distribution packages may be older).

1. Enable Android developer options and USB debugging. Connect a data-capable USB cable; on ChromeOS share the device with Linux and authorize the debugging prompt.
2. Download and extract this repository, open a terminal in its folder and run:

```bash
bash install.sh
```

3. Open http://localhost:8765 if the dashboard doesn't open automatically. Configure your area, then select **Iniciar osu!**. The game opens at http://localhost:5173. Use the keyboard to hit notes.
4. Stop via the dashboard or Ctrl+C. Disable USB debugging when finished.

## Limitations

No hover, true pen pressure, system-wide cursor control, native osu! integration, Windows support or drawing application support yet. The dashboard is currently in Portuguese. Motion samples per second are not an end-to-end latency measurement. Use for offline/private play; competitive service compatibility is unverified. The installer pins wosu! to `12a2bac0389c0b69287c949abb6ca8e89133ba0a`, the base tested with v0.3. The v0.3.1 release candidate still requires hardware validation. The game may need network access to download beatmaps.

## Credits and licensing

[wosu!](https://github.com/Mostlime12195/wosu) by Mostlime12195 is a separate project; its code is MIT licensed, while some media have separate terms. This repository does not bundle its media or source tree; the installer fetches it from upstream and applies local integration changes. Preserve upstream license notices. osu! is a trademark of ppy Pty Ltd. InkLink is unofficial and not affiliated with either project.

InkLink is licensed under MIT; see LICENSE. See THIRD_PARTY.md.

## Feedback

Report your Android model, Linux distribution, Chrome version, and symptoms. Remove device serials and personal information from logs before sharing.
