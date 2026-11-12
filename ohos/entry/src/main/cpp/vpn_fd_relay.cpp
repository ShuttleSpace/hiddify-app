/*
 * VPN tun-fd relay for OHOS.
 *
 * Why this exists: on OHOS a `type: "vpn"` extension ability always runs in a
 * process of its own (`<bundle>:vpn`); `extensionProcessMode: "bundle"` only
 * merges a bundle's extensions together and `runWithMainProcess` is reserved
 * for statusBarView.  The vNIC file descriptor returned by
 * `VpnConnection.create()` therefore lives in the extension process, while
 * hiddify-core runs in the main (Flutter) process, and a file descriptor is a
 * per-process integer.  The only way across is SCM_RIGHTS over an AF_UNIX
 * socket, which ArkTS cannot do by itself.
 *
 *   extension process:  create() -> fd -> sendFd(path, fd)
 *   main process:       receiveFd(path, timeoutMs) -> fd (valid here) -> SetupTun(fd)
 *
 * Both ports are the same bundle and share a sandbox, so `context.filesDir`
 * is the same path in both.
 */
#include <napi/native_api.h>

#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <cstring>
#include <string>
#include <vector>

#include <arpa/inet.h>
#include <dlfcn.h>
#include <stdio.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace {

// Details of the last failed receive, reported in the rejection message.
char g_lastError[160] = {0};

// The ancillary buffer. One descriptor needs CMSG_SPACE(sizeof(int)) = 24 bytes, but the
// kernel may attach more than that: the OHOS kernel delivers the sender's credentials with
// the message, and a 24-byte buffer made it truncate the whole control data (MSG_CTRUNC,
// controllen = 0), i.e. drop the descriptor.
constexpr size_t kControlBufferSize = 512;

// OHOS app sandboxes deny bind() on a filesystem path (unix_stream_socket
// name_bind -> EACCES), so the relay uses the Linux abstract namespace instead:
// sun_path[0] is NUL and the name lives in the rest of the buffer. Abstract
// sockets are scoped to the network namespace and need no writable directory.
//
// The name carries the process uid so two apps, or two sockets of one app,
// cannot collide.
bool FillSockAddr(const std::string &name, sockaddr_un *addr, socklen_t *addrLength) {
  if (name.empty()) {
    return false;
  }
  std::memset(addr, 0, sizeof(*addr));
  addr->sun_family = AF_UNIX;
  std::string fullName = "hiddify.vpn." + name + "." + std::to_string(::getuid());
  if (fullName.size() + 1 > sizeof(addr->sun_path)) {
    return false;
  }
  addr->sun_path[0] = '\0';
  std::memcpy(addr->sun_path + 1, fullName.c_str(), fullName.size());
  *addrLength = static_cast<socklen_t>(offsetof(sockaddr_un, sun_path) + 1 + fullName.size());
  return true;
}

// Connects to the listener `name` and hands `fd` over with SCM_RIGHTS.
// Returns 0 on success or a negative errno.
int SendFdOnce(const std::string &name, int fd) {
  if (fd < 0) {
    return -EBADF;
  }
  sockaddr_un addr{};
  socklen_t addrLength = 0;
  if (!FillSockAddr(name, &addr, &addrLength)) {
    return -EINVAL;
  }
  int sock = ::socket(AF_UNIX, SOCK_STREAM, 0);
  if (sock < 0) {
    return -errno;
  }
  if (::connect(sock, reinterpret_cast<sockaddr *>(&addr), addrLength) < 0) {
    int err = errno;
    ::close(sock);
    return -err;
  }

  char payload = 'F';
  iovec iov{};
  iov.iov_base = &payload;
  iov.iov_len = 1;

  // Only the space one descriptor needs: the kernel walks the control buffer by
  // cmsg_len, and a larger zeroed buffer makes it walk into the padding and
  // reject the message (sendmsg -> EPIPE).
  char control[CMSG_SPACE(sizeof(int))];
  std::memset(control, 0, sizeof(control));
  msghdr msg{};
  msg.msg_iov = &iov;
  msg.msg_iovlen = 1;
  msg.msg_control = control;
  msg.msg_controllen = sizeof(control);

  cmsghdr *header = CMSG_FIRSTHDR(&msg);
  header->cmsg_level = SOL_SOCKET;
  header->cmsg_type = SCM_RIGHTS;
  header->cmsg_len = CMSG_LEN(sizeof(int));
  std::memcpy(CMSG_DATA(header), &fd, sizeof(int));

  ssize_t sent = ::sendmsg(sock, &msg, 0);
  int err = errno;
  ::close(sock);
  return sent == 1 ? 0 : -err;
}

// Binds a listener `name`, waits up to `timeoutMs` for exactly one
// connection and returns the received fd (>= 0) or a negative errno.
int ReceiveFdOnce(const std::string &name, int timeoutMs) {
  sockaddr_un addr{};
  socklen_t addrLength = 0;
  if (!FillSockAddr(name, &addr, &addrLength)) {
    return -EINVAL;
  }

  int server = ::socket(AF_UNIX, SOCK_STREAM, 0);
  if (server < 0) {
    return -errno;
  }
  if (::bind(server, reinterpret_cast<sockaddr *>(&addr), addrLength) < 0) {
    int err = errno;
    ::close(server);
    return -err;
  }
  if (::listen(server, 1) < 0) {
    int err = errno;
    ::close(server);
    return -err;
  }

  pollfd poller{};
  poller.fd = server;
  poller.events = POLLIN;
  int ready = ::poll(&poller, 1, timeoutMs);
  if (ready <= 0) {
    int err = ready == 0 ? ETIMEDOUT : errno;
    ::close(server);
    return -err;
  }

  int conn = ::accept(server, nullptr, nullptr);
  int err = errno;
  ::close(server);
  if (conn < 0) {
    return -err;
  }

  char payload = 0;
  iovec iov{};
  iov.iov_base = &payload;
  iov.iov_len = 1;

  // The receiver needs room for more than the descriptor: when the sender is
  // another process, the kernel delivers the sender's credentials with the
  // message, and a buffer that only fits the descriptor made it drop the whole
  // control area (MSG_CTRUNC, controllen = 0).
  char control[kControlBufferSize];
  std::memset(control, 0, sizeof(control));
  msghdr msg{};
  msg.msg_iov = &iov;
  msg.msg_iovlen = 1;
  msg.msg_control = control;
  msg.msg_controllen = sizeof(control);

  ssize_t received = ::recvmsg(conn, &msg, 0);
  ::close(conn);
  if (received < 1) {
    return -(received == 0 ? EPIPE : errno);
  }
  cmsghdr *header = CMSG_FIRSTHDR(&msg);
  if (header == nullptr) {
    std::snprintf(g_lastError, sizeof(g_lastError), "no ancillary data (flags=%#x controllen=%zu)",
                  static_cast<unsigned>(msg.msg_flags), static_cast<size_t>(msg.msg_controllen));
    return -EPROTO;
  }
  if (header->cmsg_level != SOL_SOCKET || header->cmsg_type != SCM_RIGHTS ||
      header->cmsg_len < CMSG_LEN(sizeof(int))) {
    std::snprintf(g_lastError, sizeof(g_lastError), "unexpected cmsg (level=%d type=%d len=%zu)",
                  header->cmsg_level, header->cmsg_type, static_cast<size_t>(header->cmsg_len));
    return -EPROTO;
  }
  int fd = -1;
  std::memcpy(&fd, CMSG_DATA(header), sizeof(int));
  if (fd < 0) {
    return -EPROTO;
  }
  // The vNIC must not leak into child processes; SetOhosTunFd's dup keeps the
  // engine's copy CLOEXEC, this one is only a carrier.
  ::fcntl(fd, F_SETFD, FD_CLOEXEC);
  return fd;
}

std::string StringArg(napi_env env, napi_value value) {
  size_t length = 0;
  if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
    return std::string();
  }
  std::vector<char> buffer(length + 1, '\0');
  if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &length) != napi_ok) {
    return std::string();
  }
  return std::string(buffer.data(), length);
}

napi_value IntResult(napi_env env, int32_t value) {
  napi_value result = nullptr;
  napi_create_int32(env, value, &result);
  return result;
}

// sendFd(socketPath: string, fd: number): number   (0 = ok, negative errno)
napi_value SendFd(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = {nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc < 2) {
    return IntResult(env, -EINVAL);
  }
  int32_t fd = -1;
  if (napi_get_value_int32(env, argv[1], &fd) != napi_ok) {
    return IntResult(env, -EINVAL);
  }
  return IntResult(env, SendFdOnce(StringArg(env, argv[0]), fd));
}

struct ReceiveTask {
  std::string path;
  int timeout_ms = 0;
  int32_t result = -EINVAL;
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
};

void ReceiveExecute(napi_env /*env*/, void *data) {
  auto *task = static_cast<ReceiveTask *>(data);
  task->result = ReceiveFdOnce(task->path, task->timeout_ms);
}

void ReceiveComplete(napi_env env, napi_status /*status*/, void *data) {
  auto *task = static_cast<ReceiveTask *>(data);
  if (task->result >= 0) {
    napi_resolve_deferred(env, task->deferred, IntResult(env, task->result));
  } else {
    napi_value message = nullptr;
    napi_value error = nullptr;
    const char *text = g_lastError[0] != '\0' ? g_lastError : std::strerror(-task->result);
    napi_create_string_utf8(env, text, NAPI_AUTO_LENGTH, &message);
    napi_create_error(env, nullptr, message, &error);
    napi_reject_deferred(env, task->deferred, error);
  }
  napi_delete_async_work(env, task->work);
  delete task;
}

// receiveFd(socketPath: string, timeoutMs: number): Promise<number>
napi_value ReceiveFd(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = {nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

  auto *task = new ReceiveTask();
  task->path = argc > 0 ? StringArg(env, argv[0]) : std::string();
  if (argc > 1) {
    napi_get_value_int32(env, argv[1], &task->timeout_ms);
  }
  if (task->timeout_ms <= 0) {
    task->timeout_ms = 10000;
  }

  napi_value promise = nullptr;
  napi_create_promise(env, &task->deferred, &promise);
  napi_value name = nullptr;
  napi_create_string_utf8(env, "hiddifyvpn.receiveFd", NAPI_AUTO_LENGTH, &name);
  napi_create_async_work(env, nullptr, name, ReceiveExecute, ReceiveComplete, task, &task->work);
  napi_queue_async_work(env, task->work);
  return promise;
}

// readFd(fd: number, length: number): number
//
// Reads with a plain syscall, the way hiddify-core uses the descriptor. ArkTS's
// own fs API refuses a descriptor it did not open, so this is what proves a
// relayed descriptor is usable by the core.
napi_value ReadFd(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = {nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  int32_t fd = -1;
  int32_t length = 0;
  if (argc < 2 || napi_get_value_int32(env, argv[0], &fd) != napi_ok ||
      napi_get_value_int32(env, argv[1], &length) != napi_ok) {
    return IntResult(env, -EINVAL);
  }
  char buffer[512];
  if (length <= 0) {
    length = 16;
  }
  if (length > static_cast<int32_t>(sizeof(buffer))) {
    length = static_cast<int32_t>(sizeof(buffer));
  }
  ssize_t read = ::read(fd, buffer, static_cast<size_t>(length));
  return IntResult(env, read < 0 ? -errno : static_cast<int32_t>(read));
}

// probeTcpListen(): number
//
// Binds and listens on the loopback interface and returns the port, or a
// negative errno. The VPN extension runs in the `vpn_isolate_hap` SELinux
// domain; if the core is to live in that process, the app has to reach it over
// loopback, and this is what says whether that domain may listen there.
napi_value ProbeTcpListen(napi_env env, napi_callback_info info) {
  int sock = ::socket(AF_INET, SOCK_STREAM, 0);
  if (sock < 0) {
    return IntResult(env, -errno);
  }
  int one = 1;
  ::setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  addr.sin_port = 0;
  if (::bind(sock, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) < 0) {
    int err = errno;
    ::close(sock);
    return IntResult(env, -err);
  }
  if (::listen(sock, 1) < 0) {
    int err = errno;
    ::close(sock);
    return IntResult(env, -err);
  }
  socklen_t length = sizeof(addr);
  if (::getsockname(sock, reinterpret_cast<sockaddr *>(&addr), &length) < 0) {
    int err = errno;
    ::close(sock);
    return IntResult(env, -err);
  }
  int port = ntohs(addr.sin_port);
  ::close(sock);
  return IntResult(env, port);
}

// ---------------------------------------------------------------------------
// Hosting hiddify-core inside the VPN extension process.
//
// The VPN extension runs in its own SELinux domain (vpn_isolate_hap), and the
// kernel refuses to pass a descriptor from that domain to the app process. So
// the core has to run where the vNIC fd is: in this process. The app process
// then drives it over the loopback interface, like Android drives the core in
// its VPN service.
// ---------------------------------------------------------------------------

using CoreSetupFn = char *(*)(char *, char *, char *, int, char *, char *, long long, uint8_t);
using CoreStartFn = char *(*)(char *, uint8_t);
using CoreStopFn = char *(*)(void);
using CoreFreeFn = void (*)(char *);
using CoreSetupTunFn = void (*)(int);

void *g_core = nullptr;
void *g_earlyCore = nullptr;
char g_earlyError[192] = {0};
CoreSetupFn g_coreSetup = nullptr;
CoreStartFn g_coreStart = nullptr;
CoreStopFn g_coreStop = nullptr;
CoreFreeFn g_coreFree = nullptr;
CoreSetupTunFn g_coreSetupTun = nullptr;

// Takes over the string the core returned and releases it with the core's own
// freeString, so the memory comes from the same allocator.
std::string TakeCoreString(char *value) {
  if (value == nullptr) {
    return std::string();
  }
  std::string result(value);
  if (g_coreFree != nullptr) {
    g_coreFree(value);
  }
  return result;
}

// coreLoad(path?): number — loads libhiddify-core.so and resolves its exports.
//
// The path is optional: the bare name is tried first, then the module's own
// library directory, because the extension process may not have the app's
// library directory on its loader path.
napi_value CoreLoad(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (g_core != nullptr) {
    return IntResult(env, 0);
  }
  std::string path = argc > 0 ? StringArg(env, argv[0]) : std::string();
  std::string firstError;
  if (!path.empty()) {
    g_core = ::dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (g_core == nullptr) {
      const char *error = ::dlerror();
      firstError = error != nullptr ? error : "?";
    }
  }
  if (g_core == nullptr) {
    g_core = ::dlopen("libhiddify-core.so", RTLD_NOW | RTLD_LOCAL);
  }
  if (g_core == nullptr) {
    // Some loaders accept a lazy relocation of a Go library where the eager one
    // is refused; the TLS relocation is not lazy, but try it anyway.
    g_core = ::dlopen("libhiddify-core.so", RTLD_LAZY | RTLD_LOCAL);
  }
  if (g_core == nullptr) {
    // Maybe the runtime already loaded the library at process start and a
    // dlopen of it is refused only because it is a Go c-shared library.
    g_coreSetup = reinterpret_cast<CoreSetupFn>(::dlsym(RTLD_DEFAULT, "setup"));
    if (g_coreSetup != nullptr) {
      g_coreStart = reinterpret_cast<CoreStartFn>(::dlsym(RTLD_DEFAULT, "start"));
      g_coreStop = reinterpret_cast<CoreStopFn>(::dlsym(RTLD_DEFAULT, "stop"));
      g_coreFree = reinterpret_cast<CoreFreeFn>(::dlsym(RTLD_DEFAULT, "freeString"));
      g_coreSetupTun = reinterpret_cast<CoreSetupTunFn>(::dlsym(RTLD_DEFAULT, "SetupTun"));
      g_core = reinterpret_cast<void *>(1);
      return IntResult(env, 0);
    }
    const char *error = ::dlerror();
    std::snprintf(g_lastError, sizeof(g_lastError), "late:%.90s|init:%.90s",
                  error != nullptr ? error : "?", g_earlyError[0] != '\0' ? g_earlyError : "not tried");
    return IntResult(env, -ENOENT);
  }
  g_coreSetup = reinterpret_cast<CoreSetupFn>(::dlsym(g_core, "setup"));
  g_coreStart = reinterpret_cast<CoreStartFn>(::dlsym(g_core, "start"));
  g_coreStop = reinterpret_cast<CoreStopFn>(::dlsym(g_core, "stop"));
  g_coreFree = reinterpret_cast<CoreFreeFn>(::dlsym(g_core, "freeString"));
  g_coreSetupTun = reinterpret_cast<CoreSetupTunFn>(::dlsym(g_core, "SetupTun"));
  if (g_coreSetup == nullptr || g_coreStart == nullptr || g_coreStop == nullptr ||
      g_coreFree == nullptr) {
    std::snprintf(g_lastError, sizeof(g_lastError), "dlsym: the core library is missing exports");
    return IntResult(env, -ENOENT);
  }
  return IntResult(env, 0);
}

// coreSetupTun(fd): number — hands the vNIC descriptor to the core in this process.
napi_value CoreSetupTun(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  int32_t fd = -1;
  if (argc < 1 || napi_get_value_int32(env, argv[0], &fd) != napi_ok) {
    return IntResult(env, -EINVAL);
  }
  if (g_coreSetupTun == nullptr) {
    std::snprintf(g_lastError, sizeof(g_lastError), "the core library is not loaded");
    return IntResult(env, -ENOENT);
  }
  g_coreSetupTun(fd);
  return IntResult(env, 0);
}

struct CoreSetupTask {
  std::string baseDir;
  std::string workingDir;
  std::string tempDir;
  std::string listen;
  std::string secret;
  int mode = 0;
  int64_t statusPort = 0;
  int debug = 0;
  std::string result;
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
};

void CoreSetupExecute(napi_env /*env*/, void *data) {
  auto *task = static_cast<CoreSetupTask *>(data);
  if (g_coreSetup == nullptr) {
    task->result = "the core library is not loaded";
    return;
  }
  // The core's setup blocks until it has loaded its data and started its gRPC
  // server, so it runs on a worker thread, never on the JS thread.
  task->result = TakeCoreString(g_coreSetup(
      const_cast<char *>(task->baseDir.c_str()), const_cast<char *>(task->workingDir.c_str()),
      const_cast<char *>(task->tempDir.c_str()), task->mode, const_cast<char *>(task->listen.c_str()),
      const_cast<char *>(task->secret.c_str()), static_cast<long long>(task->statusPort),
      static_cast<uint8_t>(task->debug)));
}

void CoreSetupComplete(napi_env env, napi_status /*status*/, void *data) {
  auto *task = static_cast<CoreSetupTask *>(data);
  napi_value result = nullptr;
  napi_create_string_utf8(env, task->result.c_str(), NAPI_AUTO_LENGTH, &result);
  napi_resolve_deferred(env, task->deferred, result);
  napi_delete_async_work(env, task->work);
  delete task;
}

// coreSetup(baseDir, workingDir, tempDir, mode, listen, secret, statusPort, debug): Promise<string>
napi_value CoreSetup(napi_env env, napi_callback_info info) {
  size_t argc = 8;
  napi_value argv[8] = {nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

  auto *task = new CoreSetupTask();
  if (argc > 0) task->baseDir = StringArg(env, argv[0]);
  if (argc > 1) task->workingDir = StringArg(env, argv[1]);
  if (argc > 2) task->tempDir = StringArg(env, argv[2]);
  if (argc > 3) napi_get_value_int32(env, argv[3], &task->mode);
  if (argc > 4) task->listen = StringArg(env, argv[4]);
  if (argc > 5) task->secret = StringArg(env, argv[5]);
  if (argc > 6) {
    int64_t port = 0;
    napi_get_value_int64(env, argv[6], &port);
    task->statusPort = port;
  }
  if (argc > 7) napi_get_value_int32(env, argv[7], &task->debug);

  napi_value promise = nullptr;
  napi_create_promise(env, &task->deferred, &promise);
  napi_value name = nullptr;
  napi_create_string_utf8(env, "hiddifyvpn.coreSetup", NAPI_AUTO_LENGTH, &name);
  napi_create_async_work(env, nullptr, name, CoreSetupExecute, CoreSetupComplete, task, &task->work);
  napi_queue_async_work(env, task->work);
  return promise;
}

// coreIsMapped(): number — 1 when the core library is already in this process.
napi_value CoreIsMapped(napi_env env, napi_callback_info info) {
  FILE *maps = ::fopen("/proc/self/maps", "r");
  if (maps == nullptr) {
    return IntResult(env, -errno);
  }
  char line[512];
  int found = 0;
  while (::fgets(line, sizeof(line), maps) != nullptr) {
    if (::strstr(line, "hiddify-core") != nullptr) {
      found = 1;
      break;
    }
  }
  ::fclose(maps);
  return IntResult(env, found);
}

// lastError(): string — the last error message, for diagnostics.
napi_value LastError(napi_env env, napi_callback_info info) {
  napi_value result = nullptr;
  napi_create_string_utf8(env, g_lastError, NAPI_AUTO_LENGTH, &result);
  return result;
}

// execWithFd(binaryPath, fdNumber, markerPath): number
//
// Forks, hands `fdNumber` to the child as fd 3 (dup2 clears FD_CLOEXEC, so the
// descriptor survives the exec) and runs the binary with HIDDIFY_FD and
// HIDDIFY_MARKER in its environment.
//
// This is how the core could own the vNIC descriptor: it runs as a process of
// its own, started by the VPN extension, and the descriptor is inherited.
//
// @returns the child's exit status, or a negative errno.
napi_value ExecWithFd(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value argv[3] = {nullptr, nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc < 3) {
    return IntResult(env, -EINVAL);
  }
  std::string binary = StringArg(env, argv[0]);
  int32_t fdNumber = -1;
  napi_get_value_int32(env, argv[1], &fdNumber);
  std::string marker = StringArg(env, argv[2]);

  // The binary comes from the package, so it needs the execute bit.
  ::chmod(binary.c_str(), 0755);

  // The environment is built before the fork: after a fork in a process with
  // threads only async-signal-safe calls are allowed, and setenv is not one.
  std::vector<std::string> environment;
  for (char **entry = environ; entry != nullptr && *entry != nullptr; entry++) {
    environment.emplace_back(*entry);
  }
  environment.push_back("HIDDIFY_FD=3");
  environment.push_back("HIDDIFY_MARKER=" + marker);
  std::vector<char *> envp;
  for (std::string &entry : environment) {
    envp.push_back(const_cast<char *>(entry.c_str()));
  }
  envp.push_back(nullptr);

  std::vector<char *> args;
  args.push_back(const_cast<char *>(binary.c_str()));
  args.push_back(nullptr);

  pid_t child = ::fork();
  if (child < 0) {
    return IntResult(env, -errno);
  }
  if (child == 0) {
    // Child: move the descriptor to fd 3 and run the binary.
    if (fdNumber >= 0 && fdNumber != 3) {
      ::dup2(fdNumber, 3);
    }
    ::execve(binary.c_str(), args.data(), envp.data());
    // The exit status carries the reason (errno) when the exec failed.
    ::_exit(errno);
  }
  int status = 0;
  if (::waitpid(child, &status, 0) < 0) {
    return IntResult(env, -errno);
  }
  if (WIFEXITED(status)) {
    return IntResult(env, WEXITSTATUS(status));
  }
  return IntResult(env, -ECHILD);
}

}  // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor descriptors[] = {
      {"sendFd", nullptr, SendFd, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"receiveFd", nullptr, ReceiveFd, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"readFd", nullptr, ReadFd, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"probeTcpListen", nullptr, ProbeTcpListen, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"coreLoad", nullptr, CoreLoad, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"lastError", nullptr, LastError, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"coreIsMapped", nullptr, CoreIsMapped, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"execWithFd", nullptr, ExecWithFd, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"coreSetupTun", nullptr, CoreSetupTun, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"coreSetup", nullptr, CoreSetup, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
  return exports;
}
EXTERN_C_END

static napi_module g_vpnFdRelayModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "hiddifyvpn",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterVpnFdRelayModule(void) {
  napi_module_register(&g_vpnFdRelayModule);
  // The core is a Go c-shared library: it uses initial-exec TLS, which musl
  // only accepts for a library loaded before the process has used up its
  // static TLS surplus. Try it here, at native module init, and keep the
  // result for coreLoad().
  g_earlyCore = ::dlopen("libhiddify-core.so", RTLD_NOW | RTLD_LOCAL);
  if (g_earlyCore == nullptr) {
    const char *error = ::dlerror();
    std::snprintf(g_earlyError, sizeof(g_earlyError), "%.180s", error != nullptr ? error : "?");
  } else {
    g_core = g_earlyCore;
    g_coreSetup = reinterpret_cast<CoreSetupFn>(::dlsym(g_core, "setup"));
    g_coreStart = reinterpret_cast<CoreStartFn>(::dlsym(g_core, "start"));
    g_coreStop = reinterpret_cast<CoreStopFn>(::dlsym(g_core, "stop"));
    g_coreFree = reinterpret_cast<CoreFreeFn>(::dlsym(g_core, "freeString"));
    g_coreSetupTun = reinterpret_cast<CoreSetupTunFn>(::dlsym(g_core, "SetupTun"));
  }
}
