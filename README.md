# Hangover

**Your Downloads had a big night. Hangover cleans up in the morning.**

Hangover is a small, free menu-bar app for Mac that tidies your Desktop and Downloads folders for you.

- 🧹 **Moves files into folders by rules you can edit.** Screenshots go to Pictures, installers to `Downloads/Installers`, PDFs to `Downloads/PDFs`, and so on.
- 🌙 **Waits a day.** Anything you downloaded or captured *today* stays where it is, so you can still find it. Hangover tidies it up the next morning.
- 🛡️ **Never deletes anything, and never overwrites anything.** If a file with the same name is already there, the new one becomes `name-2`.
- 🔑 **Leaves secrets alone.** Files that look like keys or passwords are never moved. Hangover tells you about them so you can put them somewhere safe.

Works on macOS 13 (Ventura) or later, on both Apple silicon and Intel Macs.

## Install (about 2 minutes)

1. **Download** `Hangover.zip` from the [latest release](https://github.com/kasidisc/hangover/releases/latest), then double-click it to unzip.
2. **Drag Hangover into your Applications folder.**
3. **Open Hangover.** macOS will say it can't check the app ("unidentified developer"). That's expected, because Hangover isn't sold through Apple. Click **Done**, then:
   open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the Hangover message. Confirm with your password or Touch ID.
4. **Allow access.** Hangover opens with a welcome screen and a preview of what it would move. When macOS asks whether Hangover may access your **Desktop** and **Downloads** folders, click **Allow**. Then click **Start sorting automatically**.

That's it. A little pill 💊 in the menu bar shows Hangover is running. It sorts every hour, when you log in, and when your Mac wakes up.

> On macOS 11 or 12? Open **System Settings → General → Software Update** and update first. Every Mac that runs macOS 11 can update for free.

## How it works

- Each watched folder has a list of rules. Rules are checked **from top to bottom**, and the **first one that matches wins**.
- A rule can match by **extension** (`png, jpg`), by **name starts with** (`SCR-`), and by **name contains** (`Screenshot`). Every box you fill in must match, and an empty box is ignored.
- **The wait:** in Downloads a file moves once the day it *arrived* is over. On the Desktop, once the day it was *created* is over.
- **Never moved:** hidden files, partly downloaded files (`.download`, `.crdownload`, `.part`), folders (except `.app` apps when a rule allows it), and files that look like secrets.
- Open **Hangover** from the menu bar to edit rules, add folders, preview, sort now, or read the log. Import and export your rules as a JSON file to move them to another Mac.

If something goes wrong, the menu-bar pill turns into a ⚠️ warning sign and the app lists the problem under **Needs attention**.

## Updating

Download the new `Hangover.zip`, replace the app in Applications, and do the **Open Anyway** step once more. Your rules and folder permissions are kept.

## Uninstall

Turn **Auto-sort** off, quit Hangover from its menu, and drag it to the Trash. Your rules live in `~/Library/Application Support/Hangover`, which you can delete too. Files Hangover already moved stay where they are.

## Build from source

Only Apple's Command Line Tools are needed (`xcode-select --install`):

```bash
scripts/test.sh      # engine tests
scripts/build.sh     # build/Hangover.app (universal)
scripts/package.sh   # tests + build + dist/Hangover.zip
```

`scripts/make-signing-cert.sh` creates a self-signed signing identity once, so every build is signed the same way and users keep their permissions across updates.

## License

MIT. See [LICENSE](LICENSE).
