const std = @import("std");
const atomic = std.atomic;

pub fn MPMCQ(comptime T: type, comptime slots: usize) type {

    const SLOT = struct {
        turn: atomic.Value(usize) align(64) = atomic.Value(usize).init(0),
        // ^ marks if slot is free
        //     free = (i * 2)
        //     in-use = (i + 2) + 1

        data: [@sizeOf(T)]u8 = undefined,
    };

    // Cache-Aligned: [head] [tail] [[slot] [slot] [slot]...]
    return struct {
        // Head and Tail continously count up
        head: atomic.Value(usize) align(64) = atomic.Value(usize).init(0),
        tail: atomic.Value(usize) align(64) = atomic.Value(usize).init(0),
        slots: [slots]SLOT align(64) = [_]SLOT{.{}} ** slots,

        pub inline fn enqueue(self: *@This(), item: *const T) void {
            // Find Next Slot
            const head = self.head.fetchAdd(1, .acq_rel);

            // Force Acquire
            const slot = &self.slots[head % slots];
            while ((head / slots) * 2 != slot.turn.load(.acquire))
                std.atomic.spinLoopHint();

            // Write
            @memcpy(&slot.data, @as([*]const u8, @ptrCast(item))[0..@sizeOf(T)]);

            // Release Slot (ittr + set odd)
            slot.turn.store((head / slots) * 2 + 1, .release);
        }

        pub inline fn dequeue(self: *@This(), item: *T) void {
            // Find Next Slot
            const tail = self.tail.fetchAdd(1, .acq_rel);

            // Force Acquire
            const slot = &self.slots[tail % slots];
            while ((tail / slots) * 2 + 1 != slot.turn.load(.acquire))
                std.atomic.spinLoopHint();

            // Write
            @memcpy(@as([*]u8, @ptrCast(item))[0..@sizeOf(T)], &slot.data); // Fill slot

            // Release Slot (itter + set-even)
            slot.turn.store((tail / slots) * 2 + 2, .release);
        }

        pub inline fn try_enqueue(self: *@This(), item: *const T) bool {
            // Get State
            var head = self.head.load(.acquire);

            // Try
            while (true) {

                // Find Free Slot
                const slot = &self.slots[head % slots];
                if ((head / slots) * 2 == slot.turn.load(.acquire)) {

                    // Try to aquire it
                    if (self.head.cmpxchgStrong(head, head + 1, .acq_rel, .acquire)) |_| {
                        head = self.head.load(.acquire);
                    } else { // aquired

                        // Write and Release
                        @memcpy(&slot.data, @as([*]const u8, @ptrCast(item))[0..@sizeOf(T)]);
                        slot.turn.store((head / slots) * 2 + 1, .release); // (itter + set-odd)

                        return true; // Success!
                    }
                } else { // No Free Slot?

                    // Check Acain
                    const prev_head = head;
                    head = self.head.load(.acquire);

                    // No Change?
                    if (head == prev_head) return false; // Fail! (choked quene)
                }
            }
        }

        pub inline fn try_dequeue(self: *@This(), item: *T) bool {
            // Get State
            var tail = self.tail.load(.acquire);

            // Try
            while (true) {

                // Find Free Slot
                const slot = &self.slots[tail % slots];
                if ((tail / slots) * 2 + 1 == slot.turn.load(.acquire)) {

                    // Try to aquire it
                    if (self.tail.cmpxchgStrong(tail, tail + 1, .acq_rel, .acquire)) |_| {
                        tail = self.tail.load(.acquire);
                    } else { // aquired

                        // Write and Release
                        @memcpy(@as([*]u8, @ptrCast(item))[0..@sizeOf(T)], &slot.data);
                        slot.turn.store((tail / slots) * 2 + 2, .release); // (itter + set-even)

                        return true; // Success!
                    }

                }  else { // No Free Slot?

                    // Check again
                    const prev_tail = tail;
                    tail = self.tail.load(.acquire);

                    // No Change?
                    if (tail == prev_tail) return false; // Fail! (choked quene)
                }
            }
        }
    };
}
