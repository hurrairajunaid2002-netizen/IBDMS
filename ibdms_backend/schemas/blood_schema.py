from pydantic import BaseModel, Field

class BloodRequestCreateSchema(BaseModel):
    blood_group_needed: str = Field(..., min_length=2, max_length=5)
    units_required: int = Field(..., ge=1)
    urgency_level: str = Field(..., description="Low, Medium, or Critical")
    request_latitude: float
    request_longitude: float