#ifndef TASKPORT_PTY_H
#define TASKPORT_PTY_H
#include <sys/types.h>

/// Forks only inside C; the child immediately execs without entering Swift.
pid_t tp_spawn(const char *directory, char *const argv[], char *const env[], int *master);
int tp_resize(int master, unsigned short columns, unsigned short rows);
int tp_foreground(int master);
int tp_signal_foreground(int master, pid_t session, int signal_number);
/// Signals processes still belonging to an owned POSIX session. Detached daemons are excluded.
int tp_signal_session(pid_t session, int signal_number);
typedef struct {
    pid_t session;
    unsigned short port;
} tp_listener;
/// One read-only process snapshot for all owned sessions (IPv4 and IPv6 TCP listeners).
int tp_listening_ports(const pid_t *sessions, int session_count, tp_listener *listeners, int capacity);
/// Returns 1 when reaped, 0 while running, -1 on error. Exit uses shell-style 128+signal.
int tp_reap(pid_t child, int *exit_code);
#endif
