#ifndef PROTOCOL_H
#define PROTOCOL_H

#include <string>
#include <vector>
#include <chrono>
#include <ctime>
#include <iomanip>
#include <sstream>
// This implements a simplified protobuf wire format for compatibility with the Rust implementation

// Enum for protobuf wire types
enum WireType {
    VARINT = 0,          // int32, int64, uint32, uint64, sint32, sint64, bool, enum
    FIXED64 = 1,         // fixed64, sfixed64, double
    LENGTH_DELIMITED = 2 // string, bytes, embedded messages, packed repeated fields
};

// Simple chat message class
class ChatMessage {
public:
    ChatMessage() : timestamp_(0) {}
    
    ChatMessage(const std::string& nick, const std::string& payload) 
        : timestamp_(std::chrono::system_clock::to_time_t(std::chrono::system_clock::now())),
          nick_(nick),
          payload_(payload.begin(), payload.end()) {}
    
    // Protobuf-compatible serialization
    std::vector<uint8_t> serialize() const {
        std::vector<uint8_t> result;
        
        // Field 1: timestamp (uint64, varint encoding)
        // Tag: (field_number << 3) | wire_type = (1 << 3) | 0 = 8
        result.push_back(8);
        
        // Encode timestamp as varint
        uint64_t value = timestamp_;
        do {
            uint8_t byte = value & 0x7F;
            value >>= 7;
            if (value) byte |= 0x80;  // Set MSB if there are more bytes
            result.push_back(byte);
        } while (value);
        
        // Field 2: nick (string, length-delimited)
        // Tag: (field_number << 3) | wire_type = (2 << 3) | 2 = 18
        result.push_back(18);
        
        // Length of nick as varint
        size_t length = nick_.length();
        do {
            uint8_t byte = length & 0x7F;
            length >>= 7;
            if (length) byte |= 0x80;  // Set MSB if there are more bytes
            result.push_back(byte);
        } while (length);
        
        // Nick string bytes
        result.insert(result.end(), nick_.begin(), nick_.end());
        
        // Field 3: payload (bytes, length-delimited)
        // Tag: (field_number << 3) | wire_type = (3 << 3) | 2 = 26
        result.push_back(26);
        
        // Length of payload as varint
        length = payload_.size();
        do {
            uint8_t byte = length & 0x7F;
            length >>= 7;
            if (length) byte |= 0x80;  // Set MSB if there are more bytes
            result.push_back(byte);
        } while (length);
        
        // Payload bytes
        result.insert(result.end(), payload_.begin(), payload_.end());
        
        return result;
    }
    
    // Protobuf-compatible deserialization
    bool deserialize(const std::vector<uint8_t>& data) {
        if (data.empty()) return false;
        
        size_t pos = 0;
        
        while (pos < data.size()) {
            // Read tag
            if (pos >= data.size()) return false;
            uint8_t tag = data[pos++];
            
            // Extract field number and wire type
            uint32_t field_number = tag >> 3;
            uint32_t wire_type = tag & 0x07;
            
            switch (field_number) {
                case 1:  // timestamp
                    if (wire_type != VARINT) return false;
                    
                    // Decode varint
                    timestamp_ = 0;
                    for (int shift = 0; pos < data.size(); shift += 7) {
                        uint8_t byte = data[pos++];
                        timestamp_ |= static_cast<uint64_t>(byte & 0x7F) << shift;
                        if ((byte & 0x80) == 0) break;  // Last byte doesn't have MSB set
                        if (shift > 63) return false;  // Overflow
                    }
                    break;
                    
                case 2:  // nick
                    if (wire_type != LENGTH_DELIMITED) return false;
                    
                    // Decode string length (varint)
                    {
                        uint64_t length = 0;
                        for (int shift = 0; pos < data.size(); shift += 7) {
                            uint8_t byte = data[pos++];
                            length |= static_cast<uint64_t>(byte & 0x7F) << shift;
                            if ((byte & 0x80) == 0) break;  // Last byte doesn't have MSB set
                            if (shift > 63) return false;  // Overflow
                        }
                        
                        // Read string bytes
                        if (pos + length > data.size()) return false;
                        nick_ = std::string(data.begin() + pos, data.begin() + pos + length);
                        pos += length;
                    }
                    break;
                    
                case 3:  // payload
                    if (wire_type != LENGTH_DELIMITED) return false;
                    
                    // Decode bytes length (varint)
                    {
                        uint64_t length = 0;
                        for (int shift = 0; pos < data.size(); shift += 7) {
                            uint8_t byte = data[pos++];
                            length |= static_cast<uint64_t>(byte & 0x7F) << shift;
                            if ((byte & 0x80) == 0) break;  // Last byte doesn't have MSB set
                            if (shift > 63) return false;  // Overflow
                        }
                        
                        // Read bytes
                        if (pos + length > data.size()) return false;
                        payload_ = std::vector<uint8_t>(data.begin() + pos, data.begin() + pos + length);
                        pos += length;
                    }
                    break;
                    
                default:
                    // Unknown field, skip it
                    if (wire_type == VARINT) {
                        // Skip varint
                        while (pos < data.size() && (data[pos] & 0x80)) pos++;
                        if (pos < data.size()) pos++;  // Skip last byte
                    } else if (wire_type == FIXED64) {
                        // Skip 8 bytes
                        pos += 8;
                    } else if (wire_type == LENGTH_DELIMITED) {
                        // Skip length-delimited field
                        uint64_t length = 0;
                        for (int shift = 0; pos < data.size(); shift += 7) {
                            uint8_t byte = data[pos++];
                            length |= static_cast<uint64_t>(byte & 0x7F) << shift;
                            if ((byte & 0x80) == 0) break;
                        }
                        pos += length;
                    } else {
                        // Unknown wire type
                        return false;
                    }
                    break;
            }
        }
        
        return true;
    }
    
    // Getters
    time_t timestamp() const { return timestamp_; }
    const std::string& nick() const { return nick_; }
    std::string message() const { return std::string(payload_.begin(), payload_.end()); }
    
    // Format timestamp as string
    std::string formattedTimestamp() const {
        std::tm* tm = std::localtime(&timestamp_);
        std::stringstream ss;
        ss << std::put_time(tm, "%Y-%m-%d %H:%M:%S");
        return ss.str();
    }
    
private:
    time_t timestamp_;
    std::string nick_;
    std::vector<uint8_t> payload_;
};

#endif // PROTOCOL_H 