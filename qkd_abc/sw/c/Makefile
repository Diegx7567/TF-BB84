# Makefile del shim: 'make' produce pcilib.so listo para ctypes
CC      = gcc
CFLAGS  = -O2 -Wall -fPIC
all: pcilib.so
pcilib.so: pcilib_shim.c
	$(CC) $(CFLAGS) -shared -o $@ $<
clean:
	rm -f pcilib.so
