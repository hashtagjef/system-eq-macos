# System EQ

A native macOS system-wide equalizer built with SwiftUI and Core Audio process taps.

## Requirements

- macOS 14.2 or later
- Xcode 16 or later

## Build and run

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open "build/System EQ.app"
```

The first time you turn the EQ on, macOS asks for System Audio Recording permission. If the app was denied, enable it in **System Settings > Privacy & Security > Screen & System Audio Recording** and relaunch the app.

Turning the EQ off destroys the private Core Audio tap and restores the normal audio route.

Use the save button beside the preset picker to store the current curve, preamp, and automatic-headroom setting. Saved presets remain available after relaunching the app; saving with an existing name updates that preset.

Edit the frequency field directly below any slider and use the adjacent filter control to choose a bell, shelf, pass, notch, or band-pass response. Frequencies may be entered in hertz or in compact form such as `1.5k`. Custom band settings are included in saved presets.

Each band also has an editable Q value from 0.1 to 20. Q values are processed live and stored with presets.

Use the level-meter button beside the preset controls to show or hide live RMS and peak output levels for every EQ band. Each meter follows its band's editable center frequency, and analysis runs only while the meters are visible and System EQ is processing audio.

Use the band-count stepper above the EQ to add bands or remove the rightmost band. The EQ strip scrolls horizontally beyond ten bands, and custom presets restore their saved band count.
