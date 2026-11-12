/* curl-on-Wine stall repro: SO_SNDBUF=64K (as curl sets from SIO_IDEAL_SEND_BACKLOG_QUERY),
 * 64K sends, then curl's multi_wait: select() precheck, else wait for FD_WRITE (1 s max). */
#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    WSADATA wd; SOCKET s; struct sockaddr_in a = {0}; u_long nb = 1;
    static char buf[65536];
    WSAEVENT ev; DWORD start, t0, w;
    int sndbuf = 65536, total = (argc > 2 ? atoi(argv[2]) : 4) << 20;
    int sent = 0, stalls = 0, waits = 0, wouldblock = 0, n;

    WSAStartup(MAKEWORD(2, 2), &wd);
    ev = WSACreateEvent();
    s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    a.sin_family = AF_INET; a.sin_port = htons(atoi(argv[1]));
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (connect(s, (struct sockaddr *)&a, sizeof(a))) return 1;
    ioctlsocket(s, FIONBIO, &nb);
    setsockopt(s, SOL_SOCKET, SO_SNDBUF, (char *)&sndbuf, sizeof(sndbuf));
    start = GetTickCount();

    while (sent < total)
    {
        n = send(s, buf, sizeof(buf), 0);
        if (n > 0) sent += n;
        else if (WSAGetLastError() == WSAEWOULDBLOCK) wouldblock++;
        else { printf("send err %d\n", WSAGetLastError()); break; }

        {   /* curl multi_wait() */
            fd_set wf; struct timeval tv = {0, 0};
            WSANETWORKEVENTS ne;
            FD_ZERO(&wf); FD_SET(s, &wf);
            send(s, NULL, 0, 0);
            WSAEventSelect(s, ev, FD_READ | FD_WRITE | FD_ACCEPT | FD_CONNECT | FD_CLOSE);
            if (select(0, NULL, &wf, NULL, &tv) == 0)
            {
                waits++;
                t0 = GetTickCount();
                WSAWaitForMultipleEvents(1, &ev, FALSE, 1000, FALSE);
                if ((w = GetTickCount() - t0) >= 900) stalls++;
            }
            WSAEnumNetworkEvents(s, NULL, &ne);
            WSAEventSelect(s, ev, 0);
            WSAResetEvent(ev);
        }
    }
    printf("sent %d MiB in %lu ms: %d waits, %d stalls of ~1s, %d wouldblock\n",
           sent >> 20, GetTickCount() - start, waits, stalls, wouldblock);
    closesocket(s);
    return stalls ? 2 : 0;
}
