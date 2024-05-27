#include "wrapper.h"
#include <stdint.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>

uint8_t SCREEN[32][64];
uint8_t * i;
uint8_t v[16];
#define STACK_DEPTH 16
jmp_buf stack[STACK_DEPTH];
uint8_t sp = 0;
uint8_t TIMER_DELAY = 0;
uint8_t TIMER_SOUND = 0;

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
      if (*(i + row) & (0x80 >> col)) {
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

uint8_t ram_2cd[] = { 0x7c, 0xfe, 0x7c, 0x60, 0xf0, 0x60, 0x40, 0xe0, 0xa0, 0xf8 };
uint8_t ram_2f8[] = { 0x00, 0x00, 0x00 };
void run() {
 clear();
lbl_200:
	i = ram_2cd + 0x000;
lbl_202:
	v[0x09] = 0x38;
lbl_204:
	v[0x0a] = 0x08;
lbl_206:
	v[0xF] = plot(v[0x9], v[0xa], 0x03);
lbl_208:
	i = ram_2cd + 0x003;
lbl_20a:
	v[0x0b] = 0x00;
lbl_20c:
	v[0x0c] = 0x03;
lbl_20e:
	v[0xF] = plot(v[0xb], v[0xc], 0x03);
lbl_210:
	i = ram_2cd + 0x009;
lbl_212:
	v[0x04] = 0x1d;
lbl_214:
	v[0x05] = 0x1f;
lbl_216:
	v[0xF] = plot(v[0x4], v[0x5], 0x01);
lbl_218:
	v[0x07] = 0x00;
lbl_21a:
	v[0x08] = 0x0f;
lbl_21c:
	if (sp == STACK_DEPTH) { puts("Stack overflow"); return; } if (! setjmp(stack[sp])) { sp ++; goto lbl_2a2; } else sp --;
lbl_21e:
	if (sp == STACK_DEPTH) { puts("Stack overflow"); return; } if (! setjmp(stack[sp])) { sp ++; goto lbl_2ac; } else sp --;
lbl_220:
	if (v[0x08] != 0x00) goto lbl_224;
lbl_222:
	return;
lbl_224:
	v[0x04] = 0x1e;
lbl_226:
	v[0x05] = 0x1c;
lbl_228:
	i = ram_2cd + 0x006;
lbl_22a:
	v[0xF] = plot(v[0x4], v[0x5], 0x03);
lbl_22c:
	v[0x0e] = 0x00;
lbl_22e:
	v[0x06] = 0x80;
lbl_230:
	v[0x0d] = 0x04;
lbl_232:
	if (! check_key(v[0x0d])) goto lbl_236;
lbl_234:
	v[0x06] = 0xff;
lbl_236:
	v[0x0d] = 0x05;
lbl_238:
	if (! check_key(v[0x0d])) goto lbl_23c;
lbl_23a:
	v[0x06] = 0x00;
lbl_23c:
	v[0x0d] = 0x06;
lbl_23e:
	if (! check_key(v[0x0d])) goto lbl_242;
lbl_240:
	v[0x06] = 0x01;
lbl_242:
	if (v[0x06] == 0x80) goto lbl_246;
lbl_244:
	if (sp == STACK_DEPTH) { puts("Stack overflow"); return; } if (! setjmp(stack[sp])) { sp ++; goto lbl_2d8; } else sp --;
lbl_246:
	i = ram_2cd + 0x003;
lbl_248:
	v[0xF] = plot(v[0xb], v[0xc], 0x03);
lbl_24a:
	v[0x0d] = rand() & 0x01;
lbl_24c:
	{ uint16_t result = v[0x0b] + v[0x0d];
	v[0x0b] = result;
v[0xF] = (result > 255 ? 1 : 0);}
lbl_24e:
	v[0xF] = plot(v[0xb], v[0xc], 0x03);
lbl_250:
	if (v[0x0f] == 0x00) goto lbl_254;
lbl_252:
	goto lbl_292;
lbl_254:
	i = ram_2cd + 0x000;
lbl_256:
	v[0xF] = plot(v[0x9], v[0xa], 0x03);
lbl_258:
	v[0x0d] = rand() & 0x01;
lbl_25a:
	if (v[0x0d] == 0x00) goto lbl_25e;
lbl_25c:
	v[0x0d] = 0xff;
lbl_25e:
	v[0x09] += 0xfe;
lbl_260:
	v[0xF] = plot(v[0x9], v[0xa], 0x03);
lbl_262:
	if (v[0x0f] == 0x00) goto lbl_266;
lbl_264:
	goto lbl_28c;
lbl_266:
	if (v[0x0e] != 0x00) goto lbl_26a;
lbl_268:
	goto lbl_22e;
lbl_26a:
	i = ram_2cd + 0x006;
lbl_26c:
	v[0xF] = plot(v[0x4], v[0x5], 0x03);
lbl_26e:
	if (v[0x05] != 0x00) goto lbl_272;
lbl_270:
	goto lbl_286;
lbl_272:
	v[0x05] += 0xff;
lbl_274:
	{ uint16_t result = v[0x04] + v[0x06];
	v[0x04] = result;
v[0xF] = (result > 255 ? 1 : 0);}
lbl_276:
	v[0xF] = plot(v[0x4], v[0x5], 0x03);
lbl_278:
	if (v[0x0f] == 0x01) goto lbl_27c;
lbl_27a:
	goto lbl_246;
lbl_27c:
	v[0x0d] = 0x08;
lbl_27e:
	v[0x0d] &= v[0x05];
	v[0xF] = 0;
lbl_280:
	if (v[0x0d] != 0x08) goto lbl_284;
lbl_282:
	goto lbl_28c;
lbl_284:
	goto lbl_292;
lbl_286:
	if (sp == STACK_DEPTH) { puts("Stack overflow"); return; } if (! setjmp(stack[sp])) { sp ++; goto lbl_2ac; } else sp --;
lbl_288:
	v[0x08] += 0xff;
lbl_28a:
	goto lbl_21e;
lbl_28c:
	if (sp == STACK_DEPTH) { puts("Stack overflow"); return; } if (! setjmp(stack[sp])) { sp ++; goto lbl_2a2; } else sp --;
lbl_28e:
	v[0x07] += 0x05;
lbl_290:
	goto lbl_296;
lbl_292:
	if (sp == STACK_DEPTH) { puts("Stack overflow"); return; } if (! setjmp(stack[sp])) { sp ++; goto lbl_2a2; } else sp --;
lbl_294:
	v[0x07] += 0x0f;
lbl_296:
	if (sp == STACK_DEPTH) { puts("Stack overflow"); return; } if (! setjmp(stack[sp])) { sp ++; goto lbl_2a2; } else sp --;
lbl_298:
	v[0x0d] = 0x03;
lbl_29a:
	TIMER_SOUND = v[0x0d];
lbl_29c:
	i = ram_2cd + 0x006;
lbl_29e:
	v[0xF] = plot(v[0x4], v[0x5], 0x03);
lbl_2a0:
	goto lbl_286;
lbl_2a2:
	i = ram_2f8 + 0x000;
lbl_2a4:
	{ unsigned char value = v[0x07];
*(i + 2) = value % 10; value /= 10;
*(i + 1) = value % 10; *i = value / 10;}
lbl_2a6:
	v[0x03] = 0x00;
lbl_2a8:
	if (sp == STACK_DEPTH) { puts("Stack overflow"); return; } if (! setjmp(stack[sp])) { sp ++; goto lbl_2b6; } else sp --;
lbl_2aa:
	if (sp == 0) { puts("Stack underflow"); return; } longjmp(stack[sp - 1], 1);
lbl_2ac:
	i = ram_2f8 + 0x000;
lbl_2ae:
	{ unsigned char value = v[0x08];
*(i + 2) = value % 10; value /= 10;
*(i + 1) = value % 10; *i = value / 10;}
lbl_2b0:
	v[0x03] = 0x32;
lbl_2b2:
	if (sp == STACK_DEPTH) { puts("Stack overflow"); return; } if (! setjmp(stack[sp])) { sp ++; goto lbl_2b6; } else sp --;
lbl_2b4:
	if (sp == 0) { puts("Stack underflow"); return; } longjmp(stack[sp - 1], 1);
lbl_2b6:
	v[0x0d] = 0x1b;
lbl_2b8:
	for (unsigned char j = 0; j <= 0x02; j ++, i ++)
		v[j] = *i;
lbl_2ba:
	i = & FONT[5 * (v[0x00] & 0xF)];
lbl_2bc:
	v[0xF] = plot(v[0x3], v[0xd], 0x05);
lbl_2be:
	v[0x03] += 0x05;
lbl_2c0:
	i = & FONT[5 * (v[0x01] & 0xF)];
lbl_2c2:
	v[0xF] = plot(v[0x3], v[0xd], 0x05);
lbl_2c4:
	v[0x03] += 0x05;
lbl_2c6:
	i = & FONT[5 * (v[0x02] & 0xF)];
lbl_2c8:
	v[0xF] = plot(v[0x3], v[0xd], 0x05);
lbl_2ca:
	if (sp == 0) { puts("Stack underflow"); return; } longjmp(stack[sp - 1], 1);
lbl_2d8:
	v[0x0e] = 0x01;
lbl_2da:
	v[0x0d] = 0x10;
lbl_2dc:
	TIMER_SOUND = v[0x0d];
lbl_2de:
	if (sp == 0) { puts("Stack underflow"); return; } longjmp(stack[sp - 1], 1);
}
