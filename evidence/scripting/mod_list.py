"""6.12: ModList through the endpoint, before and after `ojd mod install` and `ojd mod remove`.

Needs a token with the Read scope and the package folder named by OJD_PACKAGE.
"""

import os

from endpoint_client import Client, ojd

package = os.environ["OJD_PACKAGE"]

client = Client(["Read"])
print("== before")
client.ask({"kind": "ModList"})
ojd("mod", "install", package)
print("== after install, on the same connection")
client.ask({"kind": "ModList"})
ojd("--json", "mod", "list")
ojd("mod", "remove", os.path.basename(package), "--force")
print("== after remove")
client.ask({"kind": "ModList"})
client.close()

print("== a Control-only connection has no Read scope")
client = Client(["Control"])
client.ask({"kind": "ModList"})
client.close()
