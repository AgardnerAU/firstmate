# Live run: fm-bearings-board.sh build against real lavish-axi 0.1.78

Setup: a disposable lab FM_HOME (bin/fm-lab-home.sh create). A private Lavish server with LAVISH_AXI_STATE_DIR=<lab>/lavish-state and LAVISH_AXI_PORT=4799. A PATH shim for macOS `open`, which the lavish-axi `open` npm dependency calls to launch a browser window. The shim logs each launch URL and does not open a window. A real Chromium page (Playwright) stayed connected to the session URL as the captain's review window.

| Step | Board build | Browser windows launched | Session outcome |
|---|---|---|---|
| 1 | First build (no session yet) | 1 | session: live, armed |
| 2 | Rebuild with changed payload, window connected | 0 | session: live, already-armed; the connected window moved from artifact_revision=1 to 2 and shows "REBUILT: ..." (same JS window marker) |
| 3a | Rebuild again (session open) | 0 | session: live |
| 3b | `lavish-axi end` (agent ends session) | 0 | status: ended |
| 3c | Rebuild after agent end | 1 | session: live, armed |
| (extra) | Rebuild while session open (Send & End needed a message first) | 0 | session: live |
| 4 | Captain clicks Send & End in browser, then rebuild | 1 (only the --reopen call; the plain call returned user-ended) | session: reopened, armed |
| BASELINE | base commit dbe124d, rebuild of already-open session | **1** (the bug) | session: live |
| AFTER | target a21283f, rebuild of same open session | **0** | session: live |

Lavish session listing after step 4 Send & End: `sessions: []` (the old session was ended by the captain, not by the build). The build never ended a session.
