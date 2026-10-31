# Quire for iPad: a plan

Nothing here is built yet. This is the plan to agree on first, so the iPad version is designed for
the larger screen rather than stretched from the phone.

## What changes, and what doesn't

The model, storage, streaming, memory, costs, backups and PDF export are shared and don't change.
What changes is the shell around them: how screens are arranged, how you move between them, and
how the app answers a keyboard, a trackpad and a pencil as well as a finger.

Today the app assumes one window, one navigation stack and a narrow screen:

- `AppModel.path` is the single navigation stack, and launch restores one screen per scene.
- Settings is a layer that slides over the chats from the leading edge (`SettingsDrawer`).
- `StackSwipes` hooks the navigation controller's own back gesture (a private selector, guarded).
- Toasts live in one window of their own (`ToastWindow`).
- The build targets iPhone only (`TARGETED_DEVICE_FAMILY: "1"`).

## Layout

Layouts follow the window's width, not the device, so the same code serves a full-screen iPad, Split
View, Slide Over and Stage Manager windows of any size.

- **Compact width** (Slide Over, narrow Split View): exactly the iPhone app.
- **Regular width**: a `NavigationSplitView`.
  - **Sidebar:** chats and projects, the same journal list in a narrower column, with search
    at its top.
  - **Detail:** the open chat. The empty-chat greeting and the mark sit centred in it.
- **Reading measure:** replies capped at about 70 characters a line (roughly 680 pt), centred in
  the detail column. Long lines are the main thing that makes a stretched phone app tiring to read.
- **Message box:** under the reading column and the same width, still floating glass. It isn't
  pinned to the screen's edges.
- **Settings:** opens as a large sheet with its own split view: sections on the left, the page on
  the right. The slide-in drawer is phone-only.
- **Small sheets:** the model picker, chat settings, sources and Export as PDF open as popovers
  or form sheets anchored to what opened them, rather than full-height sheets.

## Input

- **Keyboard shortcuts** (listed when you hold ⌘):
  - ⌘N new chat, ⇧⌘N incognito chat
  - ⌘F search, ⌘, settings
  - ⌘[ / ⌘] previous / next chat
  - ⌘↩ send (Return sends anyway with the setting on), Esc stops a reply
  - ⌘R regenerate, ⌘C on a selected message copies it
  - ⌘K focuses the message box
- **Pointer and trackpad:**
  - hover effects on rows, pills and buttons (`.hoverEffect`)
  - right-click for each context menu
  - two-finger swipes that match the touch swipes
- **Drag and drop:**
  - images and files dropped on the message box attach
  - a reply's text or an image can be dragged out to another app
  - chats can be dragged onto a project in the sidebar
- **Apple Pencil:** Scribble already works in the message box. Nothing more is planned.

## Gestures

- The sidebar replaces the swipe-in settings drawer and the swipe-back-from-anywhere at regular
  width. The system's own edge swipe still shows and hides the sidebar.
- Swipe actions on rows (archive, pin, delete) stay.
- At compact width every phone gesture comes back unchanged.

## Haptics

iPads have no Taptic Engine, so `Haptics` already does nothing there and needs no change. What the
haptics tell you on iPhone has to come from motion and the pointer instead:

- the press scale on buttons
- the accent ring settling
- hover highlights

The one exception is the Apple Pencil Pro, which has haptics, but nothing in Quire is drawn with a
pencil.

## Windows

Multiple windows (`UIApplicationSupportsMultipleScenes: true`) let two chats sit side by side.
They need the biggest change:

- navigation state moves from `AppModel` into a per-window model;
- `ToastWindow` and the launch landing become per-scene;
- each window restores its own screen (it already uses `@SceneStorage`).

I suggest it as its own phase, after the single-window layout is right.

## Phases

1. **Foundation**
   - iPad in the build
   - split view at regular width
   - reading measure
   - popovers and form sheets
   - settings as a sheet with its own split view
   - iPad screenshots from the simulator in CI, to check layouts at each width
2. **Input**: keyboard shortcuts, pointer and hover, drag and drop.
3. **Windows**: per-window navigation, two chats side by side, Stage Manager sizes.
4. **Polish**
   - landscape and the floating keyboard
   - Slide Over
   - the empty chat, About and Spending laid out for the space they have, not centred phone
     columns

## Decisions for you

1. Should the sidebar stay open by default in landscape and close in portrait (the system
   default), or always start closed so the chat has the full width?
2. Settings: a large sheet (my suggestion), or a third column beside the chat?
3. Multiple windows in the first iPad release, or after it?
4. Should projects get their own section in the sidebar (my suggestion), or stay as the shelf of
   cards at the top of the list?
