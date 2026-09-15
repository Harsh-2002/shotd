# shotd

## Native macOS Screenshot & Recording Post-Processing Daemon

**Platform:** macOS  
**Implementation:** Swift  
**Runtime:** Headless CLI + LaunchAgent  
**Capture engine:** Apple Screenshot  
**UI:** None  
**Image processing:** CoreGraphics / ImageIO  
**Video processing:** AVFoundation / VideoToolbox  
**Clipboard:** AppKit / NSPasteboard  
**Desktop wallpaper:** AppKit / NSWorkspace  
**Cloud storage:** Generic S3-compatible API  
**Configuration:** JSON  
**Primary design goal:** Minimal, reliable, automatic and native.

---

# 1. Product Definition

`shotd` is a lightweight background utility that extends Apple's built-in screenshot and screen-recording workflow.

It is deliberately **not a screenshot application**.

Apple continues to own:

```text
⌘⇧3
⌘⇧4
⌘⇧5

window selection
area selection
full-screen capture
screen recording
Retina capture
native window shadows
Markup
annotations
capture permissions
```

`shotd` begins working only after macOS creates or modifies the resulting media.

The complete workflow is:

```text
Apple Screenshot
        ↓
source file
        ↓
shotd detects it
        ↓
wait until file is complete
        ↓
inspect media
        ↓
determine dimensions / aspect ratio
        ↓
resolve background
        ↓
calculate adaptive layout
        ↓
render presentation
        ↓
encode selected output format
        ↓
save final media
        ↓
clipboard
        ↓
S3-compatible upload
        ↓
public/presigned URL
```

The normal screenshot experience should therefore remain:

```text
⌘⇧4
click window
done

⌘V
```

No editor should appear.

No background should need to be selected again.

No export button should need to be clicked.

---

# 2. Core Design Principle

The product should feel like:

```text
macOS Screenshot
      +
invisible presentation layer
      +
automatic delivery layer
```

The daemon must remain:

- headless
- event driven
- low footprint
- native
- configuration driven
- reliable
- local-first
- easy to install
- easy to remove

There should be no Electron, browser runtime, Tauri frontend, Flutter application, Qt application, or persistent graphical interface.

---

# 3. Complete Scope

Everything below belongs to the same complete implementation.

There are no staged product phases.

`shotd` supports:

### Screenshots

- window screenshots
- selected-region screenshots
- full-screen screenshots
- portrait captures
- landscape captures
- square captures
- extremely wide captures
- extremely tall captures
- Retina screenshots
- screenshots containing transparency

### Recordings

- native macOS screen recordings
- source audio preservation
- source frame-rate preservation
- adaptive background composition
- native Apple hardware encoding

### Backgrounds

- current macOS desktop wallpaper
- custom background image
- solid color
- gradient

### Image output

- preserve source format where practical
- PNG
- WebP lossless
- WebP lossy
- AVIF lossless
- AVIF lossy
- HEIC/HEIF
- JPEG

### Delivery

- local final output
- clipboard
- arbitrary S3-compatible storage
- public CDN URL
- private presigned URL

### Operations

- daemon
- LaunchAgent
- CLI
- install
- uninstall
- start
- stop
- restart
- status
- doctor
- configuration validation
- automatic config reload
- secure credential storage
- upload retries

---

# 4. Important Source-File Rule

`shotd` must **not destroy or modify Apple's original capture by default**.

The input and generated result are separate objects.

Recommended directories:

```text
~/Pictures/shotd/
├── inbox/
├── output/
└── backgrounds/
```

Apple writes:

```text
~/Pictures/shotd/inbox/
```

`shotd` writes:

```text
~/Pictures/shotd/output/
```

Example:

```text
inbox/
└── Screenshot 2026-09-15 at 14.20.14.png

output/
└── Screenshot 2026-09-15 at 14.20.14.webp
```

The input might be PNG while the final result is WebP, AVIF, HEIC or another configured output.

Input format and output format are therefore completely independent.

---

# 5. Source Retention

The complete implementation supports both retention policies:

```text
keep
deleteAfterSuccess
```

Default:

```text
keep
```

With:

```text
deleteAfterSuccess
```

the original is removed only after:

```text
processing succeeded
        +
final local file was atomically written
```

If cloud upload is required by policy, cleanup can additionally wait for successful upload.

The original must never disappear because encoding failed.

---

# 6. High-Level Architecture

```text
                      macOS
                        │
               Screenshot.app
                        │
                        ▼
                    inbox/
                        │
                        ▼
              DirectoryWatcher
                        │
                 FileTracker
                        │
                FileStabilizer
                        │
                        ▼
                MediaInspector
                        │
          ┌─────────────┴──────────────┐
          │                            │
          ▼                            ▼
        IMAGE                        VIDEO
          │                            │
          └────────────┬───────────────┘
                       │
                       ▼
                 LayoutEngine
                       │
                       ▼
              BackgroundResolver
                 │           │
        Desktop wallpaper   Custom
                 │           │
                 └─────┬─────┘
                       │
                       ▼
                    Renderer
                       │
                       ▼
                EncoderRegistry
                       │
       ┌───────────────┼────────────────┐
       │               │                │
   ImageIO           WebP             AVIF
       │               │                │
       └───────────────┬────────────────┘
                       │
                       ▼
                 Atomic Output
                       │
          ┌────────────┼────────────┐
          │            │            │
          ▼            ▼            ▼
        Local       Clipboard       S3
                                    │
                                    ▼
                              Public/Private URL
```

---

# 7. Repository Structure

```text
shotd/
├── Package.swift
├── README.md
├── LICENSE
│
├── Sources/
│   ├── shotd/
│   │   └── main.swift
│   │
│   └── ShotCore/
│       ├── Runtime/
│       │   ├── Daemon.swift
│       │   ├── LaunchAgent.swift
│       │   └── SignalHandler.swift
│       │
│       ├── Config/
│       │   ├── Config.swift
│       │   ├── ConfigLoader.swift
│       │   └── ConfigValidator.swift
│       │
│       ├── Watcher/
│       │   ├── DirectoryWatcher.swift
│       │   ├── FileTracker.swift
│       │   └── FileStabilizer.swift
│       │
│       ├── Media/
│       │   ├── MediaInspector.swift
│       │   ├── MediaType.swift
│       │   └── MediaDimensions.swift
│       │
│       ├── Background/
│       │   ├── BackgroundResolver.swift
│       │   ├── DesktopWallpaperResolver.swift
│       │   ├── CustomBackground.swift
│       │   ├── SolidBackground.swift
│       │   └── GradientBackground.swift
│       │
│       ├── Layout/
│       │   ├── LayoutEngine.swift
│       │   ├── AspectRatio.swift
│       │   └── Canvas.swift
│       │
│       ├── Image/
│       │   ├── ImageProcessor.swift
│       │   ├── ImageRenderer.swift
│       │   └── ImageDecoder.swift
│       │
│       ├── Encoding/
│       │   ├── Encoder.swift
│       │   ├── EncoderRegistry.swift
│       │   ├── ImageIOEncoder.swift
│       │   ├── WebPEncoder.swift
│       │   └── AVIFEncoder.swift
│       │
│       ├── Video/
│       │   ├── VideoProcessor.swift
│       │   ├── VideoCompositor.swift
│       │   └── VideoEncoder.swift
│       │
│       ├── Clipboard/
│       │   └── ClipboardService.swift
│       │
│       ├── Storage/
│       │   ├── S3Client.swift
│       │   ├── S3Signer.swift
│       │   ├── S3Uploader.swift
│       │   ├── MultipartUploader.swift
│       │   └── CredentialStore.swift
│       │
│       ├── Output/
│       │   ├── OutputManager.swift
│       │   └── AtomicWriter.swift
│       │
│       └── Logging/
│           └── Log.swift
│
├── CodecKit/
│   ├── WebP/
│   └── AVIF/
│
├── Tests/
│   ├── Fixtures/
│   ├── Golden/
│   └── ShotCoreTests/
│
└── Packaging/
    └── io.shotd.plist
```

The goal remains a small codebase.

These modules separate responsibilities; they are not intended to become separate services or processes.

---

# 8. Input Format Handling

Never assume Apple generated PNG simply because screenshots commonly use PNG.

Determine file format using:

```text
ImageIO
UTType
file contents
```

rather than only the filename extension.

Possible input examples:

```text
PNG
JPEG
HEIC
TIFF
WebP
```

Anything ImageIO can safely decode may be accepted.

For video:

```text
MOV
MP4
```

through AVFoundation.

The source media is decoded into a normalized internal representation before presentation rendering.

---

# 9. Output Format Architecture

Output format must be a first-class configuration choice.

Conceptually:

```text
rendered image
      ↓
EncoderRegistry
      ↓
selected codec
      ↓
final file
```

The layout/rendering system must not care whether the final file becomes:

```text
PNG
WebP
AVIF
HEIC
JPEG
```

This separation prevents codec logic from contaminating rendering logic.

---

# 10. Supported Image Output Modes

## PNG

Mode:

```text
png
```

Properties:

```text
lossless
excellent screenshot compatibility
alpha support
large files compared with modern codecs
```

Recommended when compatibility matters most.

---

## WebP Lossless

Mode:

```text
webp-lossless
```

Properties:

```text
lossless
alpha support
typically substantially smaller than PNG
excellent for screenshots and UI
```

This should be the recommended compressed-lossless option.

Example:

```json
"image": {
  "format": "webp",
  "compression": "lossless"
}
```

---

## WebP Lossy

Mode:

```text
webp
```

Configuration:

```json
"image": {
  "format": "webp",
  "compression": "lossy",
  "quality": 90
}
```

Useful when extremely small files matter more than perfect pixel preservation.

---

# 11. AVIF Output

Support both:

```text
avif-lossless
avif
```

Lossless example:

```json
"image": {
  "format": "avif",
  "compression": "lossless"
}
```

Lossy example:

```json
"image": {
  "format": "avif",
  "compression": "lossy",
  "quality": 85
}
```

AVIF offers excellent compression but is more computationally expensive than WebP.

It should therefore run only after screenshot rendering, not inside the rendering pipeline itself.

Lossless AVIF configuration must use encoder settings that preserve full chroma and alpha.

Automated round-trip tests must verify:

```text
encode
↓
decode
↓
compare pixels
```

for the supported lossless mode.

If the chosen AVIF encoder configuration is not pixel-exact, it must not be labelled `lossless`.

---

# 12. HEIC / HEIF

Support:

```text
heic
```

Use Apple's native ImageIO implementation.

HEIC is useful when:

```text
small file size
+
Apple ecosystem compatibility
```

matter.

It should not be presented as the primary cross-platform lossless screenshot format.

Recommended use:

```json
"image": {
  "format": "heic",
  "quality": 0.9
}
```

---

# 13. JPEG

Support:

```text
jpeg
```

because users may want maximum application compatibility.

It is always treated as lossy.

JPEG should not be the default for screenshots containing text.

---

# 14. Preserve Format

Support:

```text
preserve
```

Example:

```json
"image": {
  "format": "preserve"
}
```

Behavior:

```text
PNG input  → PNG output
JPEG input → JPEG output
HEIC input → HEIC output
WebP input → WebP output
```

If the corresponding encoder is unavailable:

```text
fallback → PNG
```

Never silently use a lossy replacement for a lossless source.

---

# 15. Encoder Selection

`EncoderRegistry` handles codec discovery.

At startup:

```text
query ImageIO supported destination types
        ↓
register available native encoders
        ↓
register bundled WebP encoder
        ↓
register bundled AVIF encoder
```

For formats ImageIO can natively encode:

```text
use ImageIO
```

For guaranteed WebP support:

```text
use native encoder if suitable
otherwise bundled libwebp
```

For guaranteed AVIF support:

```text
bundled libavif + narrowly scoped encoder backend
```

Do not use:

```text
FFmpeg
ImageMagick
Node
Python
external Homebrew executable
```

just for image conversion.

The binary should remain self-contained after installation.

---

# 16. Codec Footprint Policy

Minimal footprint remains an important requirement.

The only non-Apple codec dependencies permitted are those required for guaranteed:

```text
WebP
AVIF
```

They should be:

```text
statically linked
or
packaged directly with shotd
```

No external daemon is required.

No package manager runtime dependency is required.

The build should use the smallest supported codec configuration needed for:

```text
single-frame still images
alpha
lossless
lossy
```

Animation support is unnecessary.

General-purpose multimedia frameworks must not be included merely for still-image encoding.

---

# 17. Recommended Output Defaults

Default disk output:

```text
WebP lossless
```

because the primary workload consists of:

```text
UI screenshots
terminals
browsers
code
documentation
```

where visual fidelity matters.

Recommended fallback:

```text
PNG
```

Suggested default:

```json
"image": {
  "format": "webp",
  "compression": "lossless",
  "fallbackFormat": "png"
}
```

Users who care more about universal compatibility can simply select:

```text
png
```

Users who prioritize smallest output can select:

```text
avif
```

---

# 18. Clipboard Format Is Separate From Disk Format

This is important.

Suppose final storage format is:

```text
AVIF
```

Some macOS applications may not accept AVIF directly from the clipboard.

Therefore clipboard representation must not blindly mirror the disk format.

Clipboard pipeline:

```text
rendered CGImage
        │
        ├── disk encoder → AVIF/WebP/etc.
        │
        └── clipboard → native image representation
```

For screenshots, publish:

```text
PNG representation
NSImage
local output file URL
```

through `NSPasteboard`.

Therefore:

```text
disk = WebP lossless
```

can still behave as:

```text
⌘V → normal image
```

in Slack, Discord, browsers, Notes and similar applications.

This improves compatibility without forcing PNG storage.

---

# 19. S3 Uses the Actual Encoded Output

If disk output is:

```text
.webp
```

S3 uploads:

```text
.webp
Content-Type: image/webp
```

If output is:

```text
.avif
```

use:

```text
image/avif
```

If output is:

```text
.heic
```

use the appropriate HEIC/HEIF MIME type.

The URL extension should correspond to the actual encoded object.

---

# 20. Background Sources

`shotd` supports four complete background sources:

```text
desktop
image
solid
gradient
```

Example:

```json
"background": {
  "type": "desktop"
}
```

or:

```json
"background": {
  "type": "image",
  "path": "~/Pictures/shotd/backgrounds/my-background.jpg"
}
```

---

# 21. Native macOS Desktop Wallpaper

When:

```text
background.type = desktop
```

use:

```text
NSWorkspace.shared.desktopImageURL(for:)
```

to resolve the configured macOS desktop image.

Do this when processing rather than only once during installation.

That means if the user changes wallpaper:

```text
old wallpaper
     ↓
System Settings changes wallpaper
     ↓
next screenshot
     ↓
shotd resolves new wallpaper
```

No config change is required.

---

# 22. Wallpaper Resolution Component

Component:

```text
DesktopWallpaperResolver
```

Responsibilities:

```text
enumerate NSScreen
determine appropriate screen policy
query NSWorkspace
obtain wallpaper URL
obtain desktop-image options
decode image
cache decoded result
invalidate when wallpaper changes
```

Calls to `NSWorkspace` that require the main thread must be executed appropriately on the main actor.

---

# 23. Multiple Displays

macOS may have different wallpapers on different displays.

Configuration supports:

```text
main
specific
bestMatch
```

Example:

```json
"background": {
  "type": "desktop",
  "screen": "main"
}
```

This is the default.

---

## Main

Use wallpaper from:

```text
NSScreen.main
```

This is deterministic and works well for window and area screenshots where the source file itself does not reliably tell us which physical screen it came from.

---

## Specific Display

Allow selection using a stable display identifier.

Example:

```json
"background": {
  "type": "desktop",
  "screen": "specific",
  "display": "DISPLAY_IDENTIFIER"
}
```

Useful for multi-monitor setups with different wallpapers.

---

## Best Match

For full-display screenshots:

```text
screenshot dimensions
        ↓
compare against attached display pixel dimensions
        ↓
matching display found
        ↓
use that display's wallpaper
```

For arbitrary window/region screenshots there may be insufficient information to reliably determine the original display.

In that case:

```text
bestMatch
   ↓
cannot determine
   ↓
main display wallpaper
```

Never make an unreliable guess merely because aspect ratios look similar.

---

# 24. Dynamic Wallpapers

macOS wallpapers may be:

```text
static
dynamic HEIC
time-based
appearance-dependent
animated/video-based
```

The public desktop-image API gives `shotd` the configured desktop-image resource.

The daemon should use that resource when it can be decoded as an image.

For dynamic HEIC wallpapers, ImageIO may resolve an appropriate still representation.

However, `shotd` must not promise that the image obtained from the wallpaper resource is necessarily the exact currently displayed frame of every animated/time-varying macOS wallpaper implementation.

Fallback:

```text
desktop wallpaper cannot produce usable static frame
        ↓
configured fallback background
```

Example:

```json
"background": {
  "type": "desktop",

  "fallback": {
    "type": "solid",
    "color": "#1E1E1E"
  }
}
```

---

# 25. Custom Background Image

Custom backgrounds support any safely decodable image format.

Example:

```json
"background": {
  "type": "image",
  "path": "~/Pictures/background.heic",
  "fit": "cover",
  "position": "center"
}
```

Potential inputs include:

```text
PNG
JPEG
HEIC
WebP
TIFF
```

The background is decoded once and cached.

If the background file changes:

```text
invalidate cache
↓
decode new background
```

No daemon restart required.

---

# 26. Background Scaling

Default:

```text
cover
```

Equivalent conceptually to:

```css
background-size: cover;
background-position: center;
```

Algorithm:

```text
source background aspect ratio
        ↓
target canvas aspect ratio
        ↓
proportional scale
        ↓
fill complete canvas
        ↓
crop only overflow
```

Never stretch the background.

Supported modes:

```text
cover
contain
stretch
```

Recommended default:

```text
cover
```

---

# 27. Solid and Gradient Backgrounds

Solid example:

```json
"background": {
  "type": "solid",
  "color": "#17191F"
}
```

Gradient example:

```json
"background": {
  "type": "gradient",
  "angle": 135,
  "colors": [
    "#7F7FD5",
    "#86A8E7",
    "#91EAE4"
  ]
}
```

Render using CoreGraphics/CoreImage.

No external asset required.

---

# 28. Adaptive Layout Requirement

The same background algorithm must work correctly for:

```text
application window
browser window
terminal
small dialog
full display
tiny crop
wide crop
portrait crop
square crop
```

Never assume:

```text
16:9
```

or any other fixed source ratio.

---

# 29. Media Geometry

For every image determine:

```text
width
height
aspect ratio
alpha
orientation
pixel density where relevant
```

Calculate:

```text
ratio = width / height
```

The layout engine should operate on actual source geometry.

---

# 30. Ratio Classes

Use layout classes for presentation decisions:

```text
portrait
near-square
landscape
wide
ultra-wide
```

Approximate classification:

```text
ratio < 0.80
portrait

0.80–1.25
near-square

1.25–1.80
landscape

1.80–2.50
wide

> 2.50
ultra-wide
```

These are layout hints, not forced output ratios.

---

# 31. Adaptive Padding

Never apply exactly the same pixel padding to a 500 × 300 capture and a 6000 × 3500 capture.

Base calculation:

```text
baseDimension = min(width, height)

padding =
    baseDimension × paddingPercent
```

Then clamp:

```text
minimumPadding
maximumPadding
```

Example:

```text
paddingPercent = 0.07
minimumPadding = 40
maximumPadding = 160
```

Thus:

```text
small window
→ ~40px

normal window
→ ~60–90px

large Retina screenshot
→ ~120–160px
```

---

# 32. Extreme Aspect Ratios

For something such as:

```text
1800 × 280
```

equal padding on every side can look visually poor.

The layout engine may separately calculate:

```text
horizontalPadding
verticalPadding
```

while maintaining the configured visual padding ratio.

Example:

```text
very wide screenshot

horizontal padding = 100
vertical padding   = 55
```

The goal is visual balance rather than rigid pixel equality.

---

# 33. Adaptive Canvas

Normal calculation:

```text
canvasWidth =
    renderedWidth
    + leftPadding
    + rightPadding

canvasHeight =
    renderedHeight
    + topPadding
    + bottomPadding
```

The screenshot remains centered.

Example:

```text
source:
1400 × 900

padding:
75

output:
1550 × 1050
```

No stretching occurs.

---

# 34. Full-Screen Captures

Full-screen Retina screenshots can already be extremely large.

Therefore padding is capped.

Example:

```text
source:
3456 × 2234

7% theoretical padding:
156px

maximum configured:
150px

actual:
150px
```

This prevents output dimensions from becoming unnecessarily huge.

---

# 35. Window Screenshots

Window screenshots are the primary workflow.

Apple may already provide:

```text
window transparency
rounded window shape
native shadow
```

These must be preserved.

Do not flatten the source before composition.

Correct:

```text
background canvas
        ↓
draw source PNG including alpha
```

Do not unnecessarily add:

```text
second shadow
second rounded mask
```

around a window screenshot that already contains those effects.

---

# 36. Region Screenshots

Area captures usually contain an opaque rectangular image.

For these, apply configured presentation styling:

```text
adaptive corner radius
shadow
background
padding
```

The decision should be based primarily on image geometry and edge alpha rather than fragile filename heuristics.

---

# 37. Alpha-Aware Styling

Inspect source alpha.

If meaningful transparency exists around the screenshot:

```text
assume source may already provide visual shape
```

Preserve it.

If source is completely opaque:

```text
presentation corner radius
+
presentation shadow
```

may be applied.

This automatically handles most distinction between native window screenshots and region screenshots.

---

# 38. Rendering Pipeline

```text
source
  ↓
ImageIO decode
  ↓
CGImage
  ↓
inspect geometry
  ↓
resolve background
  ↓
calculate canvas
  ↓
create CGContext
  ↓
render background
  ↓
render shadow if needed
  ↓
render source preserving alpha
  ↓
obtain final CGImage
  ↓
EncoderRegistry
```

Rendering and encoding remain separate.

---

# 39. Lossless Means Lossless

Formats labelled:

```text
lossless
```

must be tested by decoding their encoded result.

Test:

```text
original rendered pixel buffer
        ↓
encode
        ↓
decode
        ↓
pixel comparison
```

For RGB + alpha output:

```text
difference = 0
```

must hold where the format claims exact losslessness.

Do not label:

```text
quality = 100
```

as lossless unless the codec actually guarantees it.

---

# 40. Color Management

Screenshots can contain different color profiles.

Preserve:

```text
color space
ICC/profile information where appropriate
alpha
```

Internal rendering should use a consistent color-managed pipeline.

Default presentation output should target a broadly compatible color space such as:

```text
sRGB
```

unless configured otherwise.

Avoid accidental color shifts between:

```text
original screenshot
processed PNG
processed WebP
processed AVIF
```

Golden tests should include color-sensitive fixtures.

---

# 41. Image Size Limits

Do not arbitrarily resize screenshots.

Default:

```text
keep original content pixel resolution
```

If resulting dimensions exceed a configurable safety threshold:

```text
maximumDimension
```

downscale proportionally.

Never upscale.

Example:

```json
"image": {
  "maximumDimension": 10000
}
```

---

# 42. Video Processing

Native recordings are processed with:

```text
AVFoundation
CoreMedia
CoreVideo
VideoToolbox
```

Pipeline:

```text
MOV/MP4
   ↓
inspect
   ↓
layout
   ↓
background
   ↓
frame composition
   ↓
hardware encoding
   ↓
final video
```

Preserve:

```text
duration
frame rate
audio
orientation
```

---

# 43. Video Background

Video uses the same `BackgroundResolver`.

Therefore:

```text
background = desktop
```

also works for video.

The wallpaper/background should be resolved once when video processing begins.

Do not re-query the wallpaper for every frame.

---

# 44. Video Compression

Supported video output:

```text
H.264
HEVC
```

Default:

```text
H.264 MP4
```

for compatibility.

HEVC can be selected when smaller output matters.

Video compression configuration is independent from still-image output configuration.

---

# 45. File Detection

Watch:

```text
~/Pictures/shotd/inbox
```

using native event-driven APIs.

Use:

```text
DispatchSourceFileSystemObject
```

for the simple single-directory use case.

No:

```text
while true
sleep 1
scan directory
```

polling loop.

---

# 46. File Stabilization

A filesystem event does not mean the source is ready.

Use:

```text
event
 ↓
size + mtime
 ↓
debounce
 ↓
size + mtime
 ↓
stable?
 ↓
attempt decode/open
 ↓
ready
```

This is particularly important for recordings.

---

# 47. Apple Markup

If a screenshot changes after initial capture because the user uses Apple's Markup:

```text
mtime changes
      ↓
stabilize again
      ↓
re-render
      ↓
replace processed output
      ↓
refresh clipboard
      ↓
re-upload
```

Thus Apple's annotation tools continue to work naturally.

---

# 48. Event Deduplication

Track:

```text
path
size
mtime
inode where useful
state
```

A duplicate event with identical stable state does nothing.

A genuine new stable source version causes reprocessing.

---

# 49. Atomic Output

Never encode directly into the final filename.

Use:

```text
.output.UUID.tmp
        ↓
complete encoding
        ↓
validate
        ↓
fsync where appropriate
        ↓
atomic rename
```

This applies to:

```text
PNG
WebP
AVIF
HEIC
JPEG
MP4
MOV
```

---

# 50. Clipboard

For screenshots, publish:

```text
native image representation
PNG representation
final local file URL
```

The user should be able to:

```text
capture
↓
⌘V
```

without caring that disk output may actually be WebP or AVIF.

For video, clipboard should normally publish:

```text
local file URL
```

and, once upload succeeds:

```text
remote URL
```

according to configuration.

---

# 51. S3 Storage

Storage implementation must be provider-neutral.

Required support:

```text
Amazon S3
Cloudflare R2
MinIO
Backblaze B2 S3
Wasabi
DigitalOcean Spaces
Ceph RGW
Garage
custom S3 implementations
```

Configuration controls:

```text
endpoint
region
bucket
access key identity
path style
virtual-host style
TLS
object prefix
public base URL
presigned URL
```

No AWS-only assumptions.

---

# 52. S3 Implementation

Use:

```text
URLSession
CryptoKit
```

Implement AWS Signature V4.

Operations:

```text
PUT Object
HEAD Object
DELETE Object

CreateMultipartUpload
UploadPart
CompleteMultipartUpload
AbortMultipartUpload
```

Still images will normally use:

```text
PUT Object
```

Large videos use multipart upload.

---

# 53. S3 Credentials

Secrets must not appear in:

```text
config.json
```

Store:

```text
access key
secret key
session token
```

using macOS Keychain through:

```text
Security.framework
```

Configuration refers to:

```json
"credential": "primary"
```

CLI:

```bash
shotd storage set-credentials primary
```

---

# 54. Upload Behavior

Local rendering never depends on cloud availability.

Correct flow:

```text
render
 ↓
local save
 ↓
clipboard image available
 ↓
S3 upload
```

If S3 is offline:

```text
local media remains valid
        ↓
upload enters retry queue
```

Network failure must never destroy a screenshot.

---

# 55. Upload Retry

Use bounded exponential backoff:

```text
1s
2s
4s
8s
16s
...
```

Persist pending uploads to lightweight local state so daemon restart does not lose them.

---

# 56. Object Naming

Example:

```text
screenshots/2026/09/
3f51aa-Screenshot-2026-09-15.webp
```

Video:

```text
recordings/2026/09/
7ac921-Screen-Recording-2026-09-15.mp4
```

Never expose local absolute paths.

---

# 57. Public URLs

Support:

```text
publicBaseURL
```

Example:

```json
"publicBaseURL": "https://media.example.com"
```

Object:

```text
screenshots/2026/09/abc.webp
```

becomes:

```text
https://media.example.com/screenshots/2026/09/abc.webp
```

For private buckets, generate SigV4 presigned GET URLs.

---

# 58. Configuration

Location:

```text
~/Library/Application Support/shotd/config.json
```

Use Swift `Codable`.

No YAML/TOML dependency required.

---

# 59. Complete Configuration Example

```json
{
  "version": 1,

  "watch": {
    "directory": "~/Pictures/shotd/inbox"
  },

  "source": {
    "retention": "keep"
  },

  "output": {
    "directory": "~/Pictures/shotd/output"
  },

  "background": {
    "type": "desktop",
    "screen": "main",
    "fit": "cover",
    "position": "center",

    "fallback": {
      "type": "solid",
      "color": "#17191F"
    }
  },

  "layout": {
    "paddingPercent": 0.07,
    "minimumPadding": 40,
    "maximumPadding": 160,
    "alignment": "center"
  },

  "style": {
    "adaptiveCornerRadius": true,

    "shadow": {
      "enabled": true,
      "adaptive": true,
      "opacity": 0.22
    }
  },

  "image": {
    "format": "webp",
    "compression": "lossless",
    "fallbackFormat": "png",
    "maximumDimension": 10000,
    "colorSpace": "sRGB"
  },

  "video": {
    "format": "mp4",
    "codec": "h264",
    "preserveFrameRate": true,
    "preserveAudio": true
  },

  "clipboard": {
    "image": "image",
    "video": "url"
  },

  "storage": {
    "endpoint": "https://s3.example.com",
    "region": "auto",
    "bucket": "shotd",
    "credential": "primary",

    "addressing": "auto",

    "publicBaseURL": "https://media.example.com",

    "paths": {
      "images": "screenshots",
      "videos": "recordings"
    },

    "multipartThresholdMB": 100,
    "multipartPartSizeMB": 16
  }
}
```

---

# 60. Custom-Background Configuration Example

Switching from desktop wallpaper to a custom image should require only:

```json
"background": {
  "type": "image",
  "path": "~/Pictures/shotd/backgrounds/background.heic",
  "fit": "cover",
  "position": "center"
}
```

No restart.

---

# 61. AVIF Configuration Example

```json
"image": {
  "format": "avif",
  "compression": "lossless",
  "fallbackFormat": "png"
}
```

Lossy:

```json
"image": {
  "format": "avif",
  "compression": "lossy",
  "quality": 85
}
```

---

# 62. PNG Configuration Example

```json
"image": {
  "format": "png"
}
```

This is the maximum-compatibility lossless configuration.

---

# 63. Configuration Reload

Watch `config.json`.

Flow:

```text
file changes
    ↓
decode new config
    ↓
validate
    ↓
valid?
 │       │
yes      no
 │       │
swap    log error
config  retain old config
```

Never stop a functioning daemon because a new configuration contains a typo.

---

# 64. CLI

```bash
shotd install
shotd uninstall

shotd start
shotd stop
shotd restart
shotd status

shotd run

shotd process <file>

shotd config path
shotd config validate

shotd storage set-credentials <name>
shotd storage test

shotd codecs
shotd doctor
```

---

# 65. `shotd codecs`

Useful because codec availability is important.

Example:

```text
$ shotd codecs

Image encoders

PNG
  available: yes
  lossless: yes
  backend: ImageIO

WebP
  available: yes
  lossless: yes
  backend: bundled libwebp

AVIF
  available: yes
  lossless: yes
  backend: bundled libavif

HEIC
  available: yes
  backend: ImageIO

JPEG
  available: yes
  backend: ImageIO
```

---

# 66. `shotd doctor`

Example:

```text
$ shotd doctor

shotd diagnostics

✓ Configuration valid
✓ Screenshot inbox exists
✓ Output directory writable

Background
✓ Desktop wallpaper resolved
✓ Wallpaper image readable

Codecs
✓ PNG
✓ WebP
✓ AVIF
✓ HEIC
✓ JPEG

Runtime
✓ LaunchAgent installed
✓ Daemon running
✓ Clipboard available

Storage
✓ Credential present
✓ S3 endpoint reachable
✓ Authentication valid
✓ Bucket writable
✓ Temporary upload/delete successful

Everything looks good.
```

---

# 67. LaunchAgent

Install:

```text
~/Library/LaunchAgents/io.shotd.plist
```

Use:

```text
RunAtLoad = true
KeepAlive = true
```

The executable does not fork or daemonize itself.

`launchd` owns its lifecycle.

---

# 68. Resource Model

Idle:

```text
CPU ≈ 0
network = 0
disk = 0
```

No polling.

No periodic cloud activity.

No analytics.

No telemetry.

Memory should remain small and stable.

Large backgrounds should be cached intelligently rather than decoded on every screenshot.

Large videos should stream from disk.

---

# 69. Background Cache

Cache the resolved background using an identity such as:

```text
path
mtime
target characteristics
```

For desktop wallpaper:

```text
wallpaper URL
mtime
display
```

If unchanged:

```text
reuse decoded image
```

If wallpaper changes:

```text
invalidate
↓
decode replacement
```

This keeps repeated screenshot processing fast.

---

# 70. Concurrency

Use bounded queues.

```text
image processing:
1

video processing:
1

uploads:
2–3
```

Screenshot latency has priority over video encoding.

If a long video is encoding and a new screenshot arrives, the screenshot should not have to wait for the entire video job to finish.

---

# 71. Complete Screenshot Flow

```text
User presses ⌘⇧4
        ↓
Apple captures window
        ↓
source appears in inbox
        ↓
shotd detects event
        ↓
wait until stable
        ↓
decode source
        ↓
inspect:
    dimensions
    aspect ratio
    alpha
        ↓
resolve background:
    current desktop wallpaper
    OR custom image
    OR solid
    OR gradient
        ↓
calculate:
    adaptive canvas
    adaptive padding
    placement
    shadow/radius behavior
        ↓
render final CGImage
        ↓
selected encoder:
    PNG
    WebP
    AVIF
    HEIC
    JPEG
        ↓
atomic local output
        ↓
publish compatible image to clipboard
        ↓
upload encoded file to S3
        ↓
construct public/presigned URL
        ↓
done
```

---

# 72. Example Window Screenshot

Input:

```text
1380 × 890
PNG with alpha
```

Current desktop wallpaper:

```text
6016 × 6016 HEIC
```

Layout engine determines:

```text
landscape
padding = 62px
source already has alpha/window shadow
do not add duplicate clipping
```

Canvas:

```text
1504 × 1014
```

Background:

```text
desktop image
scaled using cover
center cropped
```

Output configuration:

```text
WebP lossless
```

Final:

```text
Screenshot....webp
```

Clipboard:

```text
PNG/native image representation
```

S3:

```text
image/webp
```

---

# 73. Example Wide Area Capture

Input:

```text
2200 × 380
```

Classification:

```text
ultra-wide
```

Layout:

```text
horizontal padding = 100
vertical padding = 52
```

Output:

```text
2400 × 484
```

The original remains:

```text
2200 × 380
```

inside the canvas.

It is never forced to 16:9.

---

# 74. Example Portrait Capture

Input:

```text
620 × 1400
```

Classification:

```text
portrait
```

The canvas grows around the source:

```text
adaptive left/right padding
adaptive top/bottom padding
```

The background is cropped according to the final portrait canvas.

The screenshot remains portrait.

No landscape template is imposed.

---

# 75. Complete Recording Flow

```text
⌘⇧5
record
stop
    ↓
MOV finalizes
    ↓
shotd detects stable video
    ↓
AVFoundation inspection
    ↓
adaptive canvas
    ↓
resolve background
    ↓
AVFoundation composition
    ↓
preserve audio
    ↓
preserve frame rate
    ↓
VideoToolbox encoding
    ↓
atomic MP4/MOV
    ↓
local file
    ↓
S3 multipart upload if necessary
    ↓
URL
    ↓
clipboard
```

---

# 76. Testing Requirements

Test geometry using:

```text
16:9
16:10
4:3
3:2
1:1
9:16
3:4
21:9
extreme wide
extreme tall
```

Test source styles:

```text
native window PNG with alpha
opaque region
fullscreen screenshot
small dialog
Retina capture
```

Test backgrounds:

```text
desktop wallpaper
different monitor wallpaper
portrait custom image
landscape custom image
square image
HEIC wallpaper
solid
gradient
```

Test encoders:

```text
PNG
WebP lossless
WebP lossy
AVIF lossless
AVIF lossy
HEIC
JPEG
```

---

# 77. Lossless Codec Validation

For every lossless codec fixture:

```text
render canonical image
       ↓
encode
       ↓
decode
       ↓
pixel compare
```

Tests must cover:

```text
RGB
RGBA
text
thin lines
gradients
transparency
shadows
```

This prevents regressions where an encoder accidentally switches into lossy mode.

---

# 78. Visual Regression Testing

Maintain golden outputs:

```text
Tests/Golden/
├── window-desktop.webp
├── window-custom.webp
├── region-wide.webp
├── region-portrait.webp
├── fullscreen.webp
└── square.webp
```

Rendering changes should be visually compared to known output.

This is especially important for an AI-developed project.

---

# 79. S3 Compatibility Tests

Use MinIO locally for automated S3 tests.

Verify:

```text
SigV4
PUT
HEAD
DELETE
multipart
presigned GET
custom endpoint
path style
virtual host style
metadata
Content-Type
```

The implementation must remain compatible with non-AWS providers.

---

# 80. Reliability Requirements

Test:

```text
partially written screenshot
duplicate event
source modified twice
Markup edit
source deleted
invalid image
invalid video
missing wallpaper
dynamic wallpaper failure
missing custom background
unsupported codec
output disk full
S3 offline
S3 403
S3 500
network disconnect
daemon restart during upload
configuration changed during processing
```

One job failure must never stop the watcher.

---

# 81. Dependency Policy

Prefer Apple frameworks:

```text
Foundation
Dispatch
AppKit
CoreGraphics
CoreImage
ImageIO
UniformTypeIdentifiers
AVFoundation
CoreMedia
CoreVideo
VideoToolbox
Security
CryptoKit
OSLog
```

External codec code is restricted to:

```text
WebP encoder
AVIF encoder
```

No large general-purpose dependency should be introduced.

---

# 82. Complete Build Order

Everything is delivered together, but implementation should proceed in dependency order:

```text
1. Swift package and CLI

2. configuration model

3. image/media inspection

4. desktop wallpaper resolver

5. custom background resolver

6. adaptive layout engine

7. CoreGraphics renderer

8. native ImageIO encoders

9. WebP codec

10. AVIF codec

11. lossless verification tests

12. clipboard

13. video compositor

14. video encoder

15. S3 SigV4

16. multipart S3

17. Keychain

18. directory watcher

19. stabilization

20. deduplication

21. upload retry persistence

22. LaunchAgent

23. installer

24. status / doctor / codecs

25. complete automated tests

26. end-to-end validation
```

This is one implementation effort and one complete product target.

---

# 83. Definition of Done

`shotd` is complete when the following experience works reliably:

```text
Set configuration once.

Take screenshot using Apple.

Done.
```

For screenshots:

```text
window
region
fullscreen
portrait
landscape
wide
square
```

must all receive a visually balanced background without distortion.

The configured background can be:

```text
current desktop wallpaper
custom image
solid color
gradient
```

The output can be:

```text
PNG
WebP lossless
WebP
AVIF lossless
AVIF
HEIC
JPEG
preserve source
```

The original source remains safe.

The processed result reaches:

```text
local disk
clipboard
S3-compatible storage
```

automatically.

Recordings receive the same presentation treatment and upload workflow.

The daemon starts at login, consumes effectively no CPU while idle, and requires no persistent graphical application.

---

# 84. Final Product Principle

`shotd` should never become an editor.

It should never compete with Apple's screenshot UI.

It should never ask the user to perform work that can be derived automatically from the source media and configuration.

Apple owns:

```text
capture
selection
recording
annotation
permissions
```

`shotd` owns:

```text
background resolution
adaptive presentation
compression
format conversion
clipboard
storage
delivery
```

The end state is:

```text
CAPTURE
   ↓
DONE
```

The daemon should become something the user eventually forgets is running.

---

# 85. Distribution And Updates

`shotd` is distributed as a Developer ID-signed, notarized Apple-silicon (`arm64`) release archive. Versions use the immutable calendar tag format:

```text
vYYYY.MM.DD
```

The installer runs only for the logged-in GUI user. It downloads the matching architecture, verifies `SHA256SUMS` and the code signature, then stages and atomically replaces:

```text
~/Library/Application Support/shotd/bin/shotd
```

If `config.json` is absent, it starts the minimal `shotd setup` onboarding flow. If it exists, installation is an upgrade and preserves configuration, state, Keychain credentials, logs, imported backgrounds, and output files.

`shotd update --check` reports the latest GitHub Release. `shotd update` verifies the archive checksum and requires the downloaded binary to have the same Developer ID team as the installed binary before it replaces anything.

No installer or updater may use `sudo`, change a shell profile, write a system-wide binary path, or install a LaunchDaemon.
