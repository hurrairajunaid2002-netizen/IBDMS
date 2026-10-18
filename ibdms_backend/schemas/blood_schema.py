from pydantic import BaseModel, Field, field_validator

from controllers.blood_compatibility import normalize_blood_group


class BloodRequestCreateSchema(BaseModel):
    blood_group_needed: str = Field(..., min_length=2, max_length=5)
    units_required: int = Field(..., ge=1)
    urgency_level: str = Field(..., description="Low, Medium, or Critical")
    request_latitude: float
    request_longitude: float

    @field_validator("blood_group_needed")
    @classmethod
    def sanitize_blood_group(cls, v: str) -> str:
        normalized = normalize_blood_group(v)
        if not normalized:
            raise ValueError(
                "Invalid blood group. Use A+, A-, B+, B-, AB+, AB-, O+, or O-."
            )
        return normalized