#pragma once

// ============================================================
// SSH Client C++ Header — Lorealis SSH Module
// 封装 libssh2 会话与通道操作，供 Lua 绑定使用
// ============================================================

#include <string>
#include <functional>
#include <cstdint>
#include <memory>

#ifdef __SWITCH__
#   include <switch.h>
#endif

// Forward declarations for libssh2 types (avoid including libssh2.h in header)
struct _LIBSSH2_SESSION;
struct _LIBSSH2_CHANNEL;
typedef struct _LIBSSH2_SESSION LIBSSH2_SESSION;
typedef struct _LIBSSH2_CHANNEL LIBSSH2_CHANNEL;

namespace ssh {

// ── 连接参数结构体 ──────────────────────────────────────────
struct ConnectParams {
    std::string host;
    uint16_t    port        = 22;
    std::string username;
    std::string password;
    std::string privkey_path;   // 私钥文件路径（可选）
    std::string pubkey_path;    // 公钥文件路径（可选）
    std::string passphrase;     // 密钥口令（可选）
    int         timeout_ms      = 10000;
};

// ── 错误枚举 ────────────────────────────────────────────────
enum class SSHError {
    None = 0,
    SocketFailed,
    ConnectFailed,
    HandshakeFailed,
    AuthFailed,
    ChannelFailed,
    PTYFailed,
    ShellFailed,
    SendFailed,
    RecvFailed,
    Disconnected,
    Timeout,
    Unknown
};

const char* sshErrorString(SSHError err);

// ── SSH 客户端主类 ──────────────────────────────────────────
class SSHClient {
public:
    SSHClient();
    ~SSHClient();

    // 禁止拷贝
    SSHClient(const SSHClient&)            = delete;
    SSHClient& operator=(const SSHClient&) = delete;

    // ── 连接与认证 ──────────────────────────────────────────

    /**
     * @brief 建立 SSH 连接并发起握手
     * @return SSHError::None 表示成功
     */
    SSHError connect(const ConnectParams& params);

    /**
     * @brief 使用密码认证
     */
    SSHError authPassword(const std::string& user, const std::string& pass);

    /**
     * @brief 使用公/私钥对认证
     */
    SSHError authPublicKey(const std::string& user,
                           const std::string& pubkey,
                           const std::string& privkey,
                           const std::string& passphrase);

    /**
     * @brief 打开 PTY 通道并启动 shell
     * @param cols  终端列数
     * @param rows  终端行数
     */
    SSHError openShell(int cols = 80, int rows = 24);

    // ── 数据读写 ────────────────────────────────────────────

    /**
     * @brief 发送数据到远程 shell
     */
    SSHError send(const std::string& data);

    /**
     * @brief 非阻塞读取远程输出（返回空字符串表示暂无数据）
     * @param maxBytes 单次最大读字节数
     */
    std::string recv(size_t maxBytes = 4096);

    /**
     * @brief 修改远程 PTY 窗口大小
     */
    SSHError resizePty(int cols, int rows);

    // ── 状态查询 ────────────────────────────────────────────

    bool isConnected() const { return connected_; }
    bool isChannelOpen() const { return channel_ != nullptr; }

    /**
     * @brief 关闭会话及所有通道
     */
    void disconnect();

    /**
     * @brief 获取远程主机指纹（SHA-256 hex）
     */
    std::string getFingerprint() const;

    /**
     * @brief 获取上次错误的描述字符串
     */
    std::string getLastError() const;

private:
    int             sock_       = -1;
    LIBSSH2_SESSION* session_   = nullptr;
    LIBSSH2_CHANNEL* channel_   = nullptr;
    bool             connected_ = false;
    std::string      lastError_;

    void cleanup();
    SSHError setNonBlocking(bool nb);
};

} // namespace ssh
