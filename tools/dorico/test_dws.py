import json
import os
import shutil
import socket
import sys
import tempfile
import threading
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import dws  # noqa: E402

UPGRADED = b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"


def server_frame(obj):
    """An unmasked text frame, as Dorico sends them."""
    data = json.dumps(obj).encode()
    assert len(data) < 126  # noqa: S101  # longer frames need a longer header
    return bytes([0x81, len(data)]) + data


def raw_frame(first, payload):
    """An unmasked frame with the length in whichever form its size needs."""
    n = len(payload)
    if n < 126:
        return bytes([first, n]) + payload
    if n < 65536:
        return bytes([first, 126]) + n.to_bytes(2, "big") + payload
    return bytes([first, 127]) + n.to_bytes(8, "big") + payload


def client_messages(data):
    """The messages in a run of masked frames, as the client sends them."""
    out = []
    while data:
        n, at = data[1] & 0x7F, 2
        if n == 126:
            n, at = int.from_bytes(data[2:4], "big"), 4
        mask, payload = data[at:at + 4], data[at + 4:at + 4 + n]
        out.append(json.loads(bytes(b ^ mask[i % 4] for i, b in enumerate(payload))))
        data = data[at + 4 + n:]
    return out


class FakeSocket:
    def __init__(self, incoming=b""):
        self.incoming = incoming
        self.sent = b""
        self.closed = False

    def sendall(self, data):
        self.sent += data

    def recv(self, n):
        chunk, self.incoming = self.incoming[:n], self.incoming[n:]
        return chunk

    def close(self):
        self.closed = True


class FakeDorico:
    """A listener on localhost that takes one WebSocket upgrade and answers it with reply (None: hang up)."""

    def __init__(self, reply):
        self.server = socket.create_server(("127.0.0.1", 0))
        self.port = self.server.getsockname()[1]
        self.request = b""
        self.thread = threading.Thread(target=self.serve, args=(reply,), daemon=True)
        self.thread.start()

    def serve(self, reply):
        conn, _ = self.server.accept()
        with conn:
            while b"\r\n\r\n" not in self.request:
                self.request += conn.recv(4096)
            if reply is None:
                return
            conn.sendall(reply)
            while conn.recv(4096):  # until the client hangs up
                pass

    def close(self):
        self.server.close()
        self.thread.join(5)


class EncodeFrameTests(unittest.TestCase):
    def test_encode_frame_small(self):
        mask = b"\x01\x02\x03\x04"
        self.assertEqual(
            dws.encode_frame(b"hi", mask),
            b"\x81\x82\x01\x02\x03\x04" + bytes([0x68 ^ 1, 0x69 ^ 2]),
        )

    def test_encode_frame_126(self):
        frame = dws.encode_frame(b"x" * 200, b"\x00\x00\x00\x00")
        self.assertEqual(frame[0], 0x81)
        self.assertEqual(frame[1], 0x80 | 126)
        self.assertEqual(frame[2:4], (200).to_bytes(2, "big"))
        self.assertEqual(len(frame), 4 + 4 + 200)

    def test_encode_frame_127(self):
        frame = dws.encode_frame(b"x" * 70000, b"\x00\x00\x00\x00")
        self.assertEqual(frame[1], 0x80 | 127)
        self.assertEqual(frame[2:10], (70000).to_bytes(8, "big"))
        self.assertEqual(len(frame), 2 + 8 + 4 + 70000)


class HandshakeTests(unittest.TestCase):
    def client(self, reply):
        dorico = FakeDorico(reply)
        self.addCleanup(dorico.close)
        token = Path(tempfile.mkdtemp()) / "token"
        self.addCleanup(shutil.rmtree, token.parent, True)
        client = dws.DoricoClient(port=dorico.port, token_path=token, timeout=5)
        self.addCleanup(lambda: client.sock and client.sock.close())
        return client, dorico

    def test_connect_upgrades_to_a_websocket_first(self):
        client, dorico = self.client(UPGRADED + server_frame({"code": "kConnected"}))
        client.connect()
        head = dorico.request.split(b"\r\n")
        self.assertEqual(head[0], b"GET / HTTP/1.1")
        self.assertIn(b"Upgrade: websocket", head)
        self.assertIn(b"Sec-WebSocket-Version: 13", head)

    def test_a_refused_upgrade_raises_with_its_status(self):
        client, _ = self.client(b"HTTP/1.1 400 Bad Request\r\n\r\n")
        with self.assertRaisesRegex(ConnectionError, "400 Bad Request"):
            client.connect()

    def test_hanging_up_during_the_handshake_raises(self):
        client, _ = self.client(None)
        with self.assertRaisesRegex(ConnectionError, "during the handshake"):
            client.connect()


class ConnectTests(unittest.TestCase):
    def setUp(self):
        folder = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, folder, True)
        self.token = folder / "token"

    def connect(self, *replies):
        sock = FakeSocket(b"".join(server_frame(r) for r in replies))
        dws.DoricoClient(sock=sock, token_path=self.token).connect()
        return client_messages(sock.sent)

    def test_a_new_session_token_is_kept_and_accepted(self):
        sent = self.connect({"sessionToken": "abc"}, {"code": "kConnected"})
        self.assertEqual(self.token.read_text(), "abc", "offered next time, so Dorico doesn't ask again")
        self.assertNotIn("sessionToken", sent[0])
        self.assertEqual(sent[1], {"message": "acceptsessiontoken", "sessionToken": "abc"})

    def test_a_kept_token_is_offered(self):
        self.token.write_text("xyz\n")
        sent = self.connect({"code": "kConnected"})
        self.assertEqual(sent[0]["sessionToken"], "xyz")
        self.assertEqual(sent[0]["clientName"], dws.CLIENT_NAME)

    def test_a_refusal_raises(self):
        with self.assertRaisesRegex(ConnectionError, "refused"):
            self.connect({"code": "kNotConnected"})


class CloseTests(unittest.TestCase):
    def test_close_says_goodbye_and_closes(self):
        sock = FakeSocket()
        client = dws.DoricoClient(sock=sock)
        client.close()
        self.assertEqual(client_messages(sock.sent), [{"message": "disconnect"}])
        self.assertTrue(sock.closed)
        self.assertIsNone(client.sock)
        client.close()  # a second close does nothing

    def test_close_survives_a_broken_connection(self):
        class Broken(FakeSocket):
            def sendall(self, data):
                raise OSError("broken pipe")
        sock = Broken()
        dws.DoricoClient(sock=sock).close()
        self.assertTrue(sock.closed)


class ReceiveTests(unittest.TestCase):
    def receive(self, data):
        return dws.DoricoClient(sock=FakeSocket(data)).recv()

    def test_16_bit_length(self):
        text = "x" * 300
        self.assertEqual(self.receive(raw_frame(0x81, json.dumps({"t": text}).encode()))["t"], text)

    def test_64_bit_length(self):
        text = "x" * 70000
        self.assertEqual(self.receive(raw_frame(0x81, json.dumps({"t": text}).encode()))["t"], text)

    def test_fragments_are_joined(self):
        data = json.dumps({"message": "response", "code": "kOK"}).encode()
        frames = raw_frame(0x01, data[:10]) + raw_frame(0x00, data[10:20]) + raw_frame(0x80, data[20:])
        self.assertEqual(self.receive(frames)["code"], "kOK")

    def test_pings_are_skipped(self):
        frames = raw_frame(0x89, b"hi") + server_frame({"message": "response"})
        self.assertEqual(self.receive(frames)["message"], "response")

    def test_close_ends_the_connection(self):
        with self.assertRaises(EOFError):
            self.receive(raw_frame(0x88, b""))

    def test_a_dropped_connection_raises(self):
        with self.assertRaises(EOFError):
            self.receive(b"\x81")

    def test_a_masked_frame_is_unmasked(self):
        self.assertEqual(self.receive(dws.encode_frame(b'{"code": "kOK"}', b"\x05\x06\x07\x08")), {"code": "kOK"})


class SettleTests(unittest.TestCase):
    def test_settle_reads_the_burst_and_returns_once_quiet(self):
        # a real socket pair, since settle waits on the socket itself
        dorico, ours = socket.socketpair()
        self.addCleanup(dorico.close)
        self.addCleanup(ours.close)
        dorico.sendall(server_frame({"message": "status", "activeOpenScoreID": 5}) + server_frame(
            {"message": "status", "canUndo": True}
        ))
        client = dws.DoricoClient(sock=ours)
        self.assertTrue(client.settle(quiet=0.2, limit=5))
        self.assertEqual(client.state, {"message": "status", "activeOpenScoreID": 5, "canUndo": True})

    def test_settle_gives_up_at_its_limit(self):
        self.assertFalse(dws.DoricoClient(sock=FakeSocket()).settle(quiet=1, limit=0))


class RequestTests(unittest.TestCase):
    def frames(self):
        return server_frame({"message": "status"}) + server_frame(
            {"message": "commandlist", "commands": []}
        )

    def test_request_skips_status(self):
        client = dws.DoricoClient(sock=FakeSocket(self.frames()))
        reply = client.request({"message": "getcommands"})
        self.assertEqual(reply, {"message": "commandlist", "commands": []})

    def test_status_merges_deltas(self):
        frames = server_frame({"message": "status", "activeOpenScoreID": 1, "hasScore": True}) + server_frame(
            {"message": "status", "hasScore": True}
        )
        client = dws.DoricoClient(sock=FakeSocket(frames))
        client.request({"message": "getstatus"}, expect="status")
        self.assertEqual(client.status()["activeOpenScoreID"], 1)

    def test_status_reads_every_status_already_waiting(self):
        # Dorico pushes status deltas unasked: one queued before the reply must not stand in for it
        frames = server_frame({"message": "status", "activeOpenScoreID": 1}) + server_frame(
            {"message": "status", "activeOpenScoreID": 2, "hasScore": True}
        )
        client = dws.DoricoClient(sock=FakeSocket(frames))
        self.assertEqual(client.status()["activeOpenScoreID"], 2)

    def test_request_expect_status(self):
        client = dws.DoricoClient(sock=FakeSocket(self.frames()))
        reply = client.request({"message": "getstatus"}, expect="status")
        self.assertEqual(reply, {"message": "status"})

    def test_command_sends_a_command(self):
        sock = FakeSocket(server_frame({"message": "response", "code": "kOK"}))
        reply = dws.DoricoClient(sock=sock).command("File.Save")
        self.assertEqual(reply["code"], "kOK")
        self.assertEqual(client_messages(sock.sent), [{"message": "command", "command": "File.Save"}])


if __name__ == "__main__":
    unittest.main()
