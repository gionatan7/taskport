#include "TaskportPTY.h"
#include <util.h>
#include <unistd.h>
#include <signal.h>
#include <fcntl.h>
#include <errno.h>
#include <stdlib.h>
#include <libproc.h>
#include <sys/ioctl.h>
#include <sys/wait.h>

pid_t tp_spawn(const char *directory, char *const argv[], char *const env[], int *master) {
    struct winsize size = { .ws_row = 24, .ws_col = 100 };
    // Find the close bound before fork; no Objective-C/Swift or allocator work in the child.
    int descriptor_limit = getdtablesize();
    pid_t child = forkpty(master, NULL, NULL, &size);
    if (child == 0) {
        sigset_t mask;
        sigemptyset(&mask);
        sigprocmask(SIG_SETMASK, &mask, NULL);
        for (int s = 1; s < NSIG; s++) signal(s, SIG_DFL);
        for (int fd = 3; fd < descriptor_limit; fd++) close(fd);
        if (chdir(directory) < 0) _exit(126);
        execve(argv[0], argv, env);
        _exit(127);
    }
    if (child > 0) {
        fcntl(*master, F_SETFD, FD_CLOEXEC);
        fcntl(*master, F_SETFL, fcntl(*master, F_GETFL) | O_NONBLOCK);
    }
    return child;
}

int tp_resize(int master, unsigned short columns, unsigned short rows) {
    struct winsize size = { .ws_row = rows, .ws_col = columns };
    return ioctl(master, TIOCSWINSZ, &size);
}

int tp_foreground(int master) { return tcgetpgrp(master); }

int tp_signal_foreground(int master, pid_t session, int signal_number) {
    pid_t group = tcgetpgrp(master);
    if (group <= 1 || getsid(group) != session) { errno = ESRCH; return -1; }
    return kill(-group, signal_number);
}

int tp_signal_session(pid_t session, int signal_number) {
    if (session <= 1 || session == getsid(0)) { errno = EINVAL; return -1; }
    int count = proc_listallpids(NULL, 0);
    if (count <= 0) return -1;
    int capacity = count + 256;
    pid_t *pids = calloc((size_t)capacity, sizeof(pid_t));
    if (!pids) return -1;
    count = proc_listallpids(pids, capacity * (int)sizeof(pid_t));
    int sent = 0;
    // Signal children first, session leader last. Call only while the child is unreaped.
    for (int i = 0; i < count && i < capacity; i++) {
        pid_t pid = pids[i];
        if (pid > 1 && pid != session && getsid(pid) == session && kill(pid, signal_number) == 0) sent++;
    }
    if (getsid(session) == session && kill(session, signal_number) == 0) sent++;
    free(pids);
    return sent;
}

int tp_reap(pid_t child, int *exit_code) {
    int status;
    pid_t result = waitpid(child, &status, WNOHANG);
    if (result <= 0) return (int)result;
    *exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
    return 1;
}
