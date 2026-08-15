const r4os = @import("r4os");

const service_name = "R4SLSVC";
const service_timeout_ms: u64 = 1000;

const App = struct {
    sys: r4os.r4sys.Context,

    fn init(r4_app: *r4os.App) ?App {
        return .{ .sys = r4_app.system() };
    }
};

var status_response: [@sizeOf(r4os.abi.NetServiceR4slStatus)]u8 = .{0xA5} ** @sizeOf(r4os.abi.NetServiceR4slStatus);
var result_response: [@sizeOf(r4os.abi.NetServiceR4slResult)]u8 = .{0xA5} ** @sizeOf(r4os.abi.NetServiceR4slResult);

pub fn r4_app_main(r4_app: *r4os.App) i32 {
    var app = App.init(r4_app) orelse return r4os.abi.err_no_group;
    const args = trim(zSlice(app.sys.argsRaw()));
    if (equalsIgnoreCase(args, "/?") or equalsIgnoreCase(args, "HELP")) {
        app.sys.println("Usage: R4SLD [/SELFTEST]");
        return 0;
    }
    return runSelfTest(&app);
}

fn runSelfTest(app: *const App) i32 {
    app.sys.println("R4SLD selftest");
    if (!app.sys.hasFn("service_start")) return fail(app, "service-manager");
    if (!app.sys.hasFn("service_call")) return fail(app, "service-api");

    var handle: u32 = 0;
    if (!ensureRunningAndOpen(app, &handle)) return fail(app, "open");
    defer _ = app.sys.serviceClose(handle);

    const before = readStatus(app, handle) orelse return fail(app, "status");
    if (!validStatus(before)) return fail(app, "status-magic");
    app.sys.write("R4SLD status: requests=");
    app.sys.printU64(before.requests);
    app.sys.write(" self=");
    app.sys.printU64(before.self_tests);
    app.sys.write(" queues=");
    app.sys.printU64(before.inbox_count);
    app.sys.write("/");
    app.sys.printU64(before.outbox_count);
    app.sys.write("\r\n");

    const poll = callResult(app, handle, r4os.abi.net_service_op_r4sl_poll_result, "") orelse return fail(app, "poll");
    if (!validResult(poll, r4os.abi.net_service_r4sl_action_poll)) return fail(app, "poll-result");
    if (poll.result != r4os.abi.serial_link_result_ok) return fail(app, "poll-code");

    const selftest = callResult(app, handle, r4os.abi.net_service_op_r4sl_selftest_result, "") orelse return fail(app, "service-selftest");
    if (!validResult(selftest, r4os.abi.net_service_r4sl_action_selftest)) return fail(app, "selftest-result");
    if (selftest.result != r4os.abi.serial_link_result_ok) return fail(app, "selftest-code");

    const reset = callResult(app, handle, r4os.abi.net_service_op_r4sl_reset_result, "") orelse return fail(app, "reset");
    if (!validResult(reset, r4os.abi.net_service_r4sl_action_reset)) return fail(app, "reset-result");
    if (reset.result != r4os.abi.serial_link_result_ok) return fail(app, "reset-code");

    var header: r4os.abi.ServiceMessageHeader = .{};
    var small: [8]u8 = .{0} ** 8;
    const bad = app.sys.serviceCall(handle, 0xFFFF, "", &header, small[0..], app.sys.ticksFromMilliseconds(100));
    if (bad < 0 or header.status != r4os.abi.service_api_result_bad_op) return fail(app, "bad-op");

    const after = readStatus(app, handle) orelse return fail(app, "after-status");
    if (!validStatus(after)) return fail(app, "after-status-magic");
    if (after.self_tests <= before.self_tests) return fail(app, "self-counter");
    if (after.bad_ops <= before.bad_ops) return fail(app, "badop-counter");
    if (after.inbox_count != 0 or after.outbox_count != 0) return fail(app, "queue-cleanup");

    app.sys.println("R4SLD selftest: OK");
    return 0;
}

fn readStatus(app: *const App, handle: u32) ?r4os.abi.NetServiceR4slStatus {
    var header: r4os.abi.ServiceMessageHeader = .{};
    const got = app.sys.serviceCall(handle, r4os.abi.net_service_op_r4sl_status_result, "", &header, status_response[0..], app.sys.ticksFromMilliseconds(service_timeout_ms));
    if (got != @as(i32, @intCast(@sizeOf(r4os.abi.NetServiceR4slStatus))) or header.status != r4os.abi.service_api_result_ok) return null;
    var status: r4os.abi.NetServiceR4slStatus = .{};
    copyStruct(&status, status_response[0..]);
    return status;
}

fn callResult(app: *const App, handle: u32, op: u16, payload: []const u8) ?r4os.abi.NetServiceR4slResult {
    var header: r4os.abi.ServiceMessageHeader = .{};
    const got = app.sys.serviceCall(handle, op, payload, &header, result_response[0..], app.sys.ticksFromMilliseconds(service_timeout_ms));
    if (got != @as(i32, @intCast(@sizeOf(r4os.abi.NetServiceR4slResult))) or header.status != r4os.abi.service_api_result_ok) return null;
    var result: r4os.abi.NetServiceR4slResult = .{};
    copyStruct(&result, result_response[0..]);
    return result;
}

fn ensureRunningAndOpen(app: *const App, out_handle: *u32) bool {
    var info: r4os.abi.ServiceInfo = .{};
    const status = app.sys.serviceStatus(service_name, &info);
    if (status != r4os.abi.service_api_result_ok) return false;
    if (info.state != r4os.abi.service_state_running) {
        const start = app.sys.serviceStart(service_name, &info);
        if (start != r4os.abi.service_api_result_ok) return false;
    }

    var tick: u32 = 0;
    while (tick < 160) : (tick += 1) {
        const open_rc = app.sys.serviceOpen(service_name, &info);
        if (open_rc == r4os.abi.service_api_result_ok and info.handle != 0) {
            out_handle.* = info.handle;
            return true;
        }
        app.sys.sleepTicks(1);
    }
    return false;
}

fn validStatus(status: r4os.abi.NetServiceR4slStatus) bool {
    return status.magic == r4os.abi.net_service_r4sl_status_magic and
        status.version == r4os.abi.net_service_r4sl_status_version;
}

fn validResult(result: r4os.abi.NetServiceR4slResult, action: u16) bool {
    return result.magic == r4os.abi.net_service_r4sl_result_magic and
        result.version == r4os.abi.net_service_r4sl_result_version and
        result.action == action;
}

fn fail(app: *const App, label: []const u8) i32 {
    app.sys.write("R4SLD selftest FAILED: ");
    app.sys.println(label);
    return 1;
}

fn copyStruct(out: anytype, data: []const u8) void {
    const out_bytes: [*]u8 = @ptrCast(out);
    const size = @sizeOf(@TypeOf(out.*));
    const len = @min(size, data.len);
    var index: usize = 0;
    while (index < len) : (index += 1) out_bytes[index] = data[index];
}

fn zSlice(ptr: [*:0]const u8) []const u8 {
    var len: usize = 0;
    while (ptr[len] != 0) : (len += 1) {}
    return ptr[0..len];
}

fn trim(value: []const u8) []const u8 {
    var start: usize = 0;
    var end = value.len;
    while (start < end and isSpace(value[start])) : (start += 1) {}
    while (end > start and isSpace(value[end - 1])) : (end -= 1) {}
    return value[start..end];
}

fn isSpace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n';
}

fn equalsIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var index: usize = 0;
    while (index < a.len) : (index += 1) {
        if (asciiUpper(a[index]) != asciiUpper(b[index])) return false;
    }
    return true;
}

fn asciiUpper(ch: u8) u8 {
    if (ch >= 'a' and ch <= 'z') return ch - 32;
    return ch;
}
