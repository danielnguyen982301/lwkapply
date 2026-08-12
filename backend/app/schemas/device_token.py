from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class DeviceTokenRegister(BaseModel):
    token: str = Field(min_length=1, max_length=4096)
    platform: Literal["android", "ios"]


class DeviceTokenRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    platform: str
    last_seen_at: datetime
