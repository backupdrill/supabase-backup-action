// Reads the JSON line `backupdrill backup` printed and writes the step outputs.
// The dump key looks like <prefix>/<project>/<snapshot>/dump.pgcustom, and the
// snapshot folder name is what `backupdrill drill --snapshot` expects.
import { appendFileSync, readFileSync } from "node:fs";

const lines = readFileSync(process.argv[2], "utf8").split("\n").filter((line) => line.trim());
const { ok, manifest } = JSON.parse(lines.at(-1) ?? "{}");
const dumpKey = manifest?.dump?.key;
if (ok !== true || typeof dumpKey !== "string") {
  console.error("::error::The backup finished but its result has no dump key.");
  process.exit(1);
}
const snapshot = dumpKey.split("/").at(-2);
// A line break in a value would start a new output, so refuse it instead of writing it.
if (!snapshot || /[\r\n]/.test(dumpKey)) {
  console.error("::error::The dump key in the backup result is not usable as an output.");
  process.exit(1);
}

const outputs = `snapshot=${snapshot}\ndump-key=${dumpKey}\n`;
if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, outputs);
else process.stdout.write(outputs);
console.error(`Snapshot ${snapshot}, written by backupdrill ${manifest.toolVersion}.`);
