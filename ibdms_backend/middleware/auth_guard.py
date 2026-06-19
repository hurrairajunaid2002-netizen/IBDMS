import os
from fastapi import HTTPException, Security, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import jwt
from datetime import datetime

# Must match the key used in auth_controller.py exactly.
# Loaded from the JWT_SECRET environment variable via load_dotenv() in
# config/database.py, which is always imported before this module.
SECRET_KEY = os.getenv("JWT_SECRET", "SUPER_SECRET_COMP_SCI_KEY")
ALGORITHM = "HS256"
security_agent = HTTPBearer()

def get_current_user(credentials: HTTPAuthorizationCredentials = Security(security_agent)):
    token = credentials.credentials
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        sub = payload.get("sub")
        role: str = payload.get("role")
        if sub is None or role is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token architecture.")
        user_id: int = int(sub)
        return {"user_id": user_id, "role": role}
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Session expired. Re-authenticate.")
    except jwt.PyJWTError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Malformed token.")

class RoleChecker:
    def __init__(self, allowed_roles: list):
        self.allowed_roles = allowed_roles

    def __call__(self, current_user: dict = Security(get_current_user)):
        if current_user["role"] not in self.allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN, 
                detail="Access Denied: Insufficient permission mapping."
            )
        return current_user