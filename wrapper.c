#include "wrapper.h"

#include <stdlib.h>
#include <unistd.h>
#include <curses.h>

#include <signal.h>
#include <sys/time.h>       /* for setitimer */

// external timers
extern uint8_t TIMER_DELAY;
extern uint8_t TIMER_SOUND;

// track key presses
unsigned char keys[16] = {};

// wait-for-vblank-after-refresh
unsigned int vblank = 0;
// await-key handler
unsigned int no_tick = 0;

void run();

//#include <sys/time.h>

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

unsigned char check_key(unsigned char value) {
    return keys[value];
}

unsigned char await_key() {
    no_tick = 1;

    // clear all current inputs and then wait for a keypress
    for (int i = 0; i < 16; i ++)
        keys[i] = 0;

    // await_key usually expects to take some time
    TIMER_DELAY = 0;
    TIMER_SOUND = 0;

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

    no_tick = 0;
    return ch;
}

void screen_set(unsigned char x, unsigned char y, unsigned char set)
{
    mvaddch(y, x, (set ? '#' : ' '));
}

void screen_update()
{
    refresh();
    vblank = 1;
    while (vblank) {
        usleep(1000);
    };
}

void tick()
{
    if (!no_tick) {
        vblank = 0;
        //refresh();

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
        if (TIMER_SOUND) {
            TIMER_SOUND --;
            if (TIMER_SOUND)
                beep();
        }
        if (TIMER_DELAY) TIMER_DELAY --;
    }
}

void screen_clear()
{
    clear();
}

int main(int argc, char * argv[])
{
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

    struct itimerval it_val;  /* for setting itimer */

    if (signal(SIGALRM, (void (*)(int)) tick) == SIG_ERR) {
        perror("Unable to catch SIGALRM");
        return EXIT_FAILURE;
    }
    it_val.it_value.tv_sec = 0;
    it_val.it_value.tv_usec = 16667;
    it_val.it_interval = it_val.it_value;
    if (setitimer(ITIMER_REAL, &it_val, NULL) == -1) {
        perror("error calling setitimer()");
        return EXIT_FAILURE;
    }

    run();

    endwin_wrapper();

    return 0;
}
