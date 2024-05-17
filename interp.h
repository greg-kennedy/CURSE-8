#ifndef INTERP_H_
#define INTERP_H_

struct machine;

// Create a new CHIP-8 machine - you have to pass all the required callbacks
struct machine * chip8_create(
    void (*cb_clear)(void),
    void (*cb_plot)(unsigned char x, unsigned char y, unsigned char set),
    unsigned char (*cb_get_timer_delay)(void),
    void (*cb_set_timer_delay)(unsigned char value),
    void (*cb_set_timer_sound)(unsigned char value),
    unsigned char (*cb_check_key)(unsigned char key),
    unsigned char (*cb_await_key)(void)
);

// load a chip8 program into RAM
void chip8_load(struct machine * sys, const unsigned char * rom, unsigned short size);

// Runs one step of a machine
int chip8_step(struct machine * sys);

// Frees a machine
void chip8_destroy(struct machine * sys);

void chip8_perror(const struct machine * sys);

#endif
