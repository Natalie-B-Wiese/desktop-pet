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
- `--set-timer` opens that window. `--flip-start-mode` switches the Start page tab after 1 second.
- Example: `./build.sh --menu todos --snapshot /tmp/…/s.png`, using the session scratchpad.
- **Snapshot every UI change** and check it before telling Natalie it's done.
- **Protect her real data.** Before testing with fake data, back it up, and restore it afterwards (check with `cmp`). Her real data:
  - UserDefaults for to-dos, notes, reminders, math history, `startPage.mode`, `mathPage.mode`, `convert.*`, `settings.*` (e.g. `settings.militaryTime`), and pet settings
  - ⚠️ `defaults import` **merges**; it doesn't remove keys added while testing. After restoring, `defaults delete` any test-only keys, then compare the XML (`plutil -convert xml1`) with the backup.
  - `~/Library/Application Support/DesktopPet/Clipboard/`
- Only write defaults (`defaults write com.nataliewiese.DesktopPet …`) while the app is **not running**, or the running app overwrites them.
- Her current settings: name "Topsy", scale 5 (M), a grey body palette, and Military time **on**.
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
- `PetCharacter.swift`: `PetSpecies` (cat, dog; each has a small pixel icon, `Resources/<species> icon.png`) and the patterns. Cats come in 2 **shapes** × 5 patterns. Shapes, in cycle order: `up-long` (the original cat), `down-long` (folded-down ears). Patterns, in cycle order: tuxedo, calico, colorpoint, tortie, van. Images are `Resources/cat <shape> <pattern>.png`, all 24×24 with feet on the bottom row (Natalie's down-ears tuxedo arrived one row too high and was shifted down, as the original tuxedo once was; check new art for this). Up-ear tips are on row 2. Dogs come in 4 **shapes** × 4 patterns. Shapes, in cycle order: `down-long`, `down-stub`, `up-long`, `up-stub` (ears down/up, long/stub tail; down-long is the original dog). Patterns, in cycle order: dog (`default` image), spots, brindle, mask. Images are `Resources/dog <shape> <pattern>.png`. Natalie's originals for both species are in `~/Pictures/Desktop Pet/<Cat|Dog>/<Shape name>/` (the Cat/Up Ears tuxedo there is the old floating one; keep the app's). For both species, IDs are `<pattern>.<shape>`, and old saved IDs without a shape (`spots`, `tortie`) load as the species' first shape. Down-ear tips are on row 3, up-ear tips on row 1. Dog eyes are black. `PetCharacter.shape`/`pattern`. Their parts are Body / Accents / Ears for the default dog (blue is the ears) and Body / Accents / Markings for spots and brindle (blue is a patch or the stripes), all saving blue as `color.ears`. The mask is different: red is the Head, green the Accents, and blue the Body, listed Body / Head / Accents. Its blue saves as `color.main` and its red as `color.ears`, so the body keeps its color when switching dogs. Each has part names (Body / Accents / Eyes; the van is Body / Eye1 / Eye2, where Eye1 is the blue pixels on the image's left and `partOrder` lists it before the green Eye2) and `partKeys`, where colors are saved as `color.<key>`. Patterns that share a key share its color, so switching keeps her colors. Parts the image doesn't use are hidden in Customize. A **dog** can be added the same way.
  - The pattern names are deliberately never shown to the user. Customize has a boxed row under the size buttons with three captioned steppers split by thin dividers: `‹ [species icon] ›` Species, `‹ 2/4 ›` Shape, `‹ 3/4 ›` Pattern. All wrap around. Changing shape keeps the pattern and vice versa. Switching species returns to the character it last had (saved as `character.<species>`).
- `PetSettings.swift`: character (saved as `character`), per-part colors (`palette` is the current character's three), scale (2…12; the UI offers S=4, M=5, L=6), and name (max 20 characters), saved to UserDefaults.
  - ⚠️ Never reassign an `@Observable` property inside its own `didSet`. It recurses forever; this crashed the app once.
  - Clamp values in the callers instead.
- `SpeechBubble.swift` (large): `SpeechBubbleController`, `BubbleView`, `BubbleMenu.Page`, and the shared components `BubbleButton`, `MenuTile`, `BubbleTabs`, `CaretStepper`, `HeaderIconButton`, `bubbleFieldStyle` and `BubbleShape`.
  - Clicking outside the bubble closes it only on the main menu. Tool pages stay open (Natalie wants to keep her work and look things up in other apps); ✕ or clicking the pet closes them.
  - The bubble is a child window of the pet panel and resizes to fit its content with `.onGeometryChange`.
  - Each page has a fixed width in `width(of:)` and a header with a **‹ back** icon and an **✕ close** icon. Pages don't draw their own titles or Back buttons.
  - Main menu: rows of icon tiles, each row centered: Timer/Reminders/To-dos, Notes/Clipboard/Math, then Customize/Settings/Hide. The bottom row is for the pet and the app itself, so new tools don't go there.
  - Keyboard: some pages take the keyboard as soon as they open (startTimer, addReminder, editReminder, math). Others only take it when a field is clicked (timerControls, todos, notes, customize). The bubble gives keyboard focus back to the previous app when it closes.
  - When the menu is closed, clicking the bubble does one of these:
    - dismisses a due reminder
    - starts the next Pomodoro period
    - clears "Time's up"
    - otherwise, pauses or resumes the timer
- One page file per tool:
  - `BubbleCustomizePage.swift` (page width 272), top to bottom: Name box, S/M/L Size buttons (both as wide as the family box, with their labels in the left margin via `labeled(_:width:)`), species/shape/pattern row, part circles, and 12 color families × 6 shades each. (Natalie removed the Reset colors button; users don't need it.)
  - `BubbleMathPage.swift`: Calculator / Convert tabs (saved as `mathPage.mode`). `BubbleConvertTab.swift` and `UnitConverter.swift` hold the converter.
  - `BubbleSettingsPage.swift`: the Settings page (page width 190), `AppPreferences` (app-wide preferences in UserDefaults under `settings.*`, plus `clockText(_:)` for showing a time), and `BubbleSwitchStyle`, a black-outlined on/off switch that matches the bubble (the system switch looked faint grey). Settings so far: **Military time**.
  - `BubbleReminderPages.swift`, `BubbleTodoPage.swift`, `BubbleNotesPage.swift`, `BubbleClipboardPage.swift`.
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
  - ⚠️ `.onKeyPress(.delete)` never fires for the Delete key on macOS (it arrives as U+007F). Match the characters `"\u{7F}\u{8}"` instead.
- **To-dos:** checked items are deleted at the end of the day. The list scrolls after 6.
- **Notes:** multi-line sticky notes, typed on directly. There's no input box and no buttons except ✕.
  - A blank "New note" sits at the top. Typing on it makes it a real note (it keeps the blank's ID so the same TextEditor stays focused) and a fresh blank appears above.
  - Clicking a note edits it in place. Everything autosaves as it's typed, Return adds a line, and there's no cancel. Esc closes the menu.
  - When a note loses focus, it's trimmed, or deleted if empty (`NoteStore.tidy`).
  - ⚠️ Each `NoteRow` binds its TextEditor to its own `@State` copy of the text and syncs it to the store with `onChange`. Binding a macOS TextEditor straight to the store makes the cursor jump to the end after every keystroke.
  - Each editor sizes itself with a hidden copy of its text. The list is always a `ScrollView` (capped at 260pt) so rows are never rebuilt mid-typing.
- **Math:** operators `+ - * / ^` and parentheses. Typing `=` or pressing Return calculates. It keeps the last 5 results. The ~26 test cases in `MathEvaluator.swift` pass.
- **Convert** (a tab on Math): categories Length, Weight, Temperature, Volume (US cups etc.) and Screen (px, pt = 4/3 px, rem = 16px).
  - The answer updates as you type, rounded to 6 decimal places, and clicking it copies the number. The amount can be math, like `5+2`.
  - ⇅ swaps the units. Each category remembers its last two units (`convert.<category>.units`).
  - The pop-up menus are a private `BubblePopUp` (the name `BubbleMenu` is taken by the bubble's page model).
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
- Sound or notification when a timer ends.
- Countdown in the menu bar.
- App icon and a real app name.
- A global keyboard shortcut.
- Morning greetings and chatter.
- GitHub backup.
