const app = Application.currentApplication();
app.includeStandardAdditions = true;
const ojd = app.systemAttribute("OJD") || "/usr/local/bin/ojd";
const status = JSON.parse(app.doShellScript(`'${ojd}' --no-input --json status`));
const lines = status.unboundDevices.map((device) => `${device.name} (${device.connection})`);
`Service ${status.service.state}; ${status.controllers.length} controllers; unbound: ${lines.join(", ") || "none"}`;
