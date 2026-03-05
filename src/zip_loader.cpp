/**
 * ZipLoader.cpp
 *
 * Pure C++ ZIP file reader. Parses ZIP Central Directory manually,
 * supports Stored (method 0) and Deflate (method 8) compression,
 * using system zlib for decompression.
 *
 * ZIP format reference: https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT
 */
#include "zip_loader.hpp"
#include <fstream>
#include <cstring>
#include <borealis/core/logger.hpp>

// zlib for DEFLATE decompression
#ifdef PLATFORM_SWITCH
#include <zlib.h>
#else
// zlib is available via vcpkg or system on Windows/Linux/macOS
// On Windows MSVC, it's available as part of the Windows SDK or vcpkg
extern "C" {
#include <zlib.h>
}
#endif

// ============================================================
// ZIP format constants
// ============================================================
static constexpr uint32_t ZIP_LOCAL_FILE_SIG   = 0x04034b50;
static constexpr uint32_t ZIP_CENTRAL_DIR_SIG  = 0x02014b50;
static constexpr uint32_t ZIP_END_OF_CDIR_SIG  = 0x06054b50;
static constexpr uint32_t ZIP_END_OF_CDIR64_SIG= 0x07064b50;

// ============================================================
// Helper: read little-endian integers from a binary buffer
// ============================================================
static inline uint16_t readU16(const char* buf, size_t off) {
    return (uint8_t)buf[off] | ((uint8_t)buf[off+1] << 8);
}
static inline uint32_t readU32(const char* buf, size_t off) {
    return (uint8_t)buf[off] | ((uint8_t)buf[off+1] << 8)
         | ((uint8_t)buf[off+2] << 16) | ((uint8_t)buf[off+3] << 24);
}

// ============================================================
// ZipLoader implementation
// ============================================================

ZipLoader::ZipLoader(const std::string& zipPath)
    : m_zipPath(zipPath)
{
    m_open = parseCentralDirectory();
    if (!m_open) {
        brls::Logger::error("ZipLoader: Failed to open/parse '{}'", zipPath);
    } else {
        brls::Logger::debug("ZipLoader: Opened '{}' with {} entries", zipPath, m_entries.size());
    }
}

bool ZipLoader::isOpen() const { return m_open; }

std::vector<std::string> ZipLoader::listFiles() const {
    std::vector<std::string> result;
    result.reserve(m_entries.size());
    for (const auto& kv : m_entries) result.push_back(kv.first);
    return result;
}

bool ZipLoader::hasFile(const std::string& filename) const {
    return m_entries.count(filename) > 0;
}

std::string ZipLoader::readFile(const std::string& filename) const {
    auto it = m_entries.find(filename);
    if (it == m_entries.end()) {
        brls::Logger::error("ZipLoader: '{}' not found in archive", filename);
        return "";
    }
    const ZipEntry& entry = it->second;
    if (entry.compressionMethod == 0) {
        return readStoredEntry(entry);
    } else if (entry.compressionMethod == 8) {
        return inflateEntry(entry);
    } else {
        brls::Logger::error("ZipLoader: Unsupported compression method {} for '{}'",
            entry.compressionMethod, filename);
        return "";
    }
}

// ============================================================
// Parse the ZIP Central Directory to build the file index
// ============================================================
bool ZipLoader::parseCentralDirectory() {
    std::ifstream f(m_zipPath, std::ios::binary | std::ios::ate);
    if (!f.is_open()) return false;

    std::streamsize fileSize = f.tellg();
    if (fileSize < 22) return false; // Minimum ZIP size

    // Search for End of Central Directory record (last 65535+22 bytes)
    const int maxSearchLen = 65535 + 22;
    std::streamsize searchStart = std::max<std::streamsize>(0, fileSize - maxSearchLen);
    std::streamsize searchLen = fileSize - searchStart;
    std::vector<char> tailBuf((size_t)searchLen);
    f.seekg(searchStart);
    f.read(tailBuf.data(), searchLen);

    // Find EOCD signature from the end
    int eocdPos = -1;
    for (int i = (int)searchLen - 4; i >= 0; i--) {
        if (readU32(tailBuf.data(), i) == ZIP_END_OF_CDIR_SIG) {
            eocdPos = i;
            break;
        }
    }
    if (eocdPos < 0) return false; // No EOCD found

    // EOCD: central directory offset (absolute file offset)
    uint32_t cdOffset = readU32(tailBuf.data(), eocdPos + 16);
    uint32_t cdSize   = readU32(tailBuf.data(), eocdPos + 12);
    uint16_t totalEntries = readU16(tailBuf.data(), eocdPos + 8);

    // Read central directory
    std::vector<char> cd((size_t)cdSize);
    f.seekg(cdOffset);
    f.read(cd.data(), cdSize);

    size_t pos = 0;
    for (uint16_t i = 0; i < totalEntries; i++) {
        if (pos + 46 > cd.size()) break;
        if (readU32(cd.data(), pos) != ZIP_CENTRAL_DIR_SIG) break;

        uint16_t method         = readU16(cd.data(), pos + 10);
        uint32_t compressedSz   = readU32(cd.data(), pos + 20);
        uint32_t uncompressedSz = readU32(cd.data(), pos + 24);
        uint16_t fileNameLen    = readU16(cd.data(), pos + 28);
        uint16_t extraLen       = readU16(cd.data(), pos + 30);
        uint16_t commentLen     = readU16(cd.data(), pos + 32);
        uint32_t localHdrOffset = readU32(cd.data(), pos + 42);

        std::string name(cd.data() + pos + 46, fileNameLen);

        // Skip directory entries
        if (!name.empty() && name.back() != '/') {
            ZipEntry entry;
            entry.localHeaderOffset  = localHdrOffset;
            entry.compressedSize     = compressedSz;
            entry.uncompressedSize   = uncompressedSz;
            entry.compressionMethod  = method;
            m_entries[name] = entry;
        }

        pos += 46 + fileNameLen + extraLen + commentLen;
    }

    return !m_entries.empty() || totalEntries == 0;
}

// ============================================================
// Read local file header and return the data offset
// ============================================================
static int64_t getLocalDataOffset(std::ifstream& f, uint32_t localHdrOffset) {
    f.seekg(localHdrOffset);
    char lhBuf[30];
    f.read(lhBuf, 30);
    if (!f || readU32(lhBuf, 0) != ZIP_LOCAL_FILE_SIG) return -1;

    uint16_t fnLen   = readU16(lhBuf, 26);
    uint16_t extLen  = readU16(lhBuf, 28);
    return (int64_t)localHdrOffset + 30 + fnLen + extLen;
}

// ============================================================
// Read stored (uncompressed) entry
// ============================================================
std::string ZipLoader::readStoredEntry(const ZipEntry& entry) const {
    std::ifstream f(m_zipPath, std::ios::binary);
    if (!f.is_open()) return "";

    int64_t dataOffset = getLocalDataOffset(f, entry.localHeaderOffset);
    if (dataOffset < 0) return "";

    f.seekg(dataOffset);
    std::string result(entry.uncompressedSize, '\0');
    f.read(result.data(), entry.uncompressedSize);
    if (!f) return "";
    return result;
}

// ============================================================
// Read and inflate (decompress) a DEFLATE entry using zlib
// ============================================================
std::string ZipLoader::inflateEntry(const ZipEntry& entry) const {
    std::ifstream f(m_zipPath, std::ios::binary);
    if (!f.is_open()) return "";

    int64_t dataOffset = getLocalDataOffset(f, entry.localHeaderOffset);
    if (dataOffset < 0) return "";

    f.seekg(dataOffset);
    std::vector<char> compressed(entry.compressedSize);
    f.read(compressed.data(), entry.compressedSize);
    if (!f) return "";

    // Use zlib's inflate (raw DEFLATE, no header — ZIP stores raw deflate)
    std::string result(entry.uncompressedSize, '\0');

    z_stream zs{};
    zs.next_in  = reinterpret_cast<Bytef*>(compressed.data());
    zs.avail_in = entry.compressedSize;
    zs.next_out = reinterpret_cast<Bytef*>(result.data());
    zs.avail_out = entry.uncompressedSize;

    // inflateInit2 with -MAX_WBITS = raw DEFLATE (no zlib wrapper)
    if (inflateInit2(&zs, -MAX_WBITS) != Z_OK) {
        brls::Logger::error("ZipLoader: inflateInit2 failed");
        return "";
    }

    int ret = inflate(&zs, Z_FINISH);
    inflateEnd(&zs);

    if (ret != Z_STREAM_END) {
        brls::Logger::error("ZipLoader: inflate failed code={}", ret);
        return "";
    }

    return result;
}
