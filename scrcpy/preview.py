#!/usr/bin/env python3
"""Minimal Noctalia pixel-stream companion for omen/scrcpy.

Clean-room implementation of the documented companion protocol
(HELLO / REQUEST / BUFFER / FRAME over SOCK_SEQPACKET with sealed memfd
RGBA buffers). Frames come from ffmpeg reading a V4L2 loopback that a
scrcpy session fills with the phone display. No pixels pass through Lua.
"""

import array
import fcntl
import mmap
import os
import re
import signal
import socket
import struct
import subprocess
import sys
import threading
import time

MAX_PIXELS = 4194304
HEADER = struct.Struct("<II")
BUFFER_HEADER = struct.Struct("<IIII")


def create_buffer(width, height):
    size = width * height * 4
    fd = os.memfd_create("scrcpy-preview", os.MFD_CLOEXEC | os.MFD_ALLOW_SEALING)
    try:
        os.ftruncate(fd, size)
        fcntl.fcntl(fd, fcntl.F_ADD_SEALS,
                    fcntl.F_SEAL_SHRINK | fcntl.F_SEAL_GROW | fcntl.F_SEAL_SEAL)
        return fd, mmap.mmap(fd, size, access=mmap.ACCESS_WRITE)
    except Exception:
        os.close(fd)
        raise


class Server:
    def __init__(self, path, ffmpeg_argv, width, height):
        self.path = path
        self.ffmpeg_argv = ffmpeg_argv
        self.width = width
        self.height = height
        self.frame_size = width * height * 4
        self.stopped = threading.Event()
        self.condition = threading.Condition()
        self.latest = bytes([0, 0, 0, 255]) * (width * height)
        self.version = 1
        self.sent = 0
        self.child = None
        self.server = None
        self.capture_thread = None
        self.serve_thread = None
        self.latest_at = time.monotonic()
        self.received = 0

    def start(self):
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET)
        try:
            self.server.bind(str(self.path))
            os.chmod(self.path, 0o600)
            self.identity = self.path and os.lstat(self.path)
            self.server.listen(1)
            self.server.settimeout(0.25)
        except Exception:
            self.server.close()
            raise

        self.capture_thread = threading.Thread(target=self.capture, daemon=True)
        self.serve_thread = threading.Thread(target=self.serve, daemon=True)
        self.capture_thread.start()
        self.serve_thread.start()

    def capture(self):
        # scrcpy may need a moment to attach to the loopback and publish a
        # format. Retry briefly instead of failing on the first EIO.
        deadline = time.monotonic() + 12
        # Give scrcpy time to push its server and attach to the loopback before
        # the first VIDIOC_STREAMON; opening too early returns EIO.
        self.stopped.wait(1.5)
        while not self.stopped.is_set():
            try:
                self.child = subprocess.Popen(
                    self.ffmpeg_argv,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=sys.stderr,
                )
                while not self.stopped.is_set():
                    pixels = self.child.stdout.read(self.frame_size)
                    if len(pixels) != self.frame_size:
                        break
                    with self.condition:
                        self.latest = pixels
                        self.latest_at = time.monotonic()
                        self.version += 1
                        self.received += 1
                        self.condition.notify_all()
                try:
                    code = self.child.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    code = "still running"
                if self.stopped.is_set():
                    break
                if time.monotonic() >= deadline:
                    raise RuntimeError("ffmpeg stopped (%s)" % code)
                self.stopped.wait(0.5)
            except Exception as error:
                if self.stopped.is_set():
                    break
                print("scrcpy-preview: %s" % error, file=sys.stderr, flush=True)
                self.stopped.set()
                with self.condition:
                    self.condition.notify_all()
                break
            finally:
                if self.child is not None:
                    if self.child.poll() is None:
                        self.child.terminate()
                        try:
                            self.child.wait(timeout=2)
                        except subprocess.TimeoutExpired:
                            self.child.kill()
                    if self.child.stdout is not None:
                        self.child.stdout.close()
                    self.child = None

    def receive(self, client):
        while not self.stopped.is_set():
            try:
                data, ancillary, flags, _ = client.recvmsg(
                    HEADER.size, socket.CMSG_SPACE(16), socket.MSG_CMSG_CLOEXEC
                )
            except socket.timeout:
                continue
            for level, kind, value in ancillary:
                if level == socket.SOL_SOCKET and kind == socket.SCM_RIGHTS:
                    descriptors = array.array("i")
                    descriptors.frombytes(value[: len(value) // descriptors.itemsize * descriptors.itemsize])
                    for descriptor in descriptors:
                        os.close(descriptor)
            if len(data) != HEADER.size or ancillary or flags & (socket.MSG_TRUNC | socket.MSG_CTRUNC):
                return None
            return HEADER.unpack(data)
        return None

    def serve(self):
        buffers = []
        try:
            while not self.stopped.is_set():
                try:
                    client, _ = self.server.accept()
                except socket.timeout:
                    continue
                except OSError:
                    break
                with client:
                    credentials = client.getsockopt(
                        socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i")
                    )
                    if struct.unpack("3i", credentials)[1] != os.geteuid():
                        continue
                    client.settimeout(0.25)
                    if self.receive(client) != (1, 1):  # HELLO v1
                        continue
                    if not buffers:
                        buffers = [create_buffer(self.width, self.height) for _ in range(2)]
                    sent = -1
                    next_id = 0
                    last_version = 0
                    served, age_sum, stats_at = 0, 0.0, time.monotonic()
                    while not self.stopped.is_set():
                        if self.receive(client) != (2, 0):  # REQUEST
                            break
                        with self.condition:
                            self.condition.wait_for(
                                lambda: self.stopped.is_set() or self.version > last_version,
                                timeout=1.0,
                            )
                            if self.stopped.is_set():
                                break
                            last_version = self.version
                            pixels = self.latest
                            frame_at = self.latest_at
                        fd, mapping = buffers[next_id]
                        mapping[:] = pixels
                        if sent != next_id:
                            message = BUFFER_HEADER.pack(1, next_id, self.width, self.height)
                            rights = [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array("i", [fd]))]
                            if client.sendmsg([message], rights) != len(message):
                                break
                        if client.send(struct.pack("<II", 2, next_id)) != HEADER.size:
                            break
                        served += 1
                        age_sum += max(0.0, (time.monotonic() - frame_at) * 1000.0)
                        now = time.monotonic()
                        if now - stats_at >= 5.0:
                            span = now - stats_at
                            print(
                                "scrcpy-preview: recv=%.1ffps served=%.1ffps age=%.0fms"
                                % (self.received / span, served / span, age_sum / max(1, served)),
                                file=sys.stderr, flush=True,
                            )
                            self.received = 0
                            served, age_sum, stats_at = 0, 0.0, now
                        sent = next_id
                        next_id = 1 - next_id
        finally:
            for fd, mapping in buffers:
                mapping.close()
                os.close(fd)
            self.server.close()

    def stop(self):
        self.stopped.set()
        with self.condition:
            self.condition.notify_all()
        if self.server is not None:
            try:
                self.server.close()
            except OSError:
                pass
        child = self.child
        if child is not None and child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill()
        for thread in (self.capture_thread, self.serve_thread):
            if thread is not None:
                thread.join(timeout=3)
        try:
            identity = self.identity
            current = os.lstat(self.path)
            if identity and (current.st_dev, current.st_ino) == (identity.st_dev, identity.st_ino):
                os.unlink(self.path)
        except (FileNotFoundError, AttributeError):
            pass


def main(argv):
    if len(argv) != 6:
        print("usage: preview.py SOCKET WIDTH HEIGHT FPS DEVICE", file=sys.stderr)
        return 2
    path, width, height, fps, device = argv[1:]
    try:
        width, height, fps = int(width), int(height), int(fps)
    except ValueError:
        print("scrcpy-preview: width, height and fps must be numbers", file=sys.stderr)
        return 2
    if not (0 < width <= 4096 and 0 < height <= 4096 and width * height <= MAX_PIXELS):
        print("scrcpy-preview: invalid frame size", file=sys.stderr)
        return 2
    if not (1 <= fps <= 120):
        print("scrcpy-preview: invalid frame rate", file=sys.stderr)
        return 2

    ffmpeg = [
        "ffmpeg", "-nostdin", "-loglevel", "error", "-threads", "1",
        "-fflags", "+nobuffer", "-probesize", "32", "-analyzeduration", "0",
        "-f", "v4l2", "-framerate", str(fps), "-i", device,
        # fast_bilinear is enough for a live preview and cheaper than bicubic.
        "-vf", "scale=%d:%d:flags=fast_bilinear,format=rgba" % (width, height),
        "-an", "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", "rgba", "pipe:1",
    ]
    server = Server(path, ffmpeg, width, height)
    try:
        server.start()
    except Exception as error:
        print("scrcpy-preview: %s" % error, file=sys.stderr)
        return 1

    def terminate(_signum, _frame):
        server.stopped.set()

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    while not server.stopped.wait(0.5):
        pass
    server.stop()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
