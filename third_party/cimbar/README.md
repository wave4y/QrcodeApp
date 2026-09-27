# Cimbar offline runtime

- Upstream: https://github.com/sz3/libcimbar
- Release: v0.6.8 (official release archive `cimbar.wasm.tar.gz`).
- Download: https://github.com/sz3/libcimbar/releases/download/v0.6.8/cimbar.wasm.tar.gz
- Source: https://github.com/sz3/libcimbar/tree/v0.6.8
- The release's JS/WASM filenames contain the upstream build stamp `2026-08-21T2336`.
- `dist/` retains the original release contents. The JS loader and WASM are copied unchanged into `android/app/src/main/assets/cimbar/`.
- `app.js`, `decoder-worker.js`, `index.html`, and `app.css` are this app's integration, not upstream files. They implement the Chinese phone UI, persistent pause, Android file picker/save bridge, bounded camera backpressure, tightly packed VideoFrame planes, decoded-file size bounds, and a CMBAPP01 integrity/entropy envelope stripped before saving. The envelope is specific to this app; see docs/cimbar.md for external Cimbar compatibility.
- Runtime: Cimbar B (68), Wirehair fountain coding, Reed–Solomon per-frame correction, zstd level 3. Ordinary QR/RaptorQ compatibility modes remain separate.
- MPL-2.0 license and dependency notices are bundled in the APK under `assets/cimbar/`. OpenCV 4.12.0 and Emscripten 5.0.0 match the upstream release workflow. No upstream source files were modified.

The virtual HTTPS origin serves only bundled assets and a user-selected local file. Other resource requests are rejected; the app does not load cimbar.org or require a network connection. Android's INTERNET permission is present for WebView's virtual HTTPS origin, not for uploading files.
