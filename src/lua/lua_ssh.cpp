// ============================================================
// lua_ssh.cpp — libssh2 Lua 绑定层 (Lorealis SSH Module)
// 将 SSH 会话、通道、SFTP 操作暴露给 Lua 脚本
// ============================================================

#include "lua_manager.hpp"
#include <borealis/core/logger.hpp>
#include <string>
#include <cstring>
#include <thread>
#include <mutex>
#include <deque>
#include <atomic>

// ── libssh2 ────────────────────────────────────────────────
#include <libssh2.h>

#ifdef _WIN32
#   include <winsock2.h>
#   include <ws2tcpip.h>
#   pragma comment(lib, "ws2_32.lib")
    typedef SOCKET sock_t;
#   define INVALID_SOCK INVALID_SOCKET
#   define CLOSE_SOCK(s) closesocket(s)
#else
#   include <sys/socket.h>
#   include <netinet/in.h>
#   include <arpa/inet.h>
#   include <netdb.h>
#   include <unistd.h>
#   include <fcntl.h>
    typedef int sock_t;
#   define INVALID_SOCK (-1)
#   define CLOSE_SOCK(s) close(s)
#endif

using namespace brls;

// ============================================================
// LuaSSHSession — 对 libssh2 会话的 C++ 封装 (Lua 持有智能指针)
// ============================================================
class LuaSSHSession {
public:
    // ── 状态机 ─────────────────────────────────────────────
    enum class State { Idle, Connected, Authenticated, Shell, Disconnected };

    LuaSSHSession() {
        static bool libssh2_inited = false;
        if (!libssh2_inited) {
            libssh2_init(0);
            libssh2_inited = true;
        }
    }

    ~LuaSSHSession() { doDisconnect(); }

    // ── 建立 TCP + SSH 握手 ────────────────────────────────
    std::string connect(const std::string& host, int port, int timeoutMs) {
        if (state_ != State::Idle && state_ != State::Disconnected) {
            return "already connected";
        }
        doDisconnect();

#ifdef _WIN32
        // Windows 需要初始化 Winsock
        static bool wsaInitialized = false;
        if (!wsaInitialized) {
            WSADATA wsaData;
            int wsaResult = WSAStartup(MAKEWORD(2, 2), &wsaData);
            if (wsaResult != 0) {
                return "WSAStartup failed: " + std::to_string(wsaResult);
            }
            wsaInitialized = true;
        }
#endif

        // ① 解析主机名
        struct addrinfo hints{}, *res = nullptr;
        hints.ai_family   = AF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;
        std::string portStr = std::to_string(port);
        if (getaddrinfo(host.c_str(), portStr.c_str(), &hints, &res) != 0) {
            return "DNS resolution failed for: " + host;
        }

        // ② 创建 socket
        sock_ = socket(res->ai_family, SOCK_STREAM, 0);
        if (sock_ == INVALID_SOCK) {
            freeaddrinfo(res);
            return "socket() failed";
        }

        // ③ 设置连接超时（非 blocking connect）
#ifdef _WIN32
        u_long mode = 1;
        ioctlsocket(sock_, FIONBIO, &mode);
#else
        int flags = fcntl(sock_, F_GETFL, 0);
        fcntl(sock_, F_SETFL, flags | O_NONBLOCK);
#endif
        ::connect(sock_, res->ai_addr, static_cast<socklen_t>(res->ai_addrlen));
        freeaddrinfo(res);

        // ④ 等待连接完成（select 超时）
        fd_set wset;
        FD_ZERO(&wset);
        FD_SET(sock_, &wset);
        struct timeval tv;
        tv.tv_sec  = timeoutMs / 1000;
        tv.tv_usec = (timeoutMs % 1000) * 1000;
        int sel = select(static_cast<int>(sock_) + 1, nullptr, &wset, nullptr, &tv);
        if (sel <= 0) {
            CLOSE_SOCK(sock_);
            sock_ = INVALID_SOCK;
            return "connection timed out";
        }

        // ⑤ 恢复阻塞模式
#ifdef _WIN32
        mode = 0;
        ioctlsocket(sock_, FIONBIO, &mode);
#else
        fcntl(sock_, F_SETFL, flags & ~O_NONBLOCK);
#endif

        // ⑥ 创建 libssh2 会话
        session_ = libssh2_session_init();
        if (!session_) {
            CLOSE_SOCK(sock_);
            sock_ = INVALID_SOCK;
            return "libssh2_session_init failed";
        }
        libssh2_session_set_blocking(session_, 1);

        // ⑦ SSH 握手
        int rc = libssh2_session_handshake(session_, static_cast<libssh2_socket_t>(sock_));
        if (rc != 0) {
            std::string err = "SSH handshake failed: " + getSessionError();
            doDisconnect();
            return err;
        }

        state_       = State::Connected;
        host_        = host;
        port_        = port;
        return "";   // 空字符串 = 成功
    }

    // ── 密码认证 ───────────────────────────────────────────
    std::string authPassword(const std::string& user, const std::string& pass) {
        if (state_ != State::Connected) return "not connected";
        int rc = libssh2_userauth_password(session_, user.c_str(), pass.c_str());
        if (rc != 0) return "password auth failed: " + getSessionError();
        state_ = State::Authenticated;
        user_  = user;
        return "";
    }

    // ── 公钥认证 ───────────────────────────────────────────
    std::string authPublicKey(const std::string& user,
                               const std::string& pubkeyPath,
                               const std::string& privkeyPath,
                               const std::string& passphrase) {
        if (state_ != State::Connected) return "not connected";
        int rc = libssh2_userauth_publickey_fromfile(
            session_,
            user.c_str(),
            pubkeyPath.empty() ? nullptr : pubkeyPath.c_str(),
            privkeyPath.c_str(),
            passphrase.empty()  ? nullptr : passphrase.c_str()
        );
        if (rc != 0) return "pubkey auth failed: " + getSessionError();
        state_ = State::Authenticated;
        user_  = user;
        return "";
    }

    // ── 打开 PTY Shell 通道 ────────────────────────────────
    std::string openShell(int cols, int rows) {
        if (state_ != State::Authenticated) return "not authenticated";

        channel_ = libssh2_channel_open_session(session_);
        if (!channel_) return "channel open failed: " + getSessionError();

        // 请求 xterm-256color PTY
        int rc = libssh2_channel_request_pty_ex(
            channel_,
            "xterm-256color", 15,
            nullptr, 0,
            cols, rows,
            0, 0
        );
        if (rc != 0) {
            libssh2_channel_free(channel_);
            channel_ = nullptr;
            return "PTY request failed: " + getSessionError();
        }

        rc = libssh2_channel_shell(channel_);
        if (rc != 0) {
            libssh2_channel_free(channel_);
            channel_ = nullptr;
            return "shell failed: " + getSessionError();
        }

        // 设置非阻塞读取
        libssh2_channel_set_blocking(channel_, 0);
        state_ = State::Shell;
        return "";
    }

    // ── 发送数据 ───────────────────────────────────────────
    std::string send(const std::string& data) {
        if (!channel_ || state_ != State::Shell) return "channel not open";
        ssize_t sent = libssh2_channel_write(channel_, data.c_str(), data.size());
        if (sent < 0 && sent != LIBSSH2_ERROR_EAGAIN) {
            return "send failed: " + getSessionError();
        }
        return "";
    }

    // ── 非阻塞读取 ─────────────────────────────────────────
    // 返回 {data, error_msg}
    std::pair<std::string, std::string> recv(size_t maxBytes) {
        if (!channel_ || state_ != State::Shell) {
            return {"", "channel not open"};
        }
        std::string buf(maxBytes, '\0');
        ssize_t n = libssh2_channel_read(channel_, &buf[0], maxBytes);
        if (n == LIBSSH2_ERROR_EAGAIN) {
            return {"", ""};  // 暂无数据，正常
        }
        if (n < 0) {
            if (libssh2_channel_eof(channel_)) {
                state_ = State::Disconnected;
                return {"", "eof"};
            }
            return {"", "recv error: " + getSessionError()};
        }
        buf.resize(n);
        return {buf, ""};
    }

    // ── PTY 窗口大小调整 ───────────────────────────────────
    std::string resizePty(int cols, int rows) {
        if (!channel_ || state_ != State::Shell) return "channel not open";
        int rc = libssh2_channel_request_pty_size(channel_, cols, rows);
        if (rc != 0 && rc != LIBSSH2_ERROR_EAGAIN)
            return "resize failed: " + getSessionError();
        return "";
    }

    // ── 断开连接 ───────────────────────────────────────────
    void disconnect() { doDisconnect(); }

    // ── 状态查询 ───────────────────────────────────────────
    bool isConnected()     const { return state_ >= State::Connected && state_ < State::Disconnected; }
    bool isAuthenticated() const { return state_ >= State::Authenticated; }
    bool isShellOpen()     const { return state_ == State::Shell; }
    std::string stateStr() const {
        switch (state_) {
            case State::Idle:          return "idle";
            case State::Connected:     return "connected";
            case State::Authenticated: return "authenticated";
            case State::Shell:         return "shell";
            case State::Disconnected:  return "disconnected";
        }
        return "unknown";
    }

    // ── 指纹获取 ───────────────────────────────────────────
    std::string getFingerprint() const {
        if (!session_) return "";
        // libssh2_hostkey_hash 返回二进制 MD5
        const char* fp = libssh2_hostkey_hash(session_, LIBSSH2_HOSTKEY_HASH_SHA1);
        if (!fp) return "";
        char hex[64] = {};
        for (int i = 0; i < 20; ++i)
            std::snprintf(hex + i * 3, 4, "%02X:", (unsigned char)fp[i]);
        if (strlen(hex) > 0) hex[strlen(hex) - 1] = '\0'; // 去掉末尾冒号
        return hex;
    }

    std::string getHost() const { return host_; }
    int         getPort() const { return port_; }
    std::string getUser() const { return user_; }

private:
    LIBSSH2_SESSION* session_ = nullptr;
    LIBSSH2_CHANNEL* channel_ = nullptr;
    sock_t           sock_    = INVALID_SOCK;
    State            state_   = State::Idle;
    std::string      host_, user_;
    int              port_    = 22;

    std::string getSessionError() const {
        if (!session_) return "no session";
        char* msg = nullptr;
        libssh2_session_last_error(session_, &msg, nullptr, 0);
        return msg ? std::string(msg) : "unknown error";
    }

    void doDisconnect() {
        if (channel_) {
            libssh2_channel_close(channel_);
            libssh2_channel_free(channel_);
            channel_ = nullptr;
        }
        if (session_) {
            libssh2_session_disconnect(session_, "Bye");
            libssh2_session_free(session_);
            session_ = nullptr;
        }
        if (sock_ != INVALID_SOCK) {
            CLOSE_SOCK(sock_);
            sock_ = INVALID_SOCK;
        }
        state_ = State::Disconnected;
    }
};

// ============================================================
// 注册 SSH Lua 绑定
// ============================================================
void LuaManager::registerSSHBindings(sol::table& brls_ns) {
    auto ssh_ns = brls_ns["SSH"].get_or_create<sol::table>();

    // ── LuaSSHSession 用户类型 ─────────────────────────────
    sol::usertype<LuaSSHSession> session_type = lua.new_usertype<LuaSSHSession>(
        "SSHSession",
        sol::constructors<LuaSSHSession()>()
    );

    // connect(host, port, timeout_ms) -> errMsg (空 = 成功)
    session_type.set_function("connect", [](LuaSSHSession& self,
                                            const std::string& host,
                                            sol::optional<int> port,
                                            sol::optional<int> timeout) -> std::string {
        return self.connect(host, port.value_or(22), timeout.value_or(10000));
    });

    // authPassword(user, pass) -> errMsg
    session_type["authPassword"] = &LuaSSHSession::authPassword;

    // authPublicKey(user, pubkey, privkey, passphrase) -> errMsg
    session_type.set_function("authPublicKey", [](LuaSSHSession& self,
                                                  const std::string& user,
                                                  const std::string& pub,
                                                  const std::string& priv,
                                                  sol::optional<std::string> pass) -> std::string {
        return self.authPublicKey(user, pub, priv, pass.value_or(""));
    });

    // openShell(cols, rows) -> errMsg
    session_type.set_function("openShell", [](LuaSSHSession& self,
                                              sol::optional<int> cols,
                                              sol::optional<int> rows) -> std::string {
        return self.openShell(cols.value_or(80), rows.value_or(24));
    });

    // send(data) -> errMsg
    session_type["send"] = &LuaSSHSession::send;

    // recv(maxBytes) -> data, errMsg
    session_type.set_function("recv", [](LuaSSHSession& self,
                                         sol::optional<int> maxBytes)
                                          -> std::tuple<std::string, std::string> {
        auto [data, err] = self.recv(static_cast<size_t>(maxBytes.value_or(4096)));
        return {data, err};
    });

    // resizePty(cols, rows) -> errMsg
    session_type["resizePty"] = &LuaSSHSession::resizePty;

    // disconnect()
    session_type["disconnect"] = &LuaSSHSession::disconnect;

    // 状态属性
    session_type["isConnected"]     = &LuaSSHSession::isConnected;
    session_type["isAuthenticated"] = &LuaSSHSession::isAuthenticated;
    session_type["isShellOpen"]     = &LuaSSHSession::isShellOpen;
    session_type["state"]           = &LuaSSHSession::stateStr;
    session_type["getFingerprint"]  = &LuaSSHSession::getFingerprint;
    session_type["getHost"]         = &LuaSSHSession::getHost;
    session_type["getPort"]         = &LuaSSHSession::getPort;
    session_type["getUser"]         = &LuaSSHSession::getUser;

    // ── 工厂函数 ───────────────────────────────────────────
    ssh_ns["newSession"] = []() -> std::shared_ptr<LuaSSHSession> {
        return std::make_shared<LuaSSHSession>();
    };

    // ── libssh2 版本信息 ───────────────────────────────────
    ssh_ns["version"] = []() -> std::string {
        return libssh2_version(0);
    };

    Logger::info("SSH: libssh2 Lua bindings registered (v{})", libssh2_version(0));
}
