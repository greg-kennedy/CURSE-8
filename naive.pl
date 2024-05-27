#!/usr/bin/env perl
use strict;
use warnings;
use autodie;

use List::Util qw( max );

my @rom = do {
  open my $fp, '<:raw', $ARGV[0];
  read $fp, my $string, max( 4096 - 512, -s $fp );
  unpack 'C*', $string;
};

# set up the RAM area
my @ram = (
  0xF0, 0x90, 0x90, 0x90, 0xF0,    # 0
  0x20, 0x60, 0x20, 0x20, 0x70,    # 1
  0xF0, 0x10, 0xF0, 0x80, 0xF0,    # 2
  0xF0, 0x10, 0xF0, 0x10, 0xF0,    # 3
  0x90, 0x90, 0xF0, 0x10, 0x10,    # 4
  0xF0, 0x80, 0xF0, 0x10, 0xF0,    # 5
  0xF0, 0x80, 0xF0, 0x90, 0xF0,    # 6
  0xF0, 0x10, 0x20, 0x40, 0x40,    # 7
  0xF0, 0x90, 0xF0, 0x90, 0xF0,    # 8
  0xF0, 0x90, 0xF0, 0x10, 0xF0,    # 9
  0xF0, 0x90, 0xF0, 0x90, 0x90,    # A
  0xE0, 0x90, 0xE0, 0x90, 0xE0,    # B
  0xF0, 0x80, 0x80, 0x80, 0xF0,    # C
  0xE0, 0x90, 0x90, 0x90, 0xE0,    # D
  0xF0, 0x80, 0xF0, 0x80, 0xF0,    # E
  0xF0, 0x80, 0xF0, 0x80, 0x80     # F
);

# copy rom into ram
for ( my $i = 0 ; $i < scalar @rom ; $i++ ) {
  $ram[ $i + 0x200 ] = $rom[$i];
}

# dump C
print <<EOF;
#include <stdint.h>
#include <setjmp.h>
#include <stdlib.h>
#include <string.h>

#include "wrapper.h"

// machine guts
static uint8_t SCREEN[32][64] = {};
static uint16_t I = 0;
static uint8_t V[0x10] = {};

#define STACK_DEPTH 16
static jmp_buf STACK[STACK_DEPTH] = {};
static uint8_t SP = 0;

uint8_t TIMER_DELAY = 0;
uint8_t TIMER_SOUND = 0;

// RAM contents
static uint8_t RAM[4096] = {
EOF

print join( ", ", map { sprintf( "0x%02x", defined $_ ? $_ : 0 ) } @ram );

print <<EOF;
};

// helper functions
static const uint8_t plot(uint8_t x, uint8_t y, uint8_t height) {
  uint8_t collision = 0;

  y %= 32;
  x %= 64;

  if (y + height > 32) height = 32 - y;
  for (uint8_t row = 0; row < height; row ++) {
    uint8_t width = 8;
    if (x + width > 64) width = 64 - x;
    for (uint8_t col = 0; col < width; col ++) {
      if (RAM[I + row] & (0x80 >> col)) {
        uint8_t p = ! SCREEN[y + row][x + col];
        SCREEN[y + row][x + col] = p;
        screen_set(x + col, y + row, p);
        if ( ! p) collision = 1;
      }
    }
  }

  screen_update();

  return collision;
}

static void clear() {
  memset(SCREEN, 0, 64 * 32);
  screen_clear();
}

void run() {
  clear();
EOF

for ( my $j = 0 ; $j < 2 ; $j++ ) {
  for ( my $i = 0x200 + $j ; $i < 4095 ; $i += 2 ) {

    # decompile opcodes
    my $op = ( ( $ram[$i] || 0 ) << 8 ) | ( $ram[ $i + 1 ] || 0 );

    my $opA = ( ( $op & 0xF000 ) >> 12 );
    my $opB = ( ( $op & 0x0F00 ) >> 8 );
    my $opC = ( ( $op & 0x00F0 ) >> 4 );
    my $opD = ( $op & 0x000F );

    my $opL = ( $op & 0x00FF );

    my $opADDR = ( $op & 0x0FFF );

    printf "lbl_%03x:\n\t", $i;
    if ( $opA == 0 ) {

      # call machine routine
      if ( $opADDR == 0x0E0 ) {

        # screen clear - affects nothing
        print "clear();";

      } elsif ( $opADDR == 0xEE ) {

        # RET - return the machine state
        print "longjmp(STACK[SP - 1], SP);";
      } else {
        printf "return;\t// ILLEGAL OPCODE (0x%04x)", $op;
      }
    } elsif ( $opA == 1 ) {

      # infinite loop exits the program instead
      if ( $opADDR < 0x200 || $opADDR > 0xFFE ) {
        printf "return;\t// ILLEGAL OPCODE (0x%04x)", $op;
      } elsif ( $i == $opADDR ) {
        print "return;\t// INFINITE LOOP";
      } else {
        printf "goto lbl_%03x;", $opADDR;
      }
    } elsif ( $opA == 2 ) {
      if ( $opADDR < 0x200 || $opADDR > 0xFFE ) {
        printf "return;\t// ILLEGAL OPCODE (0x%04x)", $op;
      } else {
        printf "if (setjmp(STACK[SP])) SP --; else { SP ++; goto lbl_%03x; }", $opADDR;
      }
    } elsif ( $opA == 3 ) {
      printf "if (V[0x%x] == 0x%02x) goto lbl_%03x;", $opB, $opL, $i + 4;
    } elsif ( $opA == 4 ) {
      printf "if (V[0x%x] != 0x%02x) goto lbl_%03x;", $opB, $opL, $i + 4;
    } elsif ( $opA == 5 ) {
      if ( $opD == 0 ) {
        printf "if (V[0x%x] == V[0x%x]) goto lbl_%03x;", $opB, $opC, $i + 4;
      } else {
        printf "return;\t// ILLEGAL OPCODE (0x%04x)", $op;
      }
    } elsif ( $opA == 6 ) {
      printf "V[0x%x] = 0x%02x;", $opB, $opL;
    } elsif ( $opA == 7 ) {
      printf "V[0x%x] = (V[0x%x] + 0x%02x) & 0xFF;", $opB, $opB, $opL;
    } elsif ( $opA == 8 ) {
      if ( $opD == 0 ) {
        printf "V[0x%x] = V[0x%x];", $opB, $opC;
      } elsif ( $opD == 1 ) {
        printf "{ V[0x%x] |= V[0x%x]; V[0xF] = 0; }", $opB, $opC;
      } elsif ( $opD == 2 ) {
        printf "{ V[0x%x] &= V[0x%x]; V[0xF] = 0; }", $opB, $opC;
      } elsif ( $opD == 3 ) {
        printf "{ V[0x%x] ^= V[0x%x]; V[0xF] = 0; }", $opB, $opC;
      } elsif ( $opD == 4 ) {
        printf "{ uint16_t result = V[0x%x] + V[0x%x]; V[0x%x] = result & 0xFF; V[0xF] = (result > 255 ? 1 : 0); }", $opB, $opC, $opB;
      } elsif ( $opD == 5 ) {
        printf "{ uint16_t result = (V[0x%x] - V[0x%x]) & 0xFFFF; V[0x%x] = result & 0xFF; V[0xF] = (result > 255 ? 0 : 1); }", $opB, $opC, $opB;
      } elsif ( $opD == 6 ) {
        printf "{ uint8_t bit = V[0x%x] & 1; V[0x%x] = V[0x%x] >> 1; V[0xF] = bit; }", $opC, $opB, $opC;
      } elsif ( $opD == 7 ) {
        printf "{ uint16_t result = (V[0x%x] - V[0x%x]) & 0xFFFF; V[0x%x] = result & 0xFF; V[0xF] = (result > 255 ? 0 : 1); }", $opC, $opB, $opB;
      } elsif ( $opD == 0xE ) {
        printf "{ uint8_t bit = V[0x%x] >> 7; V[0x%x] = V[0x%x] << 1; V[0xF] = bit; }", $opC, $opB, $opC;
      } else {
        printf "return;\t// ILLEGAL OPCODE (0x%04x)", $op;
      }
    } elsif ( $opA == 9 ) {
      if ( $opD == 0 ) {
        printf "if (V[0x%x] != V[0x%x]) goto lbl_%03x;", $opB, $opC, $i + 4;
      } else {
        printf "return;\t// ILLEGAL OPCODE (0x%04x)", $op;
      }
    } elsif ( $opA == 0xA ) {
      printf "I = 0x%03x;", $opADDR;
    } elsif ( $opA == 0xB ) {

      # jump table
      print "switch (V[0]) {\n";
      for my $offset ( 0 .. 255 ) {
        printf "\t\tcase 0x%02x: ", $offset;
        my $dest = $offset + $opADDR;
        if ( $dest < 0x200 || $dest > 0xFFE ) {
          printf "return;\t// ILLEGAL DEST (0x%04x)\n", $dest;
        } else {
          printf "goto lbl_%03x;\n", $dest;
        }
      }
      print "\t}";
    } elsif ( $opA == 0xC ) {
      printf "V[0x%x] = rand() & 0x%02x;", $opB, $opL;
    } elsif ( $opA == 0xD ) {

      # draw sprite
      printf "V[0xF] = plot( V[0x%x], V[0x%x], 0x%x );", $opB, $opC, $opD;
    } elsif ( $opA == 0xE ) {
      if ( $opL == 0x9E ) {
        printf "if (check_key(V[0x%x])) goto lbl_%03x;", $opB, $i + 4;
      } elsif ( $opL == 0xA1 ) {
        printf "if (! check_key(V[0x%x])) goto lbl_%03x;", $opB, $i + 4;
      } else {
        printf "return;\t// ILLEGAL OPCODE (0x%04x)", $op;
      }
    } elsif ( $opA == 0xF ) {
      if ( $opL == 0x07 ) {
        printf "V[0x%x] = TIMER_DELAY;", $opB;
      } elsif ( $opL == 0x0A ) {
        printf "V[0x%x] = await_key();", $opB;
      } elsif ( $opL == 0x15 ) {
        printf "TIMER_DELAY = V[0x%x];", $opB;
      } elsif ( $opL == 0x18 ) {
        printf "TIMER_SOUND = V[0x%x];", $opB;
      } elsif ( $opL == 0x1E ) {
        printf "I += V[0x%x];", $opB;
      } elsif ( $opL == 0x29 ) {
        printf "I = 5 * (V[0x%x] & 0xF);", $opB;
      } elsif ( $opL == 0x33 ) {
        printf "{ unsigned char value = V[0x%x]; RAM[I + 2] = value %% 10; value /= 10; RAM[I + 1] = value %% 10; RAM[I] = value / 10; }", $opB;
      } elsif ( $opL == 0x55 ) {
        printf "for (unsigned char j = 0; j <= 0x%x; j ++, I ++) RAM[I] = V[j];", $opB;
      } elsif ( $opL == 0x65 ) {
        printf "for (unsigned char j = 0; j <= 0x%x; j ++, I ++) V[j] = RAM[I];", $opB;
      } else {
        printf "return;\t// ILLEGAL OPCODE (0x%04x)", $op;
      }
    }
    print "\n";
  }
  print "return;\t// PC END\n\n";
}

print "}\n";

