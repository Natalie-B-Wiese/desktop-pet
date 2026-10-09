# DesktopPet ("Topsy")

A macOS **menu bar app** that shows a floating, draggable, always-on-top 24×24 pixel-art pet. The pet is a cat by default (dogs are also available), and the user named her **Topsy**. Clicking her opens a speech-bubble menu of small tools. "DesktopPet" is a placeholder app name.

The user is Natalie. She vibecodes this app: she describes what she wants, and the agent writes all the code. She iterates closely on UI details and gives precise visual feedback.

## Location and repo
- Project: `~/xcode/my_widgets/`
- The git repo is local only, on branch `main`, with no remote. A private GitHub backup was offered but hasn't been set up. Ask before pushing anything anywhere.
- Commit after each finished change, using short messages like `Customize: …` or `Clipboard: …`. End commit messages with the attribution line the harness asks for, currently `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- `build/` and `DesktopPet.xcodeproj/` are generated and gitignored.

## Build and run
- `./build.sh [launch args…]` does the whole cycle:
  1. regenerates the project with **XcodeGen** from `project.yml`
  2. builds Release into `build/`
  3. quits the running app and waits for it to exit
  4. installs to `/Applications/DesktopPet.app`
  5. relaunches, passing any args through
- Never edit the `.xcodeproj` directly. Change `project.yml` instead.
- Settings in `project.yml`:
  - Swift 5 mode, macOS 15 target
  - bundle ID `com.nataliewiese.DesktopPet`, team `KX9UX7C7HK`, automatic signing
  - hardened runtime, no sandbox
  - `LSUIElement` = YES (no Dock icon)
- New `.swift` files under `DesktopPet/` are picked up automatically.

## Verifying UI (important)
The agent has no Screen Recording permission, so the app has test launch arguments. They're handled in `AppController.handleTestingArguments()`, which documents them.
- `--snapshot /path/x.png` saves each visible app window as `x-<n>.png` after 1.5s. Read the PNG to check a layout. If it misses the bubble, just run it again (it's a timing issue).
- `--menu [start|controls|reminders|add-reminder|edit-reminder|todos|math|clipboard|notes|settings]` opens the bubble on that page. `--customize` opens the Customize page.
- The following set up a timer state:
  - `--timer <sec>`, optionally with `--label <text>` and/or `--pause`
  - `--pomodoro <work> <break>`
  - `--stopwatch`
- `--type <text>` types that text into the focused window after 1s, one key every 0.1s; `⌫` in the text is Backspace (macOS blocks outside keystrokes, so this is how to test keyboard behavior). `--snapshot` waits until the typing is done. Snapshot after it, e.g. `--menu add-reminder --type "3 45" --snapshot …`.
- `--convert-input <amount>` fills in the Math page's Convert tab (set `mathPage.mode` to `convert` first).
- `--greeting` shows the morning greeting right away without saving `greeting.lastShown`, so it doesn't use up her real one. Note that any launch also runs the real morning check, which shows and remembers today's greeting if it hasn't appeared yet.
- `--set-timer` opens that window. `--flip-start-mode` switches the Start page tab after 1 second.
- Example: `./build.sh --menu todos --snapshot /tmp/…/s.png`, using the session scratchpad.
- **Snapshot every UI change** and check it before telling Natalie it's done.
- **Protect her real data.** Before testing with fake data, back it up, and restore it afterwards (check with `cmp`). Her real data:
  - UserDefaults for to-dos, notes, reminders (plus `reminders.lastMeetingPull`), `greeting.lastShown`, math and time history (`mathHistory`, `timeHistory`), `startPage.mode`, `mathPage.mode`, `convert.*`, `settings.*` (e.g. `settings.militaryTime`), and pet settings
  - ⚠️ `defaults import` **merges**; it doesn't remove keys added while testing. After restoring, `defaults delete` any test-only keys, then compare the XML (`plutil -convert xml1`) with the backup.
  - `~/Library/Application Support/DesktopPet/Clipboard/`
- Only write defaults (`defaults write com.nataliewiese.DesktopPet …`) while the app is **not running**, or the running app overwrites them.
- Her current settings: name "Topsy", scale 5 (M), a grey body palette, and Military time **off** (as of 2026-10-07; check before assuming).
- When restoring after a test, put back what the backup had (`defaults write` its value). Don't assume a setting was at its default; `defaults delete` only keys the backup didn't have.
- To snapshot another pattern, quit the app, back up with `defaults export`, `defaults write com.nataliewiese.DesktopPet character <id>`, run, then restore the backup (see the warning above).

## Architecture (files in `DesktopPet/`)
- `DesktopPetApp.swift`: `@main` app with the `MenuBarExtra` menu (Show/Hide, timers, Pomodoro, stopwatch, screenshot, pages, Launch at Login via `SMAppService`, Quit).
- `AppController.swift`: `@Observable` singleton that owns every model and window. It also handles the pet's right-click menu, hops when a timer ends or a reminder comes due, and the test args.
- `PetPanel.swift`: borderless non-activating `NSPanel` at `.floating` level on all Spaces, plus:
  - manual dragging with a 3pt threshold before a drag starts; a click without movement opens the menu
  - resizing anchored at the bottom center
  - the position saved as "PetWindow"
  - the `hop()` animation
- `PetRenderer.swift`: recolors the current character's PNG (cached per image). Pure **red / green / blue** pixels are three recolorable parts (matched with some tolerance). **Black, white and every other color never change.** It draws nearest-neighbor so pixels stay crisp. `usedSlots(for:)` detects which parts an image uses.
- `PetCharacter.swift`: `PetSpecies` (cat, dog; each has a small pixel icon, `Resources/<species> icon.png`) and the patterns. Cats come in 4 **shapes** × 5 patterns. Shapes, in cycle order: `up-long` (the original cat), `up-bob`, `down-long`, `down-bob` (ears up or folded down, long or bob tail). Patterns, in cycle order: tuxedo, calico, colorpoint, tortie, van. Images are `Resources/cat <shape> <pattern>.png`, all 24×24 with feet on the bottom row (the tuxedos used to arrive one row too high; on 2026-10-05 every tuxedo in Pictures was grounded and the bob-tail calicos' one off-green pixel was made pure green, so Pictures and the app's cat images are identical. Still check new art: feet on the bottom row and only pure red/green/blue for parts. To shift one: draw it into a 24×24 sRGB `CGContext` at y: -1 with interpolation off and save it as PNG; check that its color counts are unchanged). Up-ear tips are on row 2. Dogs come in 4 **shapes** × 4 patterns. Shapes, in cycle order: `down-long`, `down-stub`, `up-long`, `up-stub` (ears down/up, long/stub tail; down-long is the original dog). Patterns, in cycle order: dog (`default` image), spots, brindle, mask. Images are `Resources/dog <shape> <pattern>.png`. Natalie's originals for both species are in `~/Pictures/Desktop Pet/<Cat|Dog>/<Shape name>/`. For both species, IDs are `<pattern>.<shape>`, and old saved IDs without a shape (`spots`, `tortie`) load as the species' first shape. Down-ear tips are on row 3, up-ear tips on row 1. Dog eyes are black. `PetCharacter.shape`/`pattern`. Their parts are Body / Accents / Ears for the default dog (blue is the ears) and Body / Accents / Markings for spots and brindle (blue is a patch or the stripes), all saving blue as `color.ears`. The mask is different: red is the Head, green the Accents, and blue the Body, listed Body / Head / Accents. Its blue saves as `color.main` and its red as `color.ears`, so the body keeps its color when switching dogs. Each has part names (Body / Accents / Eyes; the van is Body / Eye1 / Eye2, where Eye1 is the blue pixels on the image's left and `partOrder` lists it before the green Eye2) and `partKeys`, where colors are saved as `color.<key>`. Patterns that share a key share its color, so switching keeps her colors. Parts the image doesn't use are hidden in Customize. A **dog** can be added the same way.
  - The pattern names are deliberately never shown to the user. Customize has a boxed row under the size buttons with three captioned steppers split by thin dividers: `‹ [species icon] ›` Species, `‹ 2/4 ›` Shape, `‹ 3/4 ›` Pattern. All wrap around. Changing shape keeps the pattern and vice versa. Switching species returns to the character it last had (saved as `character.<species>`).
- `PetSettings.swift`: character (saved as `character`), per-part colors (`palette` is the current character's three), scale (2…12; the UI offers S=4, M=5, L=6), and name (max 20 characters), saved to UserDefaults.
  - ⚠️ Never reassign an `@Observable` property inside its own `didSet`. It recurses forever; this crashed the app once.
  - Clamp values in the callers instead.
- `SpeechBubble.swift` (large): `SpeechBubbleController`, `BubbleView`, `BubbleMenu.Page`, and the shared components `BubbleButton`, `MenuTile`, `BubbleTabs`, `CaretStepper`, `HeaderIconButton`, `bubbleFieldStyle` and `BubbleShape`.
  - Clicking outside the bubble closes it only on the main menu. Tool pages stay open (Natalie wants to keep her work and look things up in other apps); ✕ or clicking the pet closes them.
  - The bubble is a child window of the pet panel and resizes to fit its content with `.onGeometryChange`.
  - Each page has a fixed width in `width(of:)` and a header with a **‹ back** icon and an **✕ close** icon. Pages don't draw their own titles or Back buttons.
  - Main menu: rows of icon tiles, each row centered: Timer/Reminders/To-dos, Notes/Clipboard/Math, then Customize/Settings/Hide. The bottom row is for the pet and the app itself, so new tools don't go there.
  - Keyboard: some pages take the keyboard as soon as they open (startTimer, addReminder, editReminder, math). Others only take it when a field is clicked (timerControls, todos, notes, customize, settings). The bubble gives keyboard focus back to the previous app when it closes.
  - When the menu is closed, clicking the bubble does one of these:
    - dismisses a due reminder (its "· N more" counts everything queued behind it: other due reminders, the greeting, and a finished timer or Pomodoro period; the greeting counts a finished timer the same way)
    - closes the morning greeting
    - starts the next Pomodoro period
    - clears "Time's up"
    - otherwise, pauses or resumes the timer
- One page file per tool:
  - `BubbleCustomizePage.swift` (page width 272), top to bottom: Name box, S/M/L Size buttons (both as wide as the family box, with their labels in the left margin via `labeled(_:width:)`), species/shape/pattern row, part circles, and 12 color families × 6 shades each. (Natalie removed the Reset colors button; users don't need it.)
  - `BubbleMathPage.swift`: Calculator / Time / Convert tabs (saved as `mathPage.mode`). Calculator and Time share the private `CalculatorTab` view, each with its own `MathHistory` (`mathHistory`, `timeHistory`). `BubbleConvertTab.swift` and `UnitConverter.swift` hold the converter; `TimeEvaluator.swift` does the time math.
  - `BubbleSettingsPage.swift`: the Settings page (page width 190), `AppPreferences` (app-wide preferences in UserDefaults under `settings.*`, plus `clockText(_:)` for showing a time), and `BubbleSwitchStyle`, a black-outlined on/off switch that matches the bubble (the system switch looked faint grey). Settings so far: **Military time**, **Morning greeting** (on/off, `settings.morningGreeting`, on by default), **Notification** (the hop sound, `settings.hopSound`: Silent, Purr (default), Ping or Hero, all built-in macOS sounds, played with `NSSound` at the system output volume; a saved sound no longer in the list falls back to the default; the ‹ › arrows wrap and play each sound, and a speaker button replays it (greyed out for Silent); `PetPanel.hop()` plays it, so every hop makes it) and **Meeting reminders** (how early calendar meetings remind you).
  - `BubbleReminderPages.swift`, `BubbleTodoPage.swift`, `BubbleNotesPage.swift`, `BubbleClipboardPage.swift`.
- `MorningGreeting.swift`: the greeting model (`MorningGreeting`), `GreetingStore` (the greeting currently showing, plus `greeting.lastShown`) and its bubble view `BubbleGreeting`.
- `CalendarMeetings.swift`: reads today's meetings (and all-day events, for the greeting) with EventKit (the Mac's Calendar app, which syncs Google Calendar via Internet Accounts). Needs the `com.apple.security.personal-information.calendars` entitlement (hardened runtime) and `NSCalendarsFullAccessUsageDescription`, both in `project.yml`.
- Model files: `PetTimer.swift`, `Reminders.swift`, `Todos.swift`, `Notes.swift`, `MathEvaluator.swift`, `ClipboardHistory.swift`.
- `SetTimerView.swift` is the Custom… timer window.

## Features and their rules
- **Timer:** a countdown with minutes input, caret steppers (holding repeats), and an optional label. While it runs:
  - the bubble shows the time left
  - edit buttons adjust it by ±30s and ±5m
  - clicking the bubble pauses or resumes
  - Start is hidden while a timer is busy
- **Stopwatch** counts up and takes an optional label. **Pomodoro** has work and break lengths, no long break, and waits for a click between periods. The bubble shows "Work"/"Break" with no session number.
- **Reminders:** one-time, a time plus an optional message, only in the bubble (Natalie removed the separate Reminders window). The list scrolls after 4. Clicking a reminder opens the `editReminder(id)` page, which reuses the add page with a Save button.
  - The time is an hour box `:` a minute box (same big bold style as the Timer's minutes, `bubbleNumberBoxStyle`) with AM stacked over PM beside them (`BubbleTabs(vertical: true)`). Typing in a box works like a digital clock: the last two digits win if valid, else the last one. Space or `:` in the hour box jumps to the minute box, like Tab (`onKeyPress`, so the character is never inserted). Backspace in an empty minute box jumps back to the hour box with its text selected (Natalie tried the cursor-at-the-end version first and preferred this). The minutes are kept as typed text (`minuteText`, may be empty) and padded to two digits when the box loses focus.
  - **Military time** (Settings): no AM/PM, the hour box takes 00…23 (padded to two digits), a red bold "Military time is on" (styled like the Clipboard's full warning) sits between the header and the time boxes, and reminder times everywhere show as 24-hour (`AppPreferences.clockText`). The page keeps one `hour24` state either way.
  - Both boxes keep their text exactly as typed (`hourText`, `minuteText`; may be empty or a lone "0") so the text never changes under the cursor, and are tidied when they lose focus (hour "2" → "02" in military, minutes "5" → "05", empty → the previous hour / "00"). Selecting the hour and typing replaces it, and the hour never moves to the minutes on its own. The minutes box ignores space and `:`.
  - ⚠️ Tried and removed, because Natalie found them glitchy: auto-jumping to the minutes after two hour digits; catching hour digits with `onKeyPress` (the text field lost its cursor); Backspace "resuming" the hour so 01 then 3 made 13; padding the hour while typing. Natalie wants: select the hour, type, and it's replaced.
  - ⚠️ `AppPreferences.clockText` builds military times by hand (`%02d:%02d`). `.dateTime.hour(.twoDigits(amPM: .omitted))` still gives 12-hour hours ("02:30" for 14:30) on a Mac set to a 12-hour clock.
  - **Pull meetings** (button under Add reminder) adds a reminder at the start of each of today's remaining meetings, titled with the meeting name, with a small calendar icon in its row. It skips all-day, canceled and declined meetings. Each reminder keeps `meetingID` (event ID + occurrence date) and `meetingStart`. Pulling again doesn't duplicate; it updates reminders whose meeting moved or was renamed, and removes reminders for today's meetings that disappeared. A deleted meeting reminder comes back on the next pull (Natalie wants that: deleting one by accident shouldn't lose it).
  - **Daily pull** (part of `AppController.startMorningCheck`): pulls automatically once a day, at launch, 10s after the Mac wakes or the screen unlocks (so Calendar can sync first), and at midnight (`.NSCalendarDayChanged`). It skips if meetings were already pulled today by either the button or the daily pull (`reminders.lastMeetingPull`, set in `syncMeetings`). It only runs when Calendar access is already on (`CalendarMeetings.hasAccess`), so it never shows the permission dialog itself. Not all-day syncing on calendar changes: that would keep bringing back meeting reminders she deleted on purpose.
  - Meeting reminders **can't be edited** (the calendar is the source of truth): the row isn't a button and the edit page refuses them. They can still be deleted with ✕.
  - **Meeting reminders** setting (Settings, `settings.meetingLeadMinutes`, 0…180) makes them go off that many minutes early. Its box has the meeting rows' grey calendar icon before the title, "Google Calendar meetings only" under it, then a centered minutes number box with caret steppers and "min before", like the Pomodoro rows. (Natalie brainstormed side-by-side layouts like Military time's and chose this one.) (It started as Start/5m/10m/15m tabs; Natalie wanted any number, e.g. to leave early for a meeting.) Settings takes the keyboard only when the box is clicked, and the box is unfocused on open like Customize's name. Changes apply 0.6s after typing stops (`.task(id:)`), so an in-between number like the 1 of "15" can't make a meeting come due. It only applies to meetings, never to reminders she set herself. Rows and the alert show the meeting's start (`Reminder.shownDate`), not the alert time. Changing it moves existing meeting reminders right away (`ReminderStore.applyMeetingLead`). A line under the buttons says what happened; if Calendar access is off, an Open Settings button appears.
  - ⚠️ The due-reminder alert wraps its message at 180pt with the private `WrappingWidth` layout (`BubbleReminderPages.swift`). The bubble sizes itself to its content's ideal size (`.fixedSize()`, `fittingSize`), and under that a plain `.frame(maxWidth: 180)` reports one line's height for wrapped text, so long messages pushed "Click to close" out of the bubble. Use `WrappingWidth` for any other wrapping text in the bubble.
  - ⚠️ `.onKeyPress(.delete)` never fires for the Delete key on macOS (it arrives as U+007F). Match the characters `"\u{7F}\u{8}"` instead.
- **Morning greeting:** once a day, the first morning check from 4 AM on (launch, wake or unlock, then 10s), runs right **after** the daily meeting pull so it sees today's meetings. A flag stops wake and unlock from running two checks at once. The bubble shows it when the menu is closed, after any due reminder and before the timer. Clicking the bubble closes it. It brings the pet back if she's hidden, and she hops.
  - What it says: "Good morning!" (or afternoon/evening if the first visit is later), a line for the weekday, the to-dos left (live count), the meetings (count plus the first one's time and title; "1 meeting at …" for one; "No meetings today"; no line without Calendar access), and up to 3 all-day events (birthdays, holidays, OOO) plus "N more today". It never asks for Calendar access itself.
  - Natalie chose this first version from a brainstorm. Ideas she hasn't picked yet: her own name in the greeting (needs a "Your name" setting), to-dos carried over from yesterday, when the last meeting ends, yesterday's recap (needs counting finished to-dos), weather, and quick-action buttons.
- **To-dos:** checked items are deleted at the end of the day. The list scrolls after 6.
- **Notes:** multi-line sticky notes, typed on directly. There's no input box and no buttons except ✕.
  - A blank "New note" sits at the top. Typing on it makes it a real note (it keeps the blank's ID so the same TextEditor stays focused) and a fresh blank appears above.
  - Clicking a note edits it in place. Everything autosaves as it's typed, Return adds a line, and there's no cancel. Esc closes the menu.
  - When a note loses focus, it's trimmed, or deleted if empty (`NoteStore.tidy`).
  - ⚠️ Each `NoteRow` binds its TextEditor to its own `@State` copy of the text and syncs it to the store with `onChange`. Binding a macOS TextEditor straight to the store makes the cursor jump to the end after every keystroke.
  - Each editor sizes itself with a hidden copy of its text. The list is always a `ScrollView` (capped at 260pt) so rows are never rebuilt mid-typing.
- **Math:** operators `+ - * / ^` and parentheses. Typing `=` or pressing Return calculates. It keeps the last 5 results. The ~26 test cases in `MathEvaluator.swift` pass.
- **Time** (a tab on Math): adds and subtracts times in base 60, typed like the calculator (Return or `=`, last 5 kept). Parts are `1:45`, `1:45:30`, `1h 30m`, `90 min`, `1.5h`, `45s`; a plain number is **minutes**. A part with AM/PM (`9am`, `9:30 p.m.`) is a clock time: clock ± lengths is a clock time (with `+1 day` / `-1 day` when it crosses midnight), and clock − clock is the gap (counted overnight if negative). Lengths can go past 24h (`26:30`) or below zero (`-0:15`). Clock answers follow Military time, but clicking one types it back with am/pm (`MathHistory.Entry.reuse`), since only AM/PM marks a clock time.
- **Convert** (a tab on Math): categories Length, Weight, Temperature, Volume (US cups etc.), Screen (px, pt = 4/3 px, rem = 16px), Color (below) and Time (sec, min, hr, day, and `h:mm`, so 69 min is `1:09`). A unit can override how it reads and shows amounts (`ConvertUnit.read`/`show`); `h:mm` reads like the Time tab (`TimeEvaluator.seconds`, a plain number is minutes) and shows `1:09` or `1:09:30`. Unlike the Time tab, its minutes and seconds may go past 59 (`5:70` → `6:10`, via `allowOverflow`); the Time tab stays strict so a typo like `1:75` is caught. Unit menus are 74pt wide so `h:mm` fits.
  - The answer updates as you type, rounded to 6 decimal places, and clicking it copies the number. The amount can be math, like `5+2`.
  - ⇅ swaps the units. Each category remembers its last two units (`convert.<category>.units`).
  - The pop-up menus are a private `BubblePopUp` (the name `BubbleMenu` is taken by the bubble's page model).
  - **Color** category (`ColorConverter.swift`; categories have a `Kind`, `.numbers` or `.colors`): units `hex`, `rgb`, `rgb 0–1`, `hsl`, `hsl 0–1`, `hsv`, `hsv 0–1`, all converting through `RGBColor` (0–1). Natalie designed it in a brainstorm:
    - One input box (she considered one box per channel and chose one, since pasting is the main use). The placeholder follows the from unit (`255, 136, 0`), and a grey line under the box shows how it was read (`H 32° · S 100% · L 50%`), or the expected numbers and range while empty or invalid.
    - Answers are plain numbers (`255, 136, 0`; hsl as `32, 100, 50`), hex is uppercase `#FF8800`. Rounding: whole numbers for 0–255 and degrees, 1 decimal for percents, 3 for 0–1, halves rounded up. A small swatch starts the breakdown line (it was first at the left of the answer, but that squeezed long answers like `0.725, 0.415, 0.402` too small).
    - Input is lenient: commas/spaces, `rgb(…)`/`hsl(…)`/`hsb(…)` wrappers, `°` and `%`, hex with or without `#` and 3 or 6 digits. No math. Out-of-range numbers are errors (`G must be 0–255`), and a wrapper or `#` from another family says which unit to pick. Hue 360 is 0; greys have hue 0. No alpha yet (see Ideas).
    - Defaults hex → rgb. The menu titles shrink a little so `hsl 0–1` fits in 74pt.
- **Clipboard:** the last 5 copies, including text, images as thumbnails, and files.
  - A copy button on each item keeps its position.
  - Reorder arrows sit outside the item on the left.
  - When the list is full, a red bold warning appears.
  - The screenshot button uses `screencapture -i -c`.
  - **Pick a color** (`AppController.pickColor()`) uses macOS's `NSColorSampler` magnifier and copies `#RRGGBB`, so it lands in the top slot. A text slot that's exactly `#RRGGBB` shows a color swatch, whoever copied it. (Colors briefly had their own page and main-menu tile; Natalie chose to fold them into Clipboard.)
  - It needs macOS's Paste permission and Screen Recording permission. Natalie grants these herself.

## Ideas not built yet (only when asked)
- **Accessories** (hat, bowtie, collar). Natalie asked, and the agent explained this plan without building it: each accessory is a transparent 24×24 PNG on the same grid, stacked on the cat inside `PetRenderer`, so it follows her when she moves, resizes, hops and recolors.
  - Accessories can use the red/green/blue trick to be recolorable.
  - Allow one per spot, like one hat and one neck item.
  - A tall hat needs spare transparent rows above the cat, which also means moving the bubble up.
  - Each animal needs its own version of each accessory.
  - The agent offered to draw placeholder art, or Natalie may draw her own.
- **Alpha in the Convert tab's Color category.** Natalie left it out of the first version because programs disagree on its range (0–1, 0–255 or a percent), so it needs its own design pass. Agreed so far: alpha is optional, and the answer only shows it when one was typed.
- Sound or notification when a timer ends.
- Countdown in the menu bar.
- App icon and a real app name.
- A global keyboard shortcut.
- Chatter (random lines from the pet during the day).
- GitHub backup.
