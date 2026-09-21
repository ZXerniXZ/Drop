from starlette.responses import JSONResponse

import config

_OPEN_PATHS = {
    "/health",
    "/app/version",
    "/docs",
    "/redoc",
    "/openapi.json",
    "/favicon.ico",
}


def parse_version(value: str | None) -> tuple[int, int, int]:
    if not value:
        return (0, 0, 0)
    parts = value.strip().split(".")
    numbers: list[int] = []
    for part in parts[:3]:
        digits = "".join(ch for ch in part if ch.isdigit())
        numbers.append(int(digits) if digits else 0)
    while len(numbers) < 3:
        numbers.append(0)
    return (numbers[0], numbers[1], numbers[2])


def is_supported(version: str | None, build: int | None) -> bool:
    if not version or build is None or build < 0:
        return False
    client = parse_version(version)
    minimum = parse_version(config.MIN_APP_VERSION)
    if client != minimum:
        return client > minimum
    return build >= config.MIN_APP_BUILD


def version_payload() -> dict:
    return {
        "min_version": config.MIN_APP_VERSION,
        "min_build": config.MIN_APP_BUILD,
        "message": config.APP_UPDATE_MESSAGE,
        "android_url": config.APP_UPDATE_ANDROID_URL,
        "web_url": config.APP_UPDATE_WEB_URL,
    }


def update_required_response() -> JSONResponse:
    return JSONResponse(
        status_code=426,
        content={
            "detail": {
                "code": "app_update_required",
                **version_payload(),
            }
        },
    )


class AppVersionMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or scope.get("method") == "OPTIONS":
            await self.app(scope, receive, send)
            return

        path = scope.get("path", "")
        if path in _OPEN_PATHS or path.startswith("/docs"):
            await self.app(scope, receive, send)
            return

        headers = {
            key.decode("latin-1").lower(): value.decode("latin-1")
            for key, value in scope.get("headers", [])
        }
        raw_build = headers.get("x-drop-build", "").strip()
        try:
            build = int(raw_build) if raw_build else None
        except ValueError:
            build = None

        if not is_supported(headers.get("x-drop-version"), build):
            response = update_required_response()
            await response(scope, receive, send)
            return

        await self.app(scope, receive, send)
