#include <errno.h>
#include <fcntl.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include "plugin_api_v1.h"

#define RING_SECONDS 5
#define RING_SAMPLES (MOVE_SAMPLE_RATE * 2 * RING_SECONDS)
#define AUDIO_IDLE_MS 1500
#define RECONNECT_COOLDOWN_MS 1500
#define LOG_PATH "/data/UserData/move-anything/cache/streamrtsp-runtime.log"
#define CACHE_DIR_DEFAULT "/data/UserData/move-anything/cache/streamrtsp"
#define MANUAL_SUFFIX_DEFAULT 0
#define MANUAL_PORT_DEFAULT 8554
#define MANUAL_PATH_DEFAULT "screen"
#define MAX_DISCOVERY_CANDIDATES 16
#define MAX_HISTORY_ENTRIES 5

static const host_api_v1_t *g_host = NULL;
static int g_instance_counter = 0;

typedef struct {
    char module_dir[512];
    char cache_dir[512];
    char fifo_path[512];
    char discovery_path[512];
    char last_sender_path[512];
    char auto_reconnect_path[512];
    char manual_suffix_path[512];
    char manual_port_path[512];
    char manual_path_path[512];
    char history_path[512];
    char endpoint[512];
    char discovered_url[512];
    char discovered_name[128];
    char candidate_urls[MAX_DISCOVERY_CANDIDATES][512];
    char candidate_names[MAX_DISCOVERY_CANDIDATES][128];
    int candidate_count;
    char network_prefix[32];
    char state[32];
    char error_msg[256];
    char last_error_detail[256];

    int slot;
    int fifo_fd;
    pid_t backend_pid;
    pid_t scan_pid;
    bool backend_running;
    bool scan_running;
    bool auto_reconnect;
    int manual_suffix;
    int manual_port;
    char manual_path[128];
    char history_endpoints[MAX_HISTORY_ENTRIES][512];
    int history_count;

    int buffer_mode; /* 96=Normal, 160=Safe, 320=Max Stability */
    float gain;

    int16_t ring[RING_SAMPLES];
    size_t write_pos;
    uint64_t write_abs;
    uint64_t play_abs;
    uint8_t pending_bytes[4];
    uint8_t pending_len;
    uint64_t last_audio_ms;
    uint64_t last_restart_ms;
    off_t last_log_offset;
} streamrtsp_instance_t;

static uint64_t now_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (uint64_t)tv.tv_sec * 1000ULL + (uint64_t)tv.tv_usec / 1000ULL;
}

static void ap_log(const char *msg) {
    FILE *fp;
    if (!msg || msg[0] == '\0') return;

    fp = fopen(LOG_PATH, "a");
    if (fp) {
        fprintf(fp, "%s\n", msg);
        fclose(fp);
    }

    if (g_host && g_host->log) {
        char prefixed[384];
        snprintf(prefixed, sizeof(prefixed), "[streamrtsp] %s", msg);
        g_host->log(prefixed);
    }
}

static void set_state(streamrtsp_instance_t *inst, const char *state) {
    char msg[192];
    if (!inst || !state || state[0] == '\0') return;
    if (strcmp(inst->state, state) == 0) return;

    snprintf(msg, sizeof(msg), "state: %s -> %s", inst->state[0] ? inst->state : "unset", state);
    ap_log(msg);
    snprintf(inst->state, sizeof(inst->state), "%s", state);
}

static void set_last_error_detail(streamrtsp_instance_t *inst, const char *msg) {
    if (!inst) return;
    if (!msg || msg[0] == '\0') {
        inst->last_error_detail[0] = '\0';
        return;
    }
    snprintf(inst->last_error_detail, sizeof(inst->last_error_detail), "%s", msg);
}

static void set_error(streamrtsp_instance_t *inst, const char *msg) {
    if (!inst) return;
    snprintf(inst->error_msg, sizeof(inst->error_msg), "%s", msg ? msg : "unknown error");
    set_last_error_detail(inst, inst->error_msg);
    set_state(inst, "error");
    ap_log(inst->error_msg);
}

static void clear_error(streamrtsp_instance_t *inst) {
    if (!inst) return;
    inst->error_msg[0] = '\0';
}

static bool parse_bool(const char *v) {
    if (!v) return false;
    return strcmp(v, "1") == 0 || strcmp(v, "true") == 0 || strcmp(v, "on") == 0 ||
           strcmp(v, "yes") == 0;
}

static bool resolve_ffmpeg_binary(const streamrtsp_instance_t *inst, char *out, size_t out_len) {
    const char *system_paths[] = {
        "/usr/bin/ffmpeg",
        "/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        NULL
    };
    char module_ffmpeg[1024];
    size_t i;

    if (!inst || !out || out_len == 0) return false;

    snprintf(module_ffmpeg, sizeof(module_ffmpeg), "%s/bin/ffmpeg", inst->module_dir);
    if (access(module_ffmpeg, X_OK) == 0) {
        snprintf(out, out_len, "%s", module_ffmpeg);
        return true;
    }

    for (i = 0; system_paths[i] != NULL; i++) {
        if (access(system_paths[i], X_OK) == 0) {
            snprintf(out, out_len, "%s", system_paths[i]);
            return true;
        }
    }

    out[0] = '\0';
    return false;
}

static void detect_network_prefix(char *out, size_t out_len) {
    int sockfd;
    struct sockaddr_in dst;
    struct sockaddr_in local;
    socklen_t local_len;
    char ip[64];
    unsigned int a;
    unsigned int b;
    unsigned int c;
    unsigned int d;

    if (!out || out_len == 0) return;
    snprintf(out, out_len, "192.168.0");

    sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sockfd < 0) return;

    memset(&dst, 0, sizeof(dst));
    dst.sin_family = AF_INET;
    dst.sin_port = htons(53);
    if (inet_pton(AF_INET, "1.1.1.1", &dst.sin_addr) != 1) {
        close(sockfd);
        return;
    }

    if (connect(sockfd, (struct sockaddr *)&dst, sizeof(dst)) != 0) {
        close(sockfd);
        return;
    }

    memset(&local, 0, sizeof(local));
    local_len = sizeof(local);
    if (getsockname(sockfd, (struct sockaddr *)&local, &local_len) != 0) {
        close(sockfd);
        return;
    }

    if (!inet_ntop(AF_INET, &local.sin_addr, ip, sizeof(ip))) {
        close(sockfd);
        return;
    }

    if (sscanf(ip, "%u.%u.%u.%u", &a, &b, &c, &d) == 4 &&
        a <= 255U && b <= 255U && c <= 255U) {
        snprintf(out, out_len, "%u.%u.%u", a, b, c);
    }

    close(sockfd);
}

static size_t ring_available(const streamrtsp_instance_t *inst) {
    uint64_t avail;
    if (!inst || inst->write_abs <= inst->play_abs) return 0;
    avail = inst->write_abs - inst->play_abs;
    if (avail > (uint64_t)RING_SAMPLES) avail = (uint64_t)RING_SAMPLES;
    return (size_t)avail;
}

static void clear_ring(streamrtsp_instance_t *inst) {
    if (!inst) return;
    inst->write_pos = 0;
    inst->write_abs = 0;
    inst->play_abs = 0;
    inst->pending_len = 0;
    memset(inst->pending_bytes, 0, sizeof(inst->pending_bytes));
}

static void ring_push(streamrtsp_instance_t *inst, const int16_t *samples, size_t n) {
    size_t i;
    uint64_t oldest;
    if (!inst || !samples || n == 0) return;

    for (i = 0; i < n; i++) {
        inst->ring[inst->write_pos] = samples[i];
        inst->write_pos = (inst->write_pos + 1) % RING_SAMPLES;
        inst->write_abs++;
    }

    oldest = inst->write_abs > (uint64_t)RING_SAMPLES ?
        inst->write_abs - (uint64_t)RING_SAMPLES : 0;
    if (inst->play_abs < oldest) {
        inst->play_abs = oldest;
    }
}

static size_t ring_pop(streamrtsp_instance_t *inst, int16_t *out, size_t n) {
    size_t got;
    size_t i;
    uint64_t abs_pos;

    if (!inst || !out || n == 0) return 0;
    got = ring_available(inst);
    if (got > n) got = n;

    abs_pos = inst->play_abs;
    for (i = 0; i < got; i++) {
        out[i] = inst->ring[(size_t)(abs_pos % (uint64_t)RING_SAMPLES)];
        abs_pos++;
    }
    inst->play_abs = abs_pos;
    return got;
}

static void save_last_endpoint(streamrtsp_instance_t *inst) {
    FILE *fp;
    if (!inst || inst->endpoint[0] == '\0') return;
    fp = fopen(inst->last_sender_path, "w");
    if (!fp) return;
    fprintf(fp, "endpoint=%s\n", inst->endpoint);
    fclose(fp);
}

static void load_last_endpoint(streamrtsp_instance_t *inst) {
    FILE *fp;
    char line[640];
    if (!inst) return;

    fp = fopen(inst->last_sender_path, "r");
    if (!fp) return;

    while (fgets(line, sizeof(line), fp)) {
        char *eq = strchr(line, '=');
        if (!eq) continue;
        *eq = '\0';
        if (strcmp(line, "endpoint") == 0) {
            char *val = eq + 1;
            size_t len = strlen(val);
            while (len > 0 && (val[len - 1] == '\n' || val[len - 1] == '\r')) {
                val[--len] = '\0';
            }
            snprintf(inst->endpoint, sizeof(inst->endpoint), "%s", val);
        }
    }

    fclose(fp);
}

static void save_auto_reconnect(streamrtsp_instance_t *inst) {
    FILE *fp;
    if (!inst) return;
    fp = fopen(inst->auto_reconnect_path, "w");
    if (!fp) return;
    fprintf(fp, "%d\n", inst->auto_reconnect ? 1 : 0);
    fclose(fp);
}

static void load_auto_reconnect(streamrtsp_instance_t *inst) {
    FILE *fp;
    int v = 1;
    if (!inst) return;
    fp = fopen(inst->auto_reconnect_path, "r");
    if (!fp) {
        inst->auto_reconnect = true;
        return;
    }
    if (fscanf(fp, "%d", &v) == 1) {
        inst->auto_reconnect = (v != 0);
    }
    fclose(fp);
}

static void save_manual_suffix(streamrtsp_instance_t *inst) {
    FILE *fp;
    if (!inst) return;
    fp = fopen(inst->manual_suffix_path, "w");
    if (!fp) return;
    fprintf(fp, "%d\n", inst->manual_suffix);
    fclose(fp);
}

static void load_manual_suffix(streamrtsp_instance_t *inst) {
    FILE *fp;
    int v = MANUAL_SUFFIX_DEFAULT;
    if (!inst) return;
    fp = fopen(inst->manual_suffix_path, "r");
    if (!fp) {
        inst->manual_suffix = MANUAL_SUFFIX_DEFAULT;
        return;
    }
    if (fscanf(fp, "%d", &v) == 1 && v >= 0 && v <= 254) {
        inst->manual_suffix = v;
    } else {
        inst->manual_suffix = MANUAL_SUFFIX_DEFAULT;
    }
    fclose(fp);
}

static void save_manual_port(streamrtsp_instance_t *inst) {
    FILE *fp;
    if (!inst) return;
    fp = fopen(inst->manual_port_path, "w");
    if (!fp) return;
    fprintf(fp, "%d\n", inst->manual_port);
    fclose(fp);
}

static void load_manual_port(streamrtsp_instance_t *inst) {
    FILE *fp;
    int v = MANUAL_PORT_DEFAULT;
    if (!inst) return;
    fp = fopen(inst->manual_port_path, "r");
    if (!fp) {
        inst->manual_port = MANUAL_PORT_DEFAULT;
        return;
    }
    if (fscanf(fp, "%d", &v) == 1 && v >= 1 && v <= 65535) {
        inst->manual_port = v;
    } else {
        inst->manual_port = MANUAL_PORT_DEFAULT;
    }
    fclose(fp);
}

static void sanitize_manual_path(const char *in, char *out, size_t out_len) {
    size_t src_idx = 0;
    size_t dst_idx = 0;
    if (!out || out_len == 0) return;
    out[0] = '\0';

    if (!in) {
        snprintf(out, out_len, "%s", MANUAL_PATH_DEFAULT);
        return;
    }

    while (in[src_idx] == ' ' || in[src_idx] == '\t' || in[src_idx] == '\n' || in[src_idx] == '\r') {
        src_idx++;
    }
    while (in[src_idx] == '/') {
        src_idx++;
    }

    while (in[src_idx] != '\0' && dst_idx + 1 < out_len) {
        char c = in[src_idx++];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') break;
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '/' || c == '.') {
            out[dst_idx++] = c;
        }
    }

    out[dst_idx] = '\0';
    if (out[0] == '\0') {
        snprintf(out, out_len, "%s", MANUAL_PATH_DEFAULT);
    }
}

static void save_manual_path(streamrtsp_instance_t *inst) {
    FILE *fp;
    if (!inst) return;
    fp = fopen(inst->manual_path_path, "w");
    if (!fp) return;
    fprintf(fp, "%s\n", inst->manual_path[0] ? inst->manual_path : MANUAL_PATH_DEFAULT);
    fclose(fp);
}

static void load_manual_path(streamrtsp_instance_t *inst) {
    FILE *fp;
    char line[256];
    if (!inst) return;
    fp = fopen(inst->manual_path_path, "r");
    if (!fp) {
        snprintf(inst->manual_path, sizeof(inst->manual_path), "%s", MANUAL_PATH_DEFAULT);
        return;
    }
    if (fgets(line, sizeof(line), fp)) {
        char cleaned[128];
        size_t len = strlen(line);
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) {
            line[--len] = '\0';
        }
        sanitize_manual_path(line, cleaned, sizeof(cleaned));
        snprintf(inst->manual_path, sizeof(inst->manual_path), "%s", cleaned);
    } else {
        snprintf(inst->manual_path, sizeof(inst->manual_path), "%s", MANUAL_PATH_DEFAULT);
    }
    fclose(fp);
}

static void save_history(streamrtsp_instance_t *inst) {
    FILE *fp;
    int i;
    if (!inst) return;
    fp = fopen(inst->history_path, "w");
    if (!fp) return;
    fprintf(fp, "count=%d\n", inst->history_count);
    for (i = 0; i < inst->history_count && i < MAX_HISTORY_ENTRIES; i++) {
        fprintf(fp, "entry_%d=%s\n", i, inst->history_endpoints[i]);
    }
    fclose(fp);
}

static void load_history(streamrtsp_instance_t *inst) {
    FILE *fp;
    FILE *legacy_fp;
    char line[768];
    char legacy_path[512];
    int i;
    if (!inst) return;

    inst->history_count = 0;
    for (i = 0; i < MAX_HISTORY_ENTRIES; i++) {
        inst->history_endpoints[i][0] = '\0';
    }

    fp = fopen(inst->history_path, "r");
    if (!fp) {
        /* Migrate once from legacy cache history location if present. */
        snprintf(legacy_path, sizeof(legacy_path), "%s/history.env", inst->cache_dir);
        legacy_fp = fopen(legacy_path, "r");
        if (!legacy_fp) return;
        fp = legacy_fp;
    }

    while (fgets(line, sizeof(line), fp)) {
        char *eq = strchr(line, '=');
        if (!eq) continue;
        *eq = '\0';
        {
            char *val = eq + 1;
            size_t len = strlen(val);
            int idx = -1;
            while (len > 0 && (val[len - 1] == '\n' || val[len - 1] == '\r')) {
                val[--len] = '\0';
            }
            if (sscanf(line, "entry_%d", &idx) == 1 &&
                idx >= 0 && idx < MAX_HISTORY_ENTRIES && val[0] != '\0') {
                snprintf(inst->history_endpoints[idx], sizeof(inst->history_endpoints[idx]), "%s", val);
                if (idx + 1 > inst->history_count) inst->history_count = idx + 1;
            }
        }
    }
    fclose(fp);

    /* Persist migrated/loaded history to current location. */
    save_history(inst);
}

static void add_history_endpoint(streamrtsp_instance_t *inst, const char *endpoint) {
    int i;
    int existing_idx = -1;
    int write_idx = 1;
    char entries[MAX_HISTORY_ENTRIES][512];

    if (!inst || !endpoint || endpoint[0] == '\0') return;

    for (i = 0; i < inst->history_count; i++) {
        if (strcmp(inst->history_endpoints[i], endpoint) == 0) {
            existing_idx = i;
            break;
        }
    }

    /* Already most recent and unchanged: avoid rewriting history file. */
    if (existing_idx == 0) return;

    snprintf(entries[0], sizeof(entries[0]), "%s", endpoint);
    for (i = 0; i < inst->history_count && write_idx < MAX_HISTORY_ENTRIES; i++) {
        if (inst->history_endpoints[i][0] == '\0') continue;
        if (strcmp(inst->history_endpoints[i], endpoint) == 0) continue;
        snprintf(entries[write_idx], sizeof(entries[write_idx]), "%s", inst->history_endpoints[i]);
        write_idx++;
    }

    inst->history_count = write_idx;
    for (i = 0; i < MAX_HISTORY_ENTRIES; i++) {
        inst->history_endpoints[i][0] = '\0';
    }
    for (i = 0; i < inst->history_count; i++) {
        snprintf(inst->history_endpoints[i], sizeof(inst->history_endpoints[i]), "%s", entries[i]);
    }
    save_history(inst);
}

static void build_manual_endpoint(streamrtsp_instance_t *inst, int suffix, char *out, size_t out_len) {
    int port;
    char path[128];
    if (!inst || !out || out_len == 0) return;
    if (suffix < 1 || suffix > 254) suffix = MANUAL_SUFFIX_DEFAULT;
    port = inst->manual_port;
    if (port < 1 || port > 65535) port = MANUAL_PORT_DEFAULT;
    sanitize_manual_path(inst->manual_path, path, sizeof(path));
    if (inst->network_prefix[0] == '\0') {
        detect_network_prefix(inst->network_prefix, sizeof(inst->network_prefix));
    }
    snprintf(out, out_len, "rtsp://%s.%d:%d/%s", inst->network_prefix, suffix, port, path);
}

static int create_fifo(streamrtsp_instance_t *inst) {
    if (!inst) return -1;

    snprintf(inst->fifo_path, sizeof(inst->fifo_path), "/tmp/streamrtsp-audio-%d", inst->slot);
    (void)unlink(inst->fifo_path);
    if (mkfifo(inst->fifo_path, 0666) != 0) {
        set_error(inst, "mkfifo failed");
        return -1;
    }

    inst->fifo_fd = open(inst->fifo_path, O_RDWR | O_NONBLOCK);
    if (inst->fifo_fd < 0) {
        set_error(inst, "open fifo failed");
        (void)unlink(inst->fifo_path);
        inst->fifo_path[0] = '\0';
        return -1;
    }

    return 0;
}

static void close_fifo(streamrtsp_instance_t *inst) {
    if (!inst) return;
    if (inst->fifo_fd >= 0) {
        close(inst->fifo_fd);
        inst->fifo_fd = -1;
    }
    if (inst->fifo_path[0] != '\0') {
        (void)unlink(inst->fifo_path);
        inst->fifo_path[0] = '\0';
    }
}

static void terminate_child(pid_t *pid_io, bool *running_io) {
    pid_t pid;
    int status = 0;
    pid_t rc;
    uint64_t start;

    if (!pid_io) return;
    pid = *pid_io;
    if (pid <= 0) {
        if (running_io) *running_io = false;
        *pid_io = -1;
        return;
    }

    rc = waitpid(pid, &status, WNOHANG);
    if (rc == 0) {
        (void)kill(-pid, SIGTERM);
        (void)kill(pid, SIGTERM);
        start = now_ms();
        while ((now_ms() - start) < 750ULL) {
            rc = waitpid(pid, &status, WNOHANG);
            if (rc == pid || (rc < 0 && errno == ECHILD)) {
                break;
            }
            usleep(50000);
        }
    }

    if (rc == 0) {
        (void)kill(-pid, SIGKILL);
        (void)kill(pid, SIGKILL);
        start = now_ms();
        while ((now_ms() - start) < 300ULL) {
            rc = waitpid(pid, &status, WNOHANG);
            if (rc == pid || (rc < 0 && errno == ECHILD)) {
                break;
            }
            usleep(20000);
        }
    }

    *pid_io = -1;
    if (running_io) *running_io = false;
}

static void supervisor_stop(streamrtsp_instance_t *inst) {
    if (!inst) return;

    terminate_child(&inst->backend_pid, &inst->backend_running);
    clear_ring(inst);
    set_state(inst, "disconnected");
}

static int supervisor_start(streamrtsp_instance_t *inst, const char *endpoint, bool reconnecting) {
    char backend_script[1024];
    char ffmpeg_bin[1024];
    struct stat st;
    pid_t pid;

    if (!inst || !endpoint || endpoint[0] == '\0') {
        if (inst) set_error(inst, "missing RTSP endpoint");
        return -1;
    }

    snprintf(backend_script, sizeof(backend_script), "%s/bin/streamrtsp_backend.sh", inst->module_dir);
    if (access(backend_script, X_OK) != 0) {
        set_error(inst, "streamrtsp_backend.sh missing or not executable");
        return -1;
    }

    if (!resolve_ffmpeg_binary(inst, ffmpeg_bin, sizeof(ffmpeg_bin))) {
        set_error(inst, "ffmpeg missing on Move (install/bundle ffmpeg)");
        return -1;
    }

    supervisor_stop(inst);
    clear_error(inst);
    inst->last_log_offset = 0;
    if (stat(LOG_PATH, &st) == 0 && st.st_size > 0) {
        inst->last_log_offset = st.st_size;
    }

    pid = fork();
    if (pid < 0) {
        set_error(inst, "fork failed for RTSP backend");
        return -1;
    }

    if (pid == 0) {
        int devnull;
        int logfd;
        (void)setpgid(0, 0);

        devnull = open("/dev/null", O_WRONLY);
        if (devnull >= 0) {
            dup2(devnull, STDOUT_FILENO);
            close(devnull);
        }

        logfd = open(LOG_PATH, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (logfd >= 0) {
            dup2(logfd, STDERR_FILENO);
            close(logfd);
        }

        (void)setenv("FFMPEG_BIN", ffmpeg_bin, 1);

        execl(backend_script,
              "streamrtsp_backend.sh",
              inst->fifo_path,
              endpoint,
              LOG_PATH,
              (char *)NULL);
        _exit(127);
    }

    (void)setpgid(pid, pid);
    inst->backend_pid = pid;
    inst->backend_running = true;
    inst->last_restart_ms = now_ms();
    inst->last_audio_ms = 0;
    snprintf(inst->endpoint, sizeof(inst->endpoint), "%s", endpoint);
    save_last_endpoint(inst);

    if (reconnecting) {
        set_state(inst, "reconnecting");
    } else {
        set_state(inst, "connecting");
    }
    return 0;
}

static void parse_discovery_file(streamrtsp_instance_t *inst) {
    FILE *fp;
    char line[768];
    int discovered_count = 0;
    int i;
    if (!inst) return;

    inst->discovered_url[0] = '\0';
    inst->discovered_name[0] = '\0';
    inst->candidate_count = 0;
    for (i = 0; i < MAX_DISCOVERY_CANDIDATES; i++) {
        inst->candidate_urls[i][0] = '\0';
        inst->candidate_names[i][0] = '\0';
    }

    fp = fopen(inst->discovery_path, "r");
    if (!fp) return;

    while (fgets(line, sizeof(line), fp)) {
        char *eq = strchr(line, '=');
        if (!eq) continue;
        *eq = '\0';

        {
            char *val = eq + 1;
            size_t len = strlen(val);
            while (len > 0 && (val[len - 1] == '\n' || val[len - 1] == '\r')) {
                val[--len] = '\0';
            }

            if (strcmp(line, "count") == 0) {
                discovered_count = atoi(val);
            } else if (strcmp(line, "resolved_url") == 0) {
                snprintf(inst->discovered_url, sizeof(inst->discovered_url), "%s", val);
            } else if (strcmp(line, "resolved_name") == 0) {
                snprintf(inst->discovered_name, sizeof(inst->discovered_name), "%s", val);
            } else {
                int idx = -1;
                if (sscanf(line, "candidate_%d_url", &idx) == 1 &&
                    idx >= 0 && idx < MAX_DISCOVERY_CANDIDATES) {
                    snprintf(inst->candidate_urls[idx], sizeof(inst->candidate_urls[idx]), "%s", val);
                    if (idx + 1 > inst->candidate_count) inst->candidate_count = idx + 1;
                } else if (sscanf(line, "candidate_%d_name", &idx) == 1 &&
                           idx >= 0 && idx < MAX_DISCOVERY_CANDIDATES) {
                    snprintf(inst->candidate_names[idx], sizeof(inst->candidate_names[idx]), "%s", val);
                    if (idx + 1 > inst->candidate_count) inst->candidate_count = idx + 1;
                }
            }
        }
    }

    fclose(fp);

    if (discovered_count > 0 && discovered_count < MAX_DISCOVERY_CANDIDATES) {
        inst->candidate_count = discovered_count;
    } else if (discovered_count >= MAX_DISCOVERY_CANDIDATES) {
        inst->candidate_count = MAX_DISCOVERY_CANDIDATES;
    }

    {
        char msg[704];
        snprintf(msg,
                 sizeof(msg),
                 "discovery completed: count=%d resolved_name=%s resolved_url=%s candidate_0_name=%s candidate_0_url=%s",
                 inst->candidate_count,
                 inst->discovered_name[0] ? inst->discovered_name : "(none)",
                 inst->discovered_url[0] ? inst->discovered_url : "(none)",
                 inst->candidate_names[0][0] ? inst->candidate_names[0] : "(none)",
                 inst->candidate_urls[0][0] ? inst->candidate_urls[0] : "(none)");
        ap_log(msg);
    }
}

static void read_runtime_log_since_offset(const streamrtsp_instance_t *inst, char *buf, size_t buf_len) {
    FILE *fp;
    long end = 0;
    long start = 0;
    size_t n = 0;

    if (!buf || buf_len == 0) return;
    buf[0] = '\0';

    fp = fopen(LOG_PATH, "r");
    if (!fp) return;

    if (fseek(fp, 0, SEEK_END) == 0) {
        end = ftell(fp);
        if (end > 0) {
            if (inst && inst->last_log_offset > 0 && inst->last_log_offset < end) {
                start = inst->last_log_offset;
            } else {
                start = end > 8192 ? end - 8192 : 0;
            }
            if (fseek(fp, start, SEEK_SET) != 0) {
                start = 0;
                (void)fseek(fp, 0, SEEK_SET);
            }
        } else {
            (void)fseek(fp, 0, SEEK_SET);
        }
    } else {
        (void)fseek(fp, 0, SEEK_SET);
    }

    n = fread(buf, 1, buf_len - 1, fp);
    buf[n] = '\0';
    fclose(fp);
}

static bool classify_backend_exit_and_set_error(streamrtsp_instance_t *inst, int status) {
    char tail[8192];

    if (!inst) return false;

    if (WIFEXITED(status) && WEXITSTATUS(status) == 127) {
        set_error(inst, "ffmpeg missing on Move (install/bundle ffmpeg)");
        return true;
    }

    read_runtime_log_since_offset(inst, tail, sizeof(tail));
    if (tail[0] == '\0') return false;

    if (strstr(tail, "Output file does not contain any stream") != NULL ||
        strstr(tail, "matches no streams") != NULL) {
        set_error(inst, "RTSP stream has no audio (enable sender audio)");
        return true;
    }

    if (strstr(tail, "404 Not Found") != NULL ||
        strstr(tail, "Server returned 404 Not Found") != NULL) {
        set_last_error_detail(inst, "404 endpoint not found");
        clear_error(inst);
        set_state(inst, "waiting_for_sender");
        ap_log("RTSP endpoint not found; waiting for sender and scheduling retry");
        return true;
    }

    if (strstr(tail, "503Service Unavailable") != NULL ||
        strstr(tail, "Server returned 5XX Server Error reply") != NULL ||
        strstr(tail, "method DESCRIBE failed") != NULL) {
        set_last_error_detail(inst, "503 server unavailable");
        clear_error(inst);
        set_state(inst, "waiting_for_sender");
        ap_log("RTSP server unavailable; waiting for sender and scheduling retry");
        return true;
    }

    if (strstr(tail, "Connection refused") != NULL) {
        set_last_error_detail(inst, "RTSP connection refused");
        clear_error(inst);
        set_state(inst, "waiting_for_sender");
        ap_log("RTSP server unavailable; waiting for sender and scheduling retry");
        return true;
    }

    if (strstr(tail, "Connection timed out") != NULL) {
        set_last_error_detail(inst, "RTSP connection timed out");
        clear_error(inst);
        set_state(inst, "waiting_for_sender");
        ap_log("RTSP server unavailable; waiting for sender and scheduling retry");
        return true;
    }

    return false;
}

static void poll_scan_process(streamrtsp_instance_t *inst) {
    int status;
    pid_t rc;

    if (!inst || !inst->scan_running || inst->scan_pid <= 0) return;

    rc = waitpid(inst->scan_pid, &status, WNOHANG);
    if (rc == 0) return;

    inst->scan_running = false;
    inst->scan_pid = -1;
    parse_discovery_file(inst);

    if (inst->discovered_url[0] != '\0') {
        if (inst->auto_reconnect && !inst->backend_running) {
            (void)supervisor_start(inst, inst->discovered_url, false);
        } else if (!inst->backend_running) {
            set_state(inst, "disconnected");
        }
    } else if (!inst->backend_running) {
        set_state(inst, "disconnected");
    }
}

static void start_scan(streamrtsp_instance_t *inst) {
    char discover_script[1024];
    pid_t pid;

    if (!inst) return;
    if (inst->scan_running) return;
    ap_log("scan requested");

    snprintf(discover_script, sizeof(discover_script), "%s/bin/screenstream_discovery.sh", inst->module_dir);
    if (access(discover_script, X_OK) != 0) {
        set_error(inst, "screenstream_discovery.sh missing or not executable");
        return;
    }

    pid = fork();
    if (pid < 0) {
        set_error(inst, "fork failed for discovery scan");
        return;
    }

    if (pid == 0) {
        int logfd = open(LOG_PATH, O_WRONLY | O_CREAT | O_APPEND, 0644);
        (void)setpgid(0, 0);
        if (logfd >= 0) {
            dup2(logfd, STDERR_FILENO);
            close(logfd);
        }

        execl(discover_script, "screenstream_discovery.sh", inst->cache_dir, (char *)NULL);
        _exit(127);
    }

    (void)setpgid(pid, pid);
    inst->scan_pid = pid;
    inst->scan_running = true;
    set_state(inst, "scanning");
}

static void check_backend_alive(streamrtsp_instance_t *inst) {
    int status;
    pid_t rc;
    uint64_t now;

    if (!inst || !inst->backend_running || inst->backend_pid <= 0) return;

    rc = waitpid(inst->backend_pid, &status, WNOHANG);
    if (rc == 0) return;

    inst->backend_pid = -1;
    inst->backend_running = false;

    if (classify_backend_exit_and_set_error(inst, status)) {
        return;
    }

    now = now_ms();
    if (inst->auto_reconnect && inst->endpoint[0] != '\0') {
        if (now > inst->last_restart_ms &&
            (now - inst->last_restart_ms) >= RECONNECT_COOLDOWN_MS) {
            (void)supervisor_start(inst, inst->endpoint, true);
        } else {
            clear_error(inst);
            set_state(inst, "waiting_for_sender");
        }
        return;
    }

    set_error(inst, "RTSP backend exited unexpectedly");
}

static void maybe_retry_sender(streamrtsp_instance_t *inst) {
    uint64_t now;

    if (!inst) return;
    if (inst->backend_running || inst->scan_running) return;
    if (!inst->auto_reconnect || inst->endpoint[0] == '\0') return;
    if (strcmp(inst->state, "waiting_for_sender") != 0 &&
        strcmp(inst->state, "reconnecting") != 0) {
        return;
    }

    now = now_ms();
    if (now <= inst->last_restart_ms) return;
    if ((now - inst->last_restart_ms) < RECONNECT_COOLDOWN_MS) return;

    (void)supervisor_start(inst, inst->endpoint, true);
}

static void pump_pipe(streamrtsp_instance_t *inst) {
    uint8_t buf[2048];
    uint8_t merged[4096];
    int16_t samples[2048];

    if (!inst || inst->fifo_fd < 0) return;

    while (1) {
        ssize_t n;
        size_t merged_bytes;
        size_t aligned_bytes;
        size_t remainder;
        size_t sample_count;

        if (ring_available(inst) + 2048 >= (size_t)RING_SAMPLES) break;

        n = read(inst->fifo_fd, buf, sizeof(buf));
        if (n <= 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) break;
            break;
        }

        merged_bytes = inst->pending_len;
        if (inst->pending_len > 0) {
            memcpy(merged, inst->pending_bytes, inst->pending_len);
        }
        memcpy(merged + merged_bytes, buf, (size_t)n);
        merged_bytes += (size_t)n;

        aligned_bytes = merged_bytes & ~((size_t)3U);
        remainder = merged_bytes - aligned_bytes;

        if (remainder > 0) {
            memcpy(inst->pending_bytes, merged + aligned_bytes, remainder);
        }
        inst->pending_len = (uint8_t)remainder;

        sample_count = aligned_bytes / sizeof(int16_t);
        if (sample_count > 0) {
            memcpy(samples, merged, sample_count * sizeof(int16_t));
            ring_push(inst, samples, sample_count);
            inst->last_audio_ms = now_ms();
            set_last_error_detail(inst, "");
            if (strcmp(inst->state, "connecting") == 0 ||
                strcmp(inst->state, "reconnecting") == 0) {
                set_state(inst, "buffering");
            }
        }

        if ((size_t)n < sizeof(buf)) break;
    }
}

static void* v2_create_instance(const char *module_dir, const char *json_defaults) {
    streamrtsp_instance_t *inst;

    (void)json_defaults;

    inst = calloc(1, sizeof(*inst));
    if (!inst) return NULL;

    inst->slot = ++g_instance_counter;
    snprintf(inst->module_dir, sizeof(inst->module_dir), "%s", module_dir ? module_dir : ".");
    snprintf(inst->cache_dir, sizeof(inst->cache_dir), "%s", CACHE_DIR_DEFAULT);
    snprintf(inst->discovery_path, sizeof(inst->discovery_path), "%s/discovery.env", inst->cache_dir);
    snprintf(inst->last_sender_path, sizeof(inst->last_sender_path), "%s/last_sender.env", inst->cache_dir);
    snprintf(inst->auto_reconnect_path, sizeof(inst->auto_reconnect_path), "%s/auto_reconnect.env", inst->cache_dir);
    snprintf(inst->manual_suffix_path, sizeof(inst->manual_suffix_path), "%s/manual_suffix.env", inst->cache_dir);
    snprintf(inst->manual_port_path, sizeof(inst->manual_port_path), "%s/manual_port.env", inst->cache_dir);
    snprintf(inst->manual_path_path, sizeof(inst->manual_path_path), "%s/manual_path.env", inst->cache_dir);
    snprintf(inst->history_path, sizeof(inst->history_path), "%s/history.env", inst->module_dir);
    detect_network_prefix(inst->network_prefix, sizeof(inst->network_prefix));

    inst->fifo_fd = -1;
    inst->backend_pid = -1;
    inst->scan_pid = -1;
    inst->backend_running = false;
    inst->scan_running = false;
    inst->gain = 1.0f;
    inst->buffer_mode = 320;
    inst->manual_suffix = MANUAL_SUFFIX_DEFAULT;
    inst->manual_port = MANUAL_PORT_DEFAULT;
    snprintf(inst->manual_path, sizeof(inst->manual_path), "%s", MANUAL_PATH_DEFAULT);
    inst->history_count = 0;
    inst->last_log_offset = 0;
    set_state(inst, "disconnected");

    (void)mkdir(inst->cache_dir, 0755);
    load_auto_reconnect(inst);
    load_manual_suffix(inst);
    load_manual_port(inst);
    load_manual_path(inst);
    load_history(inst);
    load_last_endpoint(inst);

    if (create_fifo(inst) != 0) {
        free(inst);
        return NULL;
    }

    ap_log("streamrtsp plugin instance created");
    return inst;
}

static void v2_destroy_instance(void *instance) {
    streamrtsp_instance_t *inst = (streamrtsp_instance_t *)instance;
    if (!inst) return;

    terminate_child(&inst->scan_pid, &inst->scan_running);

    supervisor_stop(inst);
    close_fifo(inst);
    free(inst);

    if (g_instance_counter > 0) g_instance_counter--;
    ap_log("streamrtsp plugin instance destroyed");
}

static void v2_on_midi(void *instance, const uint8_t *msg, int len, int source) {
    (void)instance;
    (void)msg;
    (void)len;
    (void)source;
}

static void v2_set_param(void *instance, const char *key, const char *val) {
    streamrtsp_instance_t *inst = (streamrtsp_instance_t *)instance;
    if (!inst || !key || !val) return;

    if (strcmp(key, "gain") == 0) {
        float g = (float)atof(val);
        if (g < 0.0f) g = 0.0f;
        if (g > 2.0f) g = 2.0f;
        inst->gain = g;
        return;
    }

    if (strcmp(key, "quality") == 0) {
        int q = atoi(val);
        if (q != 96 && q != 160 && q != 320) q = 320;
        inst->buffer_mode = q;
        return;
    }

    if (strcmp(key, "auto_reconnect") == 0) {
        inst->auto_reconnect = parse_bool(val);
        save_auto_reconnect(inst);
        return;
    }

    if (strcmp(key, "scan") == 0) {
        ap_log("scan button pressed");
        start_scan(inst);
        return;
    }

    if (strcmp(key, "endpoint") == 0) {
        if (val[0] != '\0') {
            char msg[640];
            snprintf(inst->endpoint, sizeof(inst->endpoint), "%s", val);
            save_last_endpoint(inst);
            snprintf(msg, sizeof(msg), "endpoint updated: %s", inst->endpoint);
            ap_log(msg);
        }
        return;
    }

    if (strcmp(key, "manual_suffix") == 0) {
        int suffix = atoi(val);
        if (suffix < 0) suffix = 0;
        if (suffix > 254) suffix = 254;
        inst->manual_suffix = suffix;
        save_manual_suffix(inst);
        return;
    }

    if (strcmp(key, "manual_port") == 0) {
        int port = atoi(val);
        if (port < 1) port = MANUAL_PORT_DEFAULT;
        if (port > 65535) port = 65535;
        inst->manual_port = port;
        save_manual_port(inst);
        return;
    }

    if (strcmp(key, "manual_path") == 0) {
        char cleaned[128];
        sanitize_manual_path(val, cleaned, sizeof(cleaned));
        snprintf(inst->manual_path, sizeof(inst->manual_path), "%s", cleaned);
        save_manual_path(inst);
        return;
    }

    if (strcmp(key, "connect_manual") == 0) {
        char endpoint[512];
        char msg[704];
        if (inst->manual_suffix < 1 || inst->manual_suffix > 254) {
            set_error(inst, "enter IP suffix before connecting");
            return;
        }
        build_manual_endpoint(inst, inst->manual_suffix, endpoint, sizeof(endpoint));
        snprintf(msg, sizeof(msg), "connect_manual requested: target=%s", endpoint);
        ap_log(msg);
        add_history_endpoint(inst, endpoint);
        (void)supervisor_start(inst, endpoint, false);
        return;
    }

    if (strcmp(key, "connect_suffix") == 0) {
        int suffix = val[0] ? atoi(val) : inst->manual_suffix;
        char endpoint[512];
        char msg[704];
        if (suffix < 1 || suffix > 254) {
            set_error(inst, "invalid IP suffix");
            return;
        }
        build_manual_endpoint(inst, suffix, endpoint, sizeof(endpoint));
        snprintf(msg, sizeof(msg), "connect_suffix requested: suffix=%d target=%s", suffix, endpoint);
        ap_log(msg);
        add_history_endpoint(inst, endpoint);
        (void)supervisor_start(inst, endpoint, false);
        return;
    }

    if (strcmp(key, "connect_history") == 0) {
        int idx = atoi(val);
        char msg[704];
        if (idx < 0 || idx >= inst->history_count ||
            inst->history_endpoints[idx][0] == '\0') {
            set_error(inst, "invalid history selection");
            return;
        }
        snprintf(msg, sizeof(msg), "connect_history requested: index=%d target=%s",
                 idx, inst->history_endpoints[idx]);
        ap_log(msg);
        add_history_endpoint(inst, inst->history_endpoints[idx]);
        (void)supervisor_start(inst, inst->history_endpoints[idx], false);
        return;
    }

    if (strcmp(key, "connect_candidate") == 0) {
        int idx = atoi(val);
        char msg[704];
        if (idx < 0 || idx >= inst->candidate_count ||
            inst->candidate_urls[idx][0] == '\0') {
            set_error(inst, "invalid discovery selection");
            return;
        }
        snprintf(msg, sizeof(msg), "connect_candidate requested: index=%d target=%s",
                 idx, inst->candidate_urls[idx]);
        ap_log(msg);
        (void)supervisor_start(inst, inst->candidate_urls[idx], false);
        return;
    }

    if (strcmp(key, "connect") == 0) {
        const char *target = val;
        char msg[704];
        if (target[0] == '\0') {
            target = inst->discovered_url[0] != '\0' ? inst->discovered_url : inst->endpoint;
        }
        snprintf(msg, sizeof(msg), "connect requested: target=%s", target[0] ? target : "(none)");
        ap_log(msg);
        if (target[0] != '\0') add_history_endpoint(inst, target);
        (void)supervisor_start(inst, target, false);
        return;
    }

    if (strcmp(key, "connect_last") == 0) {
        load_last_endpoint(inst);
        if (inst->endpoint[0] == '\0') {
            ap_log("connect_last requested without saved endpoint; triggering scan");
            start_scan(inst);
            return;
        }
        {
            char msg[640];
            snprintf(msg, sizeof(msg), "connect_last requested: endpoint=%s", inst->endpoint);
            ap_log(msg);
        }
        (void)supervisor_start(inst, inst->endpoint, false);
        return;
    }

    if (strcmp(key, "disconnect") == 0) {
        ap_log("disconnect requested");
        supervisor_stop(inst);
        set_last_error_detail(inst, "");
        return;
    }

    if (strcmp(key, "restart") == 0) {
        const char *target = inst->endpoint;
        if (target[0] == '\0') target = inst->discovered_url;
        if (target[0] == '\0') {
            set_error(inst, "no endpoint configured");
            return;
        }
        {
            char msg[704];
            snprintf(msg, sizeof(msg), "restart requested: target=%s", target);
            ap_log(msg);
        }
        (void)supervisor_start(inst, target, false);
        return;
    }

    if (strcmp(key, "reset_client") == 0) {
        ap_log("reset_client requested");
        supervisor_stop(inst);
        clear_error(inst);
        set_last_error_detail(inst, "");
        inst->endpoint[0] = '\0';
        inst->discovered_url[0] = '\0';
        inst->discovered_name[0] = '\0';
        inst->manual_suffix = MANUAL_SUFFIX_DEFAULT;
        inst->manual_port = MANUAL_PORT_DEFAULT;
        snprintf(inst->manual_path, sizeof(inst->manual_path), "%s", MANUAL_PATH_DEFAULT);
        save_manual_suffix(inst);
        save_manual_port(inst);
        save_manual_path(inst);
        set_state(inst, "disconnected");
        return;
    }
}

static int v2_get_param(void *instance, const char *key, char *buf, int buf_len) {
    streamrtsp_instance_t *inst = (streamrtsp_instance_t *)instance;
    size_t avail;
    int pct;

    if (!key || !buf || buf_len <= 0) return -1;

    if (strcmp(key, "gain") == 0) {
        return snprintf(buf, (size_t)buf_len, "%.2f", inst ? inst->gain : 1.0f);
    }

    if (strcmp(key, "quality") == 0) {
        return snprintf(buf, (size_t)buf_len, "%d", inst ? inst->buffer_mode : 320);
    }

    if (strcmp(key, "auto_reconnect") == 0) {
        return snprintf(buf, (size_t)buf_len, "%s", (inst && inst->auto_reconnect) ? "1" : "0");
    }

    if (strcmp(key, "device_name") == 0) {
        if (inst && inst->discovered_name[0] != '\0') {
            return snprintf(buf, (size_t)buf_len, "%s", inst->discovered_name);
        }
        return snprintf(buf, (size_t)buf_len, "ScreenStream Sender");
    }

    if (strcmp(key, "track_name") == 0) {
        if (inst && inst->discovered_url[0] != '\0') {
            return snprintf(buf, (size_t)buf_len, "%s", inst->discovered_url);
        }
        return snprintf(buf, (size_t)buf_len, "%s", inst ? inst->endpoint : "");
    }

    if (strcmp(key, "track_artist") == 0) {
        return snprintf(buf, (size_t)buf_len, "%s", "RTSP Audio");
    }

    if (strcmp(key, "playback_event") == 0) {
        return snprintf(buf, (size_t)buf_len, "%s", inst ? inst->state : "disconnected");
    }

    if (strcmp(key, "backend_state") == 0) {
        return snprintf(buf, (size_t)buf_len, "%s", inst ? inst->state : "disconnected");
    }

    if (strcmp(key, "endpoint") == 0) {
        return snprintf(buf, (size_t)buf_len, "%s", inst ? inst->endpoint : "");
    }

    if (strcmp(key, "discovered_url") == 0) {
        return snprintf(buf, (size_t)buf_len, "%s", inst ? inst->discovered_url : "");
    }

    if (strcmp(key, "candidate_count") == 0) {
        return snprintf(buf, (size_t)buf_len, "%d", inst ? inst->candidate_count : 0);
    }

    if (inst) {
        int idx = -1;
        if (sscanf(key, "candidate_%d_name", &idx) == 1) {
            if (idx >= 0 && idx < inst->candidate_count) {
                return snprintf(buf, (size_t)buf_len, "%s", inst->candidate_names[idx]);
            }
            return snprintf(buf, (size_t)buf_len, "%s", "");
        }
        if (sscanf(key, "candidate_%d_url", &idx) == 1) {
            if (idx >= 0 && idx < inst->candidate_count) {
                return snprintf(buf, (size_t)buf_len, "%s", inst->candidate_urls[idx]);
            }
            return snprintf(buf, (size_t)buf_len, "%s", "");
        }
    }

    if (strcmp(key, "network_prefix") == 0) {
        return snprintf(buf, (size_t)buf_len, "%s", inst ? inst->network_prefix : "192.168.0");
    }

    if (strcmp(key, "manual_suffix") == 0) {
        return snprintf(buf, (size_t)buf_len, "%d", inst ? inst->manual_suffix : MANUAL_SUFFIX_DEFAULT);
    }

    if (strcmp(key, "manual_port") == 0) {
        return snprintf(buf, (size_t)buf_len, "%d", inst ? inst->manual_port : MANUAL_PORT_DEFAULT);
    }

    if (strcmp(key, "manual_path") == 0) {
        if (inst) {
            return snprintf(buf, (size_t)buf_len, "%s",
                            inst->manual_path[0] ? inst->manual_path : MANUAL_PATH_DEFAULT);
        }
        return snprintf(buf, (size_t)buf_len, "%s", MANUAL_PATH_DEFAULT);
    }

    if (strcmp(key, "history_count") == 0) {
        return snprintf(buf, (size_t)buf_len, "%d", inst ? inst->history_count : 0);
    }

    if (inst) {
        int idx = -1;
        if (sscanf(key, "history_%d", &idx) == 1) {
            if (idx >= 0 && idx < inst->history_count) {
                return snprintf(buf, (size_t)buf_len, "%s", inst->history_endpoints[idx]);
            }
            return snprintf(buf, (size_t)buf_len, "%s", "");
        }
    }

    if (strcmp(key, "buffer_health") == 0) {
        if (!inst) return snprintf(buf, (size_t)buf_len, "0");
        avail = ring_available(inst);
        pct = (int)((avail * 100U) / (size_t)RING_SAMPLES);
        return snprintf(buf, (size_t)buf_len, "%d", pct);
    }

    if (strcmp(key, "status") == 0) {
        if (!inst) return snprintf(buf, (size_t)buf_len, "error");
        if (inst->error_msg[0] != '\0') return snprintf(buf, (size_t)buf_len, "error");
        return snprintf(buf, (size_t)buf_len, "%s", inst->state);
    }

    if (strcmp(key, "last_error") == 0) {
        if (!inst) return snprintf(buf, (size_t)buf_len, "%s", "");
        if (inst->last_error_detail[0] != '\0') {
            return snprintf(buf, (size_t)buf_len, "%s", inst->last_error_detail);
        }
        return snprintf(buf, (size_t)buf_len, "%s", inst->error_msg);
    }

    return -1;
}

static int v2_get_error(void *instance, char *buf, int buf_len) {
    streamrtsp_instance_t *inst = (streamrtsp_instance_t *)instance;
    if (!inst || !buf || buf_len <= 0 || inst->error_msg[0] == '\0') return 0;
    return snprintf(buf, (size_t)buf_len, "%s", inst->error_msg);
}

static void v2_render_block(void *instance, int16_t *out_interleaved_lr, int frames) {
    streamrtsp_instance_t *inst = (streamrtsp_instance_t *)instance;
    size_t needed;
    size_t got;
    size_t i;

    if (!out_interleaved_lr || frames <= 0) return;

    needed = (size_t)frames * 2;
    memset(out_interleaved_lr, 0, needed * sizeof(int16_t));

    if (!inst) return;

    check_backend_alive(inst);
    poll_scan_process(inst);
    maybe_retry_sender(inst);
    pump_pipe(inst);

    if (inst->backend_running) {
        uint64_t now = now_ms();
        size_t avail = ring_available(inst);

        if (avail >= needed) {
            set_state(inst, "streaming");
        } else if (inst->state[0] != '\0' && strcmp(inst->state, "reconnecting") != 0) {
            set_state(inst, "buffering");
        }

        if (inst->last_audio_ms > 0 && now > inst->last_audio_ms &&
            (now - inst->last_audio_ms) > AUDIO_IDLE_MS) {
            set_state(inst, "buffering");
        }
    }

    got = ring_pop(inst, out_interleaved_lr, needed);
    if (got < needed) {
        memset(out_interleaved_lr + got, 0, (needed - got) * sizeof(int16_t));
    }

    if (inst->gain != 1.0f) {
        for (i = 0; i < needed; i++) {
            float s = (float)out_interleaved_lr[i] * inst->gain;
            if (s > 32767.0f) s = 32767.0f;
            if (s < -32768.0f) s = -32768.0f;
            out_interleaved_lr[i] = (int16_t)s;
        }
    }

    if (inst->backend_running) {
        out_interleaved_lr[needed - 1] |= 5;
    }
}

static plugin_api_v2_t g_plugin_api_v2 = {
    .api_version = MOVE_PLUGIN_API_VERSION_2,
    .create_instance = v2_create_instance,
    .destroy_instance = v2_destroy_instance,
    .on_midi = v2_on_midi,
    .set_param = v2_set_param,
    .get_param = v2_get_param,
    .get_error = v2_get_error,
    .render_block = v2_render_block,
};

plugin_api_v2_t* move_plugin_init_v2(const host_api_v1_t *host) {
    g_host = host;
    ap_log("streamrtsp plugin v2 initialized");
    return &g_plugin_api_v2;
}
