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

## Math

Click the pet and choose **Math**. The page has three tabs: **Calculator**, **Time** and **Convert**. The app remembers which tab you used last.

### Calculator

Type an equation, then press **Return** (or type `=`) to see the answer. The last 5 answers stay above the box, even after the app restarts. Click one to add its answer to the end of the box and keep going. **Esc** closes the menu.

| You type | Answer | Notes |
|---|---|---|
| `2^(3+1) * 5` | 80 | `+ - * / ^` and parentheses. `×`, `÷` and `−` work too. |
| `2(3+4)` | 14 | You can leave out `*` before parentheses. |
| `-2^2` | -4 | `^` happens before the minus sign, as in math class. |
| `ans * 2` or `_ * 2` | double the last answer | `ans` and `_` mean the newest answer in the list. |
| `80 + 20%` | 96 | Adding a percent adds that much of the number, like a tip. |
| `80 - 25%` | 60 | Subtracting a percent works like a discount. |
| `200 * 15%` | 30 | Anywhere else, `15%` just means 0.15. |
| `sqrt(9)` or `√9` | 3 | Square root, the opposite of `^2`. `2sqrt(9)` is 6. |
| `abs(-4)` | 4 | Absolute value: drops the minus sign. |
| `1,250,000 + 1` | 1,250,001 | You can type thousands commas, and answers show them. |

Some things to know:
- A comma needs exactly three digits after it, so `1,2` is an error rather than a guess.
- Clicking an answer types it back **without** commas, which is handy for pasting into code.
- `%` only means percent. There's no remainder (modulo) operator.
- Very large or very small answers show like `1.5e+20`, and that form can't be typed back in.

### Time

Adds and subtracts times, where 60 minutes make an hour. Press **Return** or type `=`, and the last 5 answers are kept, just like the Calculator.

**Lengths of time:**

| You type | Answer |
|---|---|
| `1:45 + 2:30` | 4:15 |
| `1h 30m + 90 min` | 3:00 |
| `1:30 + 45` | 2:15 (a plain number means **minutes**) |
| `1:45:30 + 45s` | 1:46:15 |
| `2d + 3h` | 51:00 |

Lengths can be `h`/`hr`/`hours`, `m`/`min`/`minutes`, `s`/`sec`/`seconds`, `d`/`days` and `w`/`weeks`, or written as `1:45` or `1:45:30`. Minutes and seconds go up to 59, so a typo like `1:75` is caught.

**Clock times** have AM or PM:

| You type | Answer |
|---|---|
| `9:30am + 2:45` | 12:15 PM |
| `11pm + 2h` | 1:00 AM +1 day |
| `5pm - 9:30am` | 7:30 (the time between them) |

Clock answers follow **Settings → Military time**. Clicking one types it back with am/pm, because that's how the Time tab knows it's a clock time.

**Dates:**

| You type | Answer |
|---|---|
| `today + 90d` | the date 90 days from today, like Sun, Jan 10, 2027 |
| `today - 2w` | the date two weeks ago |
| `Dec 25 - today` | days until Christmas, like 74 days (10w 4d) |
| `fri` | the coming Friday (today, if it's Friday) |
| `12/25/27` or `December 25, 2027` | Sat, Dec 25, 2027 |

- Dates can be `today`, `tomorrow`, `yesterday`, a weekday (`mon`, `friday`), a month and day (`Dec 25`, `December 25`), or `12/25`.
- Add a year (`Dec 25 2027`, `12/25/27`, `12/25/2027`) to pick a specific year. Without one, it picks the nearest: in October, `Jan 5` means next January, and `Oct 1` means this October.
- Add or subtract whole days and weeks: use `90d`, not `90`. A plain number means minutes, so `today + 90` is an error.
- One date minus another gives the days between them.
- Months and workdays aren't supported, and dates can't be mixed with clock times yet (`fri 5pm` doesn't work).
- Dates like `2026-12-25` don't work, because `-` means subtract.

### Convert

Pick a category, type an amount, and choose the units to convert between. The answer updates as you type. Click it to copy it. **⇅** swaps the two units, and each category remembers the units you used last.

| Category | Units |
|---|---|
| Time | sec, min, hr, day, and `h:mm` (69 min is `1:09`) |
| Length | mm, cm, m, km, in, ft, yd, mi |
| Weight | g, kg, oz, lb |
| Temperature | °C, °F, K |
| Volume | ml, L, tsp, tbsp, fl oz, cup, pt, qt, gal (US) |
| Color | hex, rgb, hsl, hsv, and 0–1 versions of each |
| Screen | px, pt (4/3 px), rem (16 px) |

- The amount can be math, like `5+2` or `1,500 * 2`.
- In `h:mm`, minutes can go past 59 (`5:70` is `6:10`), unlike the Time tab.
- **Color** takes one color at a time, pasted however you have it: `#FF8800`, `F80`, `255, 136, 0`, `rgb(255, 136, 0)` or `hsl(32, 100%, 50%)`. A line under the box shows how it was read, with a small swatch. Hex answers are uppercase, like `#FF8800`. Transparency (alpha) isn't supported yet.

## Google Calendar setup (for Reminders → Pull meetings)

**Pull meetings** on the Reminders page adds a reminder for each of today's remaining meetings. It reads meetings from the Mac's Calendar app, so your Google Calendar needs to be synced there first:

1. Open **System Settings → Internet Accounts**.
2. Click **Add Account…**, choose **Google**, and sign in.
3. Make sure **Calendars** is turned on for that account.
4. Open the **Calendar** app and check that your Google meetings show up. Pull meetings can only see what Calendar sees.
5. Click the pet, open **Reminders**, and click **Pull meetings**. The first time, macOS asks for Calendar access: click **Allow**.

If you clicked **Don't Allow**, click **Open Settings** on the Reminders page, or go to **System Settings → Privacy & Security → Calendars**, and turn on **Desktop Pet**.

After the first pull, Topsy pulls meetings by herself once a day: when she launches, when your Mac wakes up, or at midnight. Use the button to catch meetings added later in the day.

Each meeting's reminder goes off when the meeting starts. To get it earlier, open **Settings → Meeting reminders** and enter how many minutes before (up to 180), for example to leave in time to get there. That setting only affects meetings, not reminders you add yourself.

Pull meetings skips all-day events, canceled meetings and ones you declined. Pulling again won't add duplicates. It updates reminders for meetings that moved or were renamed, and removes reminders for meetings that were canceled.

Meeting reminders follow your calendar, so they can't be edited in the app. To change one, change the meeting in Google Calendar and pull again. You can still delete one with ✕, and the next pull brings it back.
