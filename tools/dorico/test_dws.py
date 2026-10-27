import json
import os
import socket
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import dws  # noqa: E402


def server_frame(obj):
    """An unmasked text frame, as Dorico sends them."""
    data = json.dumps(obj).encode()
    assert len(data) < 126
    return bytes([0x81, len(data)]) + data


def raw_frame(first, payload):
    """An unmasked frame with the length in whichever form its size needs."""
    n = len(payload)
    if n < 126:
        return bytes([first, n]) + payload
    if n < 65536:
        return bytes([first, 126]) + n.to_bytes(2, "big") + payload
    return bytes([first, 127]) + n.to_bytes(8, "big") + payload


class FakeSocket:
    def __init__(self, incoming=b""):
        self.incoming = incoming
        self.sent = b""

    def sendall(self, data):
        self.sent += data

    def recv(self, n):
        chunk, self.incoming = self.incoming[:n], self.incoming[n:]
        return chunk


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


if __name__ == "__main__":
    unittest.main()
