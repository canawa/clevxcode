# ClevVPN Design Contract — эталон macOS

Source of truth: `ClevVPNMac` + shared `Theme.swift` / `Components.swift` / `ClevLogo.swift`.

Платформы сверяются с **macOS**, не друг с другом.

## Палитра (`Theme.swift`)

| Token | Hex | Role |
|-------|-----|------|
| background | `#0B0B0D` | окно / фон |
| surface | `#16161A` | карточки |
| surfaceLight | `#1F1F25` | приподнятые поверхности |
| stroke | `#2A2A31` | бордеры |
| yellow | `#FFC400` | primary accent, switch ON, chips |
| amber | `#D18700` | градиент CTA |
| logoYellow | `#FAC300` | Connect ON plate |
| logoAmber | `#E39A00` | Connect ON gradient |
| textPrimary | `#F2F2F5` | основной текст |
| textSecondary | `#9A9AA3` | вторичный |
| green | `#30D158` | ping good / connected status |
| orange | `#FF9F0A` | ping medium |
| red | `#FF453A` | error / ping bad |

Connect rim: `#30303A` → `#121217`. Plate off: `#24242E` → `#0C0C11`.

## IA (macOS)

```
Home: logo → Connect → banners → info → filter chips → servers
Settings (gear sheet): Apps | Rules | Subscription | Language
```

## Connect button (Mac Home)

- `ConnectButton(size: 150)` — эталон desktop
- States: off / busy / on
- Icon: SF Symbol `power` (weight `.light`)
- Press scale: 0.93
- Android / Windows desktop: **150 dp/px**, не меньше

### Plate ON gradient (`Components.swift` `plateRadial`) — копировать 1:1

```
RadialGradient(
  colors: [logoYellow #FAC300, logoAmber #E39A00],
  center: (0.5, 0.42),
  startRadius: diameter * 0.05,
  endRadius: diameter * 0.6
)
```

- Top highlight: white @ 0.30 → clear (endPoint y=0.45)
- Plate OFF: `#24242E` → `#0C0C11` (тот же center/radii)
- Rim всегда `#30303A` → `#121217` (не желтеет)
- WPF: `RadialGradientBrush` RadiusX/Y = **0.6**, GradientOrigin/Center = **0.5,0.42**

## Controls

- Primary CTA: yellow→amber gradient, **чёрный** текст, cornerRadius 16
- Switch ON: **yellow** `#FFC400` (не green), ~42×24, thumb light
- Cards: radius 16, stroke `#2A2A31`
- Tint / accent везде yellow, не blue

## Brand assets (копия с Mac)

| Asset | Path in shared-design |
|-------|------------------------|
| LogoMark | `brand/LogoMark.svg` |
| App icons | `appicon/` |
| Menu bar | `menubar/icon@{1,2,3}x.png` |

Клиенты должны использовать **тот же** `LogoMark.svg` (хэш совпадает с Mac).

## SF Symbols (Mac UI)

Полный набор имён — в `icons/sf/` (SVG-прокси для Android/Windows).

Ключевые на Home:

- `power`
- `gearshape.fill`
- `bolt.horizontal.circle.fill`
- `arrow.up.arrow.down`
- `calendar`
- `arrow.clockwise.circle.fill`
- `star` / `star.fill` / `star.slash`
- `xmark.circle.fill`
- `checkmark` / `checkmark.circle.fill`
- `exclamationmark.octagon.fill`
- `exclamationmark.triangle.fill`
- `lock.shield`
- `plus.circle.fill`
- `trash`
- `square.grid.2x2`

На Apple остаются системные SF Symbols; на Android/Windows — SVG из `icons/sf/`.
