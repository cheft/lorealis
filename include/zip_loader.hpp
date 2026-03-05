#pragma once
#include <string>
#include <vector>
#include <map>
#include <cstdint>

/**
 * ZipLoader - Pure C++ ZIP file reader.
 * 
 * Supports ZIP files with:
 *   - Stored (method 0) entries
 *   - Deflated (method 8) entries (using system zlib)
 * 
 * Usage:
 *   ZipLoader zip("/absolute/path/to/file.zip");
 *   if (zip.isOpen()) {
 *       std::string content = zip.readFile("hello.xml");
 *   }
 */
class ZipLoader {
public:
    // Open and index a ZIP file by absolute path
    explicit ZipLoader(const std::string& zipPath);
    ~ZipLoader() = default;

    // Returns true if the ZIP was opened and indexed successfully
    bool isOpen() const;

    // Returns a list of all file entries in the ZIP
    std::vector<std::string> listFiles() const;

    // Returns true if the given filename exists in the ZIP
    bool hasFile(const std::string& filename) const;

    // Reads and returns the contents of the given file from the ZIP.
    // Returns an empty string on failure.
    std::string readFile(const std::string& filename) const;

private:
    struct ZipEntry {
        uint32_t localHeaderOffset;
        uint32_t compressedSize;
        uint32_t uncompressedSize;
        uint16_t compressionMethod;
    };

    std::string m_zipPath;
    std::map<std::string, ZipEntry> m_entries;
    bool m_open = false;

    bool parseCentralDirectory();
    std::string inflateEntry(const ZipEntry& entry) const;
    std::string readStoredEntry(const ZipEntry& entry) const;
};
