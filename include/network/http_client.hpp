#pragma once

#include <string>
#include <vector>
#include <functional>
#include <map>
#include <set>
#include <mutex>
#include <atomic>
#include <optional>

#ifdef _WIN32
#include <windows.h>
#include <wininet.h>
#endif

namespace brls {

class NetworkRegistry {
public:
    static uint32_t registerID(const std::string& url);
#ifdef _WIN32
    static void addHandle(uint32_t id, HINTERNET h);
#endif
    static void unregister(uint32_t id);
    static void cancel(uint32_t id);
    static bool isCancelled(uint32_t id);

private:
    static std::atomic<uint32_t> nextId;
    static std::map<uint32_t, std::string> urls;
    static std::set<uint32_t> cancelledIds;
    static std::mutex mutex;
#ifdef _WIN32
    static std::map<uint32_t, std::vector<HINTERNET>> wininetHandles;
#endif
};

class SimpleHTTPClient {
public:
    static uint32_t get(const std::string& url, std::function<void(bool success, int statusCode, const std::string& response)> callback);
    static uint32_t downloadImage(const std::string& url, std::function<void(bool success, const std::string& data)> callback);
};

} // namespace brls
