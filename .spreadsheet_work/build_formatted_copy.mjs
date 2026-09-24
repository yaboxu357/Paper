import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const root = "C:/Code/CodexPlace/Paper";
const inputPath = `${root}/results/experiment_results.xlsx`;
const outputDir = `${root}/outputs/experiment-results-formatted`;
const outputPath = `${outputDir}/experiment_results_formatted.xlsx`;
const previewPath = `${root}/.spreadsheet_work/experiment_results_formatted_preview.png`;

const input = await FileBlob.load(inputPath);
const sourceBook = await SpreadsheetFile.importXlsx(input);
const sourceSheet = sourceBook.worksheets.getItem("Sheet1");
const sourceValues = sourceSheet.getRange("A1:Z47").values;

const modelNames = [
  "E-Armor", "EMAformer", "DeepBooTS", "SimpleTM", "FilterTS",
  "xPatch", "iTransformer", "TimeMixer", "PatchTST", "DLinear", "FEDformer",
];
const sourceMetricColumns = [2, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25];
const round3 = (value) => {
  if (value === null || value === undefined || value === "") return null;
  const number = Number(value);
  return Number.isFinite(number) ? Math.round((number + Number.EPSILON) * 1000) / 1000 : value;
};

const rows = [];
const header1 = ["Dataset", "Prediction Length"];
const header2 = [null, null];
for (const name of modelNames) {
  header1.push(name, null);
  header2.push("MSE", "MAE");
}
rows.push(header1, header2);

for (let r = 2; r < sourceValues.length; r += 1) {
  const sourceRow = sourceValues[r];
  const outRow = [sourceRow[0], sourceRow[1]];
  for (const columnIndex of sourceMetricColumns) outRow.push(round3(sourceRow[columnIndex]));
  rows.push(outRow);
}

const workbook = Workbook.create();
const sheet = workbook.worksheets.add("Sheet1");
sheet.getRange("A1:X47").values = rows;

sheet.mergeCells("A1:A2");
sheet.mergeCells("B1:B2");
for (let col = 2; col < 24; col += 2) {
  const left = String.fromCharCode(65 + col);
  const right = String.fromCharCode(65 + col + 1);
  sheet.mergeCells(`${left}1:${right}1`);
}

for (let start = 3; start <= 43; start += 5) sheet.mergeCells(`A${start}:A${start + 4}`);

sheet.showGridLines = false;
sheet.freezePanes.freezeRows(2);
sheet.freezePanes.freezeColumns(2);

const all = sheet.getRange("A1:X47");
all.format.font = { name: "Arial", size: 10, color: "#222222" };
all.format.verticalAlignment = "center";

const headers = sheet.getRange("A1:X2");
headers.format.fill = "#1F4E78";
headers.format.font = { name: "Arial", size: 10, bold: true, color: "#FFFFFF" };
headers.format.horizontalAlignment = "center";
headers.format.verticalAlignment = "center";
headers.format.borders = { preset: "all", style: "thin", color: "#FFFFFF" };
headers.format.rowHeight = 24;

sheet.getRange("A3:X47").format.horizontalAlignment = "center";
sheet.getRange("C3:X47").format.numberFormat = "0.000";
sheet.getRange("A3:B47").format.font = { name: "Arial", size: 10, color: "#333333" };
sheet.getRange("A3:A47").format.font = { name: "Arial", size: 10, bold: true, color: "#333333" };

for (let start = 3; start <= 43; start += 5) {
  const avgRow = start + 4;
  sheet.getRange(`A${avgRow}:X${avgRow}`).format.fill = "#E2F0D9";
  sheet.getRange(`B${avgRow}:X${avgRow}`).format.font = { name: "Arial", size: 10, bold: false, color: "#333333" };
  sheet.getRange(`B${avgRow}`).format.font = { name: "Arial", size: 10, bold: true, color: "#333333" };
  sheet.getRange(`A${avgRow}:X${avgRow}`).format.borders = {
    top: { style: "thin", color: "#A9D18E" },
    bottom: { style: "medium", color: "#70AD47" },
  };
}

const bestColor = "#222222";
const secondColor = "#0000FF";
for (let row = 3; row <= 47; row += 1) {
  const length = rows[row - 1][1];
  if (typeof length !== "number") continue;
  for (const parity of [0, 1]) {
    const columns = [];
    for (let col = 2 + parity; col < 24; col += 2) {
      const value = rows[row - 1][col];
      if (typeof value === "number" && Number.isFinite(value)) columns.push({ col, value });
    }
    const distinct = [...new Set(columns.map((entry) => entry.value))].sort((a, b) => a - b);
    const best = distinct[0];
    const second = distinct[1];
    for (const entry of columns) {
      const address = `${String.fromCharCode(65 + entry.col)}${row}`;
      if (entry.value === best) {
        sheet.getRange(address).format.font = { name: "Arial", size: 10, bold: true, color: bestColor };
      } else if (entry.value === second) {
        sheet.getRange(address).format.font = { name: "Arial", size: 10, bold: false, color: secondColor };
      }
    }
  }
}

sheet.getRange("A1:A47").format.columnWidth = 12;
sheet.getRange("B1:B47").format.columnWidth = 17;
sheet.getRange("C1:X47").format.columnWidth = 9;
sheet.getRange("A3:X47").format.rowHeight = 20;

workbook.recalculate();

const check = await workbook.inspect({
  kind: "table",
  range: "Sheet1!A1:X12",
  include: "values,formulas",
  tableMaxRows: 12,
  tableMaxCols: 24,
  maxChars: 12000,
});
console.log("CHECK");
console.log(check.ndjson);

const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!",
  options: { useRegex: true, maxResults: 300 },
  summary: "final formula error scan",
});
console.log("ERRORS");
console.log(errors.ndjson);

await fs.mkdir(outputDir, { recursive: true });
const preview = await workbook.render({ sheetName: "Sheet1", range: "A1:X47", scale: 1, format: "png" });
await fs.writeFile(previewPath, new Uint8Array(await preview.arrayBuffer()));
const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);
console.log(`OUTPUT ${outputPath}`);
console.log(`PREVIEW ${previewPath}`);
