package com.example.qrcodeapp;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import java.util.zip.CRC32;
import net.fec.openrq.ArrayDataDecoder;
import net.fec.openrq.ArrayDataEncoder;
import net.fec.openrq.EncodingPacket;
import net.fec.openrq.OpenRQ;
import net.fec.openrq.decoder.SourceBlockDecoder;
import net.fec.openrq.encoder.SourceBlockEncoder;
import net.fec.openrq.parameters.FECParameters;

/** Mobile optical transport. The FEC codec is unmodified RFC 6330 OpenRQ. */
public final class RaptorTransferCodec {
    public static final int MAX_FILE_SIZE = 8 * 1024 * 1024;
    public static final int SYMBOL_SIZE = 320;
    public static final int MAX_BLOCK_SYMBOLS = 256;
    private static final int FRAME_MAGIC = 0x52514631; // RQF1
    private static final int OBJECT_MAGIC = 0x52514f31; // RQO1
    private static final int FRAME_SIZE = 36 + SYMBOL_SIZE;
    private static final int MAX_OBJECT_SIZE = MAX_FILE_SIZE + 1066;

    private RaptorTransferCodec() {}

    private static byte[] hash(byte[] data) {
        try { return MessageDigest.getInstance("SHA-256").digest(data); }
        catch (Exception e) { throw new IllegalStateException(e); }
    }

    public static final class FileData {
        public final String name;
        public final byte[] bytes;
        FileData(String name, byte[] bytes) { this.name = name; this.bytes = bytes; }
    }

    public static final class Sender {
        public final String name;
        public final int fileSize;
        public final int sourceSymbols;
        public final int blocks;
        private final ArrayDataEncoder encoder;
        private final byte[] id;
        private final int length;
        private long sequence;

        public Sender(String name, byte[] data) {
            if (data.length > MAX_FILE_SIZE) throw new IllegalArgumentException("文件最大支持 8 MB");
            if (name == null || name.isEmpty()) name = "file.bin";
            byte[] filename = name.getBytes(StandardCharsets.UTF_8);
            if (filename.length > 1024) throw new IllegalArgumentException("文件名过长");
            this.name = name;
            fileSize = data.length;
            ByteBuffer object = ByteBuffer.allocate(42 + filename.length + data.length);
            object.putInt(OBJECT_MAGIC).putShort((short) filename.length).putInt(data.length);
            object.put(hash(data)).put(filename).put(data);
            byte[] content = object.array();
            length = content.length;
            id = Arrays.copyOf(hash(content), 16);
            sourceSymbols = (length + SYMBOL_SIZE - 1) / SYMBOL_SIZE;
            blocks = (sourceSymbols + MAX_BLOCK_SYMBOLS - 1) / MAX_BLOCK_SYMBOLS;
            encoder = OpenRQ.newEncoder(content, FECParameters.newParameters(length, SYMBOL_SIZE, blocks));
        }

        /** Round-robin source blocks, then generate fresh repair ESIs indefinitely. */
        public byte[] nextFrame() {
            long round = sequence / blocks;
            // Rotate the block order each round: periodic camera losses must
            // not repeatedly erase the same source block.
            int blockNumber = (int) ((sequence % blocks + round) % blocks);
            sequence++;
            SourceBlockEncoder block = encoder.sourceBlock(blockNumber);
            int k = block.numberOfSourceSymbols();
            int esi = round <= 0xffffff ? (int) round : k + (int) ((round - k) % (0x1000000 - k));
            EncodingPacket packet = block.encodingPacket(esi);
            byte[] symbol = new byte[SYMBOL_SIZE];
            ByteBuffer symbols = packet.symbols();
            symbols.get(symbol, 0, symbols.remaining());
            ByteBuffer frame = ByteBuffer.allocate(FRAME_SIZE);
            frame.putInt(FRAME_MAGIC).put(id).putInt(length).putShort((short) SYMBOL_SIZE);
            frame.put((byte) blocks).put((byte) 1); // RFC 6330 N=1, Al=1
            frame.putInt((blockNumber << 24) | esi).put(symbol);
            CRC32 crc = new CRC32();
            crc.update(frame.array(), 0, FRAME_SIZE - 4);
            frame.putInt((int) crc.getValue());
            return frame.array();
        }
    }

    public static final class Receiver {
        private byte[] id;
        private int length;
        private int blocks;
        private ArrayDataDecoder decoder;
        private final Set<Integer> seen = new HashSet<>();
        private FileData file;
        public int received;
        public int needed;

        public FileData file() { return file; }
        public double progress() { return file != null ? 1.0 : needed == 0 ? 0 : Math.min(.99, received / (double) needed); }

        /** Reject corrupt/unrelated frames before allocating or invoking the decoder. */
        public String accept(byte[] frame) {
            if (frame == null || frame.length != FRAME_SIZE) return "unsupported";
            ByteBuffer b = ByteBuffer.wrap(frame);
            if (b.getInt() != FRAME_MAGIC) return "unsupported";
            CRC32 crc = new CRC32();
            crc.update(frame, 0, frame.length - 4);
            if ((int) crc.getValue() != b.getInt(frame.length - 4)) return "corrupt";
            byte[] candidateId = new byte[16]; b.get(candidateId);
            int candidateLength = b.getInt();
            int t = b.getShort() & 0xffff;
            int z = b.get() & 0xff;
            int n = b.get() & 0xff;
            int payloadId = b.getInt();
            int sbn = payloadId >>> 24;
            int esi = payloadId & 0xffffff;
            if (candidateLength < 42 || candidateLength > MAX_OBJECT_SIZE ||
                    t != SYMBOL_SIZE || z < 1 || sbn >= z || n != 1) return "unsupported";
            int k = (candidateLength + t - 1) / t;
            if (z != (k + MAX_BLOCK_SYMBOLS - 1) / MAX_BLOCK_SYMBOLS) return "unsupported";
            if (id != null && (!Arrays.equals(id, candidateId) || length != candidateLength || blocks != z)) {
                return "other";
            }
            if (file != null) return "complete";
            if (id == null) {
                decoder = OpenRQ.newDecoder(FECParameters.newParameters(candidateLength, t, z), 2);
                id = candidateId; length = candidateLength; blocks = z; needed = k;
            }
            SourceBlockDecoder block = decoder.sourceBlock(sbn);
            if (seen.contains(payloadId) || block.isSourceBlockDecoded()) return "duplicate";
            // Bound state even for valid-CRC hostile input streams.
            if (seen.size() >= needed * 4 + blocks * 32) throw new IllegalArgumentException("接收数据异常，请重新识别");
            byte[] symbol = new byte[t]; b.get(symbol);
            EncodingPacket packet = decoder.parsePacket(sbn, esi, symbol, true).value();
            seen.add(payloadId);
            received++;
            block.putEncodingPacket(packet);
            if (!decoder.isDataDecoded()) return "accepted";
            byte[] object = decoder.dataArray();
            if (!Arrays.equals(id, Arrays.copyOf(hash(object), 16))) {
                throw new IllegalArgumentException("文件完整性校验失败，请重新识别");
            }
            file = decodeObject(object);
            decoder = null;
            seen.clear();
            return "complete";
        }

        public void reset() {
            id = null; decoder = null; file = null; seen.clear();
            length = 0; blocks = 0; received = 0; needed = 0;
        }
    }

    private static FileData decodeObject(byte[] object) {
        ByteBuffer b = ByteBuffer.wrap(object);
        if (b.remaining() < 42 || b.getInt() != OBJECT_MAGIC) throw new IllegalArgumentException("文件头无效");
        int nameSize = b.getShort() & 0xffff;
        int fileSize = b.getInt();
        if (nameSize < 1 || nameSize > 1024 || fileSize < 0 || fileSize > MAX_FILE_SIZE ||
                b.remaining() != 32 + nameSize + fileSize) throw new IllegalArgumentException("文件长度无效");
        byte[] checksum = new byte[32]; b.get(checksum);
        byte[] nameBytes = new byte[nameSize]; b.get(nameBytes);
        byte[] data = new byte[fileSize]; b.get(data);
        if (!Arrays.equals(checksum, hash(data))) throw new IllegalArgumentException("文件 SHA-256 校验失败");
        String name = new String(nameBytes, StandardCharsets.UTF_8).replace('\\', '/');
        name = name.substring(name.lastIndexOf('/') + 1).replaceAll("[\\x00-\\x1f\\x7f]", "_").trim();
        if (name.isEmpty() || name.equals(".") || name.equals("..")) name = "received-file.bin";
        return new FileData(name, data);
    }
}
