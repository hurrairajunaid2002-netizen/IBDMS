from sqlalchemy import Column, Integer, String, Numeric, Enum, Boolean, Date, ForeignKey
from config.database import Base

class DonorProfile(Base):
    __tablename__ = "donor_profiles"
    
    donor_id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.user_id", ondelete="CASCADE"), unique=True, nullable=False)
    blood_group = Column(String(5), nullable=False, index=True)
    gps_latitude = Column(Numeric(10, 8), nullable=False)
    gps_longitude = Column(Numeric(11, 8), nullable=False)
    weight_kg = Column(Numeric(5, 2), nullable=False)
    dob = Column(Date, nullable=False)
    last_donation_date = Column(Date, nullable=True)
    haemoglobin_level = Column(Numeric(4, 2), nullable=False)
    availability_status = Column(Enum('Active', 'Inactive', 'Locked'), default='Active', index=True)
    is_locked = Column(Boolean, default=False)
    lock_expiry_date = Column(Date, nullable=True)