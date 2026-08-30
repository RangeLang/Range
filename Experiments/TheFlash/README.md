# The Flash synthetic capture experiment

This isolated experiment tests a narrow question: given a known HDR environment,
an equirectangular 360 camera, and a synchronized
`OFF / W / R / G / B / C / Y / M / W / OFF` sequence, can direct linear-HDR
ambient subtraction isolate an active-light response that carries material information?

It uses the CC0 `studio_small_01` HDRI from Poly Haven and a simplified GGX
metallic-sphere renderer. Every shutter state is captured as a complete 360° ×
180° equirectangular HDRI. The ambient illumination is deliberately changed
slightly between the opening and closing OFF HDRIs, then interpolated for each
flash observation.

The synthetic flash colors are normalized to equal integrated incident energy:
primaries use one unit, complementary colors split that unit across two emitters,
and white splits it across three. Hardware must replace these ideal RGB vectors
with measured LED spectral power distributions and calibrated per-emitter drive.

The capture contract is HDRI-native. Each stationary burst writes ten Radiance RGBE files:
`ambient_before.hdr`, eight `flash_*.hdr` observations, and
`ambient_after.hdr`. Analysis reloads those files, interpolates the two ambient
HDRs in linear radiance space, subtracts them from each flash HDR, and writes
eight derived `isolated_*.hdr` responses. PNGs exist only as display previews.

A single HDRI burst sees every direction around the camera, but it cannot see the
back of an opaque object. Object-complete capture would therefore use multiple
registered device poses, with a complete HDRI burst at each pose.

Run with the bundled workspace Python:

```sh
/Users/george/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 \
  /Users/george/Documents/Range/Experiments/TheFlash/render_experiment.py
```

The `output_hdri` directory contains:

- `captures/burst_00/`: ten source HDRIs and eight derived linear HDRIs.
- `hdri_burst_contact_sheet.png`: all ten panoramic source states.
- `isolated_hdri_sequence.png`: all eight panoramic difference HDRIs.
- `selected_material_responses.png`: cropped responses inside the tracked surface mask.
- `selected_surface_mask.png`: the target region in equirectangular coordinates.
- `summary.json`: fitted material values, errors, and explicit limitations.

This proves only a synthetic inverse-rendering boundary. It does not prove that
roughness, metallic character, polarization, and local illumination are jointly
recoverable from real 360-camera hardware without additional calibration and observations.
