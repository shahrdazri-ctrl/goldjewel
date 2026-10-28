#!/usr/bin/env python3
"""Retry helper for the USB-backed lab volume.

D: drops out for a few seconds at a time. Every operation retries on the agreed
5 s backoff and writes are read back before they are reported as done.
"""
from __future__ import annotations

import os
import time

ATTEMPTS = 6
DELAY = 5.0


class LabVolumeError(OSError):
    """Raised when the volume did not come back within the retry budget."""


def _attempt(fn, *args, **kwargs):
    last: OSError | None = None
    for attempt in range(1, ATTEMPTS + 1):
        try:
            return fn(*args, **kwargs)
        except OSError as exc:
            last = exc
            if attempt == ATTEMPTS:
                break
            print(
                f"[dretry] {fn.__name__} failed ({exc}); "
                f"retry {attempt}/{ATTEMPTS - 1} in {DELAY:.0f}s",
                flush=True,
            )
            time.sleep(DELAY)
    raise LabVolumeError(str(last)) from last


def read_text(path: str, encoding: str = "utf-8") -> str:
    def op() -> str:
        with open(path, encoding=encoding) as fh:
            return fh.read()

    return _attempt(op)


def read_bytes(path: str) -> bytes:
    def op() -> bytes:
        with open(path, "rb") as fh:
            return fh.read()

    return _attempt(op)


def write_text(path: str, text: str, encoding: str = "utf-8") -> None:
    def op() -> None:
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        tmp = f"{path}.tmp"
        with open(tmp, "w", encoding=encoding, newline="") as fh:
            fh.write(text)
        os.replace(tmp, path)
        if read_text(path, encoding) != text:
            raise OSError("read-back mismatch")

    _attempt(op)


def write_bytes(path: str, data: bytes) -> None:
    def op() -> None:
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        tmp = f"{path}.tmp"
        with open(tmp, "wb") as fh:
            fh.write(data)
        os.replace(tmp, path)
        if read_bytes(path) != data:
            raise OSError("read-back mismatch")

    _attempt(op)
