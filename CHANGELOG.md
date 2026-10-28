## 0.3.0

- The panel's own window is started at most once at a time. One that does not answer on the socket
  within a few seconds is ended, and the panel stays beside the window and says so.
- `panel-window.json` notes the panel as detached only once its window answers.
- A walk put away starts shown again when the app starts again.
- Window processes the walk started end with the app.
- The field to write in keeps four lines however long a step is; `commentLines` on `WalkFrame`,
  `WalkWindowApp` and `WalkPanel` sets another number.
- **Breaking:** `WalkWindowHost.start` returns the `Process` it started, or null.

## 0.2.0

Initial code commit
