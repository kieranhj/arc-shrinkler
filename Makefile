RM_RF:=rm -Rf
MKDIR_P:=mkdir -p
COPY:=cp
PYTHON3?=python
DOS2UNIX?=dos2unix

ROSE2ARC=./bin/rose2arc.py
VASM=./bin/vasmarm_std_win32.exe -m250 -Fbin -opt-adr
# no progress, data (not Amiga hunk), endian swap words, assume bytes.
SHRINKLER=./bin/shrinkler.exe -p -d -z -b

ARCULATOR_HOSTFS=../../Arculator_V2.1_Windows/hostfs

##########################################################################
##########################################################################

.PHONY:all
all: shrinkler

.PHONY:clean
clean:
	$(RM_RF) build

##########################################################################
##########################################################################

SHRINKLER_ARC=shrinkler,ff8

.PHONY:shrinkler
shrinkler: $(ARCULATOR_HOSTFS)/$(SHRINKLER_ARC)

build/shrinkler.bin: src/main.asm src/arc-shrinkler.asm build/stniccc.shri build/a252.shri build/waytoorude.shri
	$(MKDIR_P) build
	$(VASM) -L build/compile.txt -o build/shrinkler.bin src/main.asm

$(ARCULATOR_HOSTFS)/$(SHRINKLER_ARC): build/shrinkler.bin
	$(RM_RF) $(ARCULATOR_HOSTFS)/$(SHRINKLER_ARC)
	cp build/shrinkler.bin $(ARCULATOR_HOSTFS)/$(SHRINKLER_ARC)

##########################################################################
##########################################################################

build/stniccc.shri: data/stniccc.bin
	$(MKDIR_P) build
	$(SHRINKLER) $< $@

build/a252.shri: data/a252eur3.txt
	$(MKDIR_P) build
	$(SHRINKLER) $< $@

build/waytoorude.shri: data/waytoorude.bin 
	$(MKDIR_P) build
	$(SHRINKLER) $< $@
