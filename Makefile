all: benkirurgen

benkirurgen: main.l
	flex --warn -o main.c $<
	cc -D_GNU_SOURCE -std=c23 -o $@ main.c
