all: curse8

curse8:	interp.c chip8-curses.c
	cc -Wall -march=native -flto -Ofast -o curse8 chip8-curses.c interp.c -lcurses

clean:
	rm -f *.o curse8

ufo:	UFO.ch8.c wrapper.c
	cc -Wall -march=native -flto -Ofast -o ufo UFO.ch8.c wrapper.c -lcurses
