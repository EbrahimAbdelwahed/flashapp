# FlashApp — UX principles

Status: binding for every UI batch (`fu-08` through `fu-14`), set by the product owner on
2026-07-28. This document amends nothing in the architecture brief; it adds the design
direction the brief left open. Where it conflicts with the brief, the brief still wins and
the conflict becomes a decision request.

**Resolved 2026-07-28: the minimum stays iOS 17 and Liquid Glass is applied progressively**
(`docs/decision-requests/flash-up-v1/liquid-glass-minimum-os.md`). Consequences that bind
every UI batch:

- One abstraction owns the difference. A single `GlassSurface` view modifier in
  `App/Features/Shared` applies the real system glass under `if #available(iOS 26, *)` and
  a `.ultraThinMaterial` approximation below it. **No feature view may branch on OS version
  itself** — if a second `#available` for appearance appears outside that file, the
  abstraction is wrong and must absorb it.
- Layout must be identical on both paths. Only material, blur and edge treatment differ;
  nothing may move, resize or disappear between them, or the two appearances become two
  designs to maintain.
- Every UI batch verifies on both: a simulator at iOS 17 and one at the newest installed
  iOS. A batch that has only been seen on one of them is not done.
- Where the fallback cannot approximate a Liquid Glass behaviour (morphing between glass
  shapes, scroll edge effects), the fallback drops the effect entirely rather than
  imitating it badly. A plain opaque bar beats a fake.

## 1. Liquid Glass, used as a system — not as decoration

- Adopt the system materials and shapes rather than reimplementing them: glass effects,
  glass containers so nearby elements morph as one, glass button styles, morphing tab
  bars, and scroll edge effects.
- Group adjacent glass elements in one container so they merge and separate as a unit.
  Scattered independent glass surfaces are the failure mode; they read as noise.
- Glass belongs to the navigation and control layer. Card content — the thing the user is
  actually reading and grading — sits on an opaque, high-contrast surface. Study text is
  never rendered over a blurred background.
- Never hard-code the tint of a glass surface. Let the material derive from the content
  behind it so light and dark modes both come out right.

### 1a. Colour comes from the icon, through the backdrop

Amended 2026-07-31 by the product owner: the app icon is the brand, and the interface has
to belong to it.

- `App/Design/Palette.swift` is the only place a colour is named. Its terracotta is sampled
  from the icon's stroke and its canvas from the icon's background. **No feature view may
  write a system colour** (`.blue`, `.orange`, `.green`, `.red`) or a raw hex value.
- Views ask for a role — `due`, `new`, `success`, `destructive` — never for a shade. Roles
  are what let the palette move in one place.
- The app's warmth reaches the glass through the **backdrop**, never through a tint on the
  surface: `screenCanvas()` on the scrolling root of every screen, which is what §1's rule
  above requires. A screen that omits it is the one screen that still looks like stock iOS.
- Each hue has a `…Text` variant that clears WCAG AA 4.5:1 on the canvas. Under type, use
  that one; the plain variant is for fills, strokes and glyphs only.

## 2. Zero learning curve

- **One primary action per screen, always in the same place.** On Today it is "Study now";
  in a session it is "Show answer" then the four grades; in the library it is "Add".
- **The app opens on the action, not on a menu.** If cards are due, Today puts the user one
  tap from the first card. Nothing the user needs daily may be more than two taps deep.
- **No feature is discoverable only through a long press, a swipe, or a hidden gesture.**
  Every gesture shortcut must have a visible equivalent. Gestures are accelerators for
  people who already know the app; they are never the only route.
- **Empty states teach.** A screen with no content states what it is for and offers its
  primary action inline — never a bare "no items".
- **Naming follows the user's words, not the domain's.** Avoid "note type", "template key",
  "supersession"; use what a student would say in Italian and English.

## 3. Speed of entry

- No modal blocks the first launch except the mandatory 3-step onboarding, which ends by
  installing the demo deck so the app is never empty on first open.
- Import is reachable from both the library and Today; a user who arrives with a CSV in
  hand never has to look for it in Settings.
- Anything destructive or irreversible (delete, leave a group, erase all data) is behind a
  confirmation that names the consequence in full. That is the only place friction is
  deliberate.

## 4. Motion contract

Derived from Apple's *Designing Fluid Interfaces* via the `apple-design` skill
(`~/.claude/skills/apple-design`). That skill's examples are web code; the principles below
are its rules restated for SwiftUI, and the SwiftUI form is what this project follows.

- **Springs, not durations.** Use `.smooth` (critically damped, the default for anything
  that simply appears), `.snappy` for control feedback, and `.bouncy` only when the user's
  own gesture carried momentum — a flicked card, a thrown sheet. Overshoot on a menu that
  merely faded in is wrong.
- **Feedback on touch-down, not on release.** A grade button highlights the instant it is
  pressed and commits on lift. Anything that waits for the release reads as dead.
- **Interruptible always.** Never disable input during a transition. SwiftUI springs
  already retarget from the current presentation value; do not replace them with
  fixed-duration `linear`/`easeInOut` animations on anything the user can touch.
- **1:1 tracking with the finger.** A dragged sheet or swiped card follows the touch
  exactly, respecting where it was grabbed. Use `DragGesture`'s
  `predictedEndTranslation` to choose the landing point — that is Apple's momentum
  projection, already computed for us — rather than snapping from the release point.
- **Symmetric paths.** What slides in from an edge dismisses to that same edge. Sheets and
  popovers originate from the control that opened them.
- **Soft boundaries.** At the end of a list or a drag range, resist progressively instead
  of stopping hard.
- **Haptics only where they earn it.** `sensoryFeedback` on commit-level moments — a grade
  registered, a session completed, an import finished — never on ordinary navigation.
  Visual, sound and haptic fire on the same frame or not at all.
- **Reduced motion is a different animation, not the absence of one.** Under
  `accessibilityReduceMotion`, glass morphing and the card flip become cross-fades; the
  feedback stays, the vestibular movement goes.

## 5. Non-negotiables inherited from the spec

These are not softened by the design direction:

- Dynamic Type on every screen; no fixed font sizes.
- Accessibility labels, traits and values on every control, including the grade buttons.
- `accessibilityReduceMotion` respected — glass morphing and the card flip both need a
  reduced variant.
- Every user-facing string ships in English and Italian in the same batch that adds it.
- Contrast must survive the glass: verify legibility over both light and dark content.
