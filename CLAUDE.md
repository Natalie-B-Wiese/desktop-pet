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
- `--menu [start|controls|reminders|add-reminder|todos|math|clipboard|notes]` opens the bubble on that page. `--customize` opens the Customize page.
- The following set up a timer state:
  - `--timer <sec>`, optionally with `--label <text>` and/or `--pause`
  - `--pomodoro <work> <break>`
  - `--stopwatch`
- `--set-timer` and `--reminders` open those windows. `--flip-start-mode` switches the Start page tab after 1 second.
- Example: `./build.sh --menu todos --snapshot /tmp/…/s.png`, using the session scratchpad.
- **Snapshot every UI change** and check it before telling Natalie it's done.
- **Protect her real data.** Before testing with fake data, back it up, and restore it afterwards (check with `cmp`). Her real data:
  - UserDefaults for to-dos, notes, reminders, math history, `startPage.mode`, and pet settings
  - `~/Library/Application Support/DesktopPet/Clipboard/`
- Only write defaults (`defaults write com.nataliewiese.DesktopPet …`) while the app is **not running**, or the running app overwrites them.
- Her current settings: name "Topsy", scale 5 (M), and a grey body palette.
- To snapshot another pattern, quit the app, back up with `defaults export`, `defaults write com.nataliewiese.DesktopPet character <id>`, run, then `defaults import` the backup.

## Architecture (files in `DesktopPet/`)
- `DesktopPetApp.swift`: `@main` app with the `MenuBarExtra` menu (Show/Hide, timers, Pomodoro, stopwatch, screenshot, pages, Launch at Login via `SMAppService`, Quit).
- `AppController.swift`: `@Observable` singleton that owns every model and window. It also handles the pet's right-click menu, hops when a timer ends or a reminder comes due, and the test args.
- `PetPanel.swift`: borderless non-activating `NSPanel` at `.floating` level on all Spaces, plus:
  - manual dragging with a 3pt threshold before a drag starts; a click without movement opens the menu
  - resizing anchored at the bottom center
  - the position saved as "PetWindow"
  - the `hop()` animation
- `PetRenderer.swift`: recolors the current character's PNG (cached per image). Pure **red / green / blue** pixels are three recolorable parts (matched with some tolerance). **Black, white and every other color never change.** It draws nearest-neighbor so pixels stay crisp. `usedSlots(for:)` detects which parts an image uses.
- `PetCharacter.swift`: `PetSpecies` (cat, dog; each has a small pixel icon, `Resources/<species> icon.png`) and the patterns. Cats, in cycle order: tuxedo, calico, colorpoint, tortie, van (`Resources/cat <id>.png`, all 24×24, feet on the bottom row, ear tips on row 2). Dogs: dog (`dog default.png`) and beagle (`dog beagle.png`), ear tips on row 3, parts Body / Accents / Ears (blue is the ears, plus the beagle's saddle; dog eyes are black). Each has part names (Body / Accents / Eyes; the van is Body / Eye1 / Eye2, where Eye1 is the blue pixels on the image's left and `partOrder` lists it before the green Eye2) and `partKeys`, where colors are saved as `color.<key>`. Patterns that share a key share its color, so switching keeps her colors. Parts the image doesn't use are hidden in Customize. A **dog** can be added the same way.
  - The pattern names are deliberately never shown to the user. Customize has a boxed row under the name field: `‹ [species icon] ›` then `‹ 3/5 ›` (patterns of that species). Both wrap around. Switching species returns to the pattern it last had (saved as `character.<species>`).
- `PetSettings.swift`: character (saved as `character`), per-part colors (`palette` is the current character's three), scale (2…12; the UI offers S=4, M=5, L=6), and name (max 20 characters), saved to UserDefaults.
  - ⚠️ Never reassign an `@Observable` property inside its own `didSet`. It recurses forever; this crashed the app once.
  - Clamp values in the callers instead.
- `SpeechBubble.swift` (large): `SpeechBubbleController`, `BubbleView`, `BubbleMenu.Page`, and the shared components `BubbleButton`, `MenuTile`, `BubbleTabs`, `CaretStepper`, `HeaderIconButton`, `bubbleFieldStyle` and `BubbleShape`.
  - The bubble is a child window of the pet panel and resizes to fit its content with `.onGeometryChange`.
  - Each page has a fixed width in `width(of:)` and a header with a **‹ back** icon and an **✕ close** icon. Pages don't draw their own titles or Back buttons.
  - Main menu: a 3×3 icon grid (Timer/Reminders/To-dos, Notes/Clipboard/Math, Customize/Hide).
  - Keyboard: some pages take the keyboard as soon as they open (startTimer, addReminder, math). Others only take it when a field is clicked (timerControls, todos, notes, customize). The bubble gives keyboard focus back to the previous app when it closes.
  - When the menu is closed, clicking the bubble does one of these:
    - dismisses a due reminder
    - starts the next Pomodoro period
    - clears "Time's up"
    - otherwise, pauses or resumes the timer
- One page file per tool:
  - `BubbleCustomizePage.swift`: 12 color families × 6 shades each, pet name, S/M/L size buttons as wide as the family box, and Reset colors.
  - `BubbleReminderPages.swift`, `BubbleTodoPage.swift`, `BubbleNotesPage.swift`, `BubbleMathPage.swift`, `BubbleClipboardPage.swift`.
- Model files: `PetTimer.swift`, `Reminders.swift`, `Todos.swift`, `Notes.swift`, `MathEvaluator.swift`, `ClipboardHistory.swift`.
- `SetTimerView.swift` is the Custom… timer window. `RemindersView.swift` is the Reminders window.

## Features and their rules
- **Timer:** a countdown with minutes input, caret steppers (holding repeats), and an optional label. While it runs:
  - the bubble shows the time left
  - edit buttons adjust it by ±30s and ±5m
  - clicking the bubble pauses or resumes
  - Start is hidden while a timer is busy
- **Stopwatch** counts up and takes an optional label. **Pomodoro** has work and break lengths, no long break, and waits for a click between periods. The bubble shows "Work"/"Break" with no session number.
- **Reminders:** one-time, a time plus an optional message, available in the bubble and in a window.
- **To-dos:** checked items are deleted at the end of the day. The list scrolls after 6.
- **Notes:** multi-line sticky notes. Click one to edit it. ⌘Return saves. The list scrolls after 5.
- **Math:** operators `+ - * / ^` and parentheses. Typing `=` or pressing Return calculates. It keeps the last 5 results. The ~26 test cases in `MathEvaluator.swift` pass.
- **Clipboard:** the last 5 copies, including text, images as thumbnails, and files.
  - A copy button on each item keeps its position.
  - Reorder arrows sit outside the item on the left.
  - When the list is full, a red bold warning appears.
  - The screenshot button uses `screencapture -i -c`.
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
