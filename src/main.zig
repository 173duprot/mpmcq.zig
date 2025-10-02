const std = @import("std");
const atomic = std.atomic;

pub fn MPMCQ(comptime T: type, comptime slots: usize) type {
    const SLOT = struct {
        turn: atomic.Value(usize) align(64) = atomic.Value(usize).init(0),
        data: [@sizeOf(T)]u8 = undefined,
    };
    return struct {
        head: atomic.Value(usize) align(64) = atomic.Value(usize).init(0),
        tail: atomic.Value(usize) align(64) = atomic.Value(usize).init(0),
        slots_array: [slots]SLOT align(64) = [_]SLOT{.{}} ** slots,
        pub inline fn enqueue(self: *@This(), item: *const T) void {
            const head = self.head.fetchAdd(1, .acq_rel);
            const slot = &self.slots_array[head % slots];
            while ((head / slots) * 2 != slot.turn.load(.acquire)) std.atomic.spinLoopHint();
            @memcpy(&slot.data, @as([*]const u8, @ptrCast(item))[0..@sizeOf(T)]);
            slot.turn.store((head / slots) * 2 + 1, .release);
        }
        pub inline fn dequeue(self: *@This(), item: *T) void {
            const tail = self.tail.fetchAdd(1, .acq_rel);
            const slot = &self.slots_array[tail % slots];
            while ((tail / slots) * 2 + 1 != slot.turn.load(.acquire)) std.atomic.spinLoopHint();
            @memcpy(@as([*]u8, @ptrCast(item))[0..@sizeOf(T)], &slot.data);
            slot.turn.store((tail / slots) * 2 + 2, .release);
        }
        pub inline fn try_enqueue(self: *@This(), item: *const T) bool {
            var head = self.head.load(.acquire);
            while (true) {
                const slot = &self.slots_array[head % slots];
                if ((head / slots) * 2 == slot.turn.load(.acquire)) {
                    if (self.head.cmpxchgStrong(head, head + 1, .acq_rel, .acquire)) |_| {
                        head = self.head.load(.acquire);
                    } else {
                        @memcpy(&slot.data, @as([*]const u8, @ptrCast(item))[0..@sizeOf(T)]);
                        slot.turn.store((head / slots) * 2 + 1, .release);
                        return true;
                    }
                } else {
                    const prev_head = head;
                    head = self.head.load(.acquire);
                    if (head == prev_head) return false;
                }
            }
        }
        pub inline fn try_dequeue(self: *@This(), item: *T) bool {
            var tail = self.tail.load(.acquire);
            while (true) {
                const slot = &self.slots_array[tail % slots];
                if ((tail / slots) * 2 + 1 == slot.turn.load(.acquire)) {
                    if (self.tail.cmpxchgStrong(tail, tail + 1, .acq_rel, .acquire)) |_| {
                        tail = self.tail.load(.acquire);
                    } else {
                        @memcpy(@as([*]u8, @ptrCast(item))[0..@sizeOf(T)], &slot.data);
                        slot.turn.store((tail / slots) * 2 + 2, .release);
                        return true;
                    }
                } else {
                    const prev_tail = tail;
                    tail = self.tail.load(.acquire);
                    if (tail == prev_tail) return false;
                }
            }
        }
    };
}

pub fn main() !void {
    const Queue = MPMCQ(c_int, 10);
    var queue = Queue{};

    var value1: c_int = 42;
    var value2: c_int = 0;

    queue.enqueue(&value1);
    queue.dequeue(&value2);

    std.debug.print("Enqueued: {}, Dequeued: {}\n", .{ value1, value2 });

    var value3: c_int = 100;
    var value4: c_int = 0;

    if (queue.try_enqueue(&value3)) {
        std.debug.print("Successfully enqueued: {}\n", .{value3});
    }

    if (queue.try_dequeue(&value4)) {
        std.debug.print("Successfully dequeued: {}\n", .{value4});
    }
}
