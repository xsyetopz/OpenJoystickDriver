# Inventory of stored-document readers and writers

Task 1.1 of `0-6-0-alpha-3`, taken on branch `feat/0.6.0-alpha.3` before any code of group 1 moved.

A site is a line in `Sources/`, `Scripts/`, `Tools/`, or `Tests/` that uses `JSONDecoder`, `JSONEncoder`, `JSONSerialization`, `OrderedJSON.parse`, or the `formattedData` and `ordered` helpers (Swift), or `json.load`, `json.loads`, `json.dump`, `json.dumps` (Python). Comment lines and imports are not sites.

- `document`: a file with `apiVersion` and `kind` that OJD stores (record, patch, protocol description, catalog rules, crosswalk, error catalog, virtual device, persona, profile, settings, access grants, package manifest), or a test or script that reads, writes, or builds one.
- `message`: `ojd --json` output, the local endpoint, report files, RPC, captures, and files with no `apiVersion` and `kind`. JSON Schema files stay JSON and count as `message`.
- The kind is set per file from what the file stores. Check a row against its line before a move.
- Role is `read` or `write`, taken from the call on that line.

## Counts

| Area | document | message | total |
| --- | ---: | ---: | ---: |
| Swift, `Sources/` and `Tools/` | 42 | 85 | 127 |
| Swift, `Tests/` | 131 | 444 | 575 |
| Python, `Scripts/` and `Tests/` | 36 | 48 | 84 |
| All | 209 | 577 | 786 |

Not in the table: shell scripts read only Apple `Info.plist` files through `plutil`; `Scripts/GUI/ax.js` and `window-list.js` print window lists (message).

## Sites

| Site | Role | Kind | What |
| --- | --- | --- | --- |
| `Scripts/Catalog/catalog_rules.py:28` | read | document | catalog rules document |
| `Scripts/Catalog/generate_controller_catalog.py:468` | read | document | controller record |
| `Scripts/Catalog/generate_controller_catalog.py:502` | read | document | controller record |
| `Scripts/Catalog/generate_crosswalk.py:34` | read | document | crosswalk document |
| `Scripts/Catalog/generate_error_codes.py:61` | read | document | error catalog |
| `Scripts/Catalog/generate_error_codes.py:63` | read | document | error catalog |
| `Scripts/Catalog/generate_error_codes.py:161` | read | document | error catalog |
| `Scripts/Catalog/generate_error_codes.py:170` | write | document | error catalog |
| `Scripts/Catalog/generate_error_codes.py:178` | read | document | error catalog |
| `Scripts/Catalog/protocol_descriptions.py:22` | read | document | protocol description |
| `Scripts/Catalog/xpad_io.py:10` | write | document | controller record text |
| `Scripts/Diagnostics/browser_gamepad.py:200` | read | message | payload, report, or capture |
| `Scripts/Diagnostics/browser_gamepad.py:205` | write | message | payload, report, or capture |
| `Scripts/Diagnostics/browser_gamepad.py:287` | write | message | payload, report, or capture |
| `Scripts/Diagnostics/browser_gamepad.py:321` | write | message | payload, report, or capture |
| `Scripts/Diagnostics/browser_gamepad.py:329` | write | message | payload, report, or capture |
| `Scripts/GUI/capture.py:258` | read | message | payload, report, or capture |
| `Scripts/Quality/repository_tool.py:75` | read | document | bundled documents |
| `Scripts/Quality/repository_tool.py:120` | read | document | bundled documents |
| `Scripts/Quality/validate_schemas.py:61` | read | document | bundled documents checked against schemas |
| `Scripts/SDK/reference_client.py:60` | read | message | `ojd --json` output or input |
| `Scripts/SDK/reference_client.py:78` | write | message | `ojd --json` output or input |
| `Scripts/SDK/reference_client.py:84` | read | message | `ojd --json` output or input |
| `Scripts/SDK/reference_client.py:122` | write | message | `ojd --json` output or input |
| `Sources/OJDRepositoryTool/main.swift:142` | write | document | `format-json` rewrites bundled JSON files |
| `Sources/OJDRepositoryTool/main.swift:154` | read | document | `format-json` rewrites bundled JSON files |
| `Sources/OJDRepositoryTool/main.swift:202` | write | document | `format-json` rewrites bundled JSON files |
| `Sources/OpenJoystickDriverCLI/CLIOutput.swift:50` | write | message | `ojd --json` output or input |
| `Sources/OpenJoystickDriverCLI/CLIOutput.swift:61` | write | message | `ojd --json` output or input |
| `Sources/OpenJoystickDriverCLI/CLIOutput.swift:72` | write | message | `ojd --json` output or input |
| `Sources/OpenJoystickDriverCLI/Commands/Binding/BindingOptions.swift:351` | read | message | `ojd --json` output or input |
| `Sources/OpenJoystickDriverCLI/Commands/Profile/ProfileValueCommands.swift:61` | read | message | `ojd --json` output or input |
| `Sources/OpenJoystickDriverCLI/Commands/Profile/ProfileValueCommands.swift:66` | read | message | `ojd --json` output or input |
| `Sources/OpenJoystickDriverCLI/Commands/Profile/ProfileValueCommands.swift:72` | write | message | `ojd --json` output or input |
| `Sources/OpenJoystickDriverCLI/Commands/Profile/ProfileValueCommands.swift:290` | write | message | `ojd --json` output or input |
| `Sources/OpenJoystickDriverCLI/Commands/Record/RecordCommand.swift:160` | read | document | controller record text |
| `Sources/OpenJoystickDriverCLI/Commands/Record/RecordDraftCommand.swift:197` | read | document | controller record text |
| `Sources/OpenJoystickDriverCLI/Commands/Virtual/VirtualFeedCommand.swift:128` | read | message | `ojd --json` output or input |
| `Sources/OpenJoystickDriverGameControllerViewer/main.swift:222` | write | message | payload, report, or capture |
| `Sources/OpenJoystickDriverHIDTool/PassiveUSBProbeRunner.swift:10` | write | message | payload, report, or capture |
| `Sources/OpenJoystickDriverHIDTool/main.swift:368` | write | message | payload, report, or capture |
| `Sources/OpenJoystickDriverKit/ApplicationService/Client/ApplicationServiceClient+Requests.swift:29` | read | message | RPC |
| `Sources/OpenJoystickDriverKit/ApplicationService/Client/ApplicationServiceClient+Requests.swift:57` | read | message | RPC |
| `Sources/OpenJoystickDriverKit/ApplicationService/Client/ApplicationServiceClient+Requests.swift:72` | read | message | RPC |
| `Sources/OpenJoystickDriverKit/ApplicationService/Client/ApplicationServiceClient+Requests.swift:88` | read | message | RPC |
| `Sources/OpenJoystickDriverKit/ApplicationService/Client/ApplicationServiceClient+Requests.swift:223` | read | message | RPC |
| `Sources/OpenJoystickDriverKit/ApplicationService/Client/ApplicationServiceClient+Requests.swift:240` | read | message | RPC |
| `Sources/OpenJoystickDriverKit/ApplicationService/Client/ApplicationServiceClient+Requests.swift:363` | read | message | RPC |
| `Sources/OpenJoystickDriverKit/ApplicationService/Client/ApplicationServiceClient+Requests.swift:382` | read | message | RPC |
| `Sources/OpenJoystickDriverKit/ApplicationService/Client/ApplicationServiceClient+Requests.swift:403` | read | message | RPC |
| `Sources/OpenJoystickDriverKit/ApplicationService/RPC/LocalServiceRPCServer.swift:319` | write | message | RPC |
| `Sources/OpenJoystickDriverKit/ApplicationService/RPC/LocalServiceRPCServer.swift:324` | read | message | RPC |
| `Sources/OpenJoystickDriverKit/ApplicationService/RPC/LocalServiceRPCServer.swift:328` | write | message | RPC |
| `Sources/OpenJoystickDriverKit/ApplicationService/RPC/LocalServiceRPCServer.swift:354` | write | message | RPC |
| `Sources/OpenJoystickDriverKit/ApplicationService/RPC/LocalServiceRPCServer.swift:366` | write | message | RPC |
| `Sources/OpenJoystickDriverKit/ApplicationService/RPC/LocalServiceRPCTransport+CallState.swift:87` | write | message | RPC |
| `Sources/OpenJoystickDriverKit/ApplicationService/RPC/LocalServiceRPCTransport+CallState.swift:88` | write | message | RPC |
| `Sources/OpenJoystickDriverKit/ApplicationService/RPC/LocalServiceRPCTransport+CallState.swift:104` | read | message | RPC |
| `Sources/OpenJoystickDriverKit/ApplicationService/RPC/LocalServiceRPCTransport+CallState.swift:109` | read | message | RPC |
| `Sources/OpenJoystickDriverKit/ApplicationService/RPC/ServiceListenerFailure.swift:160` | write | message | listener failure report file |
| `Sources/OpenJoystickDriverKit/ApplicationService/RPC/ServiceListenerFailure.swift:238` | read | message | listener failure report file |
| `Sources/OpenJoystickDriverKit/ApplicationService/RPC/ServiceListenerFailure.swift:337` | read | message | listener failure report file |
| `Sources/OpenJoystickDriverKit/ApplicationService/RPC/ServiceListenerFailure.swift:339` | read | message | listener failure report file |
| `Sources/OpenJoystickDriverKit/ApplicationService/RPC/ServiceListenerFailure.swift:340` | write | message | listener failure report file |
| `Sources/OpenJoystickDriverKit/Diagnostics/ControllerRecordProbePlan.swift:81` | read | document | controller record text |
| `Sources/OpenJoystickDriverKit/Diagnostics/SupportReport.swift:368` | write | message | payload, report, or capture |
| `Sources/OpenJoystickDriverKit/Diagnostics/SystemGamepadSupportAudit.swift:252` | read | message | payload, report, or capture |
| `Sources/OpenJoystickDriverKit/Migration/DocumentMigrator.swift:58` | read | document | stored documents of older versions (`ojd migrate` input) |
| `Sources/OpenJoystickDriverKit/Migration/DocumentMigrator.swift:107` | write | document | stored documents of older versions (`ojd migrate` input) |
| `Sources/OpenJoystickDriverKit/Migration/DocumentMigrator.swift:118` | read | document | stored documents of older versions (`ojd migrate` input) |
| `Sources/OpenJoystickDriverKit/Migration/DocumentMigrator.swift:119` | read | document | stored documents of older versions (`ojd migrate` input) |
| `Sources/OpenJoystickDriverKit/Migration/DocumentMigrator.swift:128` | read | document | stored documents of older versions (`ojd migrate` input) |
| `Sources/OpenJoystickDriverKit/Output/Profiles/VirtualDevice+Decoding.swift:175` | read | message | payload, report, or capture |
| `Sources/OpenJoystickDriverKit/Output/Profiles/VirtualGamepadMappingDocument.swift:105` | write | message | payload, report, or capture |
| `Sources/OpenJoystickDriverKit/Output/Profiles/VirtualHIDProfileOverrideStore.swift:233` | read | message | payload, report, or capture |
| `Sources/OpenJoystickDriverKit/Packages/ModPackageManifest.swift:62` | read | message | payload, report, or capture |
| `Sources/OpenJoystickDriverKit/Packages/ModPackageStore+Validation.swift:180` | read | document | kind check of a package manifest |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerDefaults.swift:62` | read | document | controller defaults and patch sections |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerDefaults.swift:63` | read | document | controller defaults and patch sections |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerDefaults.swift:72` | read | document | controller defaults and patch sections |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerDefaults.swift:76` | read | document | controller defaults and patch sections |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecord+Test.swift:58` | read | message | capture and expectation files of `ojd record test` |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecord+Test.swift:96` | read | message | capture and expectation files of `ojd record test` |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecord+Test.swift:134` | write | message | capture and expectation files of `ojd record test` |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecord+Test.swift:136` | read | message | capture and expectation files of `ojd record test` |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecordDraft.swift:119` | read | document | controller record text |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecordSet+Patches.swift:174` | read | document | controller patch files |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecordSet+Patches.swift:175` | read | document | controller patch files |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecordSet+Patches.swift:259` | read | document | controller patch files |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecordSet.swift:239` | read | document | controller record, patch, and protocol description files |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecordSet.swift:240` | read | document | controller record, patch, and protocol description files |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecordSet.swift:281` | write | document | controller record, patch, and protocol description files |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecordSet.swift:284` | read | document | controller record, patch, and protocol description files |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecordSet.swift:301` | read | document | controller record, patch, and protocol description files |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecordSet.swift:309` | read | document | controller record, patch, and protocol description files |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecordWriter.swift:189` | read | document | controller record and patch files |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecordWriter.swift:190` | write | document | controller record and patch files |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecordWriter.swift:234` | read | document | controller record and patch files |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/OrderedJSON+Access.swift:35` | read | message | payload, report, or capture |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/RepositoryValidation+Patches.swift:68` | write | document | controller record and patch files |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/RepositoryValidation+Patches.swift:114` | read | document | controller record and patch files |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/RepositoryValidation+Patches.swift:115` | read | document | controller record and patch files |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/RepositoryValidation+Patches.swift:156` | read | document | controller record and patch files |
| `Sources/OpenJoystickDriverKit/Protocol/Catalog/RepositoryValidation+Patches.swift:157` | read | document | controller record and patch files |
| `Sources/OpenJoystickDriverKit/Protocol/Classification/ProtocolDescription.swift:405` | read | message | payload, report, or capture |
| `Sources/OpenJoystickDriverKit/Remapping/Profile/Document/Store.swift:20` | read | document | profile files |
| `Sources/OpenJoystickDriverKit/Remapping/Profile/Document/Store.swift:55` | write | document | profile files |
| `Sources/OpenJoystickDriverKit/Remapping/Profile/Validation/Profile+Validation.swift:94` | write | message | payload, report, or capture |
| `Sources/OpenJoystickDriverKit/Settings/SettingsStore.swift:144` | write | document | settings file |
| `Sources/OpenJoystickDriverKit/Settings/SettingsStore.swift:194` | read | document | settings file |
| `Sources/OpenJoystickDriverKit/Update/Checker.swift:223` | read | message | payload, report, or capture |
| `Sources/OpenJoystickDriverPresentation/Controllers/Actions/ControllerPacketCapture.swift:96` | write | message | payload, report, or capture |
| `Sources/OpenJoystickDriverPresentation/Settings/Developer/DeveloperToolsModel.swift:247` | write | message | payload, report, or capture |
| `Sources/OpenJoystickDriverService/Remapping/Profiles/RemappingProfileLibrary+Persistence.swift:39` | read | document | profile library files |
| `Sources/OpenJoystickDriverService/Remapping/Profiles/RemappingProfileLibrary+Persistence.swift:89` | write | document | profile library files |
| `Sources/OpenJoystickDriverService/Runtime/Endpoint/AccessGrantStore.swift:220` | read | document | access grants file |
| `Sources/OpenJoystickDriverService/Runtime/Endpoint/AccessGrantStore.swift:235` | write | document | access grants file |
| `Sources/OpenJoystickDriverService/Runtime/Endpoint/EndpointConnection.swift:236` | read | message | local endpoint |
| `Sources/OpenJoystickDriverService/Runtime/Endpoint/EndpointConnection.swift:237` | write | message | local endpoint |
| `Sources/OpenJoystickDriverService/Runtime/Endpoint/EndpointHeader.swift:13` | read | message | local endpoint |
| `Sources/OpenJoystickDriverService/Runtime/Endpoint/EndpointServer+Feed.swift:102` | read | message | local endpoint |
| `Sources/OpenJoystickDriverService/Runtime/Endpoint/EndpointServer+Feed.swift:109` | read | message | local endpoint |
| `Sources/OpenJoystickDriverService/Runtime/Endpoint/EndpointServer+Handshake.swift:244` | read | message | local endpoint |
| `Sources/OpenJoystickDriverService/Runtime/RPC/ApplicationServiceServer+ControllerRequests.swift:31` | write | message | RPC |
| `Sources/OpenJoystickDriverService/Runtime/RPC/ApplicationServiceServer+ControllerRequests.swift:50` | write | message | RPC |
| `Sources/OpenJoystickDriverService/Runtime/RPC/ApplicationServiceServer+ControllerRequests.swift:59` | write | message | RPC |
| `Sources/OpenJoystickDriverService/Runtime/RPC/ApplicationServiceServer+ControllerRequests.swift:65` | write | message | RPC |
| `Sources/OpenJoystickDriverService/Runtime/RPC/ApplicationServiceServer+ControllerRequests.swift:96` | write | message | RPC |
| `Sources/OpenJoystickDriverService/Runtime/RPC/ApplicationServiceServer+ControllerRequests.swift:102` | write | message | RPC |
| `Sources/OpenJoystickDriverService/Runtime/RPC/ApplicationServiceServer+ControllerRequests.swift:108` | write | message | RPC |
| `Sources/OpenJoystickDriverService/Runtime/RPC/ApplicationServiceServer+ControllerRequests.swift:120` | write | message | RPC |
| `Sources/OpenJoystickDriverService/Runtime/RPC/ApplicationServiceServer+ControllerRequests.swift:134` | write | message | RPC |
| `Sources/OpenJoystickDriverService/Runtime/RPC/LocalRPCBridge.swift:51` | read | message | RPC |
| `Sources/OpenJoystickDriverService/Runtime/RPC/LocalRPCBridge.swift:54` | write | message | RPC |
| `Sources/OpenJoystickDriverService/Runtime/RPC/LocalRPCBridge.swift:74` | write | message | RPC |
| `Sources/OpenJoystickDriverService/Runtime/RPC/LocalRPCBridge.swift:83` | write | message | RPC |
| `Sources/OpenJoystickDriverService/Runtime/RPC/RemappingRequestCoordinator+Operations.swift:298` | write | message | RPC |
| `Sources/OpenJoystickDriverService/Runtime/RPC/RemappingRequestCoordinator+Operations.swift:312` | write | message | RPC |
| `Tests/OJDRepositoryToolTests/OJDRepositoryToolTests.swift:28` | read | document | controller record and patch files |
| `Tests/OJDRepositoryToolTests/OJDRepositoryToolTests.swift:132` | read | document | controller record and patch files |
| `Tests/OJDRepositoryToolTests/OJDRepositoryToolTests.swift:135` | write | document | controller record and patch files |
| `Tests/OJDRepositoryToolTests/OJDRepositoryToolTests.swift:176` | read | document | controller record and patch files |
| `Tests/OJDRepositoryToolTests/OJDRepositoryToolTests.swift:224` | read | document | controller record and patch files |
| `Tests/OJDRepositoryToolTests/OJDRepositoryToolTests.swift:228` | write | document | controller record and patch files |
| `Tests/OJDRepositoryToolTests/OJDRepositoryToolTests.swift:375` | read | document | controller record and patch files |
| `Tests/OJDRepositoryToolTests/OJDRepositoryToolTests.swift:378` | write | document | controller record and patch files |
| `Tests/OJDRepositoryToolTests/OJDRepositoryToolTests.swift:392` | read | document | controller record and patch files |
| `Tests/OJDRepositoryToolTests/OJDRepositoryToolTests.swift:393` | write | document | controller record and patch files |
| `Tests/OJDRepositoryToolTests/OJDRepositoryToolTests.swift:609` | read | document | controller record and patch files |
| `Tests/OJDRepositoryToolTests/OJDRepositoryToolTests.swift:641` | read | document | controller record and patch files |
| `Tests/OpenJoystickDriverCLITests/Commands/AccessCommandTests.swift:68` | read | document | access grants file |
| `Tests/OpenJoystickDriverCLITests/Commands/AccessCommandTests.swift:71` | read | document | access grants file |
| `Tests/OpenJoystickDriverCLITests/Commands/AccessCommandTests.swift:75` | read | document | access grants file |
| `Tests/OpenJoystickDriverCLITests/Commands/AccessCommandTests.swift:89` | read | document | access grants file |
| `Tests/OpenJoystickDriverCLITests/Commands/AccessCommandTests.swift:102` | read | document | access grants file |
| `Tests/OpenJoystickDriverCLITests/Commands/AccessCommandTests.swift:183` | read | document | access grants file |
| `Tests/OpenJoystickDriverCLITests/Commands/AccessCommandTests.swift:229` | read | document | access grants file |
| `Tests/OpenJoystickDriverCLITests/Commands/AccessCommandTests.swift:251` | read | document | access grants file |
| `Tests/OpenJoystickDriverCLITests/Commands/AccessCommandTests.swift:270` | read | document | access grants file |
| `Tests/OpenJoystickDriverCLITests/Commands/AccessCommandTests.swift:318` | read | document | access grants file |
| `Tests/OpenJoystickDriverCLITests/Commands/AccessCommandTests.swift:372` | read | document | access grants file |
| `Tests/OpenJoystickDriverCLITests/Commands/ConfigChangeCommandTests.swift:34` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/ControllerClaimCommandTests.swift:35` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/ControllerClaimCommandTests.swift:38` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/ControllerClaimCommandTests.swift:40` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/ControllerClaimCommandTests.swift:221` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/ControllerClaimCommandTests.swift:222` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/ControllerClaimCommandTests.swift:227` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/ControllerClaimCommandTests.swift:229` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/ControllerCommandTests.swift:25` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/ControllerCommandTests.swift:93` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/ControllerCommandTests.swift:354` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/ControllerCommandTests.swift:783` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/ControllerRemappingCommandTests.swift:30` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/ControllerSpeakerCommandTests.swift:64` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/DiagnoseCommandTests.swift:25` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/DiagnoseCommandTests.swift:26` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/DiagnoseCommandTests.swift:35` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/DiagnoseCommandTests.swift:36` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/DiagnoseCommandTests.swift:401` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/DiagnoseCommandTests.swift:427` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/DiagnoseCommandTests.swift:478` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/DiagnoseCommandTests.swift:508` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/ExplainCommandTests.swift:69` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/HomePathOutputTests.swift:98` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/HomePathOutputTests.swift:106` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/LogCommandTests.swift:120` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/ModCommandTests.swift:36` | write | document | mod package manifest |
| `Tests/OpenJoystickDriverCLITests/Commands/ModCommandTests.swift:43` | write | document | mod package manifest |
| `Tests/OpenJoystickDriverCLITests/Commands/ModCommandTests.swift:106` | read | document | mod package manifest |
| `Tests/OpenJoystickDriverCLITests/Commands/ModCommandTests.swift:109` | write | document | mod package manifest |
| `Tests/OpenJoystickDriverCLITests/Commands/PermissionCommandTests.swift:44` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/PermissionCommandTests.swift:45` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/PermissionCommandTests.swift:53` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/PermissionCommandTests.swift:54` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/ProfileCommandTests.swift:141` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/RecordTestCommandTests.swift:35` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/ServiceCommandTests.swift:154` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/SettingCommandTests.swift:25` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/SettingCommandTests.swift:36` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/SettingTestNotificationCommandTests.swift:27` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/VirtualCommandTests+Units.swift:40` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/VirtualCommandTests+Units.swift:56` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/VirtualCommandTests.swift:33` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/VirtualFeedCommandTests.swift:27` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/VirtualFeedCommandTests.swift:72` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/VirtualFeedCommandTests.swift:90` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Commands/VirtualFeedCommandTests.swift:149` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/NeutralWords/SystemWordsTests.swift:48` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Support/CLIOutputSchema.swift:45` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Support/CLIOutputSchema.swift:50` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Support/CLIOutputSchema.swift:66` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Support/CLIRun.swift:57` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Support/FakeProfileLibrary.swift:94` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Support/FakeService.swift:91` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Support/FakeService.swift:95` | write | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverCLITests/Support/GUICoverageEntries.swift:516` | read | message | `ojd --json` output or input |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/AccessValueSpellingTests.swift:8` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/ApplicationServiceDeviceDescriptionAppliedTests.swift:17` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/ApplicationServiceDeviceDescriptionAppliedTests.swift:19` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/ApplicationServiceDeviceDescriptionAppliedTests.swift:28` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/ApplicationServiceDeviceDescriptionAppliedTests.swift:31` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/ApplicationServiceDeviceDescriptionAppliedTests.swift:35` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/ApplicationServiceDeviceDescriptionAppliedTests.swift:37` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/ApplicationServicePublicationStatusTests.swift:11` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/ApplicationServicePublicationStatusTests.swift:52` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/ApplicationServicePublicationStatusTests.swift:54` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/CLIOutputValueSpellingTests.swift:8` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/CLIOutputValueSpellingTests.swift:62` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/CLIOutputValueSpellingTests.swift:68` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/CLIOutputValueSpellingTests.swift:70` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/ApplicationServiceRemappingSnapshotPayloadTests.swift:19` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/ApplicationServiceRemappingSnapshotPayloadTests.swift:21` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/ApplicationServiceRemappingSnapshotPayloadTests.swift:37` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/ApplicationServiceRemappingSnapshotPayloadTests.swift:40` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/ApplicationServiceRemappingSnapshotPayloadTests.swift:43` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RPCAcceptLoopTests.swift:48` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RPCTests.swift:22` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RPCTests.swift:23` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RPCTests.swift:134` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RPCTests.swift:167` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RPCTests.swift:180` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RPCTests.swift:217` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RPCTests.swift:226` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RPCTests.swift:254` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RPCTests.swift:264` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RPCTests.swift:271` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RPCTests.swift:312` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RPCTests.swift:392` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RPCTests.swift:394` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RPCTests.swift:476` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RPCTests.swift:511` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:13` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:14` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:23` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:39` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:45` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:75` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:85` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:104` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:159` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:165` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:167` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:174` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:176` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:181` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:183` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:188` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:190` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:192` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:197` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:199` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:205` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:207` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:212` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:214` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:220` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:222` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:227` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:229` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:235` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:237` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:242` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:243` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:317` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:319` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:347` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:348` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:356` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:372` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRPCTests.swift:373` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRouteWireTests.swift:8` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/RemappingRouteWireTests.swift:9` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/VirtualHIDProfileOverrideArgumentsTests.swift:9` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/VirtualHIDProfileOverrideArgumentsTests.swift:16` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/VirtualHIDProfileOverrideArgumentsTests.swift:19` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/VirtualHIDProfileOverrideArgumentsTests.swift:22` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/VirtualHIDProfileOverrideArgumentsTests.swift:31` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/VirtualHIDProfileOverrideArgumentsTests.swift:37` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/VirtualHIDProfileOverrideArgumentsTests.swift:39` | write | message | RPC |
| `Tests/OpenJoystickDriverKitTests/ApplicationService/VirtualHIDProfileOverrideArgumentsTests.swift:42` | read | message | RPC |
| `Tests/OpenJoystickDriverKitTests/CommandLine/CommandLineNameTests.swift:34` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Controller/ControlVocabularyTests.swift:15` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Controller/ControlVocabularyTests.swift:77` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Controller/ControlVocabularyTests.swift:192` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Controller/ControlVocabularyTests.swift:195` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Controller/ControllerStateTests.swift:44` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Controller/ControllerStateTests.swift:47` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Controller/MotionReadingTests.swift:62` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Controller/MotionReadingTests.swift:63` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Controller/MotionReadingTests.swift:88` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Controller/StickYDownSurfaceTests.swift:12` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Controller/StickYDownSurfaceTests.swift:13` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Controller/StickYDownSurfaceTests.swift:21` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Controller/TriggerButtonDerivationTests.swift:95` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Controller/TriggerButtonDerivationTests.swift:98` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Controller/TriggerButtonDerivationTests.swift:100` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/ControllerPortKeyTests.swift:68` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/ControllerPortKeyTests.swift:72` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/ControllerReferenceTests.swift:36` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/ControllerReferenceTests.swift:44` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/ControllerSessionTokenTests.swift:35` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/ControllerSessionTokenTests.swift:39` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/LogicalControllerIDTests.swift:294` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/LogicalControllerIDTests.swift:295` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/LogicalControllerIDTests.swift:316` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/LogicalControllerIDTests.swift:318` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/LogicalControllerIDTests.swift:338` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/LogicalControllerIDTests.swift:339` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/LogicalControllerIDTests.swift:343` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/LogicalControllerIDTests.swift:345` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/InputCapabilitiesTests.swift:46` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/InputCapabilitiesTests.swift:49` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/InputCapabilitiesTests.swift:69` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/InputCapabilitiesTests.swift:70` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/InputCapabilitiesTests.swift:75` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/InputCapabilitiesTests.swift:77` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/InputCapabilitiesTests.swift:109` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/InputCapabilitiesTests.swift:110` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/InputCapabilitiesTests.swift:114` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/InputCapabilitiesTests.swift:132` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/NativePassThroughTests.swift:260` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/NativePassThroughTests.swift:262` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/OwnershipObservationTests.swift:258` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/OwnershipObservationTests.swift:260` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/OwnershipObservationTests.swift:364` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/OwnershipObservationTests.swift:366` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/OwnershipReapplyTests.swift:132` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/RecordOwnershipReportTests.swift:23` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/RecordOwnershipReportTests.swift:59` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/RecordOwnershipReportTests.swift:60` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/RecordOwnershipReportTests.swift:65` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/RecordOwnershipReportTests.swift:67` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/UnboundHIDDeviceTests.swift:160` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Manager/UnboundHIDDeviceTests.swift:162` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Device/Pipeline/GatedControlTransferTests.swift:42` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Diagnostics/BuildIdentityTests.swift:17` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Diagnostics/BuildIdentityTests.swift:66` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Diagnostics/BuildIdentityTests.swift:92` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Diagnostics/ControllerRecordProbePlanTests.swift:374` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Diagnostics/ControllerRecordProbePlanTests.swift:379` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Diagnostics/ControllerRecordProbePlanTests.swift:381` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Diagnostics/ReportValueNamesTests.swift:10` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Diagnostics/SupportReportBindingTests.swift:101` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Diagnostics/SupportReportBindingTests.swift:196` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Diagnostics/SupportReportBindingTests.swift:214` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Diagnostics/SupportReportBindingTests.swift:216` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Diagnostics/SupportReportTests.swift:146` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Diagnostics/SupportReportTests.swift:171` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Diagnostics/SystemGamepadSupportAuditTests.swift:105` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Diagnostics/SystemGamepadSupportAuditTests.swift:106` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Errors/ErrorCodeTests.swift:29` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Errors/ErrorCodeTests.swift:50` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Errors/ErrorCodeTests.swift:80` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Errors/ErrorCodeTests.swift:115` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Integration/PhysicalRumbleOutputTests.swift:86` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Integration/PhysicalRumbleOutputTests.swift:109` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Integration/PhysicalRumbleOutputTests.swift:132` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Integration/PhysicalRumbleOutputTests.swift:134` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Localization/LocalizationCatalogAudit.swift:406` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Localization/LocalizationTests.swift:178` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Migration/DocumentMigratorTests.swift:65` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Migration/DocumentMigratorTests.swift:79` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Migration/DocumentMigratorTests.swift:109` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Migration/DocumentMigratorTests.swift:167` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Output/Backends/UserSpaceOutputDispatcher/FrameQueueCapacityTests.swift:34` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Output/Backends/VirtualOutputBackendStatusTests.swift:18` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Output/Backends/VirtualOutputBackendStatusTests.swift:30` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Output/Profiles/VirtualDeviceTests.swift:30` | read | document | virtual device file |
| `Tests/OpenJoystickDriverKitTests/Output/Profiles/VirtualDeviceTests.swift:33` | write | document | virtual device file |
| `Tests/OpenJoystickDriverKitTests/Output/Profiles/VirtualDeviceTests.swift:41` | write | document | virtual device file |
| `Tests/OpenJoystickDriverKitTests/Output/Profiles/VirtualGamepadMappingTests.swift:40` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Output/Profiles/VirtualGamepadMappingTests.swift:68` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Output/Profiles/VirtualHIDProfileOverrideStoreTests.swift:74` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Output/Profiles/VirtualHIDProfileTests.swift:24` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Output/Profiles/VirtualHIDProfileTests.swift:26` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Output/Profiles/VirtualHIDProfileTests.swift:33` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Packages/ModPackageFixture.swift:40` | write | document | mod package manifest |
| `Tests/OpenJoystickDriverKitTests/Packages/ModPackageFixture.swift:54` | write | document | mod package manifest |
| `Tests/OpenJoystickDriverKitTests/Packages/ModPackageFixture.swift:122` | write | document | mod package manifest |
| `Tests/OpenJoystickDriverKitTests/Packages/ModPackageListKindTests.swift:25` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Packages/ModPackageManifestSchemaTests.swift:80` | write | document | mod package manifest |
| `Tests/OpenJoystickDriverKitTests/Packages/ModPackageManifestSchemaTests.swift:85` | write | document | mod package manifest |
| `Tests/OpenJoystickDriverKitTests/Packages/ModPackageStoreHardeningTests.swift:204` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Permissions/InputReadPermissionStateTests.swift:18` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Permissions/InputReadPermissionStateTests.swift:33` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Permissions/InputReadPermissionStateTests.swift:38` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Permissions/InputReadPermissionStateTests.swift:40` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Permissions/InputReadPermissionStateTests.swift:44` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Permissions/InputReadPermissionStateTests.swift:46` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Permissions/InputReadPermissionStateTests.swift:58` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Permissions/InputReadPermissionStateTests.swift:59` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/ControllerCapabilitiesTests.swift:129` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/ControllerCapabilitiesTests.swift:135` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/ControllerCapabilitiesTests.swift:158` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/ControllerColorTests.swift:9` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/ControllerColorTests.swift:23` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/ControllerColorTests.swift:31` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/ControllerOutputCommandCodableTests.swift:9` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/ControllerOutputCommandCodableTests.swift:50` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/ControllerOutputCommandCodableTests.swift:62` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/ControllerOutputCommandCodableTests.swift:71` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/ControllerOutputCommandCodableTests.swift:85` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/ControllerOutputCommandCodableTests.swift:95` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/ControllerOutputCommandCodableTests.swift:106` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/ControllerOutputCommandCodableTests.swift:120` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/ControllerProfileCapabilitiesTests.swift:29` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/ControllerProfileCapabilitiesTests.swift:30` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/ControllerProfileCapabilitiesTests.swift:37` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/ControllerProfileCapabilitiesTests.swift:43` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/TouchSurfaceCapabilityTests.swift:27` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Capabilities/TouchSurfaceCapabilityTests.swift:29` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ConditionalInputLayoutTests.swift:19` | read | document | controller record text |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ConditionalInputLayoutTests.swift:27` | read | document | controller record text |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ConditionalInputLayoutTests.swift:124` | read | document | controller record text |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerModeConditionalTests.swift:36` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerModeMatchTests.swift:40` | write | document | controller record text |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerModeMatchTests.swift:163` | write | document | controller record text |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerModeMatchTests.swift:423` | write | document | controller record text |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerModeMatchTests.swift:622` | write | document | controller record text |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerModeMatchTests.swift:665` | write | document | controller record text |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerModeMatchTests.swift:699` | write | document | controller record text |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerModeSessionTests.swift:19` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerModeTests.swift:66` | write | document | controller record text |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerModeTests.swift:426` | read | document | controller record text |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerPatchMergeTests.swift:18` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerPatchMergeTests.swift:23` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerRecordDocumentTests.swift:450` | read | document | controller record file |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerRecordDocumentTests.swift:458` | read | document | controller record file |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerRecordDocumentTests.swift:493` | read | document | controller record file |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerRecordDocumentTests.swift:495` | write | document | controller record file |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerRecordDraftTests.swift:39` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerRecordDraftTests.swift:148` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerRecordOutputTests.swift:328` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerRecordRouteTests.swift:60` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerRecordSetTests.swift:14` | write | document | controller record set |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerRecordStartupWriteTests.swift:256` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerRecordWriterTests.swift:64` | read | document | controller record file |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerRecordWriterTests.swift:90` | read | document | controller record file |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerRecordWriterTests.swift:119` | write | document | controller record file |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerRecordWriterTests.swift:221` | read | document | controller record file |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerRecordWriterTuningTests.swift:159` | read | document | controller record file |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerRecordWriterTuningTests.swift:182` | read | document | controller record file |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerRecordWriterTuningTests.swift:207` | write | document | controller record file |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/HIDUsageMapTests.swift:50` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/IdleRecordTests.swift:21` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONEncoderTests.swift:8` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONEncoderTests.swift:10` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONEncoderTests.swift:16` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONEncoderTests.swift:117` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONEncoderTests.swift:122` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONEncoderTests.swift:129` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONEncoderTests.swift:143` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONEncoderTests.swift:151` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONEncoderTests.swift:165` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONEncoderTests.swift:170` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONTests.swift:33` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONTests.swift:44` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONTests.swift:62` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONTests.swift:102` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONTests.swift:108` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONTests.swift:121` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONTests.swift:186` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONTests.swift:187` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONTests.swift:193` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONTests.swift:207` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONTests.swift:337` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONTests.swift:351` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONTests.swift:363` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONTests.swift:380` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONTests.swift:389` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONTests.swift:407` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/OrderedJSONTests.swift:409` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ProtocolBindingIDTests.swift:41` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ProtocolBindingIDTests.swift:43` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ProtocolBindingIDTests.swift:67` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ProtocolParametersTests.swift:121` | read | document | controller record text |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ProtocolParametersTests.swift:137` | write | document | controller record text |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/RawUSBModeTests.swift:26` | write | document | controller record text |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/RawUSBModeTests.swift:58` | write | document | controller record text |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/RawUSBModeTests.swift:110` | write | document | controller record text |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/RepositoryValidationTests.swift:115` | read | document | controller record and patch files |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/RepositoryValidationTests.swift:118` | write | document | controller record and patch files |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SDLFixtureSupport.swift:38` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejectionTests.swift:23` | read | document | controller record text |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejectionTests.swift:42` | write | document | controller record text |
| `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejectionTests.swift:64` | write | document | controller record text |
| `Tests/OpenJoystickDriverKitTests/Protocol/Classification/NamedPacketDescriptionTests.swift:127` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Classification/ProtocolClassifierTests+ProtocolDescriptions.swift:108` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Classification/ProtocolDescriptionTests.swift:1095` | read | document | protocol description files |
| `Tests/OpenJoystickDriverKitTests/Protocol/Classification/ProtocolDescriptionTests.swift:1103` | write | document | protocol description files |
| `Tests/OpenJoystickDriverKitTests/Protocol/ControllerRecordTestTests.swift:22` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Drivers/Generic/ReportLayoutDriverTests.swift:35` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Drivers/Nintendo/WiiDriverIRTests.swift:66` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Drivers/Nintendo/WiiRemoteStatusTests.swift:70` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Drivers/Nintendo/WiiRemoteStatusTests.swift:71` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Drivers/Vendor/FlydigiGripRumbleTests.swift:30` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Parsers/Nintendo/JoyConParserTests.swift:152` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Parsers/Nintendo/JoyConParserTests.swift:154` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Parsers/Nintendo/NintendoCalibrationTests.swift:90` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Parsers/Sony/DualSenseCalibrationTests.swift:27` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Parsers/Valve/SteamTouchSamplesTests.swift:52` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Protocol/Parsers/Valve/SteamTouchSamplesTests.swift:54` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/CommandValueParserTests.swift:141` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/CommandValueParserTests.swift:144` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/ExtraButtonTests.swift:22` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/ExtraButtonTests.swift:24` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/MIDIOutputTests.swift:55` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/MIDIOutputTests.swift:80` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/MixedOutputTests+PassthroughAndRecovery.swift:73` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/MixedOutputTests+PassthroughAndRecovery.swift:75` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/MixedOutputTests+PassthroughAndRecovery.swift:111` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/MixedOutputTests+PassthroughAndRecovery.swift:113` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/MixedOutputTests+TapsAndToggles.swift:160` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/MixedOutputTests+TapsAndToggles.swift:162` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/MultiTapTests.swift:81` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/MultiTapTests.swift:84` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/MultiTapTests.swift:86` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/MultiTapTests.swift:94` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/ProfileControlActionTests.swift:30` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/ProfileControlActionTests.swift:50` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/SpeechOutputTests.swift:44` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/SystemActionTests.swift:24` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/SystemActionTests.swift:44` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Analog/PointerSpeedTests.swift:144` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Analog/PointerSpeedTests.swift:157` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Analog/RegionSourceTests.swift:264` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Analog/RegionSourceTests.swift:271` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Analog/RegionSourceTests.swift:278` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Chords/ChordTimingTests.swift:76` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Chords/ChordTimingTests.swift:77` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Chords/ChordTimingTests.swift:80` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Chords/ChordTimingTests.swift:110` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Chords/ChordTimingTests.swift:112` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Core/PointerBindingTests.swift:69` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Analog/StickMappingTests.swift:10` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Analog/StickMappingTests.swift:14` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Analog/StickProfileTests.swift:12` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Analog/TouchMappingTests.swift:33` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Analog/TouchMappingTests.swift:35` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Analog/TriggerMappingTests.swift:32` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Controls/ActionTests.swift:15` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Controls/ActionTests.swift:17` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Controls/BindingBehaviorTests.swift:14` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Controls/BindingBehaviorTests.swift:15` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Controls/BindingBehaviorTests.swift:18` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileTests.swift:9` | write | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileTests.swift:18` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileTests.swift:29` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileTests.swift:31` | write | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileTests.swift:74` | write | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileTests.swift:75` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileTests.swift:97` | write | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileTests.swift:98` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileTests.swift:130` | write | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileTests.swift:131` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileTests.swift:158` | write | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileTests.swift:161` | write | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileTests.swift:163` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileTests.swift:185` | write | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileTests.swift:188` | write | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileTests.swift:190` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileTests.swift:200` | write | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileTests.swift:201` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileValueSpellingTests.swift:10` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileValueSpellingTests.swift:21` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileValueSpellingTests.swift:29` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileValueSpellingTests.swift:38` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileValueSpellingTests.swift:44` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileValueSpellingTests.swift:93` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileValueSpellingTests.swift:156` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileValueSpellingTests.swift:203` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileValueSpellingTests.swift:221` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileValueSpellingTests.swift:249` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/ProfileValueSpellingTests.swift:254` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/StrictDecodingTests.swift:14` | write | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/StrictDecodingTests.swift:16` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/StrictDecodingTests.swift:22` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/StrictDecodingTests.swift:51` | write | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/StrictDecodingTests.swift:52` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/StrictDecodingTests.swift:75` | write | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Document/StrictDecodingTests.swift:76` | read | document | profile document |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Motion/GyroOutputTests.swift:27` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Motion/GyroOutputTests.swift:49` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Motion/GyroOutputTests.swift:58` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Motion/GyroOutputTests.swift:66` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Motion/GyroOutputTests.swift:86` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Motion/GyroTrackballTests.swift:12` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Motion/GyroTrackballTests.swift:16` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Motion/GyroTrackballTests.swift:19` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Motion/JoyConPairProfileTests.swift:20` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Motion/LayerMotionProfileTests.swift:15` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Motion/LayerMotionProfileTests.swift:17` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Motion/LayerMotionProfileTests.swift:19` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Motion/MotionProfileTests.swift:21` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Motion/MotionTuningTests.swift:17` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Motion/MotionTuningTests.swift:27` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Output/OutputPolicyTests.swift:53` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Output/OutputPolicyTests.swift:90` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Output/OutputPolicyTests.swift:91` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Output/OutputPolicyTests.swift:93` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Output/OutputPolicyTests.swift:95` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Validation/MacroValidationTests.swift:21` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Validation/MacroValidationTests.swift:152` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Validation/MacroValidationTests.swift:153` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Validation/MacroValidationTests.swift:177` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Validation/MacroValidationTests.swift:179` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Remapping/Profile/Validation/ValidationTests.swift:189` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverKitTests/Settings/SettingsStoreTests.swift:90` | read | document | settings file |
| `Tests/OpenJoystickDriverKitTests/Settings/SettingsStoreTests.swift:92` | write | document | settings file |
| `Tests/OpenJoystickDriverKitTests/Settings/SettingsStoreTests.swift:103` | read | document | settings file |
| `Tests/OpenJoystickDriverKitTests/Settings/SettingsStoreTests.swift:161` | read | document | settings file |
| `Tests/OpenJoystickDriverMacOSPlatformTests/GameControllerPersonalityMatchTests.swift:20` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverPresentationTests/Controllers/ControllerActionsTests.swift:120` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverPresentationTests/Controllers/ControllerActionsTests.swift:300` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverPresentationTests/Controllers/ControllerActionsTests.swift:346` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverPresentationTests/Controllers/MotionCalibration/MotionCalibrationStateTests.swift:106` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverPresentationTests/Controllers/MotionCalibration/MotionCalibrationStateTests.swift:297` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverPresentationTests/Library/LibraryRecordTextTests.swift:82` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverPresentationTests/Profiles/Draft/RuntimeProfileOutputPolicyTests.swift:33` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverPresentationTests/Profiles/Draft/RuntimeProfileOutputPolicyTests.swift:35` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverPresentationTests/Runtime/ListenerFailureStatusTests.swift:63` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverPresentationTests/Runtime/ListenerFailureStatusTests.swift:64` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverPresentationTests/Runtime/SupportDiagnosticsTests.swift:158` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverPresentationTests/Runtime/SupportDiagnosticsTests.swift:194` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverPresentationTests/Settings/Developer/DeveloperToolsTests.swift:181` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverPresentationTests/Settings/Developer/DeveloperToolsTests.swift:206` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverPresentationTests/Settings/Developer/DeveloperToolsTests.swift:406` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverPresentationTests/Settings/Developer/DeveloperToolsTests.swift:409` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverPresentationTests/Settings/Preferences/SettingsFileRecoveryTests.swift:245` | read | document | settings file |
| `Tests/OpenJoystickDriverPresentationTests/Settings/Preferences/SettingsFileRecoveryTests.swift:249` | write | document | settings file |
| `Tests/OpenJoystickDriverServiceTests/Remapping/Profiles/ProfileLibraryTests+PackageClashes.swift:165` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverServiceTests/Remapping/Profiles/ProfileLibraryTests+Packages.swift:195` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverServiceTests/Remapping/Profiles/ProfileLibraryTests+Recovery.swift:15` | read | document | profile library files |
| `Tests/OpenJoystickDriverServiceTests/Remapping/Profiles/ProfileLibraryTests+Recovery.swift:20` | write | document | profile library files |
| `Tests/OpenJoystickDriverServiceTests/Remapping/Profiles/ProfileLibraryTests+Recovery.swift:40` | read | document | profile library files |
| `Tests/OpenJoystickDriverServiceTests/Remapping/Profiles/ProfileLibraryTests+Recovery.swift:51` | write | document | profile library files |
| `Tests/OpenJoystickDriverServiceTests/Remapping/Profiles/ProfileLibraryTests+Recovery.swift:103` | read | document | profile library files |
| `Tests/OpenJoystickDriverServiceTests/Remapping/Profiles/ProfileLibraryTests+Recovery.swift:114` | write | document | profile library files |
| `Tests/OpenJoystickDriverServiceTests/Remapping/Profiles/ProfileLibraryTests+Recovery.swift:218` | read | document | profile library files |
| `Tests/OpenJoystickDriverServiceTests/Remapping/Profiles/ProfileLibraryTests+Recovery.swift:225` | read | document | profile library files |
| `Tests/OpenJoystickDriverServiceTests/Remapping/Profiles/ProfileLibraryTests+Recovery.swift:228` | write | document | profile library files |
| `Tests/OpenJoystickDriverServiceTests/Remapping/Profiles/ProfileLibraryTests.swift:451` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverServiceTests/Runtime/Endpoint/AccessGrantStoreTests.swift:472` | read | message | local endpoint |
| `Tests/OpenJoystickDriverServiceTests/Runtime/Endpoint/EndpointConnectionTests.swift:100` | read | message | local endpoint |
| `Tests/OpenJoystickDriverServiceTests/Runtime/Endpoint/EndpointMessagesTests.swift:16` | write | message | local endpoint |
| `Tests/OpenJoystickDriverServiceTests/Runtime/Endpoint/EndpointMessagesTests.swift:50` | read | message | local endpoint |
| `Tests/OpenJoystickDriverServiceTests/Runtime/Endpoint/EndpointMessagesTests.swift:61` | read | message | local endpoint |
| `Tests/OpenJoystickDriverServiceTests/Runtime/Endpoint/EndpointMessagesTests.swift:110` | read | message | local endpoint |
| `Tests/OpenJoystickDriverServiceTests/Runtime/Endpoint/EndpointMessagesTests.swift:126` | read | message | local endpoint |
| `Tests/OpenJoystickDriverServiceTests/Runtime/Endpoint/EndpointMessagesTests.swift:150` | read | message | local endpoint |
| `Tests/OpenJoystickDriverServiceTests/Runtime/Endpoint/EndpointReferenceClientTests.swift:39` | read | message | local endpoint |
| `Tests/OpenJoystickDriverServiceTests/Runtime/Endpoint/EndpointTestSupport.swift:212` | read | message | local endpoint |
| `Tests/OpenJoystickDriverServiceTests/Runtime/Endpoint/EndpointTestSupport.swift:410` | read | message | local endpoint |
| `Tests/OpenJoystickDriverServiceTests/Runtime/OutputDispatch/VirtualOutputTests+PersonaIdentity.swift:21` | write | document | persona file |
| `Tests/OpenJoystickDriverServiceTests/Runtime/OutputDispatch/VirtualOutputTests+PersonaIdentity.swift:100` | write | document | persona file |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/ControllerServerRequestsTests.swift:122` | write | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/ControllerServerRequestsTests.swift:124` | write | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/ControllerServerRequestsTests.swift:127` | read | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/ControllerTuningRequestsTests.swift:102` | write | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/ControllerTuningRequestsTests.swift:104` | write | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/ControllerTuningRequestsTests.swift:112` | read | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/LocalRPCBridgeTests.swift:77` | write | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/LocalRPCBridgeTests.swift:194` | write | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/LocalRPCBridgeTests.swift:196` | write | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/LocalRPCBridgeTests.swift:237` | write | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/LocalRPCBridgeTests.swift:239` | write | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/LocalRPCBridgeTests.swift:256` | write | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/LocalRPCBridgeTests.swift:266` | read | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/LocalRPCBridgeTests.swift:267` | read | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/LocalRPCBridgeTests.swift:280` | write | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/LocalRPCBridgeTests.swift:299` | write | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/RemappingRequestCoordinatorTests+PackageProfiles.swift:48` | write | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/RemappingRequestCoordinatorTests+ProfileMutations.swift:231` | write | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/SettingsRPCTests.swift:93` | write | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/SettingsRPCTests.swift:97` | read | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/VirtualOutputTests+ProfileOverrideRPC.swift:284` | write | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/VirtualOutputTests+ProfileOverrideRPC.swift:286` | read | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/VirtualOutputTests+ProfileOverrideRPC.swift:288` | write | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/VirtualOutputTests+ProfileOverrideRPC.swift:292` | read | message | RPC |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/VirtualOutputTests+ProfileOverrideSettings.swift:202` | read | document | persona override file |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/VirtualOutputTests+ProfileOverrideSettings.swift:255` | read | document | persona override file |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/VirtualOutputTests+ProfileOverrideSettings.swift:282` | write | document | persona override file |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/VirtualOutputTests+ProfileOverrideSettings.swift:291` | write | document | persona override file |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/VirtualOutputTests+ProfileOverrideSettings.swift:301` | write | document | persona override file |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/VirtualOutputTests+ProfileOverrideSettings.swift:302` | read | document | persona override file |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/VirtualOutputTests+ProfileOverrideSettings.swift:311` | write | document | persona override file |
| `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/VirtualOutputTests+ProfileOverrideSettings.swift:313` | read | document | persona override file |
| `Tests/OpenJoystickDriverServiceTests/Status/SystemExtension/ProbeTests.swift:25` | read | message | payload, report, or capture |
| `Tests/OpenJoystickDriverTestSupport/JSONSchemaFiles.swift:38` | read | message | reads the schema files, which stay JSON |
| `Tests/OpenJoystickDriverTestSupport/JSONSchemaFiles.swift:47` | read | message | reads the schema files, which stay JSON |
| `Tests/OpenJoystickDriverUSBTests/PassiveProbe/PassiveUSBDescriptorProbeTests+RegistryFacts.swift:154` | write | message | payload, report, or capture |
| `Tests/OpenJoystickDriverUSBTests/PassiveProbe/PassiveUSBDescriptorProbeTests+RegistryFacts.swift:155` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_access_grants_schema.py:23` | read | document | access grants example |
| `Tests/RepositoryScripts/test_catalog_generation.py:606` | read | document | controller record |
| `Tests/RepositoryScripts/test_catalog_generation.py:715` | read | document | controller record |
| `Tests/RepositoryScripts/test_catalog_rules.py:16` | write | document | catalog rules fixture |
| `Tests/RepositoryScripts/test_control_vocabulary.py:27` | read | document | vocabulary and profile documents |
| `Tests/RepositoryScripts/test_control_vocabulary.py:128` | read | document | vocabulary and profile documents |
| `Tests/RepositoryScripts/test_control_vocabulary.py:134` | read | document | vocabulary and profile documents |
| `Tests/RepositoryScripts/test_core_without_webrtc.py:18` | read | message | Package.resolved, no apiVersion or kind |
| `Tests/RepositoryScripts/test_crosswalk_table.py:34` | read | document | crosswalk |
| `Tests/RepositoryScripts/test_crosswalk_table.py:36` | write | document | crosswalk |
| `Tests/RepositoryScripts/test_crosswalk_table.py:43` | read | document | crosswalk |
| `Tests/RepositoryScripts/test_crosswalk_table.py:79` | read | document | crosswalk |
| `Tests/RepositoryScripts/test_crosswalk_table.py:81` | write | document | crosswalk |
| `Tests/RepositoryScripts/test_crosswalk_table.py:93` | read | document | crosswalk |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:27` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:52` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:62` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:75` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:82` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:154` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:169` | write | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:173` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:177` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:181` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:198` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:205` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:230` | write | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:239` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:258` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:271` | write | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:342` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:355` | write | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:360` | write | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:401` | write | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:409` | write | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_endpoint_reference_client.py:416` | write | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_error_codes.py:39` | write | document | error catalog |
| `Tests/RepositoryScripts/test_error_codes.py:195` | read | document | error catalog |
| `Tests/RepositoryScripts/test_error_codes.py:226` | read | document | error catalog |
| `Tests/RepositoryScripts/test_error_codes.py:228` | write | document | error catalog |
| `Tests/RepositoryScripts/test_gui_capture.py:180` | write | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_gui_capture.py:451` | write | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_gui_capture.py:466` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_gui_capture.py:476` | write | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_gui_capture.py:501` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_gui_capture.py:516` | write | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_gui_capture.py:546` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_gui_capture.py:693` | write | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_report_schema.py:20` | read | message | schema files, which stay JSON |
| `Tests/RepositoryScripts/test_schema_accepted_documents.py:33` | read | document | bundled documents |
| `Tests/RepositoryScripts/test_schema_header.py:19` | read | document | documents and examples |
| `Tests/RepositoryScripts/test_schema_naming.py:170` | read | message | schema files, which stay JSON |
| `Tests/RepositoryScripts/test_schema_naming.py:330` | read | message | schema files, which stay JSON |
| `Tests/RepositoryScripts/test_schema_naming.py:354` | read | message | schema files, which stay JSON |
| `Tests/RepositoryScripts/test_schema_rejection_flags.py:33` | read | document | rejection cases |
| `Tests/RepositoryScripts/test_sdk_docs.py:37` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_sdk_docs.py:86` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_sdk_docs.py:109` | read | message | payload, report, or capture |
| `Tests/RepositoryScripts/test_virtual_device_schema.py:19` | read | document | virtual device |
| `Tests/RepositoryScripts/test_vocabulary_names.py:34` | read | document | vocabulary |
| `Tools/BridgeCore/Sources/BridgeCore/Bridges.swift:129` | write | message | local endpoint |
| `Tools/BridgeCore/Sources/BridgeCore/Bridges.swift:252` | write | message | local endpoint |
| `Tools/BridgeCore/Sources/BridgeCore/EndpointSession.swift:131` | write | message | local endpoint |
| `Tools/BridgeCore/Sources/BridgeCore/EndpointSession.swift:158` | read | message | local endpoint |
| `Tools/BridgeCore/Sources/BridgeCore/PeerMessage.swift:118` | read | message | local endpoint |
| `Tools/WebRTCBridge/Sources/WebRTCBridge/main.swift:45` | read | message | local endpoint |
| `Tools/WebRTCBridge/Sources/WebRTCBridge/main.swift:92` | write | message | local endpoint |
| `Tools/WebRTCBridge/Sources/WebRTCBridgeCore/PeerLink.swift:199` | write | message | local endpoint |
| `Tools/WebRTCBridge/Sources/WebRTCBridgeCore/PeerLink.swift:211` | read | message | local endpoint |
| `Tools/WebRTCBridge/Tests/WebRTCBridgeCoreTests/FakeEndpoint.swift:97` | write | message | local endpoint |
| `Tools/WebRTCBridge/Tests/WebRTCBridgeCoreTests/FakeEndpoint.swift:115` | read | message | local endpoint |
| `Tools/WebRTCBridge/Tests/WebRTCBridgeCoreTests/HostBridgeTests.swift:106` | read | message | local endpoint |
| `Tools/WebRTCBridge/Tests/WebRTCBridgeCoreTests/PeerMessageTests.swift:27` | read | message | local endpoint |
