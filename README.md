# Desktop Pet

A macOS menu bar app that puts a small pixel-art pet on your desktop. She floats above your windows, and you can drag her anywhere. Click her to open a speech bubble of little tools: a timer and Pomodoro, reminders, to-dos, notes, a clipboard history, a calculator and unit converter, and a page for customizing how she looks.

## Building

You need:
- macOS 15 or later
- Xcode
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), which you can install with `brew install xcodegen`

Then, from this folder:

```bash
./build.sh
```

The script does five things:
1. Generates `DesktopPet.xcodeproj` from `project.yml`.
2. Builds the app.
3. Quits the running copy, if there is one.
4. Installs the app to `/Applications/DesktopPet.app`.
5. Launches it.

Run it again after any change. The Xcode project is generated, so change `project.yml` instead of editing the project in Xcode.

Signing uses the development team set in `project.yml`. To build under your own Apple account, change `DEVELOPMENT_TEAM` there.

The app lives in the menu bar and has no Dock icon. Use its menu bar icon to show or hide the pet, start timers, or quit.

## Google Calendar setup (for Reminders → Pull meetings)

**Pull meetings** on the Reminders page adds a reminder for each of today's remaining meetings. It reads meetings from the Mac's Calendar app, so your Google Calendar needs to be synced there first:

1. Open **System Settings → Internet Accounts**.
2. Click **Add Account…**, choose **Google**, and sign in.
3. Make sure **Calendars** is turned on for that account.
4. Open the **Calendar** app and check that your Google meetings show up. Pull meetings can only see what Calendar sees.
5. Click the pet, open **Reminders**, and click **Pull meetings**. The first time, macOS asks for Calendar access: click **Allow**.

If you clicked **Don't Allow**, click **Open Settings** on the Reminders page, or go to **System Settings → Privacy & Security → Calendars**, and turn on **Desktop Pet**.

Each meeting's reminder goes off when the meeting starts. To get it earlier, open **Settings → Meeting reminders** and pick 5, 10 or 15 minutes before. That setting only affects meetings, not reminders you add yourself.

Pull meetings skips all-day events, canceled meetings and ones you declined. Pulling again won't add duplicates. It updates reminders for meetings that moved or were renamed, and removes reminders for meetings that were canceled.

Meeting reminders follow your calendar, so they can't be edited in the app. To change one, change the meeting in Google Calendar and pull again. You can still delete one with ✕, and the next pull brings it back.
