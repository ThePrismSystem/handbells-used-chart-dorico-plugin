"""Minimal stdlib client for Dorico's Remote Control API (WebSocket on 127.0.0.1:4560).

Dorico asks the user to allow a new client once; the session token it hands back is kept
in token_path and offered on later connections so the prompt does not reappear.
"""
import base64
import json
import os
import select
import socket
import struct
import time
from pathlib import Path

DEFAULT_TOKEN_PATH = Path(__file__).resolve().parents[2] / ".hbuc-token"
CLIENT_NAME = "Handbells Chart Probe"


def encode_frame(payload: bytes, mask: bytes) -> bytes:
    """A masked text frame, which is what a client must send."""
    header = bytearray([0x81])
    n = len(payload)
    if n < 126:
        header.append(0x80 | n)
    elif n < 65536:
        header.append(0x80 | 126)
        header += struct.pack(">H", n)
    else:
        header.append(0x80 | 127)
        header += struct.pack(">Q", n)
    header += mask
    return bytes(header) + bytes(b ^ mask[i % 4] for i, b in enumerate(payload))


class DoricoClient:
    def __init__(self, host="127.0.0.1", port=4560, token_path=DEFAULT_TOKEN_PATH, sock=None, timeout=120):
        self.host, self.port, self.token_path, self.timeout = host, port, Path(token_path), timeout
        self.sock = sock
        self._buf = b""
        self.state = {}  # merged view of every status message: Dorico sends partial deltas

    # --- transport -------------------------------------------------------------------------
    def _open(self):
        self.sock = socket.create_connection((self.host, self.port), timeout=self.timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall(
            (f"GET / HTTP/1.1\r\nHost: {self.host}:{self.port}\r\nUpgrade: websocket\r\n"
             f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode()
        )
        while b"\r\n\r\n" not in self._buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("Dorico closed the connection during the handshake")
            self._buf += chunk
        head, self._buf = self._buf.split(b"\r\n\r\n", 1)
        if b" 101 " not in head.split(b"\r\n")[0]:
            raise ConnectionError(head.decode(errors="replace"))

    def _read(self, n):
        while len(self._buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise EOFError("Dorico closed the connection")
            self._buf += chunk
        out, self._buf = self._buf[:n], self._buf[n:]
        return out

    def send(self, msg: dict):
        self.sock.sendall(encode_frame(json.dumps(msg).encode(), os.urandom(4)))

    def _waiting(self, timeout=0.0) -> bool:
        """Whether a frame has arrived, or arrives within timeout seconds, so reading it won't block."""
        if self._buf:
            return True
        try:
            readable, _, _ = select.select([self.sock], [], [], timeout)
        except (TypeError, ValueError, OSError):  # no file descriptor, as with a test's fake socket
            return False
        return bool(readable)

    def settle(self, quiet=2.0, limit=30.0) -> bool:
        """Wait until Dorico has sent nothing for quiet seconds: it sends a burst of status messages while a project
        opens and lays out, and a script run before that ends can find a command doing nothing. False if limit
        seconds pass first."""
        deadline = time.time() + limit
        while time.time() < deadline:
            if not self._waiting(quiet):
                return True
            self.recv()
        return False

    def recv(self) -> dict:
        message = b""
        while True:
            b1, b2 = self._read(2)
            n = b2 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self._read(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", self._read(8))[0]
            if b2 & 0x80:
                mask = self._read(4)
                payload = bytes(b ^ mask[i % 4] for i, b in enumerate(self._read(n)))
            else:
                payload = self._read(n)
            opcode = b1 & 0x0F
            if opcode == 8:
                raise EOFError("Dorico closed the connection")
            if opcode in (9, 10):  # ping / pong
                continue
            message += payload
            if b1 & 0x80:
                reply = json.loads(message.decode())
                if reply.get("message") == "status":
                    self.state.update(reply)
                return reply

    # --- protocol --------------------------------------------------------------------------
    def connect(self):
        if self.sock is None:
            self._open()
        hello = {"message": "connect", "clientName": CLIENT_NAME, "handshakeVersion": "1.0"}
        if self.token_path.exists():
            hello["sessionToken"] = self.token_path.read_text().strip()
        self.send(hello)
        reply = self.recv()
        if "sessionToken" in reply:
            self.token_path.write_text(reply["sessionToken"])
            self.send({"message": "acceptsessiontoken", "sessionToken": reply["sessionToken"]})
            reply = self.recv()
        if reply.get("code") != "kConnected":
            raise ConnectionError(f"Dorico refused the connection: {reply}")

    def request(self, msg: dict, expect=None) -> dict:
        self.send(msg)
        while True:
            reply = self.recv()
            kind = reply.get("message")
            if expect is not None:
                if kind == expect:
                    return reply
            elif kind != "status":
                return reply

    def command(self, cmd: str) -> dict:
        return self.request({"message": "command", "command": cmd})

    def status(self) -> dict:
        """Dorico's status after merging the latest (possibly partial) status message."""
        self.request({"message": "getstatus"}, expect="status")
        # Dorico also pushes status deltas unasked, and one queued before the reply would stand in for it.
        while self._waiting():
            self.recv()
        return dict(self.state)

    def close(self):
        if self.sock is not None:
            try:
                self.send({"message": "disconnect"})
            except OSError:
                pass
            self.sock.close()
            self.sock = None
