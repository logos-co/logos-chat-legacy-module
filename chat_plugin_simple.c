// Minimal C implementation to satisfy build requirements
// This creates a simple shared library without external dependencies

#include <stdio.h>

// Simple function to make the library useful
const char* get_plugin_name() {
    return "chat_plugin";
}

const char* get_plugin_version() {
    return "1.0.0";
}

int initialize_plugin() {
    printf("Chat plugin initialized (stub version)\n");
    return 1; // success
}
