# Error codes

This page lists the stable error codes of OpenJoystickDriver (OJD), with the meaning of each code.

## How codes work

Each code has the form `E` and four digits. The first digit gives the area:

- `E1xxx` is the endpoint. A client of the endpoint gets the code in the `code` field of an `error` line.
- `E2xxx` is the command line.
- `E3xxx` is remapping.

A code never changes its meaning. When OJD stops using a code, the code is retired. OJD never gives a retired code to a different error.

Branch on the code in your program. The English message that comes with a code can change.

## Codes

The table is generated from the code catalog and the English text of OJD. The table lists every code, and marks a retired code.

<!-- BEGIN GENERATED: error-codes -->
| Code | Area | Meaning |
| --- | --- | --- |
| E1001 | Endpoint | The endpoint is off. Turn it on with 'ojd access enable' and connect again. |
| E1002 | Endpoint | The service refused this client. It has no grant for the scopes it asked for, or its signature or proof is not valid. Run 'ojd access list', grant the client with 'ojd access grant', and connect again. |
| E1003 | Endpoint | The service does not speak the protocol version in hello. Send one of the versions in supported, and connect again. |
| E1004 | Endpoint | The service could not accept the line. It is not valid, or it came at the wrong time. Send hello first, then one request, and check each line against the endpoint schema. |
| E1005 | Endpoint | The endpoint already serves 8 connections. Close a connection that you do not need, and connect again. |
| E1006 | Endpoint | The grant of this client was removed while it was connected. Grant it again with 'ojd access grant', and connect again. |
| E1007 | Endpoint | The client read lines too slowly, and 256 lines waited. Read lines as fast as they arrive, and connect again. |
| E1008 | Endpoint | The service already runs 4 virtual gamepads. Close a feed that you do not need, and send feed again. |
| E1009 | Endpoint | The virtual gamepad closed, or the service runs none. Connect again and send feed. |
<!-- END GENERATED: error-codes -->

## Further reading

- [Automating OpenJoystickDriver](Automating-OpenJoystickDriver.md#read-the-endpoint)
- [Troubleshooting](Troubleshooting.md)
