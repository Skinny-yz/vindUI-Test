# Vind UI

Use example.luau to load full.luau and explore the interface. Replace core.luau and full.luau together when updating the library.

Element callbacks and OnChanged listeners report failures as Callback Error notifications. See CALLBACK-HANDLER.md for coverage and validation.

The New Elements tab and its nine dedicated components have been removed from the example and library, together with CopyConfigJSON. Existing standard controls and button groups remain available.

Optional customizable startup intro: see INTRO.md. Call VindUI:ShowIntro(options):Wait() before creating the window, or leave it out entirely.

Complete live themes: see THEMES.md. Run npm run test:ui for the checked UI regressions. Module sources and generated bundles are synchronized.
