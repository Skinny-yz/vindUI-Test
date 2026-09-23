# Callback error handler

Base: Skinny-yz/vindUI-Test @ 30f6dea63f5f8097dff350760d44f2c5c81bb011

Replace core.luau and full.luau in your repository. example.luau includes the supplied example plus a Callback Handler tab with intentional errors, triggered only by interaction. Its existing GitHub URL will use this change only after full.luau is uploaded there.

Core element callbacks and OnChanged listeners now run in protected asynchronous tasks. Failures show a red Callback Error notification for five seconds, with the error message; the full traceback is written to the console. Arguments (including nils) and yielding are preserved. One failed listener does not prevent others from running. Silent updates remain silent.

Covers buttons, button groups, cards, toggles, sliders, dropdowns, textboxes, color pickers, keybinds, ratings, new value controls, notification actions, confirmations/modals, dock buttons, tab events and grid actions in core. Optional integration module callbacks and errors in separate tasks created inside a user callback are outside this handler. The existing notification appearance is reused; element titles are not changed to Callback Error.

Validation: all Luau files compile; callback regressions pass for core and full; scale tests pass. The pre-existing smoke test fails on both the original and modified core. Live Roblox rendering was not tested. Run callback checks with node tests/callbacks.mjs after npm install.

The original integrations bundle is preserved. Existing module source files differ from their checked-in bundle; rebuilding all bundles with build.mjs would also introduce unrelated integration changes.
