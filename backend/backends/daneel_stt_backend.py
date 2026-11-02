"""Voicebox STT adapter for Daneel's authenticated Whisper endpoint."""

import os
from pathlib import Path
from typing import Optional

import httpx


class DaneelSTTBackend:
    def __init__(self, model_size: str = "small"):
        self.model_size = model_size
        self.url = os.environ["VOICEBOX_STT_URL"].rstrip("/")
        self.token = os.environ["VOICEBOX_STT_TOKEN"]

    def is_loaded(self) -> bool:
        return True

    def _is_model_cached(self, model_size: str) -> bool:
        return model_size in {"small", "turbo"}

    async def load_model_async(self, model_size: Optional[str] = None) -> None:
        if model_size is not None:
            if not self._is_model_cached(model_size):
                raise ValueError(f"Daneel STT does not serve {model_size}")
            self.model_size = model_size

    load_model = load_model_async

    def unload_model(self) -> None:
        pass

    async def transcribe(
        self,
        audio_path: str,
        language: Optional[str] = None,
        model_size: Optional[str] = None,
    ) -> str:
        selected = model_size or self.model_size
        await self.load_model_async(selected)
        data = {"model": selected}
        if language:
            data["language"] = language
        headers = {"Authorization": f"Bearer {self.token}"}
        path = Path(audio_path)
        timeout = httpx.Timeout(900.0, connect=10.0)
        async with httpx.AsyncClient(timeout=timeout) as client:
            with path.open("rb") as stream:
                response = await client.post(
                    f"{self.url}/v1/audio/transcriptions",
                    headers=headers,
                    data=data,
                    files={"file": (path.name, stream, "application/octet-stream")},
                )
            response.raise_for_status()
        text = response.json().get("text")
        if not isinstance(text, str):
            raise ValueError("Daneel STT response has no transcript")
        return text.strip()

    def _get_model_path(self, model_size: str) -> str:
        return f"{self.url}/v1/audio/transcriptions#{model_size}"
