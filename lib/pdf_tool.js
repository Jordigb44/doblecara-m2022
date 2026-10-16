// pdf_tool.js — utilidades PDF con PDFKit (JavaScript for Automation, incluido en macOS)
//
// Uso:
//   osascript -l JavaScript pdf_tool.js count  <entrada.pdf>
//   osascript -l JavaScript pdf_tool.js split  <entrada.pdf> <salida.pdf> <odd|even> <normal|reverse> <pad 0|1> <rotar 0|90|180|270>
//
// "pad=1" (solo para even): si el documento tiene un número impar de páginas,
// añade una página en blanco como dorso de la última hoja, para que todas las
// hojas puedan volver a la bandeja sin tener que retirar ninguna.

ObjC.import('Foundation');
ObjC.import('Quartz'); // PDFKit vive dentro de Quartz en macOS

function openDoc(path) {
  const url = $.NSURL.fileURLWithPath(path);
  const doc = $.PDFDocument.alloc.initWithURL(url);
  if (!doc || doc.isNil()) {
    throw new Error('No se pudo abrir el PDF: ' + path);
  }
  return doc;
}

function run(argv) {
  const cmd = argv[0];
  const input = argv[1];
  const doc = openDoc(input);
  const n = doc.pageCount;

  if (cmd === 'count') {
    return String(n);
  }

  if (cmd !== 'split') {
    throw new Error('Comando desconocido: ' + cmd);
  }

  const output = argv[2];
  const mode = argv[3] || 'odd';
  const order = argv[4] || 'normal';
  const pad = argv[5] === '1';
  const rotate = parseInt(argv[6] || '0', 10) || 0;

  // Índices (base 0) de las páginas a incluir; -1 = página en blanco
  const idx = [];
  for (let i = 0; i < n; i++) {
    const p = i + 1;
    if ((mode === 'odd' && p % 2 === 1) || (mode === 'even' && p % 2 === 0)) {
      idx.push(i);
    }
  }
  if (mode === 'even' && pad && n % 2 === 1) {
    idx.push(-1); // dorso en blanco de la última hoja
  }
  if (order === 'reverse') {
    idx.reverse();
  }

  const out = $.PDFDocument.alloc.init;
  let k = 0;
  idx.forEach(function (i) {
    let page;
    if (i < 0) {
      page = $.PDFPage.alloc.init;
      try {
        const ref = doc.pageAtIndex(n - 1);
        page.setBoundsForBox(ref.boundsForBox(0), 0); // 0 = MediaBox
      } catch (e) {
        // Si falla, PDFKit usa un tamaño por defecto; suficiente para una hoja en blanco
      }
    } else {
      page = doc.pageAtIndex(i).copy;
      if (rotate) {
        page.rotation = (page.rotation + rotate) % 360;
      }
    }
    out.insertPageAtIndex(page, k);
    k++;
  });

  if (k === 0) {
    return '0';
  }
  if (!out.writeToFile(output)) {
    throw new Error('No se pudo escribir: ' + output);
  }
  return String(k);
}
