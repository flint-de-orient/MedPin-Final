# MedPin — Care Connected

Flutter build of the MedPin design canvas: all 96 artboards, split into the
doctor/clinic panel, the front desk and the patient app, plus the patient
app's Profile tab (`Patient-Me`, built in the same style; it isn't on the
canvas). The app opens with an animated splash (`lib/app/splash.dart`).

## Run

```sh
flutter pub get
flutter run            # Android / iOS
flutter run -d chrome  # web
```

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
