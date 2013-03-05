AS = nasm
ASFLAGS = -f elf -D__LINUX__ -D__ELF__ -i./lib/
LD = ld
PROGNAME = mineproxy
SOURCE = src/mineproxy.asm
OBJECT = src/mineproxy.o

all: $(PROGNAME)

$(PROGNAME):
	$(AS) $(ASFLAGS) $(SOURCE)
	$(LD) -o $(PROGNAME) $(OBJECT)

clean:
	rm -rf $(PROGNAME) $(OBJECT)
