# Menu responsiveness

The menu UI must not wait indefinitely for system tools, login registration, permission APIs, or live-runtime calls.

- System commands use `BoundedProcessRunner` off the main actor.
- Headless live-state calls use framed local RPC with connect, send, and receive deadlines.
- Permission requests await the dedicated `PermissionManager` actor and never run a shell command or poll System Settings.
- Permission state is refreshed from `IOHIDCheckAccess`; request API return values are not treated as grants.
- Hidden diagnostic views do not continuously format packet logs.
- Browser, system-extension, and signing checks return explicit timeout or failure states.

A missing runtime or stalled system tool may produce an error, but it must not freeze popover dismissal or app quitting.
