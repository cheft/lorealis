#include "network/http_client.hpp"
#include <borealis/core/thread.hpp>
#include <borealis/core/logger.hpp>

#ifdef __SWITCH__
#include <curl/curl.h>
#endif

namespace brls {

std::atomic<uint32_t> NetworkRegistry::nextId{1};
std::map<uint32_t, std::string> NetworkRegistry::urls;
std::set<uint32_t> NetworkRegistry::cancelledIds;
std::mutex NetworkRegistry::mutex;

#ifdef _WIN32
std::map<uint32_t, std::vector<HINTERNET>> NetworkRegistry::wininetHandles;
#endif

uint32_t NetworkRegistry::registerID(const std::string& url) {
    uint32_t id = nextId++;
    std::lock_guard<std::mutex> lock(mutex);
    urls[id] = url;
    return id;
}

#ifdef _WIN32
void NetworkRegistry::addHandle(uint32_t id, HINTERNET h) {
    if (!h) return;
    std::lock_guard<std::mutex> lock(mutex);
    if (cancelledIds.count(id)) {
        InternetCloseHandle(h);
        return;
    }
    wininetHandles[id].push_back(h);
}
#endif

void NetworkRegistry::unregister(uint32_t id) {
    std::lock_guard<std::mutex> lock(mutex);
#ifdef _WIN32
    wininetHandles.erase(id);
#endif
    cancelledIds.erase(id);
    urls.erase(id);
}

void NetworkRegistry::cancel(uint32_t id) {
    std::lock_guard<std::mutex> lock(mutex);
    cancelledIds.insert(id);
    
#ifdef _WIN32
    auto it = wininetHandles.find(id);
    if (it != wininetHandles.end()) {
        for (HINTERNET h : it->second) {
            if (h) InternetCloseHandle(h);
        }
        it->second.clear();
        wininetHandles.erase(it);
    }
#endif
}

bool NetworkRegistry::isCancelled(uint32_t id) {
    std::lock_guard<std::mutex> lock(mutex);
    return cancelledIds.count(id) > 0;
}

#ifdef __SWITCH__
struct CurlData {
    std::string* response;
    std::vector<unsigned char>* data;
    uint32_t id;
};

static size_t writeCallback(void* contents, size_t size, size_t nmemb, void* userp) {
    CurlData* cd = (CurlData*)userp;
    size_t realsize = size * nmemb;
    if (NetworkRegistry::isCancelled(cd->id)) return 0;
    
    if (cd->response) cd->response->append((char*)contents, realsize);
    if (cd->data) cd->data->insert(cd->data->end(), (unsigned char*)contents, (unsigned char*)contents + realsize);
    
    return realsize;
}

static int progressCallback(void* clientp, curl_off_t dltotal, curl_off_t dlnow, curl_off_t ultotal, curl_off_t ulnow) {
    uint32_t id = *(uint32_t*)clientp;
    if (NetworkRegistry::isCancelled(id)) return 1;
    return 0;
}
#endif

uint32_t SimpleHTTPClient::get(const std::string& url, std::function<void(bool success, int statusCode, const std::string& response)> callback) {
    uint32_t id = NetworkRegistry::registerID(url);
    
    Threading::async([url, callback, id]() {
        std::string response;
        bool success = false;
        int statusCode = 0;

#ifdef _WIN32
        const char* ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";
        HINTERNET hInternet = InternetOpen(ua, INTERNET_OPEN_TYPE_PRECONFIG, NULL, NULL, 0);
        if (hInternet) {
            NetworkRegistry::addHandle(id, hInternet);
            const char* headers = "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8\r\n"
                                 "Accept-Language: en-US,en;q=0.9\r\n"
                                 "Cache-Control: max-age=0\r\n";
            HINTERNET hConnect = InternetOpenUrlA(hInternet, url.c_str(), headers, -1L, INTERNET_FLAG_RELOAD | INTERNET_FLAG_NO_CACHE_WRITE, 0);
            if (hConnect) {
                NetworkRegistry::addHandle(id, hConnect);
                char buffer[8192];
                DWORD bytesRead;
                while (InternetReadFile(hConnect, buffer, sizeof(buffer) - 1, &bytesRead) && bytesRead > 0) {
                    if (NetworkRegistry::isCancelled(id)) break;
                    buffer[bytesRead] = '\0';
                    response += buffer;
                }
                DWORD code = 0;
                DWORD codeSize = sizeof(code);
                if (HttpQueryInfoA(hConnect, HTTP_QUERY_STATUS_CODE | HTTP_QUERY_FLAG_NUMBER, &code, &codeSize, NULL)) {
                    statusCode = (int)code;
                }
                
                // If it's a 403 or 503 but has content, it's likely a Cloudflare/WAF challenge page
                // We mark it as success to allow the UI to handle/display the error message or challenge
                success = (statusCode >= 200 && statusCode < 300) && !response.empty() && !NetworkRegistry::isCancelled(id);
                if (!success && !response.empty() && statusCode > 0) {
                    success = true; 
                    brls::Logger::debug("Network: Request to {} returned status {} but has content (possible challenge)", url, statusCode);
                }
                InternetCloseHandle(hConnect);
            } else {
                statusCode = -(int)GetLastError();
                brls::Logger::error("WinInet InternetOpenUrlA failed for {}: error {}", url, -statusCode);
            }
            InternetCloseHandle(hInternet);
        }
#endif

#ifdef __SWITCH__
        CURL* curl = curl_easy_init();
        if (curl) {
            CurlData cd = { &response, nullptr, id };
            struct curl_slist *headers = NULL;
            headers = curl_slist_append(headers, "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8");
            headers = curl_slist_append(headers, "Accept-Language: en-US,en;q=0.9");
            headers = curl_slist_append(headers, "Cache-Control: max-age=0");
            
            curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
            curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
            curl_easy_setopt(curl, CURLOPT_USERAGENT, "Mozilla/5.0 (Nintendo Switch; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36");
            curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, writeCallback);
            curl_easy_setopt(curl, CURLOPT_WRITEDATA, &cd);
            curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, progressCallback);
            curl_easy_setopt(curl, CURLOPT_XFERINFODATA, &id);
            curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
            curl_easy_setopt(curl, CURLOPT_TIMEOUT, 15L);
            curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
            curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
            
            CURLcode res = curl_easy_perform(curl);
            if (res == CURLE_OK && !NetworkRegistry::isCancelled(id)) {
                long code = 0;
                curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &code);
                statusCode = (int)code;
                success = !response.empty();
            }
            curl_slist_free_all(headers);
            curl_easy_cleanup(curl);
        }
#endif
        bool wasCancelled = NetworkRegistry::isCancelled(id);
        NetworkRegistry::unregister(id);
        
        Threading::sync([success, statusCode, response, callback, id, wasCancelled]() {
            if (!wasCancelled) callback(success, statusCode, response);
        });
    });
    return id;
}

uint32_t SimpleHTTPClient::downloadImage(const std::string& url, std::function<void(bool success, const std::string& data)> callback) {
    uint32_t id = NetworkRegistry::registerID(url); // Corrected from ++nextId
    
    Threading::async([url, callback, id]() {
        bool success = false;
        std::string data; // Changed from std::vector<unsigned char>

#ifdef _WIN32
        HINTERNET hInternet = InternetOpen("Mozilla/5.0", INTERNET_OPEN_TYPE_PRECONFIG, NULL, NULL, 0);
        if (hInternet) {
            NetworkRegistry::addHandle(id, hInternet);
            HINTERNET hConnect = InternetOpenUrlA(hInternet, url.c_str(), NULL, 0, INTERNET_FLAG_RELOAD, 0);
            if (hConnect) {
                NetworkRegistry::addHandle(id, hConnect);
                char buffer[4096]; // Changed from BYTE buffer[8192]
                DWORD bytesRead;
                while (InternetReadFile(hConnect, buffer, sizeof(buffer), &bytesRead) && bytesRead > 0) {
                    if (NetworkRegistry::isCancelled(id)) break;
                    data.append(buffer, bytesRead); // Changed from data.insert
                }
                if (!NetworkRegistry::isCancelled(id) && data.size() > 12) {
                    bool isJpeg = (data[0] == (char)0xFF && data[1] == (char)0xD8); // Cast to char for string access
                    bool isPng = (data[0] == (char)0x89 && data[1] == 'P' && data[2] == 'N' && data[3] == 'G');
                    bool isWebp = (data[0] == 'R' && data[1] == 'I' && data[2] == 'F' && data[3] == 'F' &&
                                 data[8] == 'W' && data[9] == 'E' && data[10] == 'B' && data[11] == 'P');
                    success = isJpeg || isPng || isWebp || (data.size() > 100); // Be more permissive if it looks like a file
                }
                InternetCloseHandle(hConnect);
            }
            InternetCloseHandle(hInternet);
        }
#endif

#ifdef __SWITCH__
        CURL* curl = curl_easy_init();
        if (curl) {
            CurlData cd = { &data, nullptr, id };
            curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
            curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, writeCallback);
            curl_easy_setopt(curl, CURLOPT_WRITEDATA, &cd);
            curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, progressCallback);
            curl_easy_setopt(curl, CURLOPT_XFERINFODATA, &id);
            curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
            curl_easy_setopt(curl, CURLOPT_TIMEOUT, 20L);
            curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
            curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
            
            CURLcode res = curl_easy_perform(curl);
            if (res == CURLE_OK && !NetworkRegistry::isCancelled(id) && data.size() > 12) {
                bool isJpeg = ((unsigned char)data[0] == 0xFF && (unsigned char)data[1] == 0xD8);
                bool isPng = ((unsigned char)data[0] == 0x89 && data[1] == 'P' && data[2] == 'N' && data[3] == 'G');
                bool isWebp = (data[0] == 'R' && data[1] == 'I' && data[2] == 'F' && data[3] == 'F' &&
                             data[8] == 'W' && data[9] == 'E' && data[10] == 'B' && data[11] == 'P');
                success = isJpeg || isPng || isWebp || (data.size() > 100);
            }
            curl_easy_cleanup(curl);
        }
#endif
        bool wasCancelled = NetworkRegistry::isCancelled(id);
        NetworkRegistry::unregister(id);
        
        Threading::sync([success, data, callback, id, wasCancelled]() {
            if (!wasCancelled) callback(success, data);
        });
    });
    return id;
}

} // namespace brls
