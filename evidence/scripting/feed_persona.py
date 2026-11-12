"""6.15: choose each virtual gamepad persona through the endpoint, and the refusals.

Needs a token with the Control scope.
"""

from endpoint_client import Client, ojd

for persona in ("Generic", "SDLCompatible", "GameControllerCompatible"):
    print(f"== FeedRequest as {persona}")
    client = Client(["Control"])
    reply = client.ask({"kind": "FeedRequest", "as": persona})
    if reply and reply.get("kind") == "FeedSession":
        client.send({"kind": "Frame", "buttons": ["South"], "holdMilliseconds": 100})
        client.send({"kind": "Frame"})
        client.send({"kind": "Drain"})
        client.receive()
    client.close()

print("== refusals")
client = Client(["Control"])
client.ask({"kind": "FeedRequest", "as": "DualShock"})
client.close()
client = Client(["Read"])
client.ask({"kind": "FeedRequest", "as": "Generic"})
client.close()
ojd("--json", "status")
