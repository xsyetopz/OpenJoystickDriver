from __future__ import annotations

import json
from typing import Any


def json_text(value: Any) -> str:
    return json.dumps(value, indent=2, ensure_ascii=False) + "\n"
