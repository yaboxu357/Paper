import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile, Workbook } from "@oai/artifact-tool";

// Detailed experiment table: every model column of results/experiment_results.xlsx,
// 3-dp truncation (no rounding) for both per-horizon rows and AVG rows,
// best bold / second underlined, trailing "1 count" row. Plain table, no fills.
const root = "C:/Code/CodexPlace/Paper";
const inputPath = `${root}/results/experiment_results.xlsx`;
const outputDir = `${root}/outputs/detailed-results`;
const outputPath = `${outputDir}/experiment_results_detailed.xlsx`;
const previewPath = `${root}/.spreadsheet_work/detailed_results_v2_preview.png`;

const sourceBook = await SpreadsheetFile.importXlsx(await FileBlob.load(inputPath));
const source = sourceBook.worksheets.getItem("Sheet1").getRange("A1:Z47").values;

// column indices into results/experiment_results.xlsx
const models = [
  { name: "E-Armor", mse: 2, mae: 4 },
  { name: "EMAformer", mse: 6, mae: 7 },
  { name: "DeepBooTS", mse: 8, mae: 9 },
  { name: "SimpleTM", mse: 10, mae: 11 },
  { name: "FilterTS", mse: 12, mae: 13 },
  { name: "xPatch", mse: 14, mae: 15 },
  { name: "iTransformer", mse: 16, mae: 17 },
  { name: "TimeMixer", mse: 18, mae: 19 },
  { name: "PatchTST", mse: 20, mae: 21 },
  { name: "DLinear", mse: 22, mae: 23 },
  { name: "FEDformer", mse: 24, mae: 25 },
];
const datasets = ["ETTh1", "ETTm1", "ETTh2", "ETTm2", "ECL", "Weather", "Solar", "Exchange", "Traffic"];
const horizons = [96, 192, 336, 720];
const isNumber = (v) => v !== null && v !== undefined && v !== "" && Number.isFinite(Number(v));
const trunc3 = (v) => (isNumber(v) ? Math.trunc((Number(v) + Number.EPSILON) * 1000) / 1000 : null);

const rows = [];
const h1 = ["Dataset", "Prediction Length"];
const h2 = [null, null];
for (const model of models) {
  h1.push(model.name, null);
  h2.push("MSE", "MAE");
}
rows.push(h1, h2);

for (let d = 0; d < datasets.length; d += 1) {
  const sourceStart = 2 + d * 5;
  for (let h = 0; h < horizons.length; h += 1) {
    const sourceRow = source[sourceStart + h];
    const out = [datasets[d], horizons[h]];
    for (const model of models) out.push(trunc3(sourceRow[model.mse]), trunc3(sourceRow[model.mae]));
    rows.push(out);
  }
  const avg = [datasets[d], "AVG"];
  for (const model of models) {
    const mseValues = horizons.map((_, h) => source[sourceStart + h][model.mse]).filter(isNumber).map(Number);
    const maeValues = horizons.map((_, h) => source[sourceStart + h][model.mae]).filter(isNumber).map(Number);
    avg.push(mseValues.length === horizons.length ? trunc3(mseValues.reduce((a, b) => a + b, 0) / mseValues.length) : null);
    avg.push(maeValues.length === horizons.length ? trunc3(maeValues.reduce((a, b) => a + b, 0) / maeValues.length) : null);
  }
  rows.push(avg);
}

// best / second rank per metric column across every row, including AVG rows
const firstCounts = Array(models.length).fill(0);
const rankings = new Map();
for (let rowIndex = 2; rowIndex < rows.length; rowIndex += 1) {
  for (const metricOffset of [0, 1]) {
    const entries = [];
    for (let modelIndex = 0; modelIndex < models.length; modelIndex += 1) {
      const colIndex = 2 + modelIndex * 2 + metricOffset;
      const value = rows[rowIndex][colIndex];
      if (isNumber(value)) entries.push({ modelIndex, colIndex, value: Number(value) });
    }
    const distinct = [...new Set(entries.map((e) => e.value))].sort((a, b) => a - b);
    const best = distinct[0];
    const second = distinct[1];
    for (const entry of entries) {
      const key = `${rowIndex + 1}:${entry.colIndex + 1}`;
      if (entry.value === best) {
        rankings.set(key, "best");
        firstCounts[entry.modelIndex] += 1;
      } else if (entry.value === second) {
        rankings.set(key, "second");
      }
    }
  }
}

const countRow = ["1 count", null];
for (const count of firstCounts) countRow.push(count, null);
rows.push(countRow);

const LAST_COL = String.fromCharCode(65 + 2 + models.length * 2 - 1); // X for 11 models
const DATA_LAST_ROW = 2 + datasets.length * 5;                        // 47
const COUNT_ROW = DATA_LAST_ROW + 1;                                  // 48

const workbook = Workbook.create();
const sheet = workbook.worksheets.add("Sheet1");
sheet.getRange(`A1:${LAST_COL}${COUNT_ROW}`).values = rows;

sheet.mergeCells("A1:A2");
sheet.mergeCells("B1:B2");
for (let col = 2; col < 2 + models.length * 2; col += 2) {
  const left = String.fromCharCode(65 + col);
  const right = String.fromCharCode(65 + col + 1);
  sheet.mergeCells(`${left}1:${right}1`);
}
for (let start = 3; start <= DATA_LAST_ROW - 4; start += 5) sheet.mergeCells(`A${start}:A${start + 4}`);
sheet.mergeCells(`A${COUNT_ROW}:B${COUNT_ROW}`);
for (let col = 2; col < 2 + models.length * 2; col += 2) {
  const left = String.fromCharCode(65 + col);
  const right = String.fromCharCode(65 + col + 1);
  sheet.mergeCells(`${left}${COUNT_ROW}:${right}${COUNT_ROW}`);
}

sheet.showGridLines = false;
sheet.freezePanes.freezeRows(2);
sheet.freezePanes.freezeColumns(2);

const all = sheet.getRange(`A1:${LAST_COL}${COUNT_ROW}`);
all.format.font = { name: "Times New Roman", size: 10, color: "#000000" };
all.format.horizontalAlignment = "center";
all.format.verticalAlignment = "center";
all.format.borders = { preset: "all", style: "thin", color: "#000000" };
sheet.getRange(`A1:${LAST_COL}2`).format.font = { name: "Times New Roman", size: 10, bold: true, color: "#000000" };
sheet.getRange(`A3:A${DATA_LAST_ROW}`).format.font = { name: "Times New Roman", size: 10, bold: true, color: "#000000" };
sheet.getRange(`B3:B${DATA_LAST_ROW}`).format.font = { name: "Times New Roman", size: 10, color: "#000000" };
sheet.getRange(`C3:${LAST_COL}${DATA_LAST_ROW}`).format.numberFormat = "0.000";
sheet.getRange(`A${COUNT_ROW}:${LAST_COL}${COUNT_ROW}`).format.font = { name: "Times New Roman", size: 10, bold: true, color: "#000000" };
sheet.getRange(`A${COUNT_ROW}:${LAST_COL}${COUNT_ROW}`).format.borders = {
  top: { style: "medium", color: "#000000" },
  bottom: { style: "medium", color: "#000000" },
  left: { style: "thin", color: "#000000" },
  right: { style: "thin", color: "#000000" },
};

for (const [key, rank] of rankings.entries()) {
  const [row, col] = key.split(":").map(Number);
  const address = `${String.fromCharCode(64 + col)}${row}`;
  // NOTE: underline must be part of the font object assignment; setting
  // `format.font.underline` on its own is silently dropped on export.
  if (rank === "best") {
    sheet.getRange(address).format.font = { name: "Times New Roman", size: 10, bold: true, color: "#000000" };
  } else {
    sheet.getRange(address).format.font = { name: "Times New Roman", size: 10, color: "#000000", underline: "single" };
  }
}

sheet.getRange(`A1:A${COUNT_ROW}`).format.columnWidth = 12;
sheet.getRange(`B1:B${COUNT_ROW}`).format.columnWidth = 17;
sheet.getRange(`C1:${LAST_COL}${COUNT_ROW}`).format.columnWidth = 9;
sheet.getRange(`A1:${LAST_COL}${COUNT_ROW}`).format.rowHeight = 20;
sheet.getRange(`A1:${LAST_COL}2`).format.rowHeight = 24;

workbook.recalculate();
const check = await workbook.inspect({
  kind: "table",
  range: `Sheet1!A1:${LAST_COL}${COUNT_ROW}`,
  include: "values,formulas",
  tableMaxRows: 50,
  tableMaxCols: 24,
  maxChars: 30000,
});
console.log("CHECK\n" + check.ndjson);
const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!",
  options: { useRegex: true, maxResults: 300 },
  summary: "formula error scan",
});
console.log("ERRORS\n" + errors.ndjson);
console.log("COUNTS " + JSON.stringify(Object.fromEntries(models.map((m, i) => [m.name, firstCounts[i]]))));

// The @oai/artifact-tool font model drops underline on export, so the
// second-best underline is injected afterwards by inject_underline.py
// using this address map.
const colName = (n) => { let out = ""; while (n > 0) { const r = (n - 1) % 26; out = String.fromCharCode(65 + r) + out; n = Math.floor((n - 1) / 26); } return out; };
const rankAddrs = { best: [], second: [] };
for (const [key, rank] of rankings.entries()) {
  const [row, col] = key.split(":").map(Number);
  rankAddrs[rank].push(`${colName(col)}${row}`);
}
await fs.writeFile(
  `${root}/.spreadsheet_work/detailed_rankings.json`,
  JSON.stringify({ sheet: "Sheet1", lastCol: LAST_COL, countRow: COUNT_ROW, ...rankAddrs }, null, 1),
);

await fs.mkdir(outputDir, { recursive: true });
const preview = await workbook.render({ sheetName: "Sheet1", range: `A1:${LAST_COL}${COUNT_ROW}`, scale: 1, format: "png" });
await fs.writeFile(previewPath, new Uint8Array(await preview.arrayBuffer()));
await (await SpreadsheetFile.exportXlsx(workbook)).save(outputPath);
console.log(`OUTPUT ${outputPath}`);
