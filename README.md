# arc-shrinkler

An Acorn Archimedes port of the [Shrinkler](https://github.com/askeksa/Shrinkler) decompressor in (26-bit) ARM assembly language by Kieran Connell.

## Compilation

Use [vasm](http://sun.hasenbraten.de/vasm/) with standard syntax.

There a few compilation options:

* `_DEBUG=1` to enable additional run-time checks and throw `OS_GenerateError` SWI calls in the event of "assert" failures etc.
* `_PARITY_MASK=0` is the "no parity context" variant that works better with byte-oriented data. Initial testing suggest this is also better for 32-bit word ARM code.
* `_PARITY_MASK=1` is the original variant for Amiga 16-bit words.
* `_ENDIAN_SWAP=0` assumes that all 32-bit long-word data has been converted to ARM little-endian byte order at compression time. This is faster but requires a custom version of the `Shrinkler.exe` tool, see Compression section for more info.
* `_ENDIAN_SWAP=1` will swap the byte order of 32-bit long-words at run-time to match ARM little-endian format. This is slower but can be used with the original `Shrinkler.exe` tool for compatibility.
* `_PARSE_HEADER=1` adds an additional function `ShrinklerParseHeader` to parse and decompress data with a Shrinkler header.

## Usage

Call `ShrinklerDecompress` with the following registers:

    R0 = compressed data address (source)
    R1 = decompressed data address (dest)
    R2 = callback function address (or 0 if not required)
    R3 = callback argument
    R9 = context (scratch memory) buffer (NUM_CONTEXTS * 4 = 6144 bytes)

    Returns R0 = number of bytes written
    No registers are preserved!

Alternatively call `ShrinklerParseHeader` with the same register arguments.

## Compression

Either use the [original compressor](https://github.com/askeksa/Shrinkler/releases) or [my fork](https://github.com/kieranhj/Shrinkler) if you want to endian-swap the data at compression time for additional speed and smaller code.

Use Shrinkler _raw data_ compression:

    Shrinkler -p -d INPUT_FILE OUTPUT_FILE

With the following additional options:

    -b => disable "parity context" for byte-oriented data (recommended).
    -z => endian-swap 32-bit long-words in the output file (recommended).
    -w => add the Shrinker header to the output file (optional).
 
 Adjust compression options from `-1` to `-9` according to your patience and requirements. ;)

## Future Work

This code is certainly not size optimal, so there are likely to be improvements to be had. (Although a lack of Cinter or AmigaKlang port to the Archimedes hampers size-coded demo production more accutely.)

It is possible that investigating a 4 byte offset parity mask might well perform better compression on old ARM code that has fixed 32-bit instruction size. This would be at the expense of doubling the context (scratch) memory required during decompression.

## License


This code is released under the license terms of the original author Aske Simon Christensen. See [LICENSE.txt](LICENSE.txt) for details.

## Contact

Find me via the [Bitshifters website](https://bitshifters.github.io/).