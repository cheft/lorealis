#pragma once
#include <string>
#include <vector>

namespace brls {

class ImageUtils {
public:
    /**
     * Decodes a WebP image buffer to raw RGBA pixels.
     * Returns true on success, false otherwise.
     */
    static bool decodeWebP(const std::string& data, std::string& rgba, int& width, int& height);

    /**
     * Checks if the data starts with a WebP signature.
     */
    static bool isWebP(const std::string& data);
};

} // namespace brls
