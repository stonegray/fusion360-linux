import socket, sys, time
rate = float(sys.argv[2]) * 1e6  # bytes/s
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen(1); s.settimeout(60)
c, _ = s.accept()
c.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 128 * 1024)
t0 = time.time(); got = 0
while True:
    d = c.recv(16384)
    if not d: break
    got += len(d)
    ahead = got / rate - (time.time() - t0)
    if ahead > 0: time.sleep(ahead)
