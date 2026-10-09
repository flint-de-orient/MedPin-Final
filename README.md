# MedPin — Care Connected

Flutter build of the MedPin design canvas: all 96 artboards, split into the
doctor/clinic panel, the front desk and the patient app, plus the patient
app's Profile tab (`Patient-Me`, built in the same style; it isn't on the
canvas). The app opens with an animated splash (`lib/app/splash.dart`).

## Run

Start the backend first (`cd backend && npm run dev`, see [backend/README.md](backend/README.md)), then:

```sh
flutter pub get
flutter run            # Android emulator reaches the API at http://10.0.2.2:4000
flutter run -d chrome  # web uses http://localhost:4000
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:4000   # a real phone on your Wi-Fi
flutter run --dart-define=MEDPIN_PREVIEW=true                     # design launcher, no backend
```

The app opens with the splash, then the home screen of the signed-in account
(doctor dashboard, front desk Today, or patient home), or sign-in when signed
out: Login → 6-digit code → home for the account's role. New numbers with a
clinic invite continue to Register. Screens opened from the design launcher or
the screen gallery keep the design's sample data.

The app opens on a launcher: **Doctor app** (starts at sign-in), **Front desk**,
**Patient app**, or **Browse all screens** (grouped like the canvas rows;
sheets open over their parent screen).

## Layout

| Path | What |
| --- | --- |
| `lib/core/tokens.dart` | Colours (`MP`), shadows (`MPShadow`), `tx()` text styles (Figtree, CSS line-height rules), theme |
| `lib/core/icons.dart` | `Ico` (the design's exact SVG icons), `Svg` for charts, icon set `I` |
| `lib/core/nav.dart` | `Nav.go/tab/reset/back` by design stem, `openSheet`, `toast` |
| `lib/widgets/mp.dart` | Shared components: page, header, card, buttons, inputs, chips, switch, sheet… |
| `lib/widgets/navs.dart` | Floating bottom navs: `DoctorNav`, `ClinicianNav`, `StaffNav`, `PatientNav` |
| `lib/app/registry.dart` | Every screen, keyed by its design file stem (`Consult-Vitals` → `ConsultVitalsScreen`) |
| `lib/screens/auth`, `doctor`, `staff`, `patient` | One file per artboard; `common_*.dart` hold helpers shared inside a group |
| `design/` | The source artboards (`<Stem>.dc.html`) and the canvas index |
| `tool/preview_main.dart` | Dev preview: `flutter run -d chrome -t tool/preview_main.dart`, then open `#/<Stem>` |

Screens address each other by design stem, e.g. `Nav.go(context, 'Consult-Page')`.
Taps that lead to something the design doesn't contain yet show a short toast.

## Tests

```sh
flutter analyze
flutter test   # builds every screen at 360/390/430 px with the real font, plus the main flows
```
