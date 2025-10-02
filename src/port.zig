const std = @import("std");
const builtin = @import("builtin");
const atomic = std.atomic;

const SLOTS = 10;
const SLOT = @sizeOf(c_int);
const CACHE_LINE = 64;

const Slot = struct {
    turn: atomic.Value(usize) align(CACHE_LINE) = atomic.Value(usize).init(0),
    data: [SLOT]u8 = undefined,
};

const Queue = struct {
    head: atomic.Value(usize) align(CACHE_LINE) = atomic.Value(usize).init(0),
    tail: atomic.Value(usize) align(CACHE_LINE) = atomic.Value(usize).init(0),
    slots: [SLOTS]Slot align(CACHE_LINE) = [_]Slot{.{}} ** SLOTS,
};

pub inline fn enqueue(queue: *Queue, item: *const anyopaque) void {
    const head = queue.head.fetchAdd(1, .acq_rel);
    const slot = &queue.slots[head % SLOTS];
    while ((head / SLOTS) * 2 != slot.turn.load(.acquire)) {
        // busy-wait
        std.atomic.spinLoopHint();
    }
    @memcpy(&slot.data, @as([*]const u8, @ptrCast(item))[0..SLOT]);
    slot.turn.store((head / SLOTS) * 2 + 1, .release);
}

pub inline fn dequeue(queue: *Queue, item: *anyopaque) void {
    const tail = queue.tail.fetchAdd(1, .acq_rel);
    const slot = &queue.slots[tail % SLOTS];
    while ((tail / SLOTS) * 2 + 1 != slot.turn.load(.acquire)) {
        // busy-wait
        std.atomic.spinLoopHint();
    }
    @memcpy(@as([*]u8, @ptrCast(item))[0..SLOT], &slot.data);
    slot.turn.store((tail / SLOTS) * 2 + 2, .release);
}

pub inline fn try_enqueue(queue: *Queue, item: *const anyopaque) bool {
    var head = queue.head.load(.acquire);
    while (true) {
        const slot = &queue.slots[head % SLOTS];
        if ((head / SLOTS) * 2 == slot.turn.load(.acquire)) {
            if (queue.head.cmpxchgStrong(head, head + 1, .acq_rel, .acquire)) |_| {
                // cmpxchg failed, update head
                head = queue.head.load(.acquire);
            } else {
                // cmpxchg succeeded
                @memcpy(&slot.data, @as([*]const u8, @ptrCast(item))[0..SLOT]);
                slot.turn.store((head / SLOTS) * 2 + 1, .release);
                return true;
            }
        } else {
            const prev_head = head;
            head = queue.head.load(.acquire);
            if (head == prev_head) {
                return false;
            }
        }
    }
}

pub inline fn try_dequeue(queue: *Queue, item: *anyopaque) bool {
    var tail = queue.tail.load(.acquire);
    while (true) {
        const slot = &queue.slots[tail % SLOTS];
        if ((tail / SLOTS) * 2 + 1 == slot.turn.load(.acquire)) {
            if (queue.tail.cmpxchgStrong(tail, tail + 1, .acq_rel, .acquire)) |_| {
                // cmpxchg failed, update tail
                tail = queue.tail.load(.acquire);
            } else {
                // cmpxchg succeeded
                @memcpy(@as([*]u8, @ptrCast(item))[0..SLOT], &slot.data);
                slot.turn.store((tail / SLOTS) * 2 + 2, .release);
                return true;
            }
        } else {
            const prev_tail = tail;
            tail = queue.tail.load(.acquire);
            if (tail == prev_tail) {
                return false;
            }
        }
    }
}

// Example usage and test
pub fn main() !void {
    var queue = Queue{};
    
    // Test enqueue/dequeue
    var value1: c_int = 42;
    var value2: c_int = 0;
    
    enqueue(&queue, &value1);
    dequeue(&queue, &value2);
    
    std.debug.print("Enqueued: {}, Dequeued: {}\n", .{ value1, value2 });
    
    // Test try_enqueue/try_dequeue
    var value3: c_int = 100;
    var value4: c_int = 0;
    
    if (try_enqueue(&queue, &value3)) {
        std.debug.print("Successfully enqueued: {}\n", .{value3});
    }
    
    if (try_dequeue(&queue, &value4)) {
        std.debug.print("Successfully dequeued: {}\n", .{value4});
    }
}
