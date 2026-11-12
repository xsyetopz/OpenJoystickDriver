"""6.11: ProfileRequest through the endpoint (Activate, Deactivate, Set), with refusals.

Needs the scratch profile named by OJD_PROFILE and a token with the Control scope.
"""

import os

from endpoint_client import Client, ojd

profile = os.environ["OJD_PROFILE"]
renamed = profile + "-renamed"

print("== Control scope")
client = Client(["Control"])
client.ask({"kind": "ProfileRequest", "action": "Activate", "profile": profile})
client.ask({"kind": "ProfileRequest", "action": "Set", "profile": profile, "key": "name", "value": renamed})
client.ask({"kind": "ProfileRequest", "action": "Deactivate", "profile": renamed})
client.ask({"kind": "ProfileRequest", "action": "Set", "profile": renamed, "key": "name", "value": profile})
print("== a refusal that keeps the connection open")
client.ask({"kind": "ProfileRequest", "action": "Activate", "profile": "No Such Profile"})
print("== a refusal that closes the connection (Set without a value)")
client.ask({"kind": "ProfileRequest", "action": "Set", "profile": profile, "key": "name"})
client.close()

print("== Read scope only")
client = Client(["Read"])
client.ask({"kind": "ProfileRequest", "action": "Activate", "profile": profile})
client.close()

print("== the profile after the run, through ojd")
ojd("--json", "profile", "list")
