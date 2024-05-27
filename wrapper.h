#ifndef WRAPPER_H_
#define WRAPPER_H_ 

unsigned char check_key(unsigned char value);
unsigned char await_key();
void screen_set(unsigned char x, unsigned char y, unsigned char set);
void screen_update();
void screen_clear();

#endif
