from typing import List, Optional
from pydantic import BaseModel, Field


class DiscoveryDonorDTO(BaseModel):
    """Phase 1 — non-sensitive discovery payload (FOUND / CONTINUED_SEARCH)."""

    match_id: int
    donor_alias: str
    blood_group: str
    distance_km: float
    distance_label: str = ""
    status: str = "FOUND"
    requires_decision: bool = True


class MatchOverviewDTO(BaseModel):
    """Recipient decision card — no phone or exact GPS."""

    match_id: int
    request_id: int
    donor_alias: str
    blood_group: str
    distance_km: float
    distance_label: str
    status: str
    requires_decision: bool = True


class AuthorizedDonorDTO(BaseModel):
    """Phase 2 — revealed only after ACCEPTED."""

    match_id: int
    donor_alias: str
    blood_group: str
    distance_km: float
    status: str
    full_name: str
    phone: Optional[str] = None
    email: Optional[str] = None
    request_latitude: Optional[float] = None
    request_longitude: Optional[float] = None


class DiscoveryRequestDTO(BaseModel):
    """Phase 1 — donor-facing nearby request card."""

    request_id: int
    blood_group_needed: str
    units_required: int
    urgency_level: str
    distance_km: float
    distance_label: str
    status: str
    match_id: Optional[int] = None
    match_status: Optional[str] = None


class BloodRequestStatusDTO(BaseModel):
    request_id: int
    status: str
    current_radius_km: float
    next_radius_km: float
    seconds_until_expansion: int
    matched_count: int
    matched_donors: List[DiscoveryDonorDTO]
    units_required: int
    blood_group_needed: str
    compatible_donor_groups: List[str] = Field(default_factory=list)
    urgency_level: str
    created_at: Optional[str] = None


class BloodRequestLiveDTO(BloodRequestStatusDTO):
    """Live poll response — includes delta events for instant UI pop-ups."""

    new_match_events: List[DiscoveryDonorDTO] = Field(default_factory=list)


class BloodRequestCreateResponseDTO(BaseModel):
    request_id: int
    status: str
    current_radius_km: float
    next_radius_km: float
    seconds_until_expansion: int
    matched_count: int
    matched_donors: List[DiscoveryDonorDTO]
    units_required: int
    blood_group_needed: str
    compatible_donor_groups: List[str] = Field(default_factory=list)
    urgency_level: str


class AlertFeedItemDTO(BaseModel):
    alert_id: str
    alert_type: str
    title: str
    message: str
    match_id: Optional[int] = None
    request_id: Optional[int] = None
    status: str
    blood_group: Optional[str] = None
    distance_km: Optional[float] = None
    created_at: Optional[str] = None
    payload: Optional[dict] = None


class AlertFeedDTO(BaseModel):
    count: int
    alerts: List[AlertFeedItemDTO]
    new_alerts: List[AlertFeedItemDTO] = Field(default_factory=list)
    polled_at: str


class MatchActionResponseDTO(BaseModel):
    match_id: int
    status: str
    message: str
    overview: Optional[MatchOverviewDTO] = None
    authorized: Optional[AuthorizedDonorDTO] = None
    recipient_contact: Optional[dict] = None
    search_continues: bool = False


class NearbyRequestsDTO(BaseModel):
    count: int
    requests: List[DiscoveryRequestDTO]


class MatchActionSchema(BaseModel):
    note: Optional[str] = Field(None, max_length=500)
