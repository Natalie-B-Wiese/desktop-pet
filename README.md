# Desktop Pet

A macOS menu bar app that puts a small pixel-art pet on your desktop. She floats above your windows, and you can drag her anywhere. Click her to open a speech bubble of little tools: a timer and Pomodoro, reminders, to-dos, notes, a clipboard history with screenshots and screen recording, a calculator and unit converter, a few games, and a page for customizing how she looks.

![Desktop Pet's tools above a lineup of cats and dogs in different colors](screenshots/overview-with-pets.png)

## Download

1. Download the latest `DesktopPet-….zip` from the [Releases page](https://github.com/Natalie-B-Wiese/desktop-pet/releases/latest).
2. Unzip it and drag **DesktopPet.app** into your **Applications** folder.
3. Open it. macOS will say it "can't be verified," because the app isn't notarized by Apple. Click **Done**.
4. Open **System Settings → Privacy & Security**, scroll down to the message about DesktopPet, and click **Open Anyway**. You only need to do this once.

Your pet appears on your desktop. Desktop Pet has no window or Dock icon. It lives in the menu bar, under the cat icon, where you can show or hide the pet, start timers, or quit.

Desktop Pet needs macOS 15 or later and runs on both Apple Silicon and Intel Macs.

### Updates

Once a day, Desktop Pet checks GitHub for a newer version. When there is one, your pet tells you in her bubble, with a **Download** button that opens the release page. Download it and replace the app in Applications the same way you installed it; your to-dos, notes and settings stay. To check right away, click **Check for updates** at the bottom of **Settings**. This check is the only time the app goes online.

## Using the pet

- **Click the pet** to open the menu of tools. Click her again, or click ✕, to close it.
- **Drag the pet** to move her anywhere. She remembers where you left her.
- **Right-click the pet** to hide her. Bring her back from the menu bar icon.
- **The menu bar icon** can show or hide the pet, start timers, take a screenshot, record the screen, turn on **Launch at Login**, or quit.

Tool pages stay open when you click another app, so you can look something up without losing what you typed.

## The tools

- **Timer:** a countdown, a stopwatch, or Pomodoro (work and break periods; click the bubble to start the next one). While it runs, the bubble shows the time left; click it to pause.
- **Reminders:** a time and an optional message, once or on chosen days of the week. When one comes due, she hops and shows it until you click it. **Snooze** puts it off for a few minutes (set in **Settings → Snooze**); once snoozed, it shows how long in all when it comes back. Add a meeting link and the reminder gets a **Join** button. **Pull meetings** adds today's calendar meetings (see [Google Calendar setup](#google-calendar-setup-for-reminders--pull-meetings)), and **Settings → Early reminders** gives you a heads-up a few minutes before each one.
- **To-dos:** checked items move to the **Archived** tab at the end of the day, so you don't have to clean up. ↶ puts one back.
- **Notes:** sticky notes you type on directly. Everything saves as you type.
- **Clipboard:** the last 5 things you copied anywhere on your Mac: text, images, videos and files. Click one to see it up close. **Pin** up to 3 so new copies never push them out (and **Delete all** keeps them). Copies that password managers mark as private aren't saved. It also takes **Screenshots** and picks a color from anywhere on screen (**Pick color**, copied as `#RRGGBB`).
- **Screen recording:** the **Record** tab on the Clipboard page (or **Record Screen** in the menu bar). Drag across part of the screen, or click for the whole screen. Your pet and her bubbles are never in the video, so you can keep using her while you record. Click her bubble to stop; the video lands in your Clipboard list.
- **Math:** a calculator, time math and unit conversions. See [Math](#math).
- **Customize:** her name, size, animal (cat or dog), shape, pattern and colors.

## Games

Click the pet and choose **Games**. Most of them help you make a choice; two you play with her.

- **Spinner:** a highlight runs down a list and stops on a random pick: your to-dos, a coin, rock-paper-scissors, or up to three lists of your own. **Shuffle** puts your own list in a random numbered order, like who goes first.
- **Number:** a random whole number between the two you type.
- **Groups:** split a list of people or things randomly into even groups.
- **Hide & Seek:** she hides in one of your open apps. Switch between your apps to find her peeking up from a window, then click her. No permissions needed.
- **Words:** guess her word one letter at a time, with a category as a hint.
- **Ask:** think of a yes-or-no question and click **Ask** for her answer, like a Magic 8-Ball.

## Chatter

Your pet can talk now and then, in a personality you pick in **Settings → Chatter**. She starts out quiet (**None**). Her speech bubble fades once you've seen it, or click it to close it right away.

- **Butler:** formal and polite, with dry wit. Fond of tea.
- **Upbeat:** excited about everything, with Gen-Z vibes.
- **Boss:** a CEO who thinks you're the star employee, and can't resist a pun.
- **Sassy:** dramatic and a little full of herself.
- **Deadpan:** says odd things with a straight face.

On holidays and a few other special days she has something special to say, and from December 1 the morning greeting counts down the days until Christmas.

## Math

Click the pet and choose **Math**. Type, then press **Return** (or `=`). Click an answer to type it back in.

| Tab | You type | Answer |
|---|---|---|
| Calculator | `2^(3+1) * 5` | 80 |
| Calculator | `80 + 20%` / `80 - 25%` | 96 / 60 (tip and discount math) |
| Calculator | `ans * 2` | double the last answer (`_` works too) |
| Calculator | `sqrt(9)`, `abs(-4)` | 3, 4 |
| Time | `1:45 + 2:30` | 4:15 |
| Time | `9:30am + 2:45` | 12:15 PM |
| Time | `5pm - 9:30am` | 7:30 (the time between them) |
| Time | `today + 90d` | the date 90 days from today |
| Time | `Dec 25 - today` | days until Christmas |

`%` only means percent; there's no remainder (modulo) operator.

**How to write times** on the Time tab:
- **A plain number is minutes:** `1:30 + 45` is 2:15.
- **Lengths:** `1:45` is 1 hour 45 minutes, and `1:45:30` adds seconds. Or use units: `h`, `hr` or `hours`; `m`, `min` or `minutes`; `s`, `sec` or `seconds`; `d` or `days`; `w` or `weeks`. They can be combined, like `1h 30m`.
- **Clock times** have AM or PM: `9am`, `9:30pm`. A clock time plus or minus a length is a clock time (with `+1 day` if it crosses midnight), and one clock time minus another is the time between them.
- **Dates:** `today`, `tomorrow`, `yesterday`, a weekday (`fri` is the coming Friday), `Dec 25`, `12/25` or `12/25/27`. Add or subtract days with `d` or `w` (`today + 90d`, not `today + 90`, since a plain number is minutes). One date minus another gives the days between them.

**Convert:** type an amount (it can be math, like `5+2`) and pick two units. Categories: Range (maps a number from one range onto another, like 0.5 in 0–1 → 50 in 0–100), Time, Length, Weight, Temperature, Volume (US), Color (hex, rgb, hsl, hsv) and Screen (px, pt, rem). Click the answer to copy it.

## Permissions

Some features need permission from macOS. Without it they just look empty or do nothing, so check here first if something seems broken.

| Feature | Permission | Where to turn it on |
|---|---|---|
| Clipboard history | Paste from Other Apps | System Settings → Privacy & Security → **Paste from Other Apps** |
| Screenshots and screen recording | Screen Recording | System Settings → Privacy & Security → **Screen Recording** |
| Recording your mic | Microphone | System Settings → Privacy & Security → **Microphone** |
| Pull meetings, all-day events in the morning greeting | Calendars | System Settings → Privacy & Security → **Calendars** |

After turning on Screen Recording, **quit and reopen the app**: macOS only applies it after a restart.

## Google Calendar setup (for Reminders → Pull meetings)

**Pull meetings** reads meetings from the Mac's Calendar app, so your Google Calendar needs to be synced there first:

1. Open **System Settings → Internet Accounts**.
2. Click **Add Account…**, choose **Google**, and sign in.
3. Make sure **Calendars** is turned on for that account.
4. Open the **Calendar** app and check that your Google meetings show up. Pull meetings can only see what Calendar sees.
5. Click the pet, open **Reminders**, and click **Pull meetings**. The first time, macOS asks for Calendar access: click **Allow**.

After that, she pulls meetings by herself once a day; the button catches ones added later.

## For developers

To change the code and build the app yourself, you need macOS 15 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Then, from this folder:

```bash
./build.sh
```

It generates the Xcode project from `project.yml`, builds the app, installs it to Applications and relaunches it. Change `project.yml` rather than the Xcode project, which is generated. To build under your own Apple account, change `DEVELOPMENT_TEAM` there.

## License

[MIT](LICENSE)
