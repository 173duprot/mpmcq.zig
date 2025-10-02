# MPMCQ

A bounded multi-producer multi-consumer concurrent queue for Zig 0.15.1.

This is a port of [mcmpq.h](https://github.com/173duprot/mcmpq.h), which draws heavily from [Erik Rigtorp's MPMCQueue](https://github.com/rigtorp/MPMCQueue). It provides a lock-free, wait-free queue implementation optimized for high-throughput concurrent scenarios.

## Installation

Copy `mpmcq.zig` into your project, or add it as a dependency using Zig's package manager:

```zig
// build.zig.zon
.dependencies = .{
    .mpmcq = .{
        .url = "https://github.com/173duprot/mpmcq.zig/archive/refs/tags/v0.1.0.tar.gz",
        .hash = "1220KY1yysK0AACReK4QgM_NLKt7bAoZQKvjo_YYPIg0_44W",
    },
},

// build.zig
const mpmcq = b.dependency("mpmcq", .{});
exe.root_module.addImport("mpmcq", mpmcq.module("mpmcq"));
```

## API

```zig
const MPMCQ = @import("mpmcq").MPMCQ;

// Create a queue for type T with N slots
var queue = MPMCQ(T, N){};

// Blocking operations - spin until successful
queue.enqueue(&item);    // Add item to queue
queue.dequeue(&item);    // Remove item from queue

// Non-blocking operations - return immediately
const success = queue.try_enqueue(&item);  // Returns true on success
const success = queue.try_dequeue(&item);  // Returns true on success
```

## Usage

```zig
const std = @import("std");
const MPMCQ = @import("mpmcq").MPMCQ;

var queue = MPMCQ(u64, 1024){};

// Producer thread
fn producer() void {
    var i: u64 = 0;
    while (i < 1000) : (i += 1) {
        queue.enqueue(&i);
    }
}

// Consumer thread
fn consumer() void {
    var item: u64 = undefined;
    while (true) {
        queue.dequeue(&item);
        std.debug.print("Got: {}\n", .{item});
    }
}
```

The queue capacity must be a power of two for optimal performance. Blocking operations (`enqueue`/`dequeue`) spin until space or data is available. Non-blocking operations (`try_enqueue`/`try_dequeue`) return immediately if the queue is full or empty.
