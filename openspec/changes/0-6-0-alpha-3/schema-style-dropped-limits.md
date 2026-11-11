# Schema style dropped limits

Limits and rules that task 7.2 removed from schema descriptions, for task 7.3 to state as keywords (or, where JSON Schema cannot, in the wiki reference and a rejection case). Each entry is the JSON pointer of the description in the schema file, then the text that went. The old text is in git history before the commit that rewrote the file. Runtime behavior notes (absent when, present only with) are listed too, because D7 keeps runtime behavior out of descriptions; task 7.3 decides which of them is a keyword (`required`, `dependentRequired`, `if`/`then`) and which is wiki text.

## access-grants.schema.json

- `/$defs/token/properties/controlGrantedAt/description`, `/$defs/grant/properties/controlGrantedAt/description`: required with the Control scope.
- `/$defs/token/properties/origins/description`: empty for a token that works only on the Unix socket.
- `/$defs/grant/properties/publisher/properties/id/description`: required for Signed grants.
- `/$defs/grant/properties/publisher/description`: Signed matches the identifier signed by a certificate of the publisher id; Platform matches the identifier signed by the platform vendor.
- `/$defs/token/description`: the token itself is not stored.
- `/properties/web/properties/port/description`: absent until the first enable, which saves the port the system picked unless one was given.
- `/description`: only the service writes the file.

## cli-output.schema.json

- `/$defs/configShow/properties/controller/description`: absent without a controller option.
- `/$defs/configShow/properties/profile/description`: absent without a controller option, without a running service, or without an active profile for the controller.
- `/$defs/configShow/properties/defaultsProblem/description`: absent when the defaults file applies or does not exist.
- `/$defs/configShow/properties/values/items/properties/value/description`: absent while only the Driver default applies.
- `/$defs/configShow/properties/values/items/properties/families/description`: present for a tuning key without a controller option.
- `/$defs/controllerList/properties/items/items/properties/power/description`, `/$defs/controllerShow/properties/power/description`: absent when the service reports none.
- `/$defs/controllerList/properties/items/items/properties/unit/description`, `/$defs/controllerShow/properties/unit/description`: absent without a location ID.
- `/$defs/controllerShow/properties/capabilities/properties/digitalTriggers/description`: the other triggers are analog and also derive a button.
- `/$defs/controllerShow/properties/capabilities/properties/outputOwner/description`: with System, macOS serves the controller natively, so the rumble and lighting lists hold only what macOS leaves undone.
- `/$defs/controllerShow/properties/ownership/properties/serverSource/description`: the record layer that sets server, Default when no layer sets it, or Route when the system cannot serve the controller so server is OJD.
- `/$defs/controllerShow/properties/publication/properties/failure/description`: present exactly when the state is Failed.
- `/$defs/controllerShow/properties/publication/properties/reason/description`: present exactly when the state is NotPublished.
- `/$defs/controllerShow/properties/inputMapping/description`: absent unless the HIDDescriptor protocol drives the controller.
- `/$defs/controllerShow/properties/record/description`: absent when no record matches.
- `/$defs/controllerShow/properties/serving/properties/persona/description`: absent for a route that publishes nothing.
- `/$defs/controllerShow/properties/serving/properties/reason/description`: present only with OutputDisabled.
- `/$defs/controllerShow/properties/tuning/description`: absent when the record sets no tuning.
- `/$defs/controllerWatch/description`: with first-press, the first control pressed; with all, one event per line for every controller; with output, one controller state and the virtual gamepad's values per line; otherwise one controller state per line.
- `/$defs/controllerWatch/oneOf/2/properties/output/description`: absent when the controller is not published.
- `/$defs/diagnose/properties/timings/description`: empty while the service is stopped; nanoseconds are on the service's monotonic uptime clock; frames lists the newest 8 frames of each controller; summary covers the window of its newest 15000 frames; DeliveryEndpoint goes on the newest frame at the poll, and a frame replaced by a newer one before the poll gets none.
- `/$defs/migrate/properties/items/items/properties/detail/description`: only for failed.
- `/$defs/profileValidate/description`: a valid profile has every property except problem; an invalid profile has only valid and problem.
- `/$defs/profileGet/properties/value/description`: the profile file's shape is in profile.schema.json.
- `/$defs/recordTest/properties/differences/description`: empty when the states match.
- `/$defs/sharedConfigChange/properties/controller/description`: absent for the defaults patch file.
- `/$defs/sharedConfigChange/properties/previous/description`: absent while only the Driver default applies.
- `/$defs/sharedConfigChange/properties/value/description`: absent for config unset.
- `/$defs/sharedAccessRefusedToken/properties/name/description`: absent for a token that matches no grant.
- `/$defs/sharedAccessRefusedToken/properties/origin/description`: WebSocket only.
- `/$defs/sharedExclusiveOwner/description`: absent when none holds it or the interface names none.
- `/$defs/sharedExclusiveOwner/properties/name/description`: the kernel truncates a process name to 16 characters.
- `/$defs/sharedExclusiveOwner/properties/processID/description`: absent when a kernel driver holds the interface.
- `/$defs/sharedControllerWatchEvent/description`: the line has no apiVersion and kind of its own, its object does; ADDED includes controllers connected when the stream starts; DELETED carries the last object.
- `/$defs/sharedFrameTimingSummary/description`: a gap lists median, 99th percentile (nearest rank) and maximum over frames that reached both stages, absent when no frame did; a stall is a read interval longer than 3 times the median read-to-read time; ReadToRead and stalls are measured only on a window of lastSeconds; stalls is absent when the window holds fewer than two frames.
- `/$defs/sharedFrameTimingSummary/properties/lastSeconds/description`: absent for the whole ring.
- `/$defs/sharedFrameTimingSummary/properties/stalls/properties/thresholdNanoseconds/description`: 3 times the median read-to-read time.
- `/$defs/sharedWatchedController/properties/input/description`: absent until the controller has input state.
- `/$defs/sharedWatchedController/properties/output/description`: absent when the controller is not published.
- `/$defs/sharedStatus/description`: details is the command's own result, constrained by each command's entry.
- `/$defs/sharedVirtualFeedLine/description`: virtual gamepads receive only rumble commands.
- `/$defs/sharedVirtualFeedLine/oneOf/0/properties/durationMilliseconds/description`: absent while the rumble is held until the next rumble command.
- `/$defs/sharedVirtualSDL/description`: the GUID carries a zero CRC.
- `/$defs/sharedVirtualW3C/description`: a source is bN for a button, aN for an axis and h0.MASK for a hat direction, numbered as SDL numbers them.
- `/$defs/sharedVirtualOutput/description`: stick Y points down, as in the HID report.
- `/$defs/status/properties/commandLineTool/description`: the link states Installed, LinkedElsewhere, Broken, BlockedByFile, and Missing, and that target appears only for a link.
- `/$defs/status/properties/service/properties/listenerFailure/description`, `/$defs/status/properties/service/properties/listenerFailureProblem/description`: present only while the service is stopped.
- `/$defs/status/properties/service/properties/listenerFailure/properties/current/description`: false when the service is not running and the failure is why its last listener stopped.
- `/$defs/virtualShow/properties/controllers/items/properties/sdl/description`, `/$defs/virtualShow/properties/controllers/items/properties/w3c/description`: absent with no virtual gamepad.
- `/description`: every document has apiVersion and kind; a list command prints its items in items with no apiVersion or kind of their own and an empty metadata; a streaming command prints one document per line.

## controller.schema.json

- `/properties/idle/description`: the record has one default mode and no section that serves controls.
- `/$defs/modes/description`: at most one mode has the id default and no match; every other mode has a match; non-default modes are tried in order and the first whose match keys all hold is selected; a record without a default mode leaves a device that matches no mode unsupported.
- `/$defs/modeMatch/description`: all keys must hold; probes are tried last.
- `/$defs/modeInterfaceSignature/description`: only a raw-USB mode may name endpoints.
- `/$defs/modeInterfaceSignature/properties/endpoints/description`: each entry pairs with one distinct endpoint and none is left over.
- `/$defs/bcdDeviceRange/description`: min must not exceed max.
- `/$defs/modeInterface/description`: the lowest interface the device exposes is bound; first must not exceed last.
- `/$defs/modeProbe/description`: a probe never writes.
- `/$defs/protocol/properties/parameters/description`: the family's description declares names, types and values.
- `/$defs/tuning/properties/irWriteIntervalMs/description`: at least 50 ms.
- `/$defs/rumbleTemplate/description`: the bytes cover the whole report, start with the report ID, and leave motor and counter bytes distinct and inside the report.
- `/$defs/inputLayout/properties/report/properties/length/description`: with an id, the length counts the id byte.
- `/$defs/modeEndpoint/description`: every key present must hold.
- `/$defs/controlTransfer/description`: an IN transfer reads wLength bytes; an OUT transfer writes data whose byte count equals wLength.
- `/$defs/session/description`: control runs before startup, in order; startup is one list of HID report writes or one of raw-USB packets; keepAlive, settleMilliseconds, shutdown and control apply to raw-USB modes.

## endpoint.schema.json

- `/description`: the line order of the protocol (Hello, Welcome, Subscription or FeedRequest, watch lines, Frame, KeepAlive, Drain, Drained); every line except a watch line carries apiVersion and kind; a Status line with Failure is the last line before close; a non-object line is answered with E1003, a line without apiVersion or kind with E1011, another apiVersion with E1009, an unknown or misplaced kind with E1010, each carrying details.supportedAPIVersions.
- `/$defs/hello/properties/scopes/description`: each scope must be granted.
- `/$defs/hello/properties/tokenName/description`: required on the WebSocket; a client with a token is not checked by its signature.
- `/$defs/hello/properties/proof/description`: HMAC over four newline-ended lines: the hello label, the challenge nonce, the page origin, and the WebSocket port; on the socket the origin and port lines are empty.
- `/$defs/challenge/properties/nonce/description`: 32 random bytes.
- `/$defs/subscription/properties/output/description`: defaults to false.
- `/$defs/feedRequest/description`: needs the control scope; closing the connection removes the gamepad.
- `/$defs/frame/description`: missing controls are neutral; the service shows frames in order, each for at least 8 ms; it stops reading while 256 frames wait; closing the connection drops frames that have not played.
- `/$defs/frame/properties/axes/description`: sticks run from -1 to 1, positive Y down; triggers run from 0 to 1; values out of range are clamped.
- `/$defs/frame/properties/holdMilliseconds/description`: without it the frame shows until the next one.
- `/$defs/keepAlive/description`: accepted after FeedSession; resets the 2-second idle timeout; no reply; before FeedSession it gets E1010.
- `/$defs/drain/description`: accepted after FeedSession; counts as activity for the 2-second idle timeout; the service reads no line while it waits; before FeedSession it gets E1010.
- `/$defs/drained/description`: closing the connection after it drops no frame.
- `/$defs/error/properties/code/description`: the enum equals the active endpoint codes in the error catalog.
- `/$defs/error/properties/details/properties/supportedAPIVersions/description`: only with E1009, E1010 and E1011.

## error-codes.schema.json

- `/description`: a code is never reused for another error; the English explanation of a code is the localization key error.E####.
- `/$defs/entry/properties/exitCode/description`: cli entries only.
- `/$defs/entry/properties/wire/description`: remapping and document entries only.

## mod-package.schema.json

- `/description`: the folder holds Controllers/, Profiles/ and VirtualDevices/, and each list names files in the subfolder that holds that kind.
- `/properties/name/description`: lowercase letters, digits, and hyphens.
- `/properties/controllers/description`: file names are vvvv-pppp.plist after the model.
- `/properties/patches/description`: file names are vvvv-pppp.patch.plist, model-vvvv-pppp.patch.plist, or all.patch.plist after the selector.
- `/properties/virtualDevices/description`: file names are vvvv-pppp.plist or vvvv-pppp-U-unit.plist after the match.

## profile.schema.json

- `/description`: the schema checks the shape and range of each field; the profile validate command also checks rules that span fields, such as duplicate sources and IDs.
- `/properties/device/properties/unit/description`: the profile applies only to that unit; other units of the model ignore it.
- `/properties/name/description`: at most 80 characters, no space at either end, no control characters.
- `/$defs/layer/properties/name/description`: at most 40 characters, no space at either end, no control characters.
- `/$defs/action/properties/pulseDurationMs/description`, `/$defs/binding/properties/pulseDurationMs/description`: only a pulse binding sets a value other than 100.
- `/$defs/adaptiveTriggerEffect/description`: an off effect has startPosition and strength 0.
- `/$defs/chord/description`: the order of the sources does not matter.
- `/$defs/destination/oneOf/0/description`: modifiers are written sorted and without repeats.
- `/$defs/destination/oneOf/13/properties/url/description`: an absolute URL with a scheme other than file.
- `/$defs/destination/oneOf/16/properties/profile/description`: a profile identifier of the same model, Next or Previous.
- `/$defs/destination/oneOf/19/properties/voice/description`: a voice identifier that the Mac has.
- `/$defs/discreteSource/description`: any source but a whole axis.
- `/$defs/pointerSpeed/description`: multiplies all pointer movement, not scroll; minScale at 0 and maxScale at 1.
- `/$defs/gyroOutput/description`: activationSource is set exactly when activationMode is not always.
- `/$defs/lean/description`: hysteresisDegrees is less than thresholdDegrees.
- `/$defs/source/oneOf/7/description`: column is less than columns, and row is less than rows.
- `/$defs/source/oneOf/9/description`: innerRadius is less than outerRadius; fromDegrees differs from toDegrees; a sector runs clockwise from up, past 0 when toDegrees is below fromDegrees; regions of one stick do not overlap.
- `/$defs/source/oneOf/10/description`: from is less than to; bands of one trigger do not overlap; a trigger with a triggerMappings entry has no bands.
- `/$defs/source/oneOf/11/description`: x plus width and y plus height are at most 1.
- `/$defs/steering/description`: deadzoneDegrees is less than fullScaleDegrees.
- `/$defs/stickMapping/description`: flickHysteresis is less than flickThreshold.
- `/$defs/stickTuning/description`: innerDeadzone plus outerDeadzone is less than 1.
- `/$defs/triggerMapping/description`: softThreshold is less than fullThreshold, and hysteresis is less than softThreshold.

## protocol-description.schema.json

- `/properties/variants/description`: absent when the family has one contract; interface signatures, rawUSB and defaults.variants name only these.
- `/properties/recordSections/description`: input (report layouts), rumble (a rumble template), hidUsageMap, bluetoothLE, and keepAlive are the sections.
- `/properties/sessionKeys/description`: absent means none; defaults.session sets only these.
- `/properties/inputStart/description`: variants limits it to listed variants, each one the family lists; absent means every variant.
- `/properties/parameters/description`: each name is one that a driver reads.
- `/properties/parameterRules/description`: a rule applies to the listed variants, or every variant when none; None allows no parameters, AtMostOne and ExactlyOne limit how many listed parameters are set, Requires needs every listed parameter whenever any is set; listed parameters are declared by the description and variants are ones the family has.
- `/properties/writeTransports/description`: absent when the family's writes name no transport.
- `/$defs/controls/description`: the Xbox layout (without guide) when base is Xbox, less remove, plus add; a driver adds only what its record or layout makes true.
- `/$defs/recordCapabilities/description`: the exact controls a record may add with present.
- `/$defs/startupVariants/description`: absent sends it on every variant.
- `/$defs/startupWhen/description`: is matches a listed value; isNot matches other values and an unset parameter.
- `/$defs/descriptionReceiverPowerOff/description`: variants limits it to those the family lists; only one family sets it.
- `/$defs/descriptionSessionWrite/description`: a write limited by transport is sent only over that transport.
- `/$defs/generalSessionKeys/description`: any other session key belongs to the families whose drivers read it.
- `/$defs/wiiExtensionField/description`: 1 to 3 parts.
- `/$defs/wiiExtensionLayout/description`: every field lies in bits no other field uses; a mask is contiguous; a stick or trigger is 1 to 8 bits wide and an accelerometer axis 1 to 10; controls appear once; a stick halfRange is at most 2^bits; stickCenter FirstSample takes the first sample after the handshake because the extension has no documented calibration block.
- `/$defs/wiiAddress/description`: the driver adds the register space flag.
- `/$defs/wiiStep/description`: Report sets report and data, Write sets address and bytes, Read sets address and length, Sensitivity sets address and block, IRMode and MotionPlusMode set address; a step sets no other field.
- `/$defs/descriptionWiiRemote/description`: input report mode block ids 0x30 to 0x3F with no overlap; extension ids are six bytes; the IR write interval is at least 50 ms; unique ids, blocks in offset order, a choice whose mode carries its features, levels counting up from 1, a step that sets only its kind's fields.
- `/$defs/descriptionSession/description`: startup writes are all HID reports, all raw-USB packets, or all references to named packets; a reference names an id that namedPackets lists.
- `/$defs/descriptionNamedPackets/description`: a named packet's byte 2 is the sequence number the driver stamps; its id is the family name, a slash and a lowercase hyphenated name, and appears at most once.
- `/$defs/descriptionNamedPacket/properties/sessionByte/description`: the sequence number sits at byte 2.
- `/$defs/descriptionSubcommands/description`: the counter starts at 0 and wraps to 0 after modulus - 1; a startup recovery round re-sends the SPI reads whose reply has not arrived.
- `/$defs/descriptionSubcommandRequest/description`: an SPI read sends the address as four little-endian bytes and then the length; each purpose appears at most once.
- `/$defs/descriptionKeepAlive/description`: the driver adds the writes that follow its state; a list may mix HID reports and raw-USB packets, each limited to its variants.
- `/$defs/descriptionKeepAliveHIDWrite/properties/resendTuning/description`, `/$defs/descriptionKeepAliveUSBWrite/properties/resendTuning/description`: absent sends the write on every run.
- `/$defs/variant/description`: a family that has the variant lists it in its variants.
- `/$defs/descriptionSession/properties/commandChannel/description`: the channel's fields are its number, the IN endpoint, the largest reply read after each command, and the reply timeout over USB and Bluetooth LE.

## report.schema.json

- `/$defs/supportDiagnosticData/properties/frameTimings/description`: empty while the service is stopped or has no frames; nanoseconds are on the service's monotonic uptime clock; frames lists the newest 8 frames of each controller; summary covers the window of its newest 15000 frames.
- `/$defs/frameTimingSummary/description`: same rules as the cli-output frame timing summary (gap statistics over frames that reached both stages, stall is a read interval longer than 3 times the median, measured only on a lastSeconds window, stalls absent under two frames).
- `/$defs/frameTimingSummary/properties/lastSeconds/description`: absent for the whole ring.
- `/$defs/frameTimingSummary/properties/stalls/properties/thresholdNanoseconds/description`: 3 times the median read-to-read time.
- `/$defs/permissions/properties/inputRead/description`, `/$defs/permissions/properties/inputInject/description`: unknown when the service did not reply.
- `/$defs/controllerConnectionState/properties/wiiRemote/description`: absent for every other family.
- `/$defs/controllerConnectionState/properties/wiiRemote/properties/extensionKind/description`: absent while none is plugged or its ID is unknown.
- `/$defs/physicalOutputCapabilities/properties/speaker/description`: absent when the controller has none.
- `/$defs/inputMapping/description`: a matching SDL_GameControllerDB line is named by GUID and match tier.

## service-listener-failure.schema.json

- `/description`: the file sits beside the service's RPC socket with the suffix .failure.json; a successful listener start and an orderly stop delete it; the status and diagnose commands read it when the service cannot be reached.
- `/properties/pid/description`: readers report the failure only while a process with this identifier and the start time runs.
- `/properties/pidStartSeconds/description`: as the system reports it.

## settings.schema.json

- `/description`: every setting is optional; a setting the file leaves out takes its built-in default; layers are built-in defaults, then the user file.
- `/properties/launchAtLoginOptOut/description`: default false; the public key launchAtLogin is read from and written to the macOS login item, which stays the source of truth; a change in System Settings does not update this field.
- Defaults dropped from descriptions: `/properties/showInMenuBar/description` true; `/properties/showInDock/description` false; `/properties/notify/properties/controllerConnected/description`, `controllerDisconnected`, `profileActivated`, `profileDeactivated` false; `/properties/notify/properties/sounds/description` true; `/properties/updates/properties/checkAutomatically/description` false; `/properties/updates/properties/includePrereleases/description` false; `/properties/developerTools/description` false.
- `/properties/showInDock/description`: show in menu bar and show in Dock cannot both be false; when false the icon shows only while a window is open.

## virtual-device.schema.json

- `/description`: without match the record defines a persona; with match it selects a persona for one controller model or unit, and its identity and labels replace the persona's.
- `/properties/worksWithDefaultSDLHints/description`: the virtual export-mapping and show commands tell the user when it is false.
- `/properties/identity/properties/version/description`: a record with match that omits it keeps the persona's version.

## vocabulary.schema.json

- `/description`: the Swift enum Control mirrors `$defs/control` and a test keeps them equal; the other definitions are subsets for places that accept only some controls.
- `/$defs/control/description`: South, East, West and North are the face buttons by position; a stick or trigger axis is also a control.
