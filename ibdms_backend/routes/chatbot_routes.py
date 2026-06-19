from fastapi import APIRouter
from pydantic import BaseModel
from controllers.chatbot_controller import process_chatbot_query, process_chat_message

router = APIRouter(prefix="/api/chatbot", tags=["AI Conversational Agent Pipeline"])


class ChatMessageSchema(BaseModel):
    message: str


@router.get("/query")
def chat_get(user_message: str):
    """Legacy GET endpoint — preserved for compatibility."""
    return {"reply": process_chatbot_query(user_message)}


@router.post("/message")
def chat_post(payload: ChatMessageSchema):
    """
    RAG-based POST endpoint.
    Applies scope guard, BM25-lite retrieval, and returns structured response.
    """
    result = process_chat_message(payload.message)
    return {
        "reply": result["response"],
        "in_scope": result["in_scope"],
        "confidence": result["confidence"],
    }
