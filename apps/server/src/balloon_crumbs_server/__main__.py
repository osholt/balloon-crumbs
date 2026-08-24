import uvicorn

from .config import get_settings


def main() -> None:
    settings = get_settings()
    uvicorn.run(
        "balloon_crumbs_server.app:default_app",
        factory=True,
        host="0.0.0.0",  # noqa: S104
        port=8080,
        proxy_headers=True,
        forwarded_allow_ips=settings.forwarded_allow_ips,
        # Query strings for traffic and reference-map endpoints contain exact
        # coordinates. Aggregate Prometheus counters replace access logs in
        # production so a flight viewport is never retained as an URL.
        access_log=settings.environment == "development",
    )


if __name__ == "__main__":
    main()
