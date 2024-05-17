curse8:	interp.c chip8-curses.c
	cc -Wall -o curse8 chip8-curses.c interp.c -lcurses

clean:
	rm -f *.o curse8
