# Vortex Ubuntu Ascension Plymouth Theme

<p align="center">
  <img src="previews/vortex-ubuntu-ascension.gif" alt="Vortex Ubuntu Ascension animated preview" style="border: 1px solid #666; border-radius: 8px; max-width: 100%;">
</p>

An expanded evolution of the original `vortex-ubuntu-plymouth-theme`, adding
an extended animated logo formation, a Vortex sequence, and Plymouth UI support
for password and question prompts, status messages, and boot progress.

## Project layout

- `frames/` — 307 animation frames at 960 × 540.
- `assets/` — password bullet and Ubuntu-orange progress bar images.
- `previews/vortex-ubuntu-ascension.gif` — animated preview of the rendered frames.
- `vortex-ubuntu-ascension.script` — animation and Plymouth callbacks.
- `vortex-ubuntu-ascension.plymouth` — theme definition.
- `vortex-ubuntu-ascension.grub` — black GRUB background.
- `install.sh` / `uninstall.sh` — install or remove the theme.
- `test-plymouth.sh` — preview the theme in a selected Plymouth mode.

## Install (Ubuntu/Debian)

Run:

```sh
sudo ./install.sh
```

The installer saves the current `update-alternatives` selection mode
(`auto` or `manual`) and, when available, the selected Plymouth theme. It then
copies and activates Vortex and rebuilds the initramfs. If installation fails,
it attempts to restore the previous theme files, alternative registration,
selection mode, and initramfs; it reports any rollback step that fails and
retains recovery state when rollback is incomplete.
For safety, a reinstall stops before changing the system if the saved state is
incomplete or invalid; it does not infer a missing mode or replace existing
saved settings.

On uninstall, the saved mode is restored along with the prior theme selection.
If the previous theme is no longer installed and registered, a valid remaining
theme is selected automatically. The uninstaller also accepts state from older
installer versions; when that state has no saved mode, it uses the earlier
manual-selection behavior for a saved theme and automatic selection otherwise.

## Test different modes

```sh
./test-plymouth.sh                 # boot mode
./test-plymouth.sh shutdown        # reboot, suspend, resume, hibernate, or thaw
./test-plymouth.sh boot prompt     # also test password and question dialogs
```

The `prompt` test deliberately waits for input twice: enter any test password
and press Enter, then type a response to the question and press Enter. These
are demo prompts; the password is not checked or used to unlock anything. The
screen remains open while either prompt is waiting.

If the splash prevents you from entering a response or stopping the test, switch
to a text console with `Ctrl+Alt+F3` (or `Ctrl+Alt+F4`), log in, and quit Plymouth:

```sh
sudo plymouth quit
```

Then return to the desktop with `Ctrl+Alt+F1` or `Ctrl+Alt+F2` (whichever is
displaying it). If you opened a login session on the text console, type `exit`
before switching back to close that session.

## Uninstall

```sh
sudo ./uninstall.sh
```

## Features

- Plays all 307 frames at 1x the source rate (about 12.8 seconds), then holds
  on the formed logo instead of looping back to black.
- Starts non-boot modes at the already-formed logo so it appears immediately
  during shutdown or reboot.
- Displays a solid Ubuntu-orange (`#E95420`) progress bar up to 100 pixels wide
  during boot.
- Supports LUKS password prompts, yes/no questions, and status messages.
- During a real boot, password prompts appear only when a service needs input,
  for example to unlock an encrypted disk. The demo question and password
  prompts run only when explicitly requested with `prompt`; they are not shown
  during ordinary boot or shutdown.

The Plymouth script loads frames on demand rather than keeping all 307 decoded
images in a permanent array. The source frames remain 960 × 540 and playback
uses the full sequence, so this reduces the script's retained image references
without reducing resolution or frame count. Peak memory can still vary with
Plymouth's image handling while a frame changes. `PLAYBACK_FPS` in
`vortex-ubuntu-ascension.script` controls playback speed.

## Credits

The rings and logo are based on the "vortex-ubuntu-plymouth-theme" by
Emanuele Scarsella (GPL-2.0).
