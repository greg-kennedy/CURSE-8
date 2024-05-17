#include "interp.h"

#include <stdlib.h>
#include <unistd.h>
#include <time.h>
#include <curses.h>

// external timers
unsigned char timer_delay = 0;
unsigned char timer_sound = 0;

unsigned char vblank = 0;

// track key presses
unsigned char keys[16] = {};

int do_cleanup = 0;
void endwin_wrapper() {
    if (do_cleanup) {
        curs_set(1);
        nocbreak();
        echo();
        endwin();
    }
    do_cleanup = 0;
}

unsigned char cb_check_key(unsigned char value) {
    return keys[value];
}

unsigned char cb_await_key() {
    // clear all current inputs and then wait for a keypress
    for (int i = 0; i < 16; i ++)
        keys[i] = 0;

    // await_key usually expects to take some time
    timer_delay = 0;
    timer_sound = 0;

    // wait
    nodelay(stdscr, FALSE);
    int ch;
    while (1) {
        ch = getch();
        if (ch >= '0' && ch <= '9') {
            ch -= '0';
            break;
        }
        else if (ch >= 'A' && ch <= 'F') {
            ch = 0xA + ch - 'A';
            break;
        } else if (ch >= 'a' && ch <= 'f') {
            ch = 0xA + ch - 'a';
            break;
        }
    }
    nodelay(stdscr, TRUE);
    return ch;
}

void cb_set_timer_delay(unsigned char value) {
    timer_delay = value;
}

unsigned char cb_get_timer_delay() {
    return timer_delay;
}

void cb_set_timer_sound(unsigned char value) {
    timer_sound = value;
}

void cb_plot(unsigned char x, unsigned char y, unsigned char set)
{
    mvaddch(y, x, (set ? '#' : ' '));
    vblank = 1;
}

void cb_clear()
{
    clear();
}

int main(int argc, char * argv[])
{
    if (argc != 2) {
        printf("Usage: %s rom.ch8\n", argv[0]);
        return -1;
    }

    srand(time(NULL));
    struct machine * m = chip8_create(
                             cb_clear,
                             cb_plot,
                             cb_get_timer_delay,
                             cb_set_timer_delay,
                             cb_set_timer_sound,
                             cb_check_key,
                             cb_await_key
                         );

// load the ROM
    unsigned char * prog = malloc(4096);
    FILE * f = fopen(argv[1], "rb");
    unsigned int size = fread(prog, 1, 4096, f);
    fclose(f);
    chip8_load(m, prog, size);
    free(prog);

    initscr();
    atexit(endwin_wrapper);
    do_cleanup = 1;

    nodelay(stdscr, TRUE);
    noecho();
    cbreak();

    intrflush(stdscr, FALSE);
    keypad(stdscr, TRUE);
    curs_set(0);

    resizeterm(32, 64);
    int error = 0;
    while (! error) {
        // run 100 cycles or so
        for (int i = 0; i < 100 && !vblank; i ++) {
            error = chip8_step(m);
            if (error) break;
        }
        refresh();
        vblank = 0;
        // collect keyboard input
        for (int i = 0; i < 16; i ++) {
            if (keys[i]) keys[i] --;
        }

        // curses doesn't have keydown/keyup
        //  so instead, we treat every keypress as a 3-frame-long keydown
        int ch;
        while ( (ch = getch()) != ERR) {
            if (ch >= '0' && ch <= '9') {
                keys[ch - '0'] = 3;
            } else if (ch >= 'A' && ch <= 'F') {
                keys[0xA + ch - 'A'] = 3;
            } else if (ch >= 'a' && ch <= 'f') {
                keys[0xA + ch - 'a'] = 3;
            }
        }
        if (timer_sound) {
            timer_sound --;
            if (timer_sound)
                beep();
        }
        if (timer_delay) timer_delay --;
        usleep(16667);
    }

    endwin_wrapper();
    chip8_perror(m);

    return 0;
}
