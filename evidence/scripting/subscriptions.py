"""6.14: the Profiles and Mods subscriptions, each sending the whole list on change.

Needs a token with the Read scope, the scratch profile OJD_PROFILE, and the package folder OJD_PACKAGE.
"""

import os

from endpoint_client import Client, ojd

profile = os.environ["OJD_PROFILE"]
package = os.environ["OJD_PACKAGE"]

print("== Profiles")
client = Client(["Read"])
client.send({"kind": "Subscription", "stream": "Profiles"})
client.receive()
ojd("profile", "activate", profile)
client.receive()
ojd("profile", "deactivate", profile)
client.receive()
client.close()

print("== Mods")
client = Client(["Read"])
client.send({"kind": "Subscription", "stream": "Mods"})
client.receive()
ojd("mod", "install", package)
client.receive()
ojd("mod", "remove", os.path.basename(package), "--force")
client.receive()
client.close()

print("== refusals: output on Profiles, an unknown stream")
client = Client(["Read"])
client.ask({"kind": "Subscription", "stream": "Profiles", "output": True})
client.close()
client = Client(["Read"])
client.ask({"kind": "Subscription", "stream": "Logs"})
client.close()
