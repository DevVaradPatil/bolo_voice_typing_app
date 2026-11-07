# Bolo — brand

**Name:** Bolo ("speak"). **Line:** Speak in your language. Bolo types it, anywhere.
**Feel:** premium and friendly — calm, warm neutrals, one confident accent, soft geometry, nothing loud.

## Logo
`logo.svg`: a lowercase **b** on an ink squircle. The bowl of the b is a record button
with a saffron voice dot. Two strokes, one dot — it holds up at 24 px and on a launcher.

## Colour
Monochrome base, one accent. Saffron appears only where the voice is: the logo dot and live recording.

| Token | Light | Dark | Use |
|---|---|---|---|
| bg | `#F7F5F1` | `#0F0F12` | Page (warm paper / soft black) |
| surface | `#FFFFFF` | `#18181D` | Cards |
| surface2 | `#F0EDE7` | `#222228` | Inset fields, chips |
| line | `#E7E3DB` | `#2B2B32` | Hairlines |
| ink | `#17171C` | `#F4F2EE` | Text, primary buttons |
| ink2 | `#6A6973` | `#A09FA8` | Secondary text |
| saffron | `#FF6A3D` | `#FF7A50` | Voice / recording only |
| leaf | `#1F9D6B` | `#3CC48D` | Done states |

## Type
**Figtree** (bundled, OFL): 800 for display, 700 titles, 600 labels, 400–500 body.
Indian scripts fall back to Android's Noto fonts, which cover all 22 scheduled languages.

## Shape and depth
Radius 20 for cards, 14 for fields, full pills for buttons. Hairline borders over heavy shadows; one soft
shadow on the floating bubble only.

## The bubble
- **Idle:** ink disc with the white b and saffron dot
- **Hold to talk:** saffron disc that breathes with your voice level; a lock rail appears above it
- **Slide up:** locks. Let go and keep talking; the disc shows a stop square
- **Let go (or tap stop when locked):** finishes; the last phrase lands about 0.2 s later
