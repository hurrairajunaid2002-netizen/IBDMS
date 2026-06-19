from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
import os
from dotenv import load_dotenv

# Automatically looks for a .env file in your backend folder and loads it
load_dotenv()

# Using local XAMPP MySQL credentials. 
# It falls back to default settings (user: root, no password) if .env variables aren't defined.
DB_USER = os.getenv("DB_USER", "root")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_NAME = os.getenv("DB_NAME", "ibdms_db")

DATABASE_URL = f"mysql+pymysql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}/{DB_NAME}"

engine = create_engine(
    DATABASE_URL, 
    pool_size=20,         # Keeps up to 20 database connections warm for concurrent performance
    max_overflow=10,      # Safely handles unexpected temporary concurrent request spikes
    pool_recycle=3600     # Prevents "MySQL Server Has Gone Away" timeout errors
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()