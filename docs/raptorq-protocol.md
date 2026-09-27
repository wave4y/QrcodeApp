# RaptorQ mobile optical transfer (RQ1)

## Usage

Both phones run this Android app. Tap the main page title “二维码工具”.
The transfer page has “识别” and “创建” segments. The sender chooses a file
or enters text, then starts playback. The receiver points its camera at the
sender until SHA-256 verification succeeds, then saves through Android's
system file dialog. No computer, server, network transfer, or broad storage
permission is needed. Default playback is 4 fps, adjustable from 1 to 10.

Individual QR frames contain 480 ASCII characters, below the requested 500
character limit. Normal QR generation remains at 500 Unicode code points per
page. Files up to 8 MiB are supported (larger files take a long time over an
optical link). File names are preserved, with path/control characters removed
when saving. Cancelling save retains the recovered file. Pausing reception or
switching segments retains progress while this page is open; leaving the page
or process termination clears the in-memory transfer.

## Codec and compatibility

FEC: RFC 6330 RaptorQ, implemented by OpenRQ 3.3.2 (Apache-2.0).
https://www.rfc-editor.org/rfc/rfc6330.html
https://github.com/openrq-team/OpenRQ/releases/tag/3.3.2

F=encoded object length, T=320, Z=ceil(ceil(F/T)/256), N=1, Al=1.
Systematic symbols are emitted first, followed by fresh repair symbols. Source
blocks are visited once each per round, with the starting block rotating on
every round to prevent periodic camera erasures from starving a block. The
round number is the 24-bit ESI; source block number is the upper 8 bits of the
RFC FEC Payload ID. After ESI exhaustion, repair ESIs cycle in their valid range.

RQ1 is this app's optical envelope, **not** a universal RFC-defined QR format.
It does not interoperate with AirScan-QR, RaptorQR, or arbitrary third-party
senders merely because they use fountain codes or RFC 6330.

## QR transport

QR text = `RQ1:` + standard padded Base64 of the following 356-byte frame.
All integers are big-endian. Reject non-canonical Base64, wrong lengths, or
unknown versions before sending a frame to the native worker.

| Byte offset | Bytes | Meaning |
|---|---:|---|
| 0 | 4 | ASCII `RQF1` |
| 4 | 16 | First 16 bytes of SHA-256 of the complete encoded object |
| 20 | 4 | Object length F |
| 24 | 2 | Symbol size T=320 |
| 26 | 1 | Source block count Z |
| 27 | 1 | Sub-block count N=1 (Al=1 implicit in version 1) |
| 28 | 4 | RFC 6330 payload ID: SBN (8 bits), ESI (24 bits) |
| 32 | 320 | Encoding symbol (last source symbol is zero padded) |
| 352 | 4 | IEEE CRC-32 over bytes 0..351 |

## Encoded object

The entire envelope is protected by RaptorQ, so a receiver joining late does
not need an initial metadata QR. It contains:

1. `RQO1` (4 bytes).
2. UTF-8 filename byte count (u16, 1..1024).
3. Original file byte count (u32, 0..8 MiB).
4. SHA-256 of original file (32 bytes).
5. UTF-8 filename, followed by original file bytes.

Receiver verifies every frame's CRC, the object ID against its reconstructed
SHA-256, object lengths, and the complete file SHA-256 before offering save.
These checks detect accidental corruption; the optical stream is not encrypted
or authenticated. The receiver locks onto its first valid transfer and ignores
other transfer IDs until explicitly reset. Duplicate symbols and symbols for
already decoded source blocks do not increase progress. Progress is an estimate
capped at 99% until successful recovery, because K symbols do not guarantee
reconstruction. Native work runs on a serial background executor. The camera
callback has one request in flight to bound work and memory.

## Verification

- `bash scripts/test_raptorq.sh`: real OpenRQ round trips for empty, tiny, binary,
  Unicode-named and multi-block files; 33% periodic erasures, shuffled order,
  duplicates, **repair-only** recovery with every systematic symbol dropped,
  CRC rejection, transfer isolation, invalid sizes and object-hash rejection.
- `flutter test`: QR size/transport round trip, mode navigation, creation,
  playback/pause, picker cancellation, receive pause/resume, save cancellation
  and completion, plus the existing ordinary-QR regression suite.

Camera throughput and Android's real file-provider dialogs require two-device
validation. Unit/widget tests use mocked platform channels for those interactions.
