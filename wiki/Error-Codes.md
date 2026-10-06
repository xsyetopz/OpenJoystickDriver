# Error codes

This page lists the stable error codes of OpenJoystickDriver (OJD), with the meaning of each code.

## How codes work

Each code has the form `E` and four digits. The first digit gives the area:

- `E1xxx` is the endpoint. A client of the endpoint gets the code in the `code` field of an `error` line.
- `E2xxx` is the command line.
- `E3xxx` is remapping.

A code never changes its meaning. When OJD stops using a code, the code is retired. OJD never gives a retired code to a different error.

To look up a code offline, run `ojd explain E####`.
It lists active codes, and this page also lists retired ones.

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
| E1005 | Endpoint | The endpoint already serves 8 connections per transport (socket and WebSocket each). Close a connection that you do not need, and connect again. |
| E1006 | Endpoint | The grant of this client was removed while it was connected. Grant it again with 'ojd access grant', and connect again. |
| E1007 | Endpoint | The client read lines too slowly, and 256 lines waited. Read lines as fast as they arrive, and connect again. |
| E1008 | Endpoint | The service already runs 4 virtual gamepads. Close a feed that you do not need, and send feed again. |
| E1009 | Endpoint | The virtual gamepad closed, or the service runs none. Connect again and send feed. |
| E2001 | Command line | ojd hit an error it does not recognize. Run 'ojd diagnose' and report the problem with its output. Exit code 1. |
| E2002 | Command line | That is not an ojd command. Run 'ojd --help' to see the commands. Exit code 64. |
| E2003 | Command line | The command line has a wrong or missing option or value. Run the command with --help to see what it takes. Exit code 64. |
| E2004 | Command line | The OpenJoystickDriver service is not running. Start it with 'ojd service start'. Exit code 69. |
| E2005 | Command line | The service did not answer in time. Check it with 'ojd status', or wait longer with --timeout. Exit code 1. |
| E2006 | Command line | The service did not complete the request. Check it with 'ojd status' and try again. Exit code 1. |
| E2007 | Command line | The service rejected this ojd because it is not signed like the app. Run the ojd that ships inside OpenJoystickDriver.app. Exit code 1. |
| E2008 | Command line | A macOS permission is missing. Grant it with 'ojd permission request'. Exit code 77. |
| E2009 | Command line | This command changes or deletes data and needs confirmation. Run it again with --force. Exit code 64. |
| E2010 | Command line | The command stopped before it finished, because you declined, an editor failed, or no input came. Run it again. Exit code 1. |
| E2011 | Command line | The profile or record file is not valid. Fix it against its schema and try again. Exit code 1. |
| E2012 | Command line | No controller, profile, binding, or client matches, or more than one does. List them with the matching 'list' command and name one exactly. Exit code 1. |
| E2013 | Command line | The controller cannot do that now. It may be unsupported, not ready, or disconnected. Check it with 'ojd controller list'. Exit code 1. |
| E2014 | Command line | OpenJoystickDriver is not fully installed, or its signature is not valid. Reinstall the app and run 'ojd diagnose'. Exit code 1. |
| E2015 | Command line | macOS did not complete or apply the request. Check System Settings and try again. Exit code 1. |
| E2016 | Command line | A file could not be read, written, or deleted, or it already exists. Check the path and its permissions. Exit code 1. |
| E2017 | Command line | That client is unsigned or ad-hoc signed, so it cannot be granted access. Sign it with a Developer ID and try again. Exit code 1. |
| E2018 | Command line | 'ojd diagnose' found a failed check. Read its output and fix the failed items. Exit code 1. |
| E2019 | Command line | The update check did not finish. Check your network connection and try again. Exit code 1. |
| E2020 | Command line | The installed OpenJoystickDriver app is older than this ojd. Run './Scripts/ojd build install-fast dev', or set OJD_RUN_REPOSITORY_CLI=1 to run this build. Exit code 1. |
| E2021 | Command line | A repository build of ojd could not hand the command to the installed app. Reinstall OpenJoystickDriver.app and run the command again. Exit code 127. |
| E2022 | Command line | The state that the record's parser produced from the captured reports differs from the expected state. Read the fields that the command lists. Exit code 1. |
| E3001 | Remapping | The controller is not connected or not ready for remapping. Reconnect it and try again. Wire value `controller_unavailable`. |
| E3002 | Remapping | The selected Joy-Cons could not be paired. Refresh the connected controllers and try again. Wire value `joy_con_pair_unavailable`. |
| E3003 | Remapping | The controller does not report motion data. Choose a controller with motion sensors, or leave motion options off. Wire value `motion_unavailable`. |
| E3004 | Remapping | A value in the request is larger than the service accepts. Send a smaller value. Wire value `argument_too_large`. |
| E3005 | Remapping | The active profile list is damaged and could not be loaded. Repair or remove the damaged file, then try again. Wire value `library_corrupt`. |
| E3006 | Remapping | A profile with that name already exists. Choose another name; 'ojd profile list' shows the names in use. Wire value `duplicate_name`. |
| E3007 | Remapping | The request has missing or invalid arguments. Check the values and try again. Wire value `invalid_arguments`. |
| E3008 | Remapping | The profile is not valid. Review its assignments and try again. Wire value `invalid_profile`. |
| E3009 | Remapping | The profile library would become too large. Delete profiles you do not need and try again. Wire value `library_size_exceeded`. |
| E3010 | Remapping | A profile with that identifier already exists. Use a new identifier, or update the existing profile. Wire value `profile_already_exists`. |
| E3011 | Remapping | The profile changed elsewhere after you loaded it. Reload it and make your change again. Wire value `profile_update_conflict`. |
| E3012 | Remapping | The library already holds the most profiles it allows. Delete a profile you do not need and try again. Wire value `profile_count_exceeded`. |
| E3013 | Remapping | No profile has that identifier. List the profiles with 'ojd profile list'. Wire value `profile_not_found`. |
| E3014 | Remapping | The service could not encode its reply. Try again, and report the problem if it continues. Wire value `response_encoding_failed`. |
| E3015 | Remapping | The reply is larger than the service can send. Ask for less data and try again. Wire value `response_too_large`. |
| E3016 | Remapping | The remapping engine is not available. Wait a moment and try again, or restart the service. Wire value `router_engine_unavailable`. |
| E3017 | Remapping | The profile library and the remapping engine are not available. Wait a moment and try again, or restart the service. Wire value `router_library_and_engine_unavailable`. |
| E3018 | Remapping | The profile library is not available. Wait a moment and try again, or restart the service. Wire value `router_library_unavailable`. |
| E3019 | Remapping | The remapping router has shut down. Restart the service and try again. Wire value `router_shut_down`. |
| E3020 | Remapping | The service could not confirm whether the last profile change was saved. Reload the profiles and check them before you change them again. Wire value `transaction_unreconciled`. |
| E3021 | Remapping | A profile file could not be read. Check that the file exists and that the service can read it. Wire value `library_unreadable`. |
| E3022 | Remapping | Damaged profile files must be repaired or removed before profiles can change. Repair or remove them, then try again. Wire value `profile_recovery_required`. |
| E3023 | Remapping | A profile file could not be written. Check the free disk space and the folder permissions. Wire value `library_unwritable`. |
| E3024 | Remapping | The remapping service hit an error it does not recognize. Run 'ojd diagnose' and report the problem with its output. Wire value `unexpected`. |
| E3025 | Remapping | The profile produces no output. Add a binding or a light color to it, or activate it with --allow-empty. Wire value `profile_produces_no_output`. |
| E3026 | Remapping | The Joy-Con pair profile takes its gyro from the other Joy-Con. Calibrate the motion of the controller that the profile selects for the gyro. Wire value `motion_gyro_not_selected`. |
| E3027 | Remapping | No remapping profile is active for the controller, so it does not process motion. Activate a profile for it, bring its target app to the front, and try again. Wire value `motion_profile_inactive`. |
| E3028 | Remapping | The remapping session of the controller changed while the request ran. Try again. Wire value `motion_session_changed`. |
<!-- END GENERATED: error-codes -->

## Further reading

- [Automating OpenJoystickDriver](Automating-OpenJoystickDriver.md#read-the-endpoint)
- [Troubleshooting](Troubleshooting.md)
