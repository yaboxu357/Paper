import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const root = "C:/Code/CodexPlace/Paper";
const inputPath = `${root}/results/experiment_results.xlsx`;
const outputDir = `${root}/outputs/baseline-selection-1-3-5`;
const outputPath = `${outputDir}/baseline_selection_recommendations.xlsx`;
const previewDir = `${root}/.spreadsheet_work/baseline_selection_previews`;

const sourceBook = await SpreadsheetFile.importXlsx(await FileBlob.load(inputPath));
const source = sourceBook.worksheets.getItem("Sheet1").getRange("A1:Z47").values;
const detailRows = source.slice(2).filter((row) => typeof row[1] === "number");
const avgRows = source.slice(2).filter((row) => row[1] === "AVG");
const datasets = ["ETTh1", "ETTm1", "ETTh2", "ETTm2", "ECL", "Weather", "Solar", "Exchange", "Traffic"];
const columns = {
  "E-Armor": [2, 4], EMAformer: [6, 7], DeepBooTS: [8, 9], SimpleTM: [10, 11],
  FilterTS: [12, 13], xPatch: [14, 15], iTransformer: [16, 17], TimeMixer: [18, 19],
  PatchTST: [20, 21], DLinear: [22, 23], FEDformer: [24, 25],
};
const isMetric = (value) => value !== null && value !== undefined && value !== "" && Number.isFinite(Number(value));
const audit = Object.entries(columns).filter(([name]) => name !== "E-Armor").map(([name, [mseCol, maeCol]]) => {
  let comparable = 0, mseWins = 0, maeWins = 0, bothWins = 0, mseRel = 0, maeRel = 0;
  for (const row of detailRows) {
    const cells = [row[2], row[4], row[mseCol], row[maeCol]];
    if (!cells.every(isMetric)) continue;
    const [pm, pa, bm, ba] = cells.map(Number);
    comparable += 1;
    const mw = pm < bm, aw = pa < ba;
    mseWins += mw ? 1 : 0;
    maeWins += aw ? 1 : 0;
    bothWins += mw && aw ? 1 : 0;
    mseRel += (bm - pm) / bm;
    maeRel += (ba - pa) / ba;
  }
  return [name, comparable, mseWins, maeWins, bothWins, null, null, null, comparable ? mseRel / comparable : null, comparable ? maeRel / comparable : null];
});

const recommended = [
  ["DeepBooTS", 2026, "AAAI 2026", "近两年", "保留", "8/9（缺Exchange）", "4 horizons/32点", "双指标同时占优27/32", "漂移鲁棒方向与项目互补；补跑Exchange后更完整"],
  ["SimpleTM", 2025, "ICLR 2025", "近两年", "保留", "9/9", "4 horizons/36点", "双指标同时占优34/36", "轻量强基线，覆盖完整且与项目差距适中"],
  ["FilterTS", 2025, "AAAI 2025", "近两年", "保留", "论文8项 + Exchange复现", "4 horizons/36点", "双指标同时占优33/36", "频域路线；覆盖完整、整体略弱于项目"],
  ["FACTS", 2025, "ICLR 2025", "近两年", "新增", "9/9", "论文提供9数据集AVG", "项目在8/9数据集均值更优", "顶会、九数据集齐全，性能接近且总体略弱"],
  ["iTransformer", 2024, "ICLR 2024", "经典", "保留", "9/9", "4 horizons/36点", "双指标同时占优31/36", "公认强Transformer基线，不能删除"],
  ["TimeMixer", 2024, "ICLR 2024", "经典", "恢复保留", "9/9", "4 horizons/36点", "双指标同时占优36/36", "多尺度MLP经典代表；用于将经典论文保持为5篇"],
  ["PatchTST", 2023, "ICLR 2023", "经典", "保留", "9/9", "4 horizons/36点", "双指标同时占优33/36", "Patch范式经典代表，完整且总体略弱"],
  ["TimesNet", 2023, "ICLR 2023", "经典", "新增", "9/9", "原论文/后续顶会表可取全量", "九数据集AVG均弱于项目", "二维周期建模经典代表；替代过弱的DLinear"],
  ["FEDformer", 2022, "ICML 2022", "经典", "保留", "9/9（汇总表）", "4 horizons/36点", "双指标同时占优36/36", "频域Transformer奠基模型；作为下界保留一项即可"],
];

const removed = [
  ["EMAformer", 2026, "AAAI 2026", "删除（建议移附录）", "按要求从主表移除。项目在MAE上仅6/36点占优，删除会明显改善表观结果，但存在选择性比较风险，建议附录保留。"],
  ["xPatch", 2025, "AAAI 2025", "删除（建议移附录）", "项目仅在13/36点同时占优；与EMAformer/DeepBooTS的双流/分解叙事较重叠。删除会有挑弱基线嫌疑，因此建议附录保留。"],
  ["DLinear", 2023, "AAAI 2023", "删除", "项目34/36双指标胜出且平均差距过大；信息增量最低。"],
];

const facts = {
  ETTh1: [0.440, 0.428], ETTm1: [0.392, 0.397], ETTh2: [0.373, 0.399], ETTm2: [0.281, 0.325],
  ECL: [0.166, 0.263], Weather: [0.251, 0.278], Solar: [0.253, 0.272], Exchange: [0.342, 0.392], Traffic: [0.472, 0.303],
};
const timesnet = {
  ETTh1: [0.458, 0.450], ETTm1: [0.400, 0.406], ETTh2: [0.414, 0.427], ETTm2: [0.291, 0.333],
  ECL: [0.192, 0.295], Weather: [0.259, 0.287], Solar: [0.301, 0.319], Exchange: [0.416, 0.443], Traffic: [0.620, 0.336],
};
const recommendedNames = recommended.map((row) => row[0]);
const currentAvg = {};
for (const [name, [mseCol, maeCol]] of Object.entries(columns)) {
  currentAvg[name] = Object.fromEntries(avgRows.map((row, index) => [datasets[index], [row[mseCol], row[maeCol]]]));
}
currentAvg.FACTS = facts;
currentAvg.TimesNet = timesnet;

const sources = [
  ["EMAformer", "https://ojs.aaai.org/index.php/AAAI/article/download/40095/44056", "AAAI 2026论文", "官方表覆盖8个项目数据集；本地Exchange为复现值"],
  ["DeepBooTS", "https://ojs.aaai.org/index.php/AAAI/article/download/39509/43470", "AAAI 2026论文", "官方结果缺Exchange；不要将空值计为0"],
  ["SimpleTM", "https://proceedings.iclr.cc/paper_files/paper/2025/hash/27c546ab1e4f1d7d638e6a8dfbad9a07-Abstract-Conference.html", "ICLR 2025正式论文", "本地表含9数据集×4预测长度"],
  ["FilterTS", "https://ojs.aaai.org/index.php/AAAI/article/download/35438/37593", "AAAI 2025论文", "论文主表为8个数据集；本地补有Exchange复现"],
  ["FACTS", "https://proceedings.iclr.cc/paper_files/paper/2025/hash/ac58b418745b3e5f10c80110c963969f-Abstract-Conference.html", "ICLR 2025正式论文", "论文表含项目9数据集AVG MSE/MAE；用于本表均值对比"],
  ["iTransformer", "https://openreview.net/forum?id=JePfAI8fah", "ICLR 2024正式论文", "九数据集完整，主流强基线"],
  ["PatchTST", "https://openreview.net/forum?id=Jbdc0vTOcol", "ICLR 2023正式论文", "九数据集结果可由后续统一表核对"],
  ["TimesNet", "https://openreview.net/forum?id=ju_Uqw384Oq", "ICLR 2023正式论文", "本表AVG取FACTS/EMAformer统一比较表；加入正式稿需回溯全量表"],
  ["FEDformer", "https://proceedings.mlr.press/v162/zhou22g.html", "ICML 2022正式论文", "原论文数据集较少；本地九数据集值为后续统一基准汇总"],
  ["本项目", "results/experiment_results.xlsx", "本地实验汇总", "E-Armor列为日志最优结果；本表不改原文件"],
];

const wb = Workbook.create();
const conclusion = wb.worksheets.add("结论与阵容");
conclusion.getRange("A1:I1").merge();
conclusion.getRange("A1").values = [["基线重组建议（1篇2026 + 3篇2025 + 5篇经典）"]];
conclusion.getRange("A2:I2").merge();
conclusion.getRange("A2").values = [["结论：按要求从主表移除EMAformer，恢复TimeMixer，使经典论文达到5篇；DeepBooTS继续作为2026年代表。"]];
conclusion.getRange("A4:I4").values = [["模型", "年份", "会议", "分层", "动作", "数据覆盖", "数据粒度", "与本项目关系", "选择理由"]];
conclusion.getRange(`A5:I${4 + recommended.length}`).values = recommended;
const removalStart = 6 + recommended.length;
conclusion.getRange(`A${removalStart}:E${removalStart}`).values = [["拟删除模型", "年份", "会议", "动作", "理由/风险"]];
conclusion.getRange(`A${removalStart + 1}:E${removalStart + removed.length}`).values = removed;
conclusion.mergeCells(`E${removalStart}:I${removalStart}`);
for (let row = removalStart + 1; row <= removalStart + removed.length; row += 1) conclusion.mergeCells(`E${row}:I${row}`);

const auditSheet = wb.worksheets.add("当前基线审计");
auditSheet.getRange("A1:J1").merge();
auditSheet.getRange("A1").values = [["当前10个基线：本项目在36个预测点上的胜负审计（越高越好）"]];
auditSheet.getRange("A3:J3").values = [["模型", "可比点", "MSE胜点", "MAE胜点", "双胜点", "MSE胜率", "MAE胜率", "双胜率", "平均MSE相对增益", "平均MAE相对增益"]];
auditSheet.getRange(`A4:J${3 + audit.length}`).values = audit;
for (let row = 4; row <= 3 + audit.length; row += 1) {
  auditSheet.getRange(`F${row}`).formulas = [[`=IFERROR(C${row}/B${row},0)`]];
  auditSheet.getRange(`G${row}`).formulas = [[`=IFERROR(D${row}/B${row},0)`]];
  auditSheet.getRange(`H${row}`).formulas = [[`=IFERROR(E${row}/B${row},0)`]];
}

const avgSheet = wb.worksheets.add("九数据集均值");
const avgHeader1 = ["数据集"];
const avgHeader2 = [""];
for (const name of ["E-Armor", ...recommendedNames]) {
  avgHeader1.push(name, "");
  avgHeader2.push("MSE", "MAE");
}
avgSheet.getRange("A1:U1").merge();
avgSheet.getRange("A1").values = [["九数据集平均性能对比（预测长度96/192/336/720的平均；空白=来源未报告）"]];
avgSheet.getRange("A3:U4").values = [avgHeader1, avgHeader2];
for (let col = 1; col < 21; col += 2) {
  const start = String.fromCharCode(65 + col);
  const end = String.fromCharCode(65 + col + 1);
  avgSheet.mergeCells(`${start}3:${end}3`);
}
const avgData = datasets.map((dataset) => {
  const row = [dataset];
  for (const name of ["E-Armor", ...recommendedNames]) {
    const pair = currentAvg[name]?.[dataset] ?? [null, null];
    row.push(isMetric(pair[0]) ? Number(pair[0]) : null, isMetric(pair[1]) ? Number(pair[1]) : null);
  }
  return row;
});
avgSheet.getRange("A5:U13").values = avgData;

const sourceSheet = wb.worksheets.add("来源与限制");
sourceSheet.getRange("A1:D1").merge();
sourceSheet.getRange("A1").values = [["来源、可比性与使用限制"]];
sourceSheet.getRange("A3:D3").values = [["模型", "首要来源", "录用证据", "数据限制/正式写作注意事项"]];
sourceSheet.getRange(`A4:D${3 + sources.length}`).values = sources;
sourceSheet.getRange(`A${5 + sources.length}:D${5 + sources.length}`).merge();
sourceSheet.getRange(`A${5 + sources.length}`).values = [["重要：不同论文的输入长度、归一化、随机种子和实现版本可能不同。正式论文主表应优先采用同一代码库复现结果；原论文数值可作交叉核验，不应无说明混合排序。"]];

for (const sheet of [conclusion, auditSheet, avgSheet, sourceSheet]) {
  sheet.showGridLines = false;
  sheet.freezePanes.freezeRows(sheet === avgSheet ? 4 : 3);
  const used = sheet.getUsedRange();
  used.format.font = { name: "Microsoft YaHei", size: 10, color: "#233143" };
  used.format.verticalAlignment = "center";
  used.format.wrapText = true;
}

for (const [sheet, titleRange, headerRanges] of [
  [conclusion, "A1:I2", ["A4:I4", `A${removalStart}:E${removalStart}`]],
  [auditSheet, "A1:J1", ["A3:J3"]],
  [avgSheet, "A1:U1", ["A3:U4"]],
  [sourceSheet, "A1:D1", ["A3:D3"]],
]) {
  sheet.getRange(titleRange).format.fill = "#17365D";
  sheet.getRange(titleRange).format.font = { name: "Microsoft YaHei", size: 12, bold: true, color: "#FFFFFF" };
  sheet.getRange(titleRange).format.horizontalAlignment = "center";
  for (const headerRange of headerRanges) {
    sheet.getRange(headerRange).format.fill = "#2F75B5";
    sheet.getRange(headerRange).format.font = { name: "Microsoft YaHei", size: 10, bold: true, color: "#FFFFFF" };
    sheet.getRange(headerRange).format.horizontalAlignment = "center";
    sheet.getRange(headerRange).format.borders = { preset: "all", style: "thin", color: "#D9EAF7" };
  }
}

conclusion.getRange("A5:I13").format.borders = { preset: "all", style: "thin", color: "#D9E2F3" };
conclusion.getRange("A5:I5").format.fill = "#FFF2CC";
conclusion.getRange("A6:I8").format.fill = "#E2F0D9";
conclusion.getRange("A9:I13").format.fill = "#DDEBF7";
conclusion.getRange(`A${removalStart + 1}:E${removalStart + removed.length}`).format.fill = "#FCE4D6";
conclusion.getRange("A1:A30").format.columnWidth = 15;
conclusion.getRange("B1:E30").format.columnWidth = 13;
conclusion.getRange("F1:G30").format.columnWidth = 21;
conclusion.getRange("H1:H30").format.columnWidth = 24;
conclusion.getRange("I1:I30").format.columnWidth = 40;

auditSheet.getRange(`A4:J${3 + audit.length}`).format.borders = { preset: "all", style: "thin", color: "#D9E2F3" };
auditSheet.getRange(`F4:J${3 + audit.length}`).format.numberFormat = "0.0%";
auditSheet.getRange("A1:A20").format.columnWidth = 16;
auditSheet.getRange("B1:E20").format.columnWidth = 11;
auditSheet.getRange("F1:J20").format.columnWidth = 18;
auditSheet.getRange(`F4:H${3 + audit.length}`).conditionalFormats.addColorScale({ minColor: "#F8696B", midColor: "#FFEB84", maxColor: "#63BE7B" });

avgSheet.getRange("A5:U13").format.borders = { preset: "all", style: "thin", color: "#D9E2F3" };
avgSheet.getRange("B5:U13").format.numberFormat = "0.000";
avgSheet.getRange("A1:A20").format.columnWidth = 13;
avgSheet.getRange("B1:U20").format.columnWidth = 9;
for (let row = 5; row <= 13; row += 1) {
  for (let metricOffset = 0; metricOffset < 2; metricOffset += 1) {
    const cols = [];
    for (let col = 1 + metricOffset; col < 21; col += 2) {
      const value = avgData[row - 5][col];
      if (isMetric(value)) cols.push({ col, value: Number(value) });
    }
    const best = Math.min(...cols.map((x) => x.value));
    for (const item of cols.filter((x) => x.value === best)) {
      const address = `${String.fromCharCode(65 + item.col)}${row}`;
      avgSheet.getRange(address).format.fill = "#C6E0B4";
      avgSheet.getRange(address).format.font = { name: "Microsoft YaHei", size: 10, bold: true, color: "#1F1F1F" };
    }
  }
}

sourceSheet.getRange(`A4:D${3 + sources.length}`).format.borders = { preset: "all", style: "thin", color: "#D9E2F3" };
sourceSheet.getRange("A1:A30").format.columnWidth = 16;
sourceSheet.getRange("B1:B30").format.columnWidth = 65;
sourceSheet.getRange("C1:C30").format.columnWidth = 22;
sourceSheet.getRange("D1:D30").format.columnWidth = 52;
sourceSheet.getRange(`A${5 + sources.length}:D${5 + sources.length}`).format.fill = "#FFF2CC";

wb.recalculate();
await fs.mkdir(outputDir, { recursive: true });
await fs.mkdir(previewDir, { recursive: true });
const check = await wb.inspect({ kind: "table", range: "结论与阵容!A1:I18", include: "values,formulas", tableMaxRows: 20, tableMaxCols: 10, maxChars: 12000 });
console.log("CHECK\n" + check.ndjson);
const errors = await wb.inspect({ kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!", options: { useRegex: true, maxResults: 200 }, summary: "formula error scan" });
console.log("ERRORS\n" + errors.ndjson);
for (const [name, range] of [["结论与阵容", "A1:I18"], ["当前基线审计", "A1:J13"], ["九数据集均值", "A1:U13"]]) {
  const image = await wb.render({ sheetName: name, range, scale: 1, format: "png" });
  await fs.writeFile(`${previewDir}/${name}.png`, new Uint8Array(await image.arrayBuffer()));
}
await (await SpreadsheetFile.exportXlsx(wb)).save(outputPath);
console.log(`OUTPUT ${outputPath}`);
