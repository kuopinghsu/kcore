// System call implementations for newlib
// Provides minimal syscall support for console output

#include <sys/stat.h>
#include <errno.h>

// Magic console address - write character to output
#define CONSOLE_MAGIC_ADDR 0xFFFFFFF4

// Memory-mapped console magic address
volatile unsigned int* const console_putc = (unsigned int*)CONSOLE_MAGIC_ADDR;

// Simple putc function for console output
void putc(char c) {
    *console_putc = (unsigned int)c;
}

// Write system call - outputs to console via magic address
// Used by printf, puts, write, etc.
int _write(int file, char *ptr, int len) {
    int i;

    // Only support stdout (1) and stderr (2)
    if (file != 1 && file != 2) {
        errno = EBADF;
        return -1;
    }

    // Write each character to console magic address
    for (i = 0; i < len; i++) {
        *console_putc = (unsigned int)ptr[i];
    }

    return len;
}

// Stubs for other syscalls that newlib might need
int _close(int file) {
    return -1;
}

int _fstat(int file, struct stat *st) {
    st->st_mode = S_IFCHR;
    return 0;
}

int _isatty(int file) {
    return 1;
}

int _lseek(int file, int ptr, int dir) {
    return 0;
}

int _read(int file, char *ptr, int len) {
    return 0;
}

void *_sbrk(int incr) {
    extern char __heap_start;  // Defined in linker script
    static char *heap_end = 0;
    char *prev_heap_end;

    if (heap_end == 0) {
        heap_end = &__heap_start;
    }

    prev_heap_end = heap_end;
    heap_end += incr;

    return (void *)prev_heap_end;
}
