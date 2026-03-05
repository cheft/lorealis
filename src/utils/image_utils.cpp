#include "utils/image_utils.hpp"
#include <webp/decode.h>
#include <cstring>
#include <borealis.hpp>

namespace brls {

bool ImageUtils::isWebP(const std::string& data) {
    if (data.size() < 12) return false;
    return (data[0] == 'R' && data[1] == 'I' && data[2] == 'F' && data[3] == 'F' &&
            data[8] == 'W' && data[9] == 'E' && data[10] == 'B' && data[11] == 'P');
}

bool ImageUtils::decodeWebP(const std::string& data, std::string& rgba, int& width, int& height) {
    if (!isWebP(data)) return false;

    int w, h;
    uint8_t* decodedData = WebPDecodeRGBA((const uint8_t*)data.data(), data.size(), &w, &h);
    if (!decodedData) {
        brls::Logger::error("ImageUtils: Failed to decode WebP data");
        return false;
    }

    width = w;
    height = h;
    rgba.assign((const char*)decodedData, w * h * 4);
    WebPFree(decodedData);

    return true;
}

} // namespace brls
