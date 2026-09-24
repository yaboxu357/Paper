import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile, Workbook } from "@oai/artifact-tool";

// Detailed experiment table organized by the roster agreed in
// outputs/baseline-selection-1-3-5/baseline_selection_recommendations.xlsx
// (1 paper from 2026 + 3 from 2025 + 5 classic, E-Armor first).
//
// Sheet "主表"   : E-Armor + the nine recommended baselines.
// Sheet "附录"   : EMAformer / xPatch / DLinear, which the roster moves out of
//                  the main table but asks to keep available.
//
// Values are truncated (never rounded) to three decimals, per-horizon and AVG
// alike. Best per metric is bold, second best underlined, and a trailing
// "1 count" row totals first places including the AVG rows.
const root = "C:/Code/CodexPlace/Paper";
const inputPath = `${root}/results/experiment_results.xlsx`;
const rosterAvgPath = `${root}/.spreadsheet_work/roster_avg.json`;
const outputDir = `${root}/outputs/detailed-results`;
const outputPath = `${outputDir}/experiment_results_detailed.xlsx`;
const previewPath = `${root}/.spreadsheet_work/detailed_results_v3_preview.png`;

const sourceBook = await SpreadsheetFile.importXlsx(await FileBlob.load(inputPath));
const source = sourceBook.worksheets.getItem("Sheet1").getRange("A1:Z47").values;
const rosterAvg = JSON.parse(await fs.readFile(rosterAvgPath, "utf8"));

// column indices into results/experiment_results.xlsx
const LOCAL = {
  "E-Armor": [2, 4],
  EMAformer: [6, 7],
  DeepBooTS: [8, 9],
  SimpleTM: [10, 11],
  FilterTS: [12, 13],
  xPatch: [14, 15],
  iTransformer: [16, 17],
  TimeMixer: [18, 19],
  PatchTST: [20, 21],
  DLinear: [22, 23],
  FEDformer: [24, 25],
};
// roster order taken from the 「九数据集均值」 sheet of the recommendations file
const MAIN = ["E-Armor", "DeepBooTS", "SimpleTM", "FilterTS", "FACTS", "iTransformer", "TimeMixer", "PatchTST", "TimesNet", "FEDformer"];
const APPENDIX = ["EMAformer", "xPatch", "DLinear"];
const PAPER_ONLY = new Set(["FACTS", "TimesNet"]);   // dataset averages only, from the papers

const datasets = ["ETTh1", "ETTm1", "ETTh2", "ETTm2", "ECL", "Weather", "Solar", "Exchange", "Traffic"];
const horizons = [96, 192, 336, 720];
const isNumber = (v) => v !== null && v !== undefined && v !== "" && Number.isFinite(Number(v));
const trunc3 = (v) => (isNumber(v) ? Math.trunc((Number(v) + Number.EPSILON) * 1000) / 1000 : null);

function buildRows(models) {
  const rows = [];
  const h1 = ["Dataset", "Prediction Length"];
  const h2 = [null, null];
  for (const model of models) {
    h1.push(model, null);
    h2.push("MSE", "MAE");
  }
  rows.push(h1, h2);
  for (let d = 0; d < datasets.length; d += 1) {
    const sourceStart = 2 + d * 5;
    for (let h = 0; h < horizons.length; h += 1) {
      const out = [datasets[d], horizons[h]];
      for (const model of models) {
        if (PAPER_ONLY.has(model)) { out.push(null, null); continue; }
        const [mseCol, maeCol] = LOCAL[model];
        out.push(trunc3(source[sourceStart + h][mseCol]), trunc3(source[sourceStart + h][maeCol]));
      }
      rows.push(out);
    }
    const avg = [datasets[d], "AVG"];
    for (const model of models) {
      if (PAPER_ONLY.has(model)) {
        const pair = (rosterAvg[datasets[d]] || {})[model];
        avg.push(pair ? pair[0] : null, pair ? pair[1] : null);
        continue;
      }
      const [mseCol, maeCol] = LOCAL[model];
      for (const col of [mseCol, maeCol]) {
        const vals = horizons.map((_, h) => source[sourceStart + h][col]).filter(isNumber).map(Number);
        avg.push(vals.length === horizons.length ? trunc3(vals.reduce((a, b) => a + b, 0) / vals.length) : null);
      }
    }
    rows.push(avg);
  }
  return rows;
}

const colName = (n) => { let out = ""; while (n > 0) { const r = (n - 1) % 26; out = String.fromCharCode(65 + r) + out; n = Math.floor((n - 1) / 26); } return out; };

function rankRows(rows, models) {
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
        if (entry.value === best) { rankings.set(key, "best"); firstCounts[entry.modelIndex] += 1; }
        else if (entry.value === second) rankings.set(key, "second");
      }
    }
  }
  const countRow = ["1 count", null];
  for (const count of firstCounts) countRow.push(count, null);
  rows.push(countRow);
  return { firstCounts, rankings };
}

const workbook = Workbook.create();
const rankReport = {};

for (const [sheetName, models] of [["主表", MAIN], ["附录", APPENDIX]]) {
  const rows = buildRows(models);
  const { firstCounts, rankings } = rankRows(rows, models);
  rankReport[sheetName] = Object.fromEntries(models.map((m, i) => [m, firstCounts[i]]));

  const sheet = workbook.worksheets.add(sheetName);
  const lastCol = colName(2 + models.length * 2);
  const dataLastRow = 2 + datasets.length * 5;      // 47
  const countRowNo = dataLastRow + 1;               // 48
  sheet.getRange(`A1:${lastCol}${countRowNo}`).values = rows;

  sheet.mergeCells("A1:A2");
  sheet.mergeCells("B1:B2");
  for (let col = 2; col < 2 + models.length * 2; col += 2) {
    sheet.mergeCells(`${colName(col + 1)}1:${colName(col + 2)}1`);
  }
  for (let start = 3; start <= dataLastRow - 4; start += 5) sheet.mergeCells(`A${start}:A${start + 4}`);
  sheet.mergeCells(`A${countRowNo}:B${countRowNo}`);
  for (let col = 2; col < 2 + models.length * 2; col += 2) {
    sheet.mergeCells(`${colName(col + 1)}${countRowNo}:${colName(col + 2)}${countRowNo}`);
  }

  sheet.showGridLines = false;
  sheet.freezePanes.freezeRows(2);
  sheet.freezePanes.freezeColumns(2);

  const all = sheet.getRange(`A1:${lastCol}${countRowNo}`);
  all.format.font = { name: "Times New Roman", size: 10, color: "#000000" };
  all.format.horizontalAlignment = "center";
  all.format.verticalAlignment = "center";
  all.format.borders = { preset: "all", style: "thin", color: "#000000" };
  sheet.getRange(`A1:${lastCol}2`).format.font = { name: "Times New Roman", size: 10, bold: true, color: "#000000" };
  sheet.getRange(`A3:A${dataLastRow}`).format.font = { name: "Times New Roman", size: 10, bold: true, color: "#000000" };
  sheet.getRange(`B3:B${dataLastRow}`).format.font = { name: "Times New Roman", size: 10, color: "#000000" };
  sheet.getRange(`C3:${lastCol}${dataLastRow}`).format.numberFormat = "0.000";
  sheet.getRange(`A${countRowNo}:${lastCol}${countRowNo}`).format.font = { name: "Times New Roman", size: 10, bold: true, color: "#000000" };
  sheet.getRange(`A${countRowNo}:${lastCol}${countRowNo}`).format.borders = {
    top: { style: "medium", color: "#000000" },
    bottom: { style: "medium", color: "#000000" },
    left: { style: "thin", color: "#000000" },
    right: { style: "thin", color: "#000000" },
  };

  // NOTE: underline must be assigned inside the font object; setting
  // `format.font.underline` on its own is dropped on export, so it is injected
  // afterwards by inject_underline.py using the address map written below.
  const rankAddrs = { best: [], second: [] };
  for (const [key, rank] of rankings.entries()) {
    const [row, col] = key.split(":").map(Number);
    const address = `${colName(col)}${row}`;
    rankAddrs[rank].push(address);
    if (rank === "best") {
      sheet.getRange(address).format.font = { name: "Times New Roman", size: 10, bold: true, color: "#000000" };
    }
  }
  rankReport[`${sheetName}:addresses`] = rankAddrs;

  sheet.getRange(`A1:A${countRowNo}`).format.columnWidth = 12;
  sheet.getRange(`B1:B${countRowNo}`).format.columnWidth = 17;
  sheet.getRange(`C1:${lastCol}${countRowNo}`).format.columnWidth = 9;
  sheet.getRange(`A1:${lastCol}${countRowNo}`).format.rowHeight = 20;
  sheet.getRange(`A1:${lastCol}2`).format.rowHeight = 24;

  // provenance note, two rows below the table (not part of it)
  if (sheetName === "主表") {
    sheet.getRange(`A${countRowNo + 2}`).values = [[
      "空白=来源未报告：FACTS/TimesNet 仅有论文报告的数据集平均，无本地逐预测长度结果；DeepBooTS 缺 Exchange。"
      + " E-Armor 与其余基线为本地结果，AVG 由 96/192/336/720 全精度值取均值后截断。",
    ]];
    sheet.mergeCells(`A${countRowNo + 2}:${lastCol}${countRowNo + 2}`);
    sheet.getRange(`A${countRowNo + 2}`).format.font = { name: "Times New Roman", size: 10, color: "#000000" };
    sheet.getRange(`A${countRowNo + 2}`).format.horizontalAlignment = "left";
  }
}

workbook.recalculate();
for (const name of ["主表", "附录"]) {
  const errors = await workbook.inspect({
    kind: "match",
    searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!",
    options: { useRegex: true, maxResults: 300 },
    summary: `${name} formula error scan`,
  });
  console.log(`ERRORS ${name}: ${errors.ndjson.trim()}`);
}
console.log("COUNTS " + JSON.stringify(rankReport));

await fs.writeFile(`${root}/.spreadsheet_work/detailed_rankings.json`, JSON.stringify(rankReport, null, 1));
await fs.mkdir(outputDir, { recursive: true });
const preview = await workbook.render({ sheetName: "主表", range: "A1:V48", scale: 1, format: "png" });
await fs.writeFile(previewPath, new Uint8Array(await preview.arrayBuffer()));
await (await SpreadsheetFile.exportXlsx(workbook)).save(outputPath);
console.log(`OUTPUT ${outputPath}`);
