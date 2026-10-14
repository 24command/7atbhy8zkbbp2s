#!/usr/bin/env python3
"""Add an LC_LOAD_DYLIB command to a thin little-endian arm64 Mach-O.

This does not bypass code signing. The modified binary and its containing app must
be signed again before installation on a normal iOS device.
"""
from __future__ import annotations
import argparse
import shutil
import struct
from pathlib import Path

MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
LC_LOAD_DYLIB = 0x0C
LC_LOAD_WEAK_DYLIB = 0x80000018


def align(value: int, amount: int) -> int:
    return (value + amount - 1) & ~(amount - 1)


def parse_commands(data: bytearray):
    if len(data) < 32:
        raise ValueError("file is too small to be a Mach-O")
    magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack_from("<IiiIIIII", data, 0)
    if magic != MH_MAGIC_64:
        raise ValueError("only thin little-endian 64-bit Mach-O files are supported")
    offset = 32
    commands = []
    for index in range(ncmds):
        if offset + 8 > len(data):
            raise ValueError(f"load command {index} is outside the file")
        cmd, cmdsize = struct.unpack_from("<II", data, offset)
        if cmdsize < 8 or offset + cmdsize > len(data):
            raise ValueError(f"invalid load command {index}")
        commands.append((offset, cmd, cmdsize))
        offset += cmdsize
    expected_end = 32 + sizeofcmds
    if offset != expected_end:
        raise ValueError(f"load command size mismatch: parsed {offset:#x}, header says {expected_end:#x}")
    return ncmds, sizeofcmds, commands


def dylib_name(data: bytearray, offset: int, cmdsize: int) -> str | None:
    if cmdsize < 24:
        return None
    name_offset = struct.unpack_from("<I", data, offset + 8)[0]
    start, end = offset + name_offset, offset + cmdsize
    if not (offset <= start < end <= len(data)):
        return None
    return bytes(data[start:end]).split(b"\0", 1)[0].decode("utf-8", "replace")


def first_file_content_offset(data: bytearray, commands) -> int:
    candidates = []
    for offset, cmd, cmdsize in commands:
        if (cmd & 0x7FFFFFFF) != LC_SEGMENT_64 or cmdsize < 72:
            continue
        nsects = struct.unpack_from("<I", data, offset + 64)[0]
        section = offset + 72
        for _ in range(nsects):
            if section + 80 > offset + cmdsize:
                raise ValueError("truncated section table")
            section_offset = struct.unpack_from("<I", data, section + 48)[0]
            section_size = struct.unpack_from("<Q", data, section + 40)[0]
            if section_offset and section_size:
                candidates.append(section_offset)
            section += 80
    if not candidates:
        raise ValueError("could not find the first section file offset")
    return min(candidates)


def inject(path: Path, dependency: str, backup: bool) -> str:
    data = bytearray(path.read_bytes())
    ncmds, sizeofcmds, commands = parse_commands(data)
    for offset, cmd, cmdsize in commands:
        if cmd in (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB) and dylib_name(data, offset, cmdsize) == dependency:
            return "already present"

    encoded = dependency.encode("utf-8") + b"\0"
    command_size = align(24 + len(encoded), 8)
    command = bytearray(command_size)
    struct.pack_into("<IIIIII", command, 0, LC_LOAD_DYLIB, command_size, 24, 0, 0, 0)
    command[24:24 + len(encoded)] = encoded

    insert_at = 32 + sizeofcmds
    content_at = first_file_content_offset(data, commands)
    if insert_at + command_size > content_at:
        raise ValueError(
            f"not enough Mach-O header padding: need {command_size} bytes, "
            f"have {content_at - insert_at}"
        )
    if any(data[insert_at:insert_at + command_size]):
        raise ValueError("header padding is not zero; refusing to overwrite it")

    if backup:
        backup_path = path.with_suffix(path.suffix + ".before-phimod")
        if not backup_path.exists():
            shutil.copy2(path, backup_path)
    data[insert_at:insert_at + command_size] = command
    struct.pack_into("<I", data, 16, ncmds + 1)
    struct.pack_into("<I", data, 20, sizeofcmds + command_size)
    path.write_bytes(data)
    return f"inserted at {insert_at:#x}; header padding remaining: {content_at - insert_at - command_size} bytes"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("macho", type=Path)
    parser.add_argument("dependency")
    parser.add_argument("--no-backup", action="store_true")
    args = parser.parse_args()
    result = inject(args.macho, args.dependency, not args.no_backup)
    print(result)

if __name__ == "__main__":
    main()
