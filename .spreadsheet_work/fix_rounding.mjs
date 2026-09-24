import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const src = "C:/code/codexplace/paper/results/experiment_results.xlsx";
const tmp = "C:/code/codexplace/paper/.spreadsheet_work/roundtrip/experiment_results_rounded.xlsx";

const wb = await SpreadsheetFile.importXlsx(await FileBlob.load(src));
const s = wb.worksheets.getItem("Sheet1");
const formulas = s.getRange("A1:Z47").formulas;

const targets = [];
for (let r = 0; r < formulas.length; r++) {
  for (let c = 0; c < formulas[r].length; c++) {
    const fo = formulas[r][c];
    if (fo && /^=TRUNC\([A-Z]+\d+,3\)$/.test(String(fo))) targets.push({ r, c, fo: String(fo) });
  }
}
console.log("TRUNC cells found:", targets.length);
const changed = [];
for (const { r, c, fo } of targets) {
  const replaced = fo.replace(/^=TRUNC\(([A-Z]+\d+),3\)$/, "=ROUND($1,3)");
  if (replaced === fo) throw new Error("no replacement for " + fo);
  const COL = (i) => { let t = ""; i++; while (i) { const m = (i - 1) % 26; t = String.fromCharCode(65 + m) + t; i = (i - m - 1) / 26; } return t; };
  const addr = `${COL(c)}${r + 1}`;
  s.getRange(addr).formulas = [[replaced]];
  changed.push([addr, fo, replaced]);
}
console.log("rewritten:", changed.length, "example:", JSON.stringify(changed.slice(0, 3)));
const uniq = [...new Set(changed.map((x) => x[2].replace(/\d+/g, "N")))];
console.log("distinct new formulas:", JSON.stringify(uniq));

wb.recalculate();
await (await SpreadsheetFile.exportXlsx(wb)).save(tmp);
console.log("SAVED", tmp);
