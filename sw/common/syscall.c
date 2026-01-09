// System call implementations for newlib
// Provides minimal syscall support for console output

#include <sys/stat.h>
#include <errno.h>

#ifdef __cplusplus
extern "C" {
#endif

// Magic console address - write character to output
#define CONSOLE_MAGIC_ADDR 0xFFFFFFF4

// Memory-mapped console magic address
volatile unsigned int* const console_putc = (unsigned int*)CONSOLE_MAGIC_ADDR;

// Simple console output function
void console_putchar(char c) {
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

// Exit program by writing to tohost
void _exit(int status) {
    // Write debug message
    const char msg[] = "\n[_exit called with status=";
    _write(1, (char*)msg, sizeof(msg)-1);
    
    char buf[16];
    int i = 0;
    int val = status;
    if (val < 0) {
        const char minus[] = "-";
        _write(1, (char*)minus, 1);
        val = -val;
    }
    if (val == 0) {
        buf[i++] = '0';
    } else {
        char temp[16];
        int j = 0;
        while (val > 0) {
            temp[j++] = '0' + (val % 10);
            val /= 10;
        }
        while (j > 0) {
            buf[i++] = temp[--j];
        }
    }
    _write(1, buf, i);
    const char end[] = "]\n";
    _write(1, (char*)end, 2);
    
    // tohost protocol: write (exit_code << 1) | 1
    // For exit, we just use exit_code << 1
    extern volatile unsigned long tohost;
    tohost = (status << 1) | 1;
    
    // Hang forever after exit
    while (1) {
        __asm__ volatile ("nop");
    }
}

// Wrapped fflush to handle NULL FILE pointers safely
// Use -Wl,--wrap=fflush to enable this wrapper
int __real_fflush(void *stream);
int __wrap_fflush(void *stream) {
    // In our freestanding environment, printf uses _write directly (unbuffered)
    // so fflush is always a no-op. Just return success.
    (void)stream;
    (void)__real_fflush;
    return 0;
}

#ifdef __cplusplus
}
#endif
