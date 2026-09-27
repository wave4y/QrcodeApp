package com.example.qrcodeapp;

import java.nio.ByteBuffer;
import java.util.*;
import java.util.zip.CRC32;

public final class RaptorTransferCodecTest {
    static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
    static byte[] content(int length) {
        byte[] data = new byte[length]; new Random(6330 + length).nextBytes(data); return data;
    }
    static void roundTrip(int size, boolean repairOnly) {
        byte[] original = content(size);
        RaptorTransferCodec.Sender sender = new RaptorTransferCodec.Sender("中文-😀.bin", original);
        RaptorTransferCodec.Receiver receiver = new RaptorTransferCodec.Receiver();
        List<byte[]> frames = new ArrayList<>();
        int attempts = sender.sourceSymbols * 3 + sender.blocks * 30;
        for (int i = 0; i < attempts; i++) {
            byte[] frame = sender.nextFrame();
            check(4 + Base64.getEncoder().encodeToString(frame).length() <= 500, "QR frame exceeds 500 chars");
            int esi = ByteBuffer.wrap(frame).getInt(28) & 0xffffff;
            // In repair-only mode deliberately discard ALL systematic symbols.
            if (repairOnly && esi < (sender.sourceSymbols + sender.blocks - 1) / sender.blocks) continue;
            if (i % 3 == 0) continue; // deterministic 33% erasures
            frames.add(frame);
        }
        Collections.shuffle(frames, new Random(44));
        for (byte[] frame : frames) {
            receiver.accept(frame);
            receiver.accept(frame); // duplicate detections must be harmless
            if (receiver.file() != null) break;
        }
        check(receiver.file() != null, "Unable to recover " + size + " bytes repairOnly=" + repairOnly);
        check(Arrays.equals(original, receiver.file().bytes), "File bytes changed");
        check(receiver.file().name.equals("中文-😀.bin"), "Filename changed");
        check(receiver.progress() == 1, "Completed progress");
        System.out.println("PASS " + size + " bytes, repairOnly=" + repairOnly);
    }
    static void rejectionTests() {
        RaptorTransferCodec.Sender a = new RaptorTransferCodec.Sender("a.bin", content(1000));
        RaptorTransferCodec.Sender b = new RaptorTransferCodec.Sender("b.bin", content(2000));
        RaptorTransferCodec.Receiver r = new RaptorTransferCodec.Receiver();
        byte[] frame = a.nextFrame();
        byte[] bad = frame.clone(); bad[50] ^= 4;
        check(r.accept(bad).equals("corrupt"), "CRC corruption not rejected");
        check(r.needed == 0, "Corrupt frame allocated a transfer");
        check(r.accept(new byte[10]).equals("unsupported"), "Malformed frame accepted");
        r.accept(frame);
        int received = r.received;
        check(r.accept(frame).equals("duplicate") && r.received == received, "Duplicate counted");
        check(r.accept(b.nextFrame()).equals("other") && r.received == received, "Mixed transfers");
        r.reset();
        check(r.received == 0 && r.file() == null, "Reset failed");
        byte[] oversized = frame.clone();
        ByteBuffer.wrap(oversized).putInt(20, Integer.MAX_VALUE);
        CRC32 crc = new CRC32(); crc.update(oversized, 0, oversized.length - 4);
        ByteBuffer.wrap(oversized).putInt(oversized.length - 4, (int) crc.getValue());
        check(r.accept(oversized).equals("unsupported"), "Unbounded allocation accepted");
        // A syntactically valid frame with a wrong object ID must fail full-file integrity.
        RaptorTransferCodec.Sender tiny = new RaptorTransferCodec.Sender("t.bin", new byte[]{1});
        byte[] altered = tiny.nextFrame(); altered[4] ^= 1;
        crc.reset(); crc.update(altered, 0, altered.length - 4);
        ByteBuffer.wrap(altered).putInt(altered.length - 4, (int) crc.getValue());
        boolean rejected = false;
        try { r.accept(altered); } catch (IllegalArgumentException expected) { rejected = true; }
        check(rejected && r.file() == null, "Object hash mismatch not rejected");
        System.out.println("PASS CRC, duplicates, session isolation, reset, bounds, object hash");
    }
    public static void main(String[] args) {
        for (int size : new int[]{0, 1, 500, 8193, 180000}) {
            roundTrip(size, false); roundTrip(size, true);
        }
        rejectionTests();
    }
}
