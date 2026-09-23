# Accessory Packet

This document describes how to construct a Märklin CAN accessory-switching
packet according to section 4.1, "Befehl: Zubehör Schalten", of the supplied
CAN CS2 protocol document.

## Transport Format

The CAN-over-Ethernet gateway packet is exactly 13 bytes:

```text
Bytes 0..3   CAN identifier, big endian
Byte 4       DLC
Bytes 5..12  Eight CAN data bytes
```

The CAN message itself contains a 29-bit identifier, a DLC, and up to eight
data bytes. All multi-byte values use Motorola big-endian byte order.

## Input

For an accepted terminal input:

```text
<decimal accessory address><optional whitespace><R or G>
```

1. Parse the decimal accessory address.
2. Convert the direction letter to uppercase.
3. Reject addresses outside the supported MM2 accessory range.

The MM2 accessory Loc-ID range is `0x00003000` through `0x000033FF`, giving a
range of 1024 addresses. The user-facing address is one-based, so accept
`1..1024` and subtract one before constructing the Loc-ID.

## Constructing the Packet

### 1. Construct the Loc-ID

The user-facing address is one-based, so first subtract one:

```text
locID = 0x00003000 + (address - 1)
```

For example, user-facing address `3` produces:

```text
locID = 0x00003002
```

### 2. Construct the Accessory Data

The 6-byte accessory command has this format:

```text
DLC     Loc-ID (4 bytes)       Stellung  Strom
0x06    Loc-ID[31..24]         1 byte    1 byte
        Loc-ID[23..16]
        Loc-ID[15..8]
        Loc-ID[7..0]
```

Use these values:

```text
R -> Stellung = 0x00
G -> Stellung = 0x01
Strom         = 0x01
```

The protocol defines `Strom` as follows:

```text
0x00       switch off
0x01       switch on
0x02..0x1F switch on with a special function value
```

The physical meaning of `R` and `G` depends on the accessory protocol and
wiring. The `R`/`G` mapping should therefore remain configurable if the
installation uses the opposite orientation.

The eight CAN data bytes are:

```text
data[0] = byte(locID >> 24)
data[1] = byte(locID >> 16)
data[2] = byte(locID >> 8)
data[3] = byte(locID)
data[4] = stellung
data[5] = 0x01
data[6] = 0x00
data[7] = 0x00
```

### 3. Construct the CAN Identifier

For the accessory command, use:

```text
Command value     = 0x0B
CAN-ID command    = 0x16
Response bit      = 0, request
Priority          = 4, accessory command priority
```

The identifier is completed with a 16-bit collision-resolution hash:

```text
canID =
    (priority << 25) |
    (response << 24) |
    (0x16 << 16) |
    hash
```

The hash is derived from the application's configured 32-bit UID:

```text
rawHash = uint16(uid >> 16) XOR uint16(uid)
```

For CS1, bits 9..7 of the hash are the communication-area selector. They must
be `110` (bit 9 set, bit 8 set, bit 7 clear). Preserve all other bits of the
raw hash and apply that selector:

```text
hash = (rawHash & 0xFC00) | (rawHash & 0x007F) | 0x0300
```

The resulting hash must not collide with another active participant. The
`0x4711` value used in the PDF examples is a valid example hash. With the
application's default `CAN_UID=0x00004711`, the raw hash is `0x4711` and the
CS1-adjusted hash remains `0x4711`.

Write the resulting identifier in big-endian order into packet bytes `0..3`.

### 4. Assemble the 13-Byte Packet

```text
packet[0]    = byte(canID >> 24)
packet[1]    = byte(canID >> 16)
packet[2]    = byte(canID >> 8)
packet[3]    = byte(canID)
packet[4]    = 0x06
packet[5..12] = data[0..7]
```

## Example

For user-facing address `3`, direction `R`, priority `4`, and hash `0x4711`:

```text
locID = 0x00003002
canID = (4 << 25) | (0 << 24) | (0x16 << 16) | 0x4711
      = 0x08164711
```

The CAN data is:

```text
00 00 30 02 00 01 00 00
```

The complete transport packet is:

```text
08 16 47 11 06 00 00 30 02 00 01 00 00
```

## Sending

The packet must be sent as one complete 13-byte message. With TCP, use a
full-write loop because one `Write` call is not guaranteed to write every byte.
The receiver must read exactly 13 bytes at a time because TCP does not preserve
message boundaries.

The protocol document describes the original gateway as UDP rather than TCP.
That gateway accepts only UDP datagrams of exactly 13 bytes on port `15731` and
discards packets of other lengths. If the remote host is that gateway, UDP is
required even though the application currently uses TCP.
