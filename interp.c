#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#define debug(...) ;

// error codes
enum error {
    NONE = 0,
    PC_UNDERFLOW,
    PC_OVERFLOW,
    STACK_OVERFLOW,
    STACK_UNDERFLOW,
    INFINITE_LOOP,
    ILLEGAL_INSTRUCTION,
    ILLEGAL_DIGIT,
    INDEX_OVERFLOW,
    BAD_KEY
};

struct machine {
    // we track the screen ourselves for collision etc
    unsigned char SCREEN[32][64];

    unsigned char RAM[4096];

    unsigned char V[16];

    unsigned short I;
    unsigned short PC;

    unsigned short STACK[16];
    unsigned char SP;

    // callbacks
    void (*cb_clear)(void);
    void (*cb_plot)(unsigned char x, unsigned char y, unsigned char set);
    unsigned char (*cb_get_timer_delay)(void);
    void (*cb_set_timer_delay)(unsigned char value);
    void (*cb_set_timer_sound)(unsigned char value);
    unsigned char (*cb_check_key)(unsigned char key);
    unsigned char (*cb_await_key)(void);

    // crash / error handler
    enum error err;
};

// Create a new CHIP-8 machine
struct machine * chip8_create(
    void (*cb_clear)(void),
    void (*cb_plot)(unsigned char x, unsigned char y, unsigned char set),
    unsigned char (*cb_get_timer_delay)(void),
    void (*cb_set_timer_delay)(unsigned char value),
    void (*cb_set_timer_sound)(unsigned char value),
    unsigned char (*cb_check_key)(unsigned char key),
    unsigned char (*cb_await_key)(void)
)
{
    static const unsigned char FONT[0x10 * 5] = {
        0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
        0x20, 0x60, 0x20, 0x20, 0x70, // 1
        0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
        0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
        0x90, 0x90, 0xF0, 0x10, 0x10, // 4
        0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
        0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
        0xF0, 0x10, 0x20, 0x40, 0x40, // 7
        0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
        0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
        0xF0, 0x90, 0xF0, 0x90, 0x90, // A
        0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
        0xF0, 0x80, 0x80, 0x80, 0xF0, // C
        0xE0, 0x90, 0x90, 0x90, 0xE0, // D
        0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
        0xF0, 0x80, 0xF0, 0x80, 0x80  // F
    };

    struct machine * sys = malloc(sizeof(struct machine));

    // clear screen
    memset(sys->SCREEN, 0, 32 * 64);

    // copy font data
    memcpy(sys->RAM, FONT, sizeof(FONT));
    // set up ptr to font
    sys->I = 0;

    // set PC
    sys->PC = 0x200;

    // stack pointer at bottom
    sys->SP = 0;

    // copy the callback ptrs
    sys->cb_clear = cb_clear;
    sys->cb_plot = cb_plot;
    sys->cb_get_timer_delay = cb_get_timer_delay;
    sys->cb_set_timer_delay = cb_set_timer_delay;
    sys->cb_set_timer_sound = cb_set_timer_sound;
    sys->cb_check_key = cb_check_key;
    sys->cb_await_key = cb_await_key;

    // no errors (so far)
    sys->err = NONE;

    return sys;
}

// load a program
int chip8_load(struct machine * sys, const unsigned char * rom_data, const unsigned short rom_size)
{
    if (rom_size <= 4096 - 0x200) {
        memcpy(& sys->RAM[0x200], rom_data, rom_size);
        return 0;
    }

    return 1;
}

// Frees a machine
void chip8_destroy(struct machine * sys)
{
    free(sys);
}

void chip8_perror(const struct machine * sys)
{
    static const char * messages[] = {
        "NONE",
        "PC_UNDERFLOW",
        "PC_OVERFLOW",
        "STACK_OVERFLOW",
        "STACK_UNDERFLOW",
        "INFINITE_LOOP",
        "ILLEGAL_INSTRUCTION",
        "ILLEGAL_DIGIT",
        "INDEX_OVERFLOW",
        "BAD_KEY"
    };
    printf("Runtime error: %s\n", messages[sys->err]);
// machine state
    printf("PC = %04x, I = %04x, SP = %01x\n", sys->PC, sys->I, sys->SP);
    if (sys->err != PC_UNDERFLOW && sys->err != PC_OVERFLOW) {
        printf("Instruction: %04x\n", (sys->RAM[sys->PC] << 8) | sys->RAM[sys->PC + 1]);
    }
    for (int i = 0; i < sys->SP; i ++) {
        printf("\tSTACK[%d]: %04x\n", i, sys->STACK[i]);
    }
}

// Runs one step of a machine
//  returns 0 if OK or 1 if an error occurred
int chip8_step(struct machine * sys)
{

// helpers to parse an instruction
#define opA ((op & 0xF000) >> 12)
#define opB ((op & 0x0F00) >> 8)
#define opC ((op & 0x00F0) >> 4)
#define opD (op & 0x000F)

#define opL (op & 0x00FF)

#define opADDR (op & 0x0FFF)

    //debug("0x%04x : ", (sys->PC - sys->RAM));
    //unsigned char * initialPC = sys->PC;
    if (sys->PC < 0x200) {
        sys->err = PC_UNDERFLOW;
        return sys->err;
    } else if (sys->PC >= 4095) {
        // PC overflow!
        sys->err = PC_OVERFLOW;
        return sys->err;
    }

    unsigned short op = (sys->RAM[sys->PC] << 8) | sys->RAM[sys->PC + 1];
    sys->PC += 2;

    //debug("[0x%04x] : ", op);

    switch(opA) {
    case 0:
        debug("CALL ");
        switch(opADDR) {
        case 0x0E0:
            memset(sys->SCREEN, 0, 32 * 64);
            if (sys->cb_clear) sys->cb_clear();
            debug("CLEAR SCREEN");
            break;
        case 0x0EE:
            if (sys->SP < 1) {
                // Can't pop something off stack that isn't there
                sys->err = STACK_UNDERFLOW;
                return sys->err;
            }
            sys->SP --;
            sys->PC = sys->STACK[sys->SP];
            debug("RETURN TO %04x", *sys->SP - sys->RAM);
            break;
        default:
            sys->err = ILLEGAL_INSTRUCTION;
            sys->PC -= 2;
            return sys->err;
        }
        debug("\n");
        break;
    case 1:
        debug("JUMP TO %04x\n", opADDR);
        if (opADDR == sys->PC - 2) {
            // Detected simple infinite loop
            sys->err = INFINITE_LOOP;
            sys->PC -= 2;
            return sys->err;
        }
        sys->PC = opADDR;
        break;
    case 2:
        debug("CALL SUB AT %04x\n", opADDR);
        // sub
        if (sys->SP > 15) {
            // Can't push more than 16 items on the stack
            sys->err = STACK_OVERFLOW;
            return sys->err;
        }
        sys->STACK[sys->SP] = sys->PC;
        sys->SP ++;

        sys->PC = opADDR;
        break;
    case 3:
        debug("CHECK V[%d] == %d\n", opB, opL);
        // literal EQ
        if (sys->V[opB] == opL)
            sys->PC += 2;
        break;
    case 4:
        debug("CHECK V[%d] != %d\n", opB, opL);
        // literal NEQ
        if (sys->V[opB] != opL)
            sys->PC += 2;
        break;
    case 5:
        debug("COMPARE: ");
        switch(opD) {
        case 0:
            debug("CHECK V[%d] == V[%d]", opB, opC);
            if (sys->V[opB] == sys->V[opC])
                sys->PC += 2;

            break;
        default:
            sys->err = ILLEGAL_INSTRUCTION;
            sys->PC -= 2;
            return sys->err;
        }
        debug("\n");
        break;
    case 6:
        debug("SET V[%d] == %d\n", opB, opL);
        sys->V[opB] = opL;
        break;
    case 7:
        debug("ADD V[%d] += %d\n", opB, opL);
        sys->V[opB] += opL;
        break;
    case 8:
        debug("ALU OP ");
        switch(opD) {
        case 0:
            debug("SET V[%d] = V[%d]", opB, opC);
            sys->V[opB] = sys->V[opC];
            break;
        case 1:
            debug("SET V[%d] |= V[%d]", opB, opC);
            sys->V[opB] |= sys->V[opC];
            sys->V[0xF] = 0;
            break;
        case 2:
            debug("SET V[%d] &= V[%d]", opB, opC);
            sys->V[opB] &= sys->V[opC];
            sys->V[0xF] = 0;
            break;
        case 3:
            debug("SET V[%d] ^= V[%d]", opB, opC);
            sys->V[opB] ^= sys->V[opC];
            sys->V[0xF] = 0;
            break;
        case 4: {
            debug("SET V[%d] += V[%d]", opB, opC);
            unsigned short result = sys->V[opB] + sys->V[opC];
            sys->V[opB] = result & 0xFF;
            sys->V[0xF] = (result > 255 ? 1 : 0);
            break;
        }
        case 5: {
            debug("SET V[%d] -= V[%d]", opB, opC);
            unsigned short result = sys->V[opB] - sys->V[opC];
            sys->V[opB] = result & 0xFF;
            sys->V[0xF] = (result > 255 ? 0 : 1);
            break;
        }
        case 6: {
            debug("SET V[%d] = V[%d] >> 1", opB, opC);
            unsigned char bit = sys->V[opC] & 1;
            sys->V[opB] = sys->V[opC] >> 1;
            sys->V[0xF] = bit;
            break;
        }
        case 7: {
            debug("SET V[%d] = V[%d] - V[%d]", opB, opC, opB);
            unsigned short result = sys->V[opC] - sys->V[opB];
            sys->V[opB] = result & 0xFF;
            sys->V[0xF] = (result > 255 ? 0 : 1);
            break;
        }
        case 0xE: {
            debug("SET V[%d] = V[%d] << 1", opB, opC);
            unsigned char bit = (sys->V[opC] & 0x80) >> 7;
            sys->V[opB] = sys->V[opC] << 1;
            sys->V[0xF] = bit;
            break;
        }
        default:
            sys->err = ILLEGAL_INSTRUCTION;
            sys->PC -= 2;
            return sys->err;
        }
        break;
    case 9:
        debug("REG COMPARE ");
        switch(opD) {
        case 0:
            debug("CHECK V[%d] != V[%d]\n", opB, opC);
            if (sys->V[opB] != sys->V[opC])
                sys->PC += 2;

            break;
        default:
            sys->err = ILLEGAL_INSTRUCTION;
            sys->PC -= 2;
            return sys->err;
        }
        break;
    case 0xA:
        debug("SET I = %04x\n", opADDR);
        sys->I = opADDR;
        break;
    case 0xB:
        debug("SET PC = %04x + V0\n", opADDR);
        sys->PC = opADDR + sys->V[0];
        break;
    case 0xC:
        debug("GET RAND\n");
        sys->V[opB] = rand() & opL;
        break;
    case 0xD:
        debug("PLOT SPRITE AT X=V[%d] Y=V[%d] H=%d\n", opB, opC, opD);
// sprite
        sys->V[0xF] = 0;

        unsigned char screenY = sys->V[opC] % 32;

        for (int y = 0; y < opD; y ++) {
            if (sys->I + y > 4095) {
                sys->err = INDEX_OVERFLOW;
                return sys->err;
            }
            unsigned char v = sys->RAM[sys->I + y];

            unsigned char screenX = sys->V[opB] % 64;
            for (int x = 0; x < 8; x ++) {
                if (v & (0x80 >> x)) {
                    unsigned char p = ! sys->SCREEN[screenY][screenX];
                    if (sys->cb_plot) sys->cb_plot(screenX, screenY, p);
                    sys->SCREEN[screenY][screenX] = p;
                    if ( ! p) sys->V[0xF] = 1;
                }
                screenX ++;
                if (screenX > 63) break;
            }
            screenY ++;
            if (screenY > 31) break;
        }
        break;
    case 0xE:
        debug("TRAP ");
        switch(opL) {
        case 0x9E:
// check key press
            debug("CHECK KEYDOWN %d\n", opB);
            if (sys->V[opB] > 15) {
                sys->err = BAD_KEY;
                return sys->err;
            }

            if (sys->cb_check_key && sys->cb_check_key(sys->V[opB]))
                sys->PC += 2;
            break;
        case 0xA1:
// check key release
            debug("CHECK KEY UP %d\n", opB);
            if (sys->V[opB] > 15) {
                sys->err = BAD_KEY;
                return sys->err;
            }
            if (sys->cb_check_key && ! sys->cb_check_key(sys->V[opB]))
                sys->PC += 2;
            break;
        default:
            sys->err = ILLEGAL_INSTRUCTION;
            sys->PC -= 2;
            return sys->err;
        }
        break;
        debug("\n");
    case 0xF:
        debug("TRAP2 ");
        switch (opL) {
        case 0x07:
// get delay timer
            debug("GET DELAY TIMER INTO V[%d]", opB);
            if (sys->cb_get_timer_delay) sys->V[opB] = sys->cb_get_timer_delay();
            break;
        case 0x0A:
// wait keypress
            debug("AWAIT KEY INTO V[%d]", opB);
            if (sys->cb_await_key) sys->V[opB] = sys->cb_await_key();
            break;
        case 0x15:
// set delay timer
            debug("SET DELAY TIMER FROM V[%d]", opB);
            if (sys->cb_set_timer_delay) sys->cb_set_timer_delay( sys->V[opB] );
            break;
        case 0x18:
// set sound timer
            debug("SET SOUND TIMER FROM V[%d]", opB);
            if (sys->cb_set_timer_sound) sys->cb_set_timer_sound( sys->V[opB] );
            break;
        case 0x1E:
//
            debug("ADVANCE I TO BY V[%d]", opB);
            sys->I += sys->V[opB];
            break;
        case 0x29:
            debug("SET I TO DIGIT %d", opB);
            if (sys->V[opB] > 15) {
                sys->err = ILLEGAL_DIGIT;
                return sys->err;
            }
            sys->I = sys->V[opB] * 5;
            break;
        case 0x33:
        {
            debug("WRITE BCD OF V[%d] TO I", opB);
            if (sys->I > 4093) {
                sys->err = INDEX_OVERFLOW;
                return sys->err;
            }
            unsigned char value = sys->V[opB];
            sys->RAM[sys->I + 2] = value % 10;
            value /= 10;
            sys->RAM[sys->I + 1] = value % 10;
            value /= 10;
            sys->RAM[sys->I] = value;
            break;
        }
        case 0x55:
            debug("STORE %d REGISTERS", opB);
            if (sys->I + opB > 4095) {
                sys->err = INDEX_OVERFLOW;
                return sys->err;
            }
            for (int i = 0; i <= opB; i ++) {
                sys->RAM[sys->I] = sys->V[i];
                sys->I ++;
            }
            break;
        case 0x65:
            debug("LOAD %d REGISTERS", opB);
            if (sys->I + opB > 4095) {
                sys->err = INDEX_OVERFLOW;
                return sys->err;
            }
            for (int i = 0; i <= opB; i ++) {
                sys->V[i] = sys->RAM[sys->I];
                sys->I ++;
            }
            break;
        default:
            sys->err = ILLEGAL_INSTRUCTION;
            sys->PC -= 2;
            return sys->err;

        }
        debug("\n");
        break;
    }

    return 0;
}
