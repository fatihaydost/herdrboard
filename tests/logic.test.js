// Unit tests for package/contents/ui/logic.js. Run: node tests/logic.test.js
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const { execFileSync } = require("child_process");

const src = fs.readFileSync(path.join(__dirname, "../package/contents/ui/logic.js"), "utf8")
    .replace(/^\.pragma library\s*$/m, "");
const L = {};
vm.runInNewContext(src + "\nObject.assign(out, {shellQuote, validName, validPane, validMachine, actionCommand, rowKey, agentKey, attentionRank, agentWants, badgeState, agentNote, sessionLabel, machineName, subtitleFor, cleanTitle, unreachableText, unreachableCount, navRows, bestRow, navKey, followCursor, attention, sharedWorkspace, agentDetail, sessionHint, sessionMeta, badgeText, herdEmpty});", { out: L });

let n = 0;
function test(name, fn) {
    fn();
    n += 1;
    console.log("ok", n, "-", name);
}

const bash = (script) => execFileSync("bash", ["-c", script], { encoding: "utf8" });

test("shellQuote survives bash for nasty strings", () => {
    for (const s of ["plain", "it's", "a b\tc", "$(touch /tmp/pwned)", "`id`", "'; rm -rf / #", "çğış → ✓", "new\nline", ""])
        assert.strictEqual(bash("printf %s " + L.shellQuote(s)), s);
});

test("argument fences", () => {
    assert.ok(L.validName("default") && L.validName("my-proj.2") && L.validName("3"));
    for (const bad of ["", "-rf", ".hidden", "a b", "a/b", "x".repeat(65), "$(id)", "a;b"])
        assert.ok(!L.validName(bad), bad);
    assert.ok(L.validPane("w1:p2") && L.validPane("w_a-1:p-2"));
    for (const bad of ["w1", "w1:p2:x", ":p1", "w1:", "w 1:p1", "-w:p"])
        assert.ok(L.validPane(bad) === (bad === "-w:p"), bad);
    assert.ok(!L.validMachine("-x") && L.validMachine("m1"));
});

test("actionCommand quotes everything and refuses bad shapes", () => {
    const s = { name: "proj", remote: false };
    assert.strictEqual(L.actionCommand("/p a/x", "open", s), "bash '/p a/x' 'open' 'proj'");
    assert.strictEqual(L.actionCommand("/x", "focus", s, "w1:p2"), "bash '/x' 'focus' 'proj' 'w1:p2'");
    assert.strictEqual(L.actionCommand("/x", "open", { name: "default", remote: true, machineId: "m1" }), "bash '/x' 'open' 'default' 'm1'");
    assert.strictEqual(L.actionCommand("/x", "open", { name: "a;b" }), "");
    assert.strictEqual(L.actionCommand("/x", "open", { name: "ok", remote: true, machineId: "-bad" }), "");
    assert.strictEqual(L.actionCommand("/x", "open", null), "");
});

test("states: waiting beats finished beats busy", () => {
    assert.ok(L.attentionRank("blocked") < L.attentionRank("done"));
    assert.ok(L.attentionRank("done") < L.attentionRank("working"));
    assert.ok(L.attentionRank("working") < L.attentionRank("idle"));
    assert.ok(L.attentionRank("idle") < L.attentionRank("weird"));
});

test("badge: none when idle or nothing running", () => {
    assert.strictEqual(L.badgeState({ running: 0, blocked: 1 }), "");
    assert.strictEqual(L.badgeState({ running: 2 }), "");
    assert.strictEqual(L.badgeState({ running: 2, working: 1 }), "working");
    assert.strictEqual(L.badgeState({ running: 2, working: 1, done: 1 }), "done");
    assert.strictEqual(L.badgeState({ running: 2, working: 1, done: 1, blocked: 1 }), "blocked");
});

test("labels", () => {
    assert.strictEqual(L.agentNote("idle"), "ready");
    assert.strictEqual(L.agentNote("blocked"), "needs you");
    assert.strictEqual(L.sessionLabel({ name: "default", isDefault: true }), "Shared session");
    assert.strictEqual(L.sessionLabel({ name: "default", isDefault: true, remote: true, machineLabel: "box" }), "box");
    // Numbered sessions are just names here: no workspace mapping.
    assert.strictEqual(L.sessionLabel({ name: "3" }), "3");
    assert.strictEqual(L.machineName({ name: "x", remote: true, machineLabel: "box" }), "box");
    assert.strictEqual(L.machineName({ name: "x", remote: false }), "");
    assert.strictEqual(L.subtitleFor({ running: false, projects: [] }), "nothing saved");
    assert.strictEqual(L.subtitleFor({ running: false, projects: ["a", "b"] }), "a  ·  b");
    assert.strictEqual(L.subtitleFor({ running: true, projects: [], agentList: [] }), "no workspaces yet");
    assert.strictEqual(L.subtitleFor({ running: true, projects: ["a"], agentList: [{}] }), "");
    assert.strictEqual(L.cleanTitle("⠋ Building the thing"), "Building the thing");
    assert.strictEqual(L.cleanTitle("✳✳"), "✳✳");
    assert.strictEqual(L.unreachableText([{ ok: true }]), "");
    assert.strictEqual(L.unreachableText([{ ok: false, label: "gpu", error: "unreachable" }, { ok: false, id: "m3", error: "Host key" }]), "unreachable: gpu, m3 (Host key)");
    assert.strictEqual(L.unreachableCount([{ ok: true }, { ok: false }, {}]), 2);
    assert.strictEqual(L.unreachableCount(undefined), 0);
});

test("navRows and bestRow", () => {
    const sessions = [
        { name: "a", agentList: [{ status: "idle" }, { status: "working" }] },
        { name: "b", agentList: [] },
        { name: "c", agentList: [{ status: "done" }] },
    ];
    const rows = L.navRows(sessions);
    assert.deepStrictEqual(JSON.parse(JSON.stringify(rows)), [
        { sessionIndex: 0, agentIndex: 0 }, { sessionIndex: 0, agentIndex: 1 },
        { sessionIndex: 1, agentIndex: -1 }, { sessionIndex: 2, agentIndex: 0 }]);
    assert.strictEqual(L.bestRow(sessions, rows), 3);
    assert.strictEqual(L.bestRow([{ agentList: [] }], L.navRows([{ agentList: [] }])), 0);
    assert.strictEqual(L.bestRow([], []), -1);
});

test("followCursor keeps the cursor on the same row across polls", () => {
    const a = { name: "a", agentList: [{ pane: "w1:p1" }, { pane: "w1:p2" }] };
    const b = { name: "b", agentList: [] };
    const c = { name: "c", agentList: [{ pane: "w1:p1" }] };
    const before = [a, b, c];
    const keyB = L.navKey(before, L.navRows(before)[2]);
    assert.strictEqual(keyB, L.rowKey(b));
    // A new session drawn above: the cursor moves down with "b", not onto "new".
    const inserted = [{ name: "new", agentList: [{ pane: "w1:p1" }] }, a, b, c];
    assert.strictEqual(L.followCursor(inserted, keyB, 2), 3);
    // An agent row follows its pane, and same pane id in another session is not it.
    const keyC = L.navKey(before, L.navRows(before)[3]);
    assert.strictEqual(L.followCursor(inserted, keyC, 3), 4);
    // The agent left, its session stayed: the session's first row.
    const keyA2 = L.navKey(before, L.navRows(before)[1]);
    assert.strictEqual(L.followCursor([{ name: "a", agentList: [{ pane: "w1:p1" }] }, b, c], keyA2, 1), 0);
    // The session went: same place, clamped.
    assert.strictEqual(L.followCursor([a], keyB, 2), 1);
    assert.strictEqual(L.followCursor([], keyB, 2), -1);
    assert.strictEqual(L.followCursor(before, "", -1), -1);
    // Remote "default" and local "default" are different rows.
    const local = { name: "default", agentList: [] }, remote = { name: "default", machineId: "m1", agentList: [] };
    assert.strictEqual(L.followCursor([remote, local], L.rowKey(local), 0), 1);
});

test("attention: only what started asking since the last poll", () => {
    const s = (status, seq) => [{ name: "a", agentList: [{ pane: "w1:p1", status: "blocked", seq: 1 }, { pane: "w1:p2", status: status, seq: seq }] }];
    const first = L.attention(s("idle", 0), {});
    assert.strictEqual(first.fresh, L.agentKey({ name: "a" }, "w1:p1"));
    const second = L.attention(s("done", 7), first.wanting);
    assert.strictEqual(second.fresh, L.agentKey({ name: "a" }, "w1:p2"));
    const third = L.attention(s("done", 7), second.wanting);
    assert.strictEqual(third.fresh, "");
    assert.notStrictEqual(L.rowKey({ name: "default", machineId: "m1" }), L.rowKey({ name: "default" }));
});

test("attention: needs-you beats done across servers whatever the seq", () => {
    const local = { name: "a", agentList: [{ pane: "w1:p1", status: "blocked", seq: 3 }] };
    const remote = { name: "b", machineId: "m1", agentList: [{ pane: "w1:p1", status: "done", seq: 40 }] };
    assert.strictEqual(L.attention([local, remote], {}).fresh, L.agentKey(local, "w1:p1"));
    assert.strictEqual(L.attention([remote, local], {}).fresh, L.agentKey(local, "w1:p1"));
    // Within one state the newer seq still wins.
    const done2 = { name: "c", agentList: [{ pane: "w1:p1", status: "done", seq: 2 }, { pane: "w1:p2", status: "done", seq: 5 }] };
    assert.strictEqual(L.attention([done2], {}).fresh, L.agentKey(done2, "w1:p2"));
});

test("redesign helpers", () => {
    const s = { name: "default", isDefault: true, running: true, agentList: [{ workspace: "checkout-service", kind: "claude", tab: "" }, { workspace: "checkout-service", kind: "claude", tab: "3" }] };
    assert.strictEqual(L.sharedWorkspace(s), "checkout-service");
    assert.strictEqual(L.sessionHint(s), "default · checkout-service");
    assert.strictEqual(L.agentDetail(s.agentList[1], true), "claude · 3");
    assert.strictEqual(L.agentDetail(s.agentList[1], false), "claude · checkout-service · 3");
    assert.strictEqual(L.agentDetail({ workspace: "api" }, false), "api");
    assert.strictEqual(L.sharedWorkspace({ agentList: [{ workspace: "a" }, { workspace: "b" }] }), "");
    assert.strictEqual(L.sessionHint({ name: "x", agentList: [] }), "");
    assert.strictEqual(L.sessionMeta({ running: false }), "stopped");
    assert.strictEqual(L.sessionMeta({ running: true, agentList: [] }), "no agents");
    assert.strictEqual(L.sessionMeta({ running: true, agentList: [], error: "x" }), "");
    assert.strictEqual(L.badgeText({ running: 1, blocked: 3, done: 1 }), "3");
    assert.strictEqual(L.badgeText({ running: 1, done: 2 }), "");
    assert.ok(L.herdEmpty([{ name: "default", isDefault: true, running: false }]));
    assert.ok(!L.herdEmpty([{ name: "default", isDefault: true, running: true }]));
    assert.ok(!L.herdEmpty([{ name: "old", running: false }]));
});

console.log("all", n, "tests passed");
