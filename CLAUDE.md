# Lumen

Lumen is a mobile app for tracking endometriosis symptoms, menstrual cycle phases, hormone lab results, body metrics, and physical activity. This repository contains the design system (38 high-fidelity HTML mockup screens plus build tooling that generates shareable deliverables) **and the app being built from it** — see the next section.

## Full app build (beyond the design system)

The Lumen app is being built from these mockups in this same repo. The tokens/screens below remain the visual source of truth, but **implementation status never comes from this file**:

- `backend/` — .NET 10 API (`Lumen.Api`/`Application`/`Domain`/`Infrastructure` + `tests/`); build with `dotnet build backend/Lumen.slnx`.
- `client/` — Flutter app. **Always run flutter/dart with `PUB_CACHE=C:\pub_cache`** — the user-profile path contains a space, which breaks Dart native-asset build hooks ("hook.dill not found" → `flutter clean; flutter pub get` resets it). **Read the last line of the output rather than trusting the exit code:** a `PUB_CACHE` value mangled by shell escaping (the backslash is easy to lose) makes the run die at *"Failed to update packages"* while the pipeline still reports **exit 0** — which reads as a clean `analyze` and is how a false green gets into a task report (verified 2026-08-21, P4b-T21a).
- `deploy/` — Docker Compose dev stack (Caddy / Postgres / Keycloak / Vault): `docker compose -f deploy/docker-compose.yml up -d`.
- `docs/superpowers/plans/lumen-build.md` — **the living build plan; its §1 ledger is the only authority for what is done and what runs next.** Process: `docs/superpowers/RUNBOOK.md`. Architecture: `docs/ARCHITECTURE.md`.
- Root `index.html`, `screens.html`, `viewer.html`, `contact_sheet.html`, `flow_diagram.html` are design-system viewers/deliverables, not app code.

Build-phase sessions: read the plan's §0/§1/§2 first and work only your phase.

## Project structure

```
Screens/                        38 standalone HTML screen files (300px phone frames)
build_contact_sheet.js          Node.js script that reads all screens and generates contact_sheet.html
contact_sheet.html              Generated: responsive grid of all screens with lightbox and theme toggle
flow_diagram.html               Hand-crafted: SVG navigation flow diagram with hover highlights
```

There are no external dependencies, no package.json, no bundler. Everything is plain HTML/CSS/JS.

## Screen inventory

Screens are named `screen_##_name.html` (zero-padded numbers, snake_case names).

| Section               | Screens | Files                                        |
|-----------------------|---------|----------------------------------------------|
| Onboarding            | 1-7     | welcome, account, cycle_setup, baseline, goals, hormones, notifications |
| Home & logging        | 8-14    | dashboard, quick_checkin, cycle_calendar, day_detail, symptom_form, body_map, phase_correction |
| Hormones & studies    | 15-21   | hormone_chart (+landscape variant), hormone_detail, studies_library, upload_study, ocr_confirm, missing_data, confidence_explainer |
| Body & activity       | 22-25   | body_calendar, body_entry, activity_calendar, activity_entry |
| Treatment             | 26-27   | medication_log, add_medication |
| Reports               | 28-30   | insights_hub, doctor_report, share_preview |
| Settings              | 31-37   | profile, cycle_settings, hormone_prefs, notifications, data_export, privacy, help_about |

Screen 15 has a landscape variant (`screen_15_hormone_chart_landscape.html`, 540px wide) for tablet/wearable display.

## Design system tokens

### Light theme ("soft warm")
| Token       | CSS var    | Value                    |
|-------------|------------|--------------------------|
| Background  | `--b`      | `#F1EFE8`                |
| Surface     | `--f`      | `#FFFCF7`                |
| Ink         | `--ink`    | `#3B2A20`                |
| Muted       | `--mut`    | `#8A6F5E`                |
| Accent      | `--ac`     | `#C25A36` (terracotta)   |
| Accent soft | `--acs`    | `#F3D9CC`                |
| Sage        | `--sg`     | `#7B8F6B`                |
| Sage soft   | `--sgs`    | `#E4EADD`                |
| Border      | `--bd`     | `rgba(59,42,32,.12)`     |
| Input       | `--in`     | `#FAF6EF`                |

### Dark theme ("witchy")
| Token       | CSS var    | Value                    |
|-------------|------------|--------------------------|
| Background  | `--b`      | `#1A1220` (deep plum-black) |
| Surface     | `--f`      | `#241830` (plum)         |
| Ink         | `--ink`    | `#F2E4D4`                |
| Muted       | `--mut`    | `#A99BB8`                |
| Accent      | `--ac`     | `#E8A87C` (moonlit gold) |
| Accent soft | `--acs`    | `#3A2438`                |
| Sage        | `--sg`     | `#9BAE85`                |
| Sage soft   | `--sgs`    | `#28321F`                |
| Border      | `--bd`     | `rgba(242,228,212,.12)`  |
| Input       | `--in`     | `#1F1428`                |

### Hormone-specific colors (hard-coded, not theme-switched)
- Estrogen: `#C25A36`, Progesterone: `#7B8F6B`, LH: `#D4537E`
- FSH: `#378ADD`, Testosterone: `#BA7517`, Cortisol: `#7F77DD`, GLP-1: `#1D9E75`

### Cycle phase colors (light / dark)
- Menstrual (`--p1`): `#F3D9CC` / `#4A1B0C`
- Follicular (`--p2`): `#FAEEDA` / `#412402`
- Ovulatory (`--p3`): `#E4EADD` / `#28321F`
- Luteal (`--p4`): `#EEEDFE` / `#26215C`

### Typography
- Font: system sans-serif stack (`-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`)
- Weights: 400 (regular) and 500 (medium) only
- Case: sentence case everywhere, no ALL CAPS except section labels using `text-transform: uppercase`
- No emoji in UI (emoji used only for theme toggle icon)

## Screen HTML architecture

Each screen is a single HTML fragment (no `<!DOCTYPE>`, no `<html>`/`<body>` wrapper) containing a root `<div>` with `data-theme="light"` and a phone frame inside.

### Pattern A (screens 1-11)
Uses `<style>` blocks with CSS attribute selectors scoped to the screen's root ID:
```css
#s8[data-theme="light"]{ --b:#F1EFE8; ... }
#s8[data-theme="dark"]{ --b:#1A1220; ... }
```
Theme toggle sets `data-theme` attribute; CSS selectors drive variable changes.

Screen 1 uniquely uses namespaced variables (`--s1-bg`, `--s1-frame`, etc.) instead of the standard short names.

### Pattern B (screens 12-37 + landscape)
Declares CSS custom properties inline on the root div's `style` attribute:
```html
<div data-theme="light" id="r" style="--b:#F1EFE8;--f:#FFFCF7;...;background:var(--b);...">
```
Theme toggle uses `setProperty()` to update each variable via JavaScript.

### Theme toggle mechanism
Every screen has a toggle button (top-right, circular, shows moon/sun icon) with an `onclick` handler that flips `data-theme` between `"light"` and `"dark"`.

### Phone frame dimensions
- Width: 300px (all screens except landscape)
- Landscape: 540px (screen 15L only)
- Min height: 560-640px
- Border radius: 36px
- Border: 1px solid `var(--bd)`

### Modal/overlay screens
- Screen 9 (quick check-in): bottom sheet over dimmed content, uses `--ovl` variable for overlay color
- Screen 20 (missing data): bottom sheet with `rgba(0,0,0,0.35)` backdrop

## Bottom navigation (in-app)
The app has 5 bottom-nav tabs visible on main screens:
1. Home (dashboard)
2. Cycle (calendar, day detail, phase correction)
3. Hormones (chart, detail, studies, lab upload)
4. Body (metrics, activity)
5. More (treatment, reports, settings)

## Build process

### Regenerating the contact sheet
```bash
node build_contact_sheet.js
```
This reads all 38 files from `Screens/`, escapes them for JS template literals, and writes `contact_sheet.html` with the full inline manifest (~175KB).

The contact sheet:
- Embeds all screen HTML as a JS array (works from `file://`, no server needed)
- Normalizes Pattern B screens by injecting CSS attribute selector `<style>` blocks and stripping inline `--var` declarations (fixes specificity for external theme control)
- Lazy-loads iframes via IntersectionObserver
- Provides a lightbox for full-size preview on click
- Global theme toggle updates all loaded iframes

### Flow diagram
`flow_diagram.html` is hand-crafted (not generated). Edit it directly. It uses:
- SVG with viewBox 1360x900
- Color-coded section borders (terracotta=Home, rose=Cycle, sage=Hormones, gold=Body, muted=More, neutral=Onboarding)
- Hover interaction: mouseenter highlights connected sections/flows, dims the rest
- Named flows with UI trigger labels (e.g., "tap quick log", "upload lab")
- Dark mode uses a lifted intermediate shade `#1E1528` for group box backgrounds

## Style rules for new screens or deliverables
- Use the exact color tokens listed above
- Sentence case everywhere, no ALL CAPS in labels (use CSS `text-transform` for section tags)
- No emoji in content
- Two font weights only: 400 and 500
- Both light and dark theme must be supported via `data-theme` attribute
- Prefer Pattern A (CSS attribute selectors in `<style>` blocks) for new screens
