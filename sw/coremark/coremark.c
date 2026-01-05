/*
 * CoreMark Benchmark - Simplified Baremetal RISC-V Version
 *
 * Adapted from EEMBC CoreMark (https://github.com/eembc/coremark)
 * Copyright 2009 by EEMBC
 *
 * This is a simplified version for baremetal embedded systems:
 * - No dynamic memory allocation (malloc)
 * - Reduced data set for simulation
 * - Custom I/O via magic console address
 * - CSR-based timing
 *
 * NOTE: This is NOT official CoreMark compliant - use for testing only
 */

#include <stdint.h>
#include <stddef.h>
#include <csr.h>

/* Magic console output */
#define CONSOLE_ADDR 0xFFFFFFF4
#define console_putc(c) (*(volatile uint32_t*)CONSOLE_ADDR = (c))

/* Configuration */
#define ITERATIONS 10      /* Reduced for simulation */
#define LIST_SIZE 8        /* Reduced from typical 256 */
#define MATRIX_SIZE 8      /* Reduced from typical 32 */

/* Data structures */
typedef struct list_data_s {
    int16_t data16;
    int16_t idx;
} list_data;

typedef struct list_head_s {
    struct list_head_s *next;
    list_data *info;
} list_head;

/* Static memory allocation */
static list_head list_nodes[LIST_SIZE];
static list_data list_data_items[LIST_SIZE];
static int16_t matrix_a[MATRIX_SIZE * MATRIX_SIZE];
static int16_t matrix_b[MATRIX_SIZE * MATRIX_SIZE];
static int16_t matrix_c[MATRIX_SIZE * MATRIX_SIZE];

/* Simple output functions */
static void puts(const char *s) {
    while (*s) console_putc(*s++);
}

static void print_uint_recursive(uint32_t val) {
    if (val >= 10) print_uint_recursive(val / 10);
    console_putc('0' + (val % 10));
}

static void print_uint(uint32_t val) {
    print_uint_recursive(val);
}

static void print_uint64(uint64_t val) {
    if (val >= 10) print_uint64(val / 10);
    console_putc('0' + (val % 10));
}

/* CRC calculation */
static uint16_t crc16(uint16_t crc, uint16_t data) {
    uint8_t i;
    crc ^= data;
    for (i = 0; i < 16; i++) {
        if (crc & 1)
            crc = (crc >> 1) ^ 0xA001;
        else
            crc = crc >> 1;
    }
    return crc;
}

/* List operations */
static list_head* list_init(uint32_t seed) {
    uint32_t i;
    list_head *head = NULL;

    for (i = 0; i < LIST_SIZE; i++) {
        list_data_items[i].data16 = (int16_t)(seed & 0xFFFF);
        list_data_items[i].idx = (int16_t)i;
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;

        list_nodes[i].info = &list_data_items[i];
        list_nodes[i].next = head;
        head = &list_nodes[i];
    }

    return head;
}

static uint16_t list_process(list_head *head) {
    uint16_t crc = 0;
    list_head *curr = head;

    while (curr) {
        crc = crc16(crc, (uint16_t)curr->info->data16);
        crc = crc16(crc, (uint16_t)curr->info->idx);
        curr = curr->next;
    }

    return crc;
}

/* Matrix operations */
static void matrix_init(int16_t *mat, uint32_t size, uint32_t seed) {
    uint32_t i;
    for (i = 0; i < size * size; i++) {
        mat[i] = (int16_t)((seed >> (i % 16)) & 0xFF);
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    }
}

static void matrix_mul(int16_t *c, int16_t *a, int16_t *b, uint32_t size) {
    uint32_t i, j, k;
    for (i = 0; i < size; i++) {
        for (j = 0; j < size; j++) {
            int32_t sum = 0;
            for (k = 0; k < size; k++) {
                sum += (int32_t)a[i * size + k] * (int32_t)b[k * size + j];
            }
            c[i * size + j] = (int16_t)(sum & 0xFFFF);
        }
    }
}

static uint16_t matrix_checksum(int16_t *mat, uint32_t size) {
    uint16_t crc = 0;
    uint32_t i;
    for (i = 0; i < size * size; i++) {
        crc = crc16(crc, (uint16_t)mat[i]);
    }
    return crc;
}

/* State machine - process input string */
static uint16_t state_machine(const char *input) {
    enum { STATE_START, STATE_INT, STATE_FLOAT, STATE_ERROR, STATE_DONE };
    uint8_t state = STATE_START;
    uint16_t crc = 0;

    while (*input && state != STATE_DONE) {
        char c = *input++;
        crc = crc16(crc, (uint16_t)c);

        switch (state) {
            case STATE_START:
                if (c >= '0' && c <= '9') state = STATE_INT;
                else if (c == '-' || c == '+') state = STATE_INT;
                else state = STATE_ERROR;
                break;
            case STATE_INT:
                if (c >= '0' && c <= '9') state = STATE_INT;
                else if (c == '.') state = STATE_FLOAT;
                else if (c == ' ') state = STATE_DONE;
                else state = STATE_ERROR;
                break;
            case STATE_FLOAT:
                if (c >= '0' && c <= '9') state = STATE_FLOAT;
                else if (c == ' ') state = STATE_DONE;
                else state = STATE_ERROR;
                break;
            case STATE_ERROR:
                if (c == ' ') state = STATE_START;
                break;
        }
    }

    return crc;
}

int main(void) {
    uint64_t start_cycles, end_cycles, total_cycles;
    uint32_t i;
    uint16_t crc_list = 0, crc_matrix = 0, crc_state = 0;
    list_head *list_ptr;

    puts("CoreMark Benchmark (Simplified Baremetal Version)\n");
    puts("=================================================\n\n");

    puts("Configuration:\n");
    puts("  Iterations: "); print_uint(ITERATIONS); puts("\n");
    puts("  List size:  "); print_uint(LIST_SIZE); puts("\n");
    puts("  Matrix size: "); print_uint(MATRIX_SIZE); puts("x"); print_uint(MATRIX_SIZE); puts("\n\n");

    /* Read start time */
    start_cycles = read_csr_cycle64();

    /* Run benchmark iterations */
    for (i = 0; i < ITERATIONS; i++) {
        uint32_t seed = 0x12345678 + i;

        /* List processing */
        list_ptr = list_init(seed);
        crc_list ^= list_process(list_ptr);

        /* Matrix operations */
        matrix_init(matrix_a, MATRIX_SIZE, seed);
        matrix_init(matrix_b, MATRIX_SIZE, seed + 1);
        matrix_mul(matrix_c, matrix_a, matrix_b, MATRIX_SIZE);
        crc_matrix ^= matrix_checksum(matrix_c, MATRIX_SIZE);

        /* State machine */
        crc_state ^= state_machine("123 456 -789 +012 34.56 ");
        crc_state ^= state_machine("invalid 789 xyz 123.456 ");
    }

    /* Read end time */
    end_cycles = read_csr_cycle64();
    total_cycles = end_cycles - start_cycles;

    /* Report results */
    puts("Results:\n");
    puts("--------\n");
    puts("Total cycles:  "); print_uint64(total_cycles); puts("\n");
    puts("Iterations:    "); print_uint(ITERATIONS); puts("\n");
    puts("Cycles/iter:   "); print_uint64(total_cycles / ITERATIONS); puts("\n\n");

    puts("Checksums:\n");
    puts("  List:        0x");
    {
        uint16_t val = crc_list;
        const char hex[] = "0123456789ABCDEF";
        console_putc(hex[(val >> 12) & 0xF]);
        console_putc(hex[(val >> 8) & 0xF]);
        console_putc(hex[(val >> 4) & 0xF]);
        console_putc(hex[val & 0xF]);
    }
    puts("\n");

    puts("  Matrix:      0x");
    {
        uint16_t val = crc_matrix;
        const char hex[] = "0123456789ABCDEF";
        console_putc(hex[(val >> 12) & 0xF]);
        console_putc(hex[(val >> 8) & 0xF]);
        console_putc(hex[(val >> 4) & 0xF]);
        console_putc(hex[val & 0xF]);
    }
    puts("\n");

    puts("  State:       0x");
    {
        uint16_t val = crc_state;
        const char hex[] = "0123456789ABCDEF";
        console_putc(hex[(val >> 12) & 0xF]);
        console_putc(hex[(val >> 8) & 0xF]);
        console_putc(hex[(val >> 4) & 0xF]);
        console_putc(hex[val & 0xF]);
    }
    puts("\n\n");

    /* Simplified score estimate (not official CoreMark) */
    puts("Performance estimate:\n");
    puts("  NOTE: Not official CoreMark score!\n");
    puts("  Cycles/iteration: "); print_uint64(total_cycles / ITERATIONS); puts("\n");

    puts("\nCoreMark benchmark complete.\n");

    return 0;
}
