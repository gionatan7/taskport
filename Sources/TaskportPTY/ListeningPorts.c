#include "TaskportPTY.h"
#include <libproc.h>
#include <stdlib.h>
#include <unistd.h>
#include <arpa/inet.h>

int tp_listening_ports(const pid_t *sessions, int session_count, tp_listener *listeners, int capacity) {
    if (!sessions || session_count <= 0 || !listeners || capacity <= 0) return 0;
    pid_t *leaders = calloc((size_t)session_count, sizeof(pid_t));
    if (!leaders) return 0;
    int owned_count = 0;
    for (int i = 0; i < session_count; i++) {
        if (sessions[i] > 1 && getsid(sessions[i]) == sessions[i]) leaders[owned_count++] = sessions[i];
    }
    if (owned_count == 0) { free(leaders); return 0; }
    int count = proc_listallpids(NULL, 0);
    if (count <= 0) { free(leaders); return 0; }
    int pid_capacity = count + 256;
    pid_t *pids = calloc((size_t)pid_capacity, sizeof(pid_t));
    if (!pids) { free(leaders); return 0; }
    count = proc_listallpids(pids, pid_capacity * (int)sizeof(pid_t));
    int found = 0;
    for (int i = 0; i < count && i < pid_capacity && found < capacity; i++) {
        pid_t pid = pids[i];
        if (pid <= 1) continue;
        pid_t session = getsid(pid);
        int owned = 0;
        for (int owner = 0; owner < owned_count; owner++) {
            if (leaders[owner] == session) { owned = 1; break; }
        }
        if (!owned) continue;
        int size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
        if (size <= 0) continue; // Processes may exit between observations.
        size += 32 * (int)sizeof(struct proc_fdinfo);
        struct proc_fdinfo *fds = malloc((size_t)size);
        if (!fds) continue;
        int bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, size);
        int fd_count = bytes > 0 ? bytes / (int)sizeof(struct proc_fdinfo) : 0;
        for (int j = 0; j < fd_count && found < capacity; j++) {
            if (fds[j].proc_fdtype != PROX_FDTYPE_SOCKET) continue;
            struct socket_fdinfo info = {0};
            int read = proc_pidfdinfo(pid, fds[j].proc_fd, PROC_PIDFDSOCKETINFO, &info, sizeof(info));
            if (read != sizeof(info) || info.psi.soi_kind != SOCKINFO_TCP) continue;
            if (info.psi.soi_proto.pri_tcp.tcpsi_state != TSI_S_LISTEN) continue;
            unsigned short port = ntohs((unsigned short)info.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport);
            if (port != 0) listeners[found++] = (tp_listener){ .session = session, .port = port };
        }
        free(fds);
    }
    free(pids);
    free(leaders);
    return found;
}
