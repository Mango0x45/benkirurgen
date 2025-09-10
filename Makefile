all: benläkaren

benläkaren: main.l
	flex --warn -o main.c $<
	cc -std=c23 -o $@ main.c
