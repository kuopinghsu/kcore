// GDB Remote Serial Protocol Stub Implementation
// Based on GDB Remote Serial Protocol specification

#include "gdb_stub.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>
#include <ctype.h>

// Protocol helpers
static uint8_t hex_to_int(char c) {
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return 0;
}

static char int_to_hex(uint8_t val) {
    return val < 10 ? '0' + val : 'a' + (val - 10);
}

static uint32_t parse_hex(const char *str, int len) {
    uint32_t value = 0;
    for (int i = 0; i < len && str[i]; i++) {
        value = (value << 4) | hex_to_int(str[i]);
    }
    return value;
}

static void encode_hex(char *buf, uint32_t value, int bytes) {
    for (int i = bytes - 1; i >= 0; i--) {
        uint8_t byte = (value >> (i * 8)) & 0xFF;
        *buf++ = int_to_hex(byte >> 4);
        *buf++ = int_to_hex(byte & 0xF);
    }
}

static uint8_t calculate_checksum(const char *data, int len) {
    uint8_t sum = 0;
    for (int i = 0; i < len; i++) {
        sum += (uint8_t)data[i];
    }
    return sum;
}

// Send a packet to GDB
static int send_packet(gdb_stub_t *stub, const char *data) {
    char buffer[GDB_BUFFER_SIZE];
    int len = strlen(data);
    uint8_t checksum = calculate_checksum(data, len);

    snprintf(buffer, sizeof(buffer), "$%s#%02x", data, checksum);
    int sent = write(stub->client_fd, buffer, strlen(buffer));
    return sent > 0 ? 0 : -1;
}

// Receive a packet from GDB
static int receive_packet(gdb_stub_t *stub) {
    char c;
    int state = 0; // 0: wait for $, 1: read data, 2: read checksum
    int index = 0;
    uint8_t checksum_expected = 0;
    uint8_t checksum_received = 0;

    while (1) {
        if (read(stub->client_fd, &c, 1) != 1) {
            return -1;
        }

        switch (state) {
        case 0: // Wait for '$'
            if (c == '$') {
                state = 1;
                index = 0;
            } else if (c == 0x03) { // Ctrl-C
                stub->packet_buffer[0] = 0x03;
                stub->packet_size = 1;
                return 0;
            }
            break;

        case 1: // Read data
            if (c == '#') {
                stub->packet_buffer[index] = '\0';
                stub->packet_size = index;
                checksum_expected = calculate_checksum(stub->packet_buffer, index);
                state = 2;
                index = 0;
            } else {
                if (index < GDB_BUFFER_SIZE - 1) {
                    stub->packet_buffer[index++] = c;
                }
            }
            break;

        case 2: // Read checksum (2 hex digits)
            checksum_received = (checksum_received << 4) | hex_to_int(c);
            if (++index == 2) {
                // Send ACK/NACK
                c = (checksum_received == checksum_expected) ? '+' : '-';
                write(stub->client_fd, &c, 1);

                if (checksum_received == checksum_expected) {
                    return 0;
                } else {
                    return -1;
                }
            }
            break;
        }
    }
}

// Initialize GDB stub
int gdb_stub_init(gdb_context_t *ctx, uint16_t port) {
    memset(ctx, 0, sizeof(*ctx));
    ctx->stub.port = port;

    // Create socket
    ctx->stub.socket_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (ctx->stub.socket_fd < 0) {
        perror("socket");
        return -1;
    }

    // Allow reuse of address
    int opt = 1;
    setsockopt(ctx->stub.socket_fd, SOL_SOCKET, SO_REUSEADDR, &opt,
               sizeof(opt));

    // Bind to port
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(port);

    if (bind(ctx->stub.socket_fd, (struct sockaddr *)&addr, sizeof(addr)) <
        0) {
        perror("bind");
        close(ctx->stub.socket_fd);
        return -1;
    }

    // Listen for connections
    if (listen(ctx->stub.socket_fd, 1) < 0) {
        perror("listen");
        close(ctx->stub.socket_fd);
        return -1;
    }

    ctx->stub.enabled = true;
    printf("GDB stub listening on port %d\n", port);
    return 0;
}

// Accept client connection
int gdb_stub_accept(gdb_context_t *ctx) {
    struct sockaddr_in client_addr;
    socklen_t client_len = sizeof(client_addr);

    printf("Waiting for GDB connection...\n");
    ctx->stub.client_fd =
        accept(ctx->stub.socket_fd, (struct sockaddr *)&client_addr,
               &client_len);

    if (ctx->stub.client_fd < 0) {
        perror("accept");
        return -1;
    }

    ctx->stub.connected = true;
    printf("GDB connected from %s:%d\n", inet_ntoa(client_addr.sin_addr),
           ntohs(client_addr.sin_port));

    return 0;
}

// Handle query commands
static void handle_query(gdb_context_t *ctx, void *simulator,
                         const gdb_callbacks_t *callbacks) {
    char *packet = ctx->stub.packet_buffer;

    if (strncmp(packet, "qSupported", 10) == 0) {
        send_packet(&ctx->stub, "PacketSize=4096;qXfer:features:read+");
    } else if (strncmp(packet, "qAttached", 9) == 0) {
        send_packet(&ctx->stub, "1");
    } else if (strncmp(packet, "qC", 2) == 0) {
        send_packet(&ctx->stub, "QC1");
    } else if (strncmp(packet, "qfThreadInfo", 12) == 0) {
        send_packet(&ctx->stub, "m1");
    } else if (strncmp(packet, "qsThreadInfo", 12) == 0) {
        send_packet(&ctx->stub, "l");
    } else if (strncmp(packet, "qXfer:features:read:target.xml", 30) == 0) {
        const char *xml = "l<?xml version=\"1.0\"?>"
                          "<!DOCTYPE target SYSTEM \"gdb-target.dtd\">"
                          "<target version=\"1.0\">"
                          "<architecture>riscv:rv32</architecture>"
                          "</target>";
        send_packet(&ctx->stub, xml);
    } else {
        send_packet(&ctx->stub, "");
    }
}

// Read registers (g command)
static void handle_read_registers(gdb_context_t *ctx, void *simulator,
                                   const gdb_callbacks_t *callbacks) {
    char response[GDB_BUFFER_SIZE];
    char *p = response;

    // Send 33 registers (x0-x31 + pc)
    for (int i = 0; i < 32; i++) {
        uint32_t value = callbacks->read_reg(simulator, i);
        encode_hex(p, value, 4);
        p += 8;
    }

    // Add PC
    uint32_t pc = callbacks->get_pc(simulator);
    encode_hex(p, pc, 4);
    p += 8;
    *p = '\0';

    send_packet(&ctx->stub, response);
}

// Write registers (G command)
static void handle_write_registers(gdb_context_t *ctx, void *simulator,
                                    const gdb_callbacks_t *callbacks) {
    char *data = ctx->stub.packet_buffer + 1;

    for (int i = 0; i < 32; i++) {
        uint32_t value = parse_hex(data + i * 8, 8);
        callbacks->write_reg(simulator, i, value);
    }

    // Write PC
    uint32_t pc = parse_hex(data + 32 * 8, 8);
    callbacks->set_pc(simulator, pc);

    send_packet(&ctx->stub, "OK");
}

// Read memory (m command)
static void handle_read_memory(gdb_context_t *ctx, void *simulator,
                                const gdb_callbacks_t *callbacks) {
    char *packet = ctx->stub.packet_buffer + 1;
    char *comma = strchr(packet, ',');
    if (!comma) {
        send_packet(&ctx->stub, "E01");
        return;
    }

    *comma = '\0';
    uint32_t addr = parse_hex(packet, comma - packet);
    uint32_t len = parse_hex(comma + 1, strlen(comma + 1));

    if (len > GDB_BUFFER_SIZE / 2) {
        send_packet(&ctx->stub, "E02");
        return;
    }

    char response[GDB_BUFFER_SIZE];
    char *p = response;

    for (uint32_t i = 0; i < len; i++) {
        uint8_t byte = callbacks->read_mem(simulator, addr + i, 1) & 0xFF;
        *p++ = int_to_hex(byte >> 4);
        *p++ = int_to_hex(byte & 0xF);
    }
    *p = '\0';

    send_packet(&ctx->stub, response);
}

// Write memory (M command)
static void handle_write_memory(gdb_context_t *ctx, void *simulator,
                                 const gdb_callbacks_t *callbacks) {
    char *packet = ctx->stub.packet_buffer + 1;
    char *comma = strchr(packet, ',');
    char *colon = strchr(packet, ':');

    if (!comma || !colon) {
        send_packet(&ctx->stub, "E01");
        return;
    }

    *comma = '\0';
    *colon = '\0';

    uint32_t addr = parse_hex(packet, comma - packet);
    uint32_t len = parse_hex(comma + 1, colon - comma - 1);
    char *data = colon + 1;

    for (uint32_t i = 0; i < len; i++) {
        uint8_t byte = (hex_to_int(data[i * 2]) << 4) | hex_to_int(data[i * 2 + 1]);
        callbacks->write_mem(simulator, addr + i, byte, 1);
    }

    send_packet(&ctx->stub, "OK");
}

// Handle breakpoint commands (Z/z)
static void handle_breakpoint(gdb_context_t *ctx, bool insert) {
    char *packet = ctx->stub.packet_buffer + 1;
    char *comma1 = strchr(packet, ',');
    char *comma2 = comma1 ? strchr(comma1 + 1, ',') : NULL;

    if (!comma1 || !comma2) {
        send_packet(&ctx->stub, "E01");
        return;
    }

    *comma1 = '\0';
    *comma2 = '\0';

    int type = parse_hex(packet, comma1 - packet);
    uint32_t addr = parse_hex(comma1 + 1, comma2 - comma1 - 1);

    if (type != 0 && type != 1) { // Only software and hardware breakpoints
        send_packet(&ctx->stub, "");
        return;
    }

    int result;
    if (insert) {
        result = gdb_stub_add_breakpoint(ctx, addr);
    } else {
        result = gdb_stub_remove_breakpoint(ctx, addr);
    }

    send_packet(&ctx->stub, result == 0 ? "OK" : "E01");
}

// Process GDB commands
int gdb_stub_process(gdb_context_t *ctx, void *simulator,
                     const gdb_callbacks_t *callbacks) {
    if (!ctx->stub.connected) {
        return -1;
    }

    if (receive_packet(&ctx->stub) < 0) {
        return -1;
    }

    char cmd = ctx->stub.packet_buffer[0];

    switch (cmd) {
    case 0x03: // Ctrl-C (interrupt)
        ctx->should_stop = true;
        send_packet(&ctx->stub, "S05");
        break;

    case '?': // Halt reason
        send_packet(&ctx->stub, "S05");
        break;

    case 'q': // Query
        handle_query(ctx, simulator, callbacks);
        break;

    case 'g': // Read registers
        handle_read_registers(ctx, simulator, callbacks);
        break;

    case 'G': // Write registers
        handle_write_registers(ctx, simulator, callbacks);
        break;

    case 'm': // Read memory
        handle_read_memory(ctx, simulator, callbacks);
        break;

    case 'M': // Write memory
        handle_write_memory(ctx, simulator, callbacks);
        break;

    case 'c': // Continue
        ctx->should_stop = false;
        ctx->single_step = false;
        return 1; // Signal to continue execution
        break;

    case 's': // Single step
        ctx->should_stop = false;
        ctx->single_step = true;
        return 1; // Signal to execute one instruction
        break;

    case 'Z': // Insert breakpoint
        handle_breakpoint(ctx, true);
        break;

    case 'z': // Remove breakpoint
        handle_breakpoint(ctx, false);
        break;

    case 'k': // Kill
        return -1;
        break;

    case 'D': // Detach
        send_packet(&ctx->stub, "OK");
        ctx->stub.connected = false;
        return -1;
        break;

    default:
        send_packet(&ctx->stub, ""); // Not supported
        break;
    }

    return 0;
}

// Breakpoint management
int gdb_stub_add_breakpoint(gdb_context_t *ctx, uint32_t addr) {
    if (ctx->breakpoint_count >= MAX_BREAKPOINTS) {
        return -1;
    }

    // Check if already exists
    for (int i = 0; i < ctx->breakpoint_count; i++) {
        if (ctx->breakpoints[i].addr == addr) {
            ctx->breakpoints[i].enabled = true;
            return 0;
        }
    }

    ctx->breakpoints[ctx->breakpoint_count].addr = addr;
    ctx->breakpoints[ctx->breakpoint_count].enabled = true;
    ctx->breakpoint_count++;
    return 0;
}

int gdb_stub_remove_breakpoint(gdb_context_t *ctx, uint32_t addr) {
    for (int i = 0; i < ctx->breakpoint_count; i++) {
        if (ctx->breakpoints[i].addr == addr) {
            ctx->breakpoints[i].enabled = false;
            return 0;
        }
    }
    return -1;
}

void gdb_stub_clear_breakpoints(gdb_context_t *ctx) {
    ctx->breakpoint_count = 0;
}

bool gdb_stub_check_breakpoint(gdb_context_t *ctx, uint32_t pc) {
    for (int i = 0; i < ctx->breakpoint_count; i++) {
        if (ctx->breakpoints[i].enabled && ctx->breakpoints[i].addr == pc) {
            return true;
        }
    }
    return false;
}

void gdb_stub_close(gdb_context_t *ctx) {
    if (ctx->stub.client_fd >= 0) {
        close(ctx->stub.client_fd);
        ctx->stub.client_fd = -1;
    }
    if (ctx->stub.socket_fd >= 0) {
        close(ctx->stub.socket_fd);
        ctx->stub.socket_fd = -1;
    }
    ctx->stub.connected = false;
    ctx->stub.enabled = false;
}
