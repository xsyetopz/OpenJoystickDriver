# Application responsiveness

The signed application host and headless commands must not wait indefinitely
for system tools, login registration, permission APIs, or live-runtime calls.

- System commands use `BoundedProcessRunner` off the main actor.
- Headless live-state calls use framed local RPC with connect, send, and receive deadlines.
- Permission requests await the dedicated `PermissionManager` actor and never run a shell command or poll System Settings.
- System-extension and signing checks return explicit timeout or failure states.
- The host keeps its runtime on the main dispatch queue and exits through the runtime's retained signal handlers.

A missing runtime or stalled system tool may produce an error, but it must not
freeze the host shutdown path or any CLI invocation.
