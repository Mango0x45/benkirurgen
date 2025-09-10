%{
#include <err.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <libintl.h>

#define _(s) gettext(s)
#define lengthof(a) (sizeof(a) / sizeof((a)[0]))

#define YY_USER_ACTION yylloc.col += yyleng;
#define LOCNL (yylloc.col = 1, yylloc.row++)

typedef unsigned _BitInt(5) reg_t;

enum opfmt {
	R,
	I,
	D,
	B,
	CB,
	IM,
};

enum opcode {
	OP_B, OP_FMULS, OP_FDIVS, OP_FCMPS, OP_FADDS, OP_FSUBS, OP_FMULD, OP_FDIVD,
	OP_FCMPD, OP_FADDD, OP_FSUBD, OP_STURB, OP_LDURB, OP_B_COND, OP_STURH,
	OP_LDURH, OP_AND, OP_ADD, OP_ADDI, OP_ANDI, OP_BL, OP_SDIV, OP_UDIV, OP_MUL,
	OP_SMULH, OP_UMULH, OP_ORR, OP_ADDS, OP_ADDIS, OP_ORRI, OP_CBZ, OP_CBNZ,
	OP_STURW, OP_LDURSW, OP_STURS, OP_LDURS, OP_STXR, OP_LDXR, OP_EOR, OP_SUB,
	OP_SUBI, OP_EORI, OP_MOVZ, OP_LSR, OP_LSL, OP_BR, OP_ANDS, OP_SUBS, OP_SUBIS,
	OP_ANDIS, OP_MOVK, OP_STUR, OP_LDUR, OP_STURD, OP_LDURD,
};

struct opcode_desc {
	const char *name;
	int w;
	unsigned code, shamt;
	enum opfmt fmt;
};

static void bitch(const char *, ...);
static void decode(int);

static int rv;
static bool interactivep;
static const char *current_file;
static struct { size_t row, col; } yylloc = { 1, 0 };

static const char *REGISTERS[] = {
	"X0", "X1", "X2", "X3", "X4", "X5", "X6", "X7",
	"X8", "X9", "X10", "X11", "X12", "X13", "X14", "X15",
	"IP0", "IP1", "X18", "X19", "X20", "X21", "X22", "X23",
	"X24", "X25", "X26", "X27", "SP", "FP", "LR", "XZR",
};

static const struct opcode_desc OPCODES[] = {
	[OP_B]      = { "B",       6, 0b000101,            -1, B  },
	[OP_FMULS]  = { "FMULS",  11, 0b00011110001, 0b000010, R  },
	[OP_FDIVS]  = { "FDIVS",  11, 0b00011110001, 0b000110, R  },
	[OP_FCMPS]  = { "FCMPS",  11, 0b00011110001, 0b001000, R  },
	[OP_FADDS]  = { "FADDS",  11, 0b00011110001, 0b001010, R  },
	[OP_FSUBS]  = { "FSUBS",  11, 0b00011110001, 0b001110, R  },
	[OP_FMULD]  = { "FMULD",  11, 0b00011110011, 0b000010, R  },
	[OP_FDIVD]  = { "FDIVD",  11, 0b00011110011, 0b000110, R  },
	[OP_FCMPD]  = { "FCMPD",  11, 0b00011110011, 0b001000, R  },
	[OP_FADDD]  = { "FADDD",  11, 0b00011110011, 0b001010, R  },
	[OP_FSUBD]  = { "FSUBD",  11, 0b00011110011, 0b001110, R  },
	[OP_STURB]  = { "STURB",  11, 0b00111000000,       -1, D  },
	[OP_LDURB]  = { "LDURB",  11, 0b00111000010,       -1, D  },
	[OP_B_COND] = { "B.cond",  8, 0b01010100,          -1, CB },
	[OP_STURH]  = { "STURH",  11, 0b01111000000,       -1, D  },
	[OP_LDURH]  = { "LDURH",  11, 0b01111000010,       -1, D  },
	[OP_AND]    = { "AND",    11, 0b10001010000,       -1, R  },
	[OP_ADD]    = { "ADD",    11, 0b10001011000,       -1, R  },
	[OP_ADDI]   = { "ADDI",   10, 0b1001000100,        -1, I  },
	[OP_ANDI]   = { "ANDI",   10, 0b1001001000,        -1, I  },
	[OP_BL]     = { "BL",      6, 0b100101,            -1, B  },
	[OP_SDIV]   = { "SDIV",   11, 0b10011010110, 0b000010, R  },
	[OP_UDIV]   = { "UDIV",   11, 0b10011010110, 0b000011, R  },
	[OP_MUL]    = { "MUL",    11, 0b10011011000, 0b011111, R  },
	[OP_SMULH]  = { "SMULH",  11, 0b10011011010,       -1, R  },
	[OP_UMULH]  = { "UMULH",  11, 0b10011011110,       -1, R  },
	[OP_ORR]    = { "ORR",    11, 0b10101010000,       -1, R  },
	[OP_ADDS]   = { "ADDS",   11, 0b10101011000,       -1, R  },
	[OP_ADDIS]  = { "ADDIS",  10, 0b1011000100,        -1, I  },
	[OP_ORRI]   = { "ORRI",   10, 0b1011001000,        -1, I  },
	[OP_CBZ]    = { "CBZ",     8, 0b10110100,          -1, CB },
	[OP_CBNZ]   = { "CBNZ",    8, 0b10110101,          -1, CB },
	[OP_STURW]  = { "STURW",  11, 0b10111000000,       -1, D  },
	[OP_LDURSW] = { "LDURSW", 11, 0b10111000100,       -1, D  },
	[OP_STURS]  = { "STURS",  11, 0b10111100000,       -1, R  },
	[OP_LDURS]  = { "LDURS",  11, 0b10111100100,       -1, R  },
	[OP_STXR]   = { "STXR",   11, 0b11001000000,       -1, D  },
	[OP_LDXR]   = { "LDXR",   11, 0b11001000010,       -1, D  },
	[OP_EOR]    = { "EOR",    11, 0b11001010000,       -1, R  },
	[OP_SUB]    = { "SUB",    11, 0b11001011000,       -1, R  },
	[OP_SUBI]   = { "SUBI",   10, 0b1101000100,        -1, I  },
	[OP_EORI]   = { "EORI",   10, 0b1101001000,        -1, I  },
	[OP_MOVZ]   = { "MOVZ",    9, 0b110100101,         -1, IM },
	[OP_LSR]    = { "LSR",    11, 0b11010011010,       -1, R  },
	[OP_LSL]    = { "LSL",    11, 0b11010011011,       -1, R  },
	[OP_BR]     = { "BR",     11, 0b11010110000,       -1, R  },
	[OP_ANDS]   = { "ANDS",   11, 0b11101010000,       -1, R  },
	[OP_SUBS]   = { "SUBS",   11, 0b11101011000,       -1, R  },
	[OP_SUBIS]  = { "SUBIS",  10, 0b1111000100,        -1, I  },
	[OP_ANDIS]  = { "ANDIS",  10, 0b1111001000,        -1, I  },
	[OP_MOVK]   = { "MOVK",    9, 0b111100101,         -1, IM },
	[OP_STUR]   = { "STUR",   11, 0b11111000000,       -1, D  },
	[OP_LDUR]   = { "LDUR",   11, 0b11111000010,       -1, D  },
	[OP_STURD]  = { "STURD",  11, 0b11111100000,       -1, R  },
	[OP_LDURD]  = { "LDURD",  11, 0b11111100010,       -1, R  },
};
%}

%option nodefault
%option noinput nounput noyywrap

bin [01]
hex [0-9a-f]
HEX [0-9A-F]

%%

{bin}{32} { decode(2);  }
{hex}{8}  { decode(16); }
{HEX}{8}  { decode(16); }

{bin}{0,31}|{hex}{0,7}|{HEX}{0,7}|{bin}+|{hex}+|{HEX}+ {
	bitch(_("%s:%zu:%zu: opcode ‘%s’ is not 32 bits"),
	      current_file, yylloc.row, yylloc.col, yytext);
}

({bin}|{hex}|{HEX})+ {
	bitch(_("%s:%zu:%zu: invalid opcode ‘%s’"),
	      current_file, yylloc.row, yylloc.col, yytext);
}

[ \t]+ ;
\n { LOCNL; }

. {
	bitch(_("%s:%zu:%zu: unknown character ‘%c’"),
	      current_file, yylloc.row, yylloc.col, *yytext);
}

%%

void
bitch(const char *fmt, ...)
{
	va_list ap;
	va_start(ap);
	rv = EXIT_FAILURE;
	if (interactivep)
		vwarnx(fmt, ap);
	else
		verrx(rv, fmt, ap);
	va_end(ap);
}

void
decode(int base)
{
	constexpr unsigned RMSK = 0x3F;
	uint32_t n = strtol(yytext, nullptr, base);

	for (size_t i = 0; i < lengthof(OPCODES); i++) {
		struct opcode_desc opd = OPCODES[i];
		int shft = 32 - 11 + (11 - opd.w);
		if ((n >> shft) != (uint32_t)opd.code)
			continue;

		/* Några instruktioner använder SHAMT för att utmärka sig,
		   förutom LSL och LSR som använder dem som argument. */
		unsigned shamt = n>>10 & 0x3F;
		if (opd.shamt != -1 && i != OP_LSL && i != OP_LSR) {
			if (shamt != opd.shamt)
				continue;
		}

		uint16_t imm;
		uint32_t addr;
		reg_t rd, rn, rm, rt;

		switch (opd.fmt) {
		case R:
			rd = n>>0  & RMSK;
			rn = n>>5  & RMSK;
			rm = n>>16 & RMSK;
			if (i == OP_LSL || i == OP_LSR) {
				printf("%s\t%s, %s, %d\n", opd.name,
				       REGISTERS[rd], REGISTERS[rn], shamt);
			} else {
				printf("%s\t%s, %s, %s\n", opd.name,
				       REGISTERS[rd], REGISTERS[rn], REGISTERS[rm]);
			}
			break;
		case I:
			rd = n>>0 & RMSK;
			rn = n>>5 & RMSK;
			imm = n>>10 & 0xFFF;
			printf("%s\t%s, %s, %d\n", opd.name,
			       REGISTERS[rd], REGISTERS[rn], imm);
			break;
		case D:
			rt = n>>0 & RMSK;
			rn = n>>5 & RMSK;
			imm = n>>12 & 0x1FF;
			printf("%s\t%s, %s, %d\n", opd.name,
			       REGISTERS[rt], REGISTERS[rn], addr);
			break;
		case B:
			addr = n & 0x3FFFFFFul;
			printf("%s\t0x%08X\n", opd.name, addr);
			break;
		case CB:
			addr = n>>5 & 0x7FFFFul;
			rt = n & RMSK;
			printf("%s\t%s, 0x%08X\n", opd.name, REGISTERS[rt], addr);
			break;
		case IM:
			rd = n & RMSK;
			imm = n>>5 & 0xFFFF;
			printf("%s\t%s, %d\n", opd.name, REGISTERS[rd], imm);
			break;
		}

		return;
	}

	bitch(_("%s:%zu:%zu: unknown opcode ‘%s’"),
	      current_file, yylloc.row, yylloc.col, yytext);
}

int
main(int argc, char **argv)
{
	interactivep = isatty(STDIN_FILENO);
	for (int i = 1; i < argc; i++) {
		current_file = argv[i];
		if (strcmp(current_file, "-") == 0)
			yyin = stdin;
		else if ((yyin = fopen(current_file, "r")) == nullptr) {
			warn("%s", current_file);
			rv = EXIT_FAILURE;
			continue;
		}

		yylex();
		if (yyin != stdin)
			fclose(yyin);
	}
	if (argc == 1) {
		current_file = "-";
		yylex();
	}
	return rv;
}
