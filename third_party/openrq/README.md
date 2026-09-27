# OpenRQ 3.3.2

Unmodified official release used for RFC 6330 encoding/decoding on Android.

- Project: https://github.com/openrq-team/OpenRQ
- Release: https://github.com/openrq-team/OpenRQ/releases/tag/3.3.2
- Binary: https://github.com/openrq-team/OpenRQ/releases/download/3.3.2/openrq-3.3.2.jar
- Local binary: `android/app/libs/openrq-3.3.2.jar`
- SHA-256: `904603c0c6a031090c94d7b82dc4e7e1426f4968ac0dde94432ae3352cf106b8`
- License: Apache-2.0, reproduced in LICENSE in this directory.

The upstream library implements RaptorQ with one sub-block per source block.
The app uses this valid RFC 6330 profile (N=1, Al=1), with T=320 bytes and
at most 256 source symbols per source block. The optical frame format and
file envelope are implemented by this project; they are not defined by RFC 6330.
No AirScan-QR or RaptorQR implementation code is included.
