"""6.13: OutputRequest through the endpoint (Rumble, Player, Light), the same commands through ojd, and refusals.

Needs a token with the Control scope. OJD_CONTROLLER is the model, for example 2DC8:301B.
"""

import os

from endpoint_client import Client, ojd

controller = os.environ["OJD_CONTROLLER"]

ojd("--json", "controller", "list")
client = Client(["Control"])
print("== Rumble, Player, Light")
client.ask({"kind": "OutputRequest", "controller": controller, "action": "Rumble", "left": 120, "duration": 0.5})
client.ask({"kind": "OutputRequest", "controller": controller, "action": "Player", "player": 1})
client.ask({"kind": "OutputRequest", "controller": controller, "action": "Light", "color": "FF8000", "brightness": 100})
print("== the same through ojd")
ojd("controller", "rumble", controller, "--left", "120", "--duration", "0.5")
ojd("controller", "player", controller, "1")
ojd("controller", "light", controller, "--color", "FF8000", "--brightness", "100")
print("== refusals")
client.ask({"kind": "OutputRequest", "controller": "FFFF:FFFF", "action": "Rumble", "left": 10})
client.ask({"kind": "OutputRequest", "controller": controller, "action": "Rumble", "duration": 9})
client.close()
